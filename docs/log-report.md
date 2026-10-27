# Log report

`scripts/log_report.sh` summarises two log sources into a dated Markdown report
in `reports/`:

- **SSH** (`/var/log/auth.log`, or the systemd journal if the file does not exist):
  failed password attempts, the IPs and usernames behind them, and successful logins.
- **nginx** (`/var/log/nginx/access.log`): total requests, status classes, top paths,
  top client IPs, most common 404 paths, 5xx errors and scanner-style requests
  (`.env`, `wp-login`, `phpmyadmin`, `.git/`).
- **System errors** from the last 24 hours (journal, priority `err`).

If one IP has at least `FAILED_LOGIN_ALERT` failed SSH logins, an alert is raised
through `alert.sh` (with the usual cooldown).

## Usage

```bash
scripts/log_report.sh        # print the report and save a copy
scripts/log_report.sh -q     # save only (for cron)
```

## Testing with known data

```bash
tests/make_sample_logs.sh /tmp/sample-logs
NGINX_ACCESS_LOG=/tmp/sample-logs/access.log \
AUTH_LOG=/tmp/sample-logs/auth.log scripts/log_report.sh
```

The sample data contains 48 failed logins (42 from one IP) and 99 web requests,
so the expected numbers are known in advance.
