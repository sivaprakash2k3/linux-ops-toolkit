# Incident 03: Service down after a bad configuration

| | |
|---|---|
| Date | TODO: YYYY-MM-DD |
| Severity | High |
| Detected by | Health check alert (`Service nginx is not running`) |
| Time to resolve | TODO minutes |

## Symptom
nginx stopped serving requests. `curl http://localhost/` returned "Connection refused",
and the health check marked nginx `[DOWN]` with an alert.

## Timeline
- TODO hh:mm A broken file was added to `/etc/nginx/conf.d/` and nginx was restarted
- TODO hh:mm The restart failed and the service stayed down
- TODO hh:mm The health check raised an alert
- TODO hh:mm `nginx -t` identified the faulty file and line
- TODO hh:mm The file was removed and nginx started again

## Investigation
```bash
systemctl status nginx --no-pager
journalctl -xeu nginx --no-pager | tail -15
sudo nginx -t
```
- `systemctl status` showed `failed` (exit code TODO).
- The journal and `nginx -t` both reported: TODO paste the exact error line, for example
  `unknown directive ... in /etc/nginx/conf.d/broken.conf:1`.

## Root cause
An invalid configuration file was added, and `systemctl restart` stopped the working
server before the new configuration was found to be invalid.

## Fix
Removed `/etc/nginx/conf.d/broken.conf`, confirmed `nginx -t` passed, started nginx,
and checked that `curl -I http://localhost/` returned `200 OK`.

## Prevention
- Always run `sudo nginx -t` before restarting.
- Prefer `systemctl reload nginx`: it keeps the old working configuration running if
  the new one is invalid.
- Keep configuration in version control and review changes before applying them.

## What I learned
The error message names the file and line. `restart` takes the service down before
applying new settings, while `reload` is safer for configuration changes.
