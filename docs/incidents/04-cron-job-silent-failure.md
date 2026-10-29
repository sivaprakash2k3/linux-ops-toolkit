# Incident 04: Cron job failing silently

| | |
|---|---|
| Date | TODO: YYYY-MM-DD |
| Severity | Medium |
| Detected by | Noticing the log file had stopped updating |
| Time to resolve | TODO minutes |

## Symptom
A job that wrote one line to a log file every minute stopped producing output. Nothing
reported an error anywhere, so the failure was only visible because the newest log line
was older than the current time (last entry TODO, current time TODO).

## Timeline
- TODO hh:mm A test cron job was working (one heartbeat line per minute)
- TODO hh:mm The script's execute permission was removed with `chmod -x`
- TODO hh:mm The log stopped growing
- TODO hh:mm Investigation showed cron was still starting the command
- TODO hh:mm Permission restored and the job resumed

## Investigation
```bash
journalctl -u cron --since "10 minutes ago" --no-pager | tail
~/lab-heartbeat.sh
ls -l ~/lab-heartbeat.sh
```
- The cron journal showed `CMD (...)` each minute, so cron was starting the job.
- Running the script by hand printed `Permission denied`.
- `ls -l` showed `TODO paste the permissions, for example -rw-rw-r--` with no `x` bit.

## Root cause
The script lost its execute permission, so every run failed. Cron discards the error
output when no mail system is configured, so nobody saw the failure.

## Fix
`chmod +x` on the script. The log resumed within a minute.

## Prevention
- Redirect output in every cron line: `>> logs/cron.log 2>&1`. I tested this: with the
  redirect, the `Permission denied` message appeared in the log file.
- Raise an alert if an expected log line has not appeared recently.
- Check job health by looking at results (fresh files, recent timestamps), not only at
  whether the schedule exists.

## What I learned
A scheduled job can fail without any visible sign. Cron starting a command does not mean
the command worked, so capture its output and check that results keep arriving.
