#!/usr/bin/env bash
# log_report.sh - summarise SSH and nginx logs into a dated report
#
# Usage: log_report.sh [-q]
#   -q  quiet: save the report but do not print it (use this from cron)

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/common.sh"

NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/var/log/nginx/access.log}"
AUTH_LOG="${AUTH_LOG:-/var/log/auth.log}"
TOP_N="${TOP_N:-5}"
FAILED_LOGIN_ALERT="${FAILED_LOGIN_ALERT:-20}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/reports}"

QUIET=0
while getopts "q" opt; do
    case $opt in
        q) QUIET=1 ;;
        *) echo "Usage: $0 [-q]" >&2; exit 2 ;;
    esac
done

mkdir -p "$REPORT_DIR"
report_file="$REPORT_DIR/log-report-$(date +%Y%m%d-%H%M%S).md"

# SSH log lines: from the auth log file, or from the systemd journal if no file
auth_lines() {
    if [ -r "$AUTH_LOG" ]; then
        cat "$AUTH_LOG"
    else
        journalctl -u ssh --no-pager -q -o short 2>/dev/null
    fi
}

# Print the first TOP_N lines of stdin, indented, or "(none)"
top_list() {
    local out
    out=$(head -n "$TOP_N")
    if [ -z "$out" ]; then
        echo "    (none)"
    else
        printf '%s\n' "$out" | while IFS= read -r line; do echo "    ${line#"${line%%[! ]*}"}"; done
    fi
}

failed_by_ip() {
    auth_lines | grep "Failed password" | grep -oE 'from [0-9a-fA-F.:]+' \
        | awk '{print $2}' | sort | uniq -c | sort -rn
}

failed_users() {
    auth_lines \
        | sed -nE 's/.*Failed password for (invalid user )?([^ ]+) from .*/\2/p' \
        | sort | uniq -c | sort -rn
}

accepted_logins() {
    auth_lines \
        | sed -nE 's/.*Accepted ([a-z-]+) for ([^ ]+) from ([^ ]+) port.*/\2 from \3 via \1/p' \
        | sort | uniq -c | sort -rn
}

web_section() {
    local f=$NGINX_ACCESS_LOG total errors scanners
    if [ ! -r "$f" ]; then
        echo "No readable access log at $f."
        return
    fi
    total=$(wc -l < "$f")
    echo "Total requests: $total"
    echo
    echo "Responses by status class:"
    awk '$9 ~ /^[0-9][0-9][0-9]$/ {n[substr($9,1,1) "xx"]++}
         END {for (k in n) printf "%d %s\n", n[k], k}' "$f" | sort -k2 | top_list
    echo
    echo "Top requested paths:"
    awk '{print $7}' "$f" | sort | uniq -c | sort -rn | top_list
    echo
    echo "Top client IPs:"
    awk '{print $1}' "$f" | sort | uniq -c | sort -rn | top_list
    echo
    echo "Most common 404 paths:"
    awk '$9 == 404 {print $7}' "$f" | sort | uniq -c | sort -rn | top_list
    echo
    errors=$(awk '$9 ~ /^5/' "$f" | wc -l)
    echo "Server errors (5xx): $errors"
    echo
    scanners=$(grep -ciE '\.env|wp-login|phpmyadmin|\.git/|/etc/passwd' "$f")
    echo "Suspicious scanner requests: $scanners"
    if [ "$scanners" -gt 0 ]; then
        echo "Source IPs of those requests:"
        grep -iE '\.env|wp-login|phpmyadmin|\.git/|/etc/passwd' "$f" \
            | awk '{print $1}' | sort | uniq -c | sort -rn | top_list
    fi
}

build_report() {
    local auth failed errors

    echo "# Log report for $(hostname)"
    echo
    echo "Generated: $(timestamp)"
    echo
    echo "## SSH activity"
    echo
    auth=$(auth_lines)
    if [ -z "$auth" ]; then
        echo "No SSH log data found (checked $AUTH_LOG and the systemd journal)."
    else
        failed=$(echo "$auth" | grep -c "Failed password")
        echo "Failed password attempts: $failed"
        echo
        echo "Top source IPs of failed logins:"
        failed_by_ip | top_list
        echo
        echo "Top usernames tried:"
        failed_users | top_list
        echo
        echo "Successful logins:"
        accepted_logins | top_list
    fi

    echo
    echo "## Web server (nginx)"
    echo
    web_section

    echo
    echo "## System errors in the last 24 hours"
    echo
    errors=$(journalctl -p err --since "24 hours ago" --no-pager -q 2>/dev/null | tail -n "$TOP_N")
    if [ -z "$errors" ]; then
        echo "    (none)"
    else
        printf '%s\n' "$errors" | while IFS= read -r line; do echo "    $line"; done
    fi
}

build_report > "$report_file"
echo "$(timestamp) report written to $report_file" >> "$LOG_DIR/report.log"

if [ "$QUIET" -eq 0 ]; then
    cat "$report_file"
    echo
    echo "Saved to: $report_file"
fi

# Alert when a single IP has many failed SSH logins
top=$(failed_by_ip | head -n 1)
count=$(echo "$top" | awk '{print $1}')
ip=$(echo "$top" | awk '{print $2}')
if [ -n "$count" ] && [ "$count" -ge "$FAILED_LOGIN_ALERT" ]; then
    "$SCRIPT_DIR/alert.sh" ssh-bruteforce \
        "Possible SSH brute force: $count failed logins from $ip"
fi
