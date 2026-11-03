# Incident 03: Service down after a bad configuration

| | |
|---|---|
| Date | 2026-11-03 |
| Severity | High |
| Detected by | Health check: `nginx [DOWN]` (1 problem found) |
| Time to resolve | About 3 minutes (detected 07:30:50, fixed 07:33:34) |

## Symptom
nginx stopped after a restart and stayed down. The health check marked it `[DOWN]` and
reported `Result: 1 problem(s) found`.

## Timeline
- 07:28:53 Started the lab
- 07:29:40 A broken file was added to `/etc/nginx/conf.d/` and `systemctl restart nginx` failed;
  the service had been running for about a day before the restart
- 07:30:31 `nginx -t` reported the configuration error
- 07:30:50 Detection recorded
- 07:33:34 The file was removed, `nginx -t` passed, nginx started, and `curl` returned `200 OK`

## Investigation
```bash
./scripts/health_check.sh | tail -6
sudo nginx -t
systemctl status nginx --no-pager | head -8
```
- The health check showed `nginx [DOWN]`.
- `sudo nginx -t` printed the exact cause:
  `[emerg] unexpected end of file, expecting ";" or "}" in /etc/nginx/conf.d/broken.conf:2`
  followed by `configuration file /etc/nginx/nginx.conf test failed`.
- `systemctl status nginx` showed `Active: failed (Result: exit-code) since Tue 2026-11-03
  07:29:40 IST`, with `ExecStartPre=/usr/sbin/nginx -t -q ... (code=exited, status=1/FAILURE)`:
  systemd runs the configuration test before starting, and it failed.

## Root cause
An invalid configuration file was added, and `systemctl restart` stopped the working server
before the new configuration was found to be invalid.

## Fix
```bash
sudo rm /etc/nginx/conf.d/broken.conf
sudo nginx -t && sudo systemctl start nginx
curl -sI http://localhost/ | head -1
```
`nginx -t` reported `syntax is ok` and `test is successful`, and `curl` returned
`HTTP/1.1 200 OK`.

## Prevention
- Always run `sudo nginx -t` before restarting.
- Prefer `systemctl reload nginx` for configuration changes: it keeps the old working
  configuration running if the new one is invalid.
- Keep configuration in version control and review changes before applying them.

## What I learned
The error message names the file and line. `restart` takes the service down before applying
new settings, whereas `reload` is safer, and the service manager's own pre-start test is why
the unit failed instead of starting with a broken configuration.
