# Incident 02: High CPU

| | |
|---|---|
| Date | 2026-11-02 |
| Severity | Medium |
| Detected by | Health check alert: `CPU at 100% (threshold 80%)` |
| Time to resolve | About 3 minutes (detected 08:21:32, fixed by 08:24:48) |

## Symptom
CPU usage hit 100% on a 2-core VM. The health check marked CPU `[WARN]` and logged an alert.

## Timeline
- 08:21:26 Started two runaway `yes` processes (one per core), PIDs 9557 and 9558
- 08:21:31 `health_check.sh` reported `CPU 100% [WARN]`; the alert was logged at 08:21:32
- 08:21:32 `ps` showed both `yes` processes near 98% CPU after 6 seconds of runtime
- about 08:23 Lowered the priority of PID 9557 with `renice`; CPU stayed high
- about 08:24 `pkill -x yes` stopped both processes
- 08:24:22 Health check showed CPU 1% `[OK]`; fix recorded at 08:24:48

## Investigation
```bash
./scripts/health_check.sh
uptime
nproc
ps -eo pid,%cpu,etime,cmd --sort=-%cpu | head -4
```
- The health check reported `CPU 100% [WARN]` with `Load average: 0.16 0.07 0.01 (cores: 2)`.
- `ps` ranked the culprits: PID 9558 at 97.9% CPU and PID 9557 at 97.6%, both running `yes`
  with an elapsed time of 00:06.
- The load average was still low (0.16) because it is a slow-moving average: the CPU
  percentage was the faster signal.

## Root cause
Two runaway processes were each using a full core. In a real incident this could be a stuck
loop, a bad deployment or a runaway scheduled job.

## Fix
`renice +19 9557` changed its priority (old 0, new 19), yet at process age 01:46 both
processes still showed about 99.5% CPU. That is expected: with 2 cores and 2 busy processes,
nothing competes with the low-priority one, so it still gets a full core. `pkill -x yes`
stopped them, and CPU returned to 1%.

## Prevention
- Limit services with systemd (`CPUQuota=`).
- Check what changed recently (a deployment, a new cron job) before digging deeper.
- Alert on sustained high CPU or load, not only a single reading.

## What I learned
`renice` only decides who runs first when processes compete, so it does not reduce total
consumption on an otherwise idle machine. `ps --sort=-%cpu` with the elapsed time quickly
shows which process is the culprit and how long it has been running.
