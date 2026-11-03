# Incident 01: Disk full, and a deleted file that keeps its space

| | |
|---|---|
| Date | 2026-11-02 |
| Severity | Medium |
| Detected by | Health check alert: `Disk / at 90% (threshold 80%)` |
| Time to resolve | About 3 minutes (alert at 08:14:39, fixed by 08:18:07) |

## Symptom
The health check marked the root filesystem `[WARN]` at 90% used (threshold 80%) and
`logs/alerts.log` recorded a disk alert. On a real system, applications would soon fail to
write files or logs.

## Timeline
- 08:14:07 Started the lab: planned a leak file of about 24 GB on a 40 GB disk (9.5 GB used)
- 08:14:38 Created `/var/tmp/leak/app-debug.log` (24 GB) and held it open with `sleep` (PID 9163)
- 08:14:38 `health_check.sh` reported `Disk / 90% [WARN]`; the alert was logged at 08:14:39
- 08:14-08:18 `du` and `find` located the file; `rm` deleted it, but `df` still showed 90%
- 08:14-08:18 `lsof +L1` showed PID 9163 still holding the deleted file; `kill` released it
- 08:18:07 Disk usage back to 26%

## Investigation
```bash
df -h /
sudo du -xh / --max-depth=3 2>/dev/null | sort -rh | head -8
sudo find / -xdev -type f -size +100M -exec ls -lh {} + 2>/dev/null
sudo rm /var/tmp/leak/app-debug.log
df -h /
sudo lsof +L1
```
- `df` showed `/dev/sda2  40G  34G  3.9G  90% /`.
- `du` listed `24G /var/tmp/leak` as the largest folder (27G under `/var`).
- `find` named the file: `-rw-r--r-- 1 root root 24G Nov 2 08:14 /var/tmp/leak/app-debug.log`.
- After `rm`, `df -h /` still showed **34G used (90%)**: the space was not freed.
- `lsof +L1` listed the culprit among many harmless system entries:
  `sleep  9163  sivaprakash  0r  REG  8,2  25649313792  0  267690  /var/tmp/leak/app-debug.log (deleted)`
- After `kill %1` ended PID 9163, `df -h /` showed `/dev/sda2  40G  9.4G  28G  26% /`.

## Root cause
One log file grew to 24 GB. Deleting it was not enough: process 9163 still had it open, and
Linux only frees the space once the last process closes the file.

## Fix
Removed the file, found the process holding it with `lsof +L1`, and stopped it. Usage dropped
from 90% to 26%.

## Prevention
- Rotate and cap logs with `logrotate`.
- Alert earlier (for example at 70%) so there is time to react.
- After deleting a large file, check `lsof +L1` and restart the service that was writing to it.
- Filter the noisy `lsof` output, for example `sudo lsof +L1 | grep -v memfd`.

## What I learned
Deleting a file removes its name, not its data, while a process still has it open. `du` finds
big files, and `lsof +L1` finds deleted ones that still use space.
