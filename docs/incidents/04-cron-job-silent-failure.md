# Incident 04: Cron job failing silently

| | |
|---|---|
| Date | 2026-11-03 |
| Severity | Medium |
| Detected by | Noticing the log file had stopped updating |
| Time to resolve | About 5 minutes (detected 07:42:11, fixed by 07:47:16) |

## Symptom
A test job that wrote one line to `~/lab-heartbeat.log` every minute stopped producing output.
Nothing reported an error: the failure was only visible because the newest log line was
07:38:01 while the clock read 07:41:24.

## Timeline
- 07:33:48 Created the test cron job; heartbeat lines appeared every minute (07:36:02, 07:37:01, 07:38:01)
- 07:38:29 Removed the script's execute permission with `chmod -x`
- 07:38-07:41 No new log lines, while the cron journal still showed the job starting every minute
- 07:41:24 Checked: the last log entry was still 07:38:01
- 07:42:11 Investigation: running the script by hand gave `Permission denied`
- by 07:46 Execute permission restored; the log resumed (entries at 07:46:01 and 07:47:02)
- 07:47:16 Fix recorded and the test job removed

## Investigation
```bash
date
tail -2 ~/lab-heartbeat.log
journalctl -u cron --since "10 minutes ago" --no-pager | tail
~/lab-heartbeat.sh
ls -l ~/lab-heartbeat.sh
```
- `date` showed 07:41:24, but the newest heartbeat was 07:38:01.
- The cron journal showed cron **starting** the command every minute, for example
  `(sivaprakash) CMD (/home/sivaprakash/lab-heartbeat.sh)` at 07:40:01 and 07:41:01, followed by
  `(CRON) info (No MTA installed, discarding output)`.
- Running the script by hand printed `-bash: /home/sivaprakash/lab-heartbeat.sh: Permission denied`.
- `ls -l` showed `-rw-rw-r-- 1 sivaprakash sivaprakash 76 Nov 3 07:35`: no `x` bit anywhere.

## Root cause
The script lost its execute permission, so every run failed. Cron discards a job's output
when no mail system is installed, so the error message was thrown away and nobody saw it.

## Fix
`chmod +x ~/lab-heartbeat.sh`. The log resumed within a minute (`07:46:01 heartbeat ok`,
`07:47:02 heartbeat ok`). The test job and its files were then removed, leaving only the
toolkit's three jobs in the crontab.

## Prevention
- Redirect output in every cron line (`>> file 2>&1`) so errors land in a file. All three
  toolkit jobs now do this, for example:
  `*/5 * * * * /home/sivaprakash/linux-ops-toolkit/scripts/health_check.sh -q >> /home/sivaprakash/linux-ops-toolkit/logs/cron.log 2>&1`
  (`install.sh` writes these lines).
- Raise an alert if an expected log line has not appeared recently.
- Check results (fresh files, recent timestamps), not only whether the schedule exists.

## What I learned
Cron starting a command does not mean the command worked. The journal showed the job being
launched every minute even though it failed every time, and the real error was discarded
because there was no mail system, so output has to be captured on purpose.
