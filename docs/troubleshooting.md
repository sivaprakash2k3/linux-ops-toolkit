# Troubleshooting

Five incidents reproduced on the lab VM, each written up with symptom, investigation,
root cause, fix and prevention.

| # | Incident | Main tools |
|---|---|---|
| 1 | [Disk full, and a deleted file that keeps its space](incidents/01-disk-full.md) | df, du, find, lsof |
| 2 | [High CPU](incidents/02-high-cpu.md) | top, ps, kill, renice |
| 3 | [Service down after a bad config](incidents/03-service-down.md) | systemctl, journalctl, nginx -t |
| 4 | [Cron job failing silently](incidents/04-cron-job-silent-failure.md) | crontab, ls -l, chmod |
| 5 | [SSH blocked by the firewall](incidents/05-ssh-blocked-by-firewall.md) | ufw, ss, Test-NetConnection |

## A routine for any incident

1. **What changed?** A deployment, a config edit, a new job, an update.
2. **What does the monitoring say?** `logs/health.log`, `logs/alerts.log`, the log report.
3. **Check the basics:** disk (`df -h`), memory (`free -h`), CPU and load (`top`, `uptime`).
4. **Read the logs:** `journalctl -u SERVICE`, `/var/log/`, then the application's own log.
5. **Check each layer for network problems:** reachable (ping / port test), firewall, service listening (`ss -tlnp`).
6. **Fix one thing at a time**, and confirm the fix with the same command that showed the problem.
7. **Write it up**, including how to catch it sooner next time.

## Handy commands

| Question | Command |
|---|---|
| Disk usage by folder | `sudo du -xh / --max-depth=3 \| sort -rh \| head` |
| Deleted files still held open | `sudo lsof +L1` |
| Top CPU users | `ps -eo pid,%cpu,%mem,cmd --sort=-%cpu \| head` |
| Why did a service fail | `journalctl -xeu SERVICE` |
| Is a port listening | `sudo ss -tlnp` |
| File permissions | `ls -l FILE` |
| Is the config valid | `sudo nginx -t`, `sudo sshd -t` |
