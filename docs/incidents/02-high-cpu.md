# Incident 02: High CPU

| | |
|---|---|
| Date | TODO: YYYY-MM-DD |
| Severity | Medium |
| Detected by | Health check alert (`CPU at TODO%`) |
| Time to resolve | TODO minutes |

## Symptom
CPU usage stayed near 100% and the load average climbed above the number of cores.
The health check marked CPU `[WARN]` and logged an alert.

## Timeline
- TODO hh:mm Runaway `yes` processes were started (one per core)
- TODO hh:mm `health_check.sh` reported CPU `[WARN]`; alert logged
- TODO hh:mm `top` and `ps` identified the processes
- TODO hh:mm Lowered priority with `renice`, then stopped the processes
- TODO hh:mm CPU back to `[OK]`

## Investigation
```bash
uptime
top -bn1 | head -12
ps -eo pid,ppid,%cpu,%mem,etime,cmd --sort=-%cpu | head -5
```
- `uptime` showed a load average of TODO on TODO cores.
- `top` and `ps` listed `yes` at about TODO% CPU each. The oldest had been running for TODO.

## Root cause
Runaway processes were using all CPU cores. In a real incident this could be a
stuck loop, a bad deployment or a runaway scheduled job.

## Fix
`renice +19` lowered a process's priority but CPU use stayed high, because priority
only decides who runs first. `pkill -x yes` stopped the processes, and CPU returned
to normal (TODO%).

## Prevention
- Limit services with systemd (`CPUQuota=`).
- Check what changed recently (a deployment, a new cron job) before digging deeper.
- Alert on sustained high load, not only on a single reading.

## What I learned
`renice` changes scheduling order, not total consumption. `ps --sort=-%cpu` and `etime`
quickly show which process is the culprit and how long it has been running.
