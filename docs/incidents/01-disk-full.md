# Incident 01: Disk full, and a deleted file that keeps its space

| | |
|---|---|
| Date | TODO: YYYY-MM-DD |
| Severity | Medium |
| Detected by | Health check alert (`Disk / at TODO%`) |
| Time to resolve | TODO minutes |

## Symptom
The health check reported the root filesystem above the 80% threshold and
`logs/alerts.log` recorded a disk alert. On a real system, applications would soon
fail to write files or logs.

## Timeline
- TODO hh:mm A large log file was created under `/var/tmp/leak` and held open by a process
- TODO hh:mm `health_check.sh` marked Disk `[WARN]` and logged an alert
- TODO hh:mm `du` and `find` pointed at `app-debug.log`
- TODO hh:mm The file was deleted, but disk usage did not drop
- TODO hh:mm `lsof +L1` showed a process still holding the deleted file; stopping it freed the space

## Investigation
```bash
df -h /
sudo du -xh / --max-depth=3 2>/dev/null | sort -rh | head -8
sudo find / -xdev -type f -size +100M -exec ls -lh {} + 2>/dev/null
sudo lsof +L1
```
- `df` confirmed usage of TODO%.
- `du` showed `/var/tmp/leak` as the largest folder (TODO size).
- `find` named `/var/tmp/leak/app-debug.log` (TODO size).
- After `rm`, `df` still showed TODO%. `lsof +L1` listed `sleep` (PID TODO) with the
  file marked `(deleted)`.

## Root cause
One log file grew until it filled most of the disk. Deleting it was not enough: a
running process kept the file open, and Linux only frees the space once the last
process closes it.

## Fix
Removed the file, then stopped the process that held it open. `df -h /` then showed
TODO%.

## Prevention
- Rotate logs with `logrotate` and cap their size.
- Alert earlier (for example at 70%) so there is time to react.
- After deleting a large file, check `lsof +L1` and restart the service that was writing to it.

## What I learned
Deleting a file removes its name, not its data, while a process still has it open.
`du` finds big files; `lsof +L1` finds deleted ones that still use space.
