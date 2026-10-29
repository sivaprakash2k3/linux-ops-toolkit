#!/usr/bin/env bash
# run_tests.sh - end-to-end tests for the toolkit.
# Safe to run anywhere: uses a temporary folder and fake systemctl/logger commands.

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
S="$ROOT_DIR/scripts"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/data/sub" "$TMP/logs"
echo "hello" > "$TMP/data/a.txt"
echo "world" > "$TMP/data/sub/b.txt"

# Fake systemctl: "is-active --quiet NAME" fails only for names listed in FAKE_DOWN
cat > "$TMP/bin/systemctl" <<'FAKE'
#!/bin/sh
[ "$1" = "is-active" ] || exit 0
name=$3
for d in ${FAKE_DOWN:-}; do
    [ "$d" = "$name" ] && exit 3
done
exit 0
FAKE
cat > "$TMP/bin/logger" <<'FAKE'
#!/bin/sh
exit 0
FAKE
chmod +x "$TMP/bin/systemctl" "$TMP/bin/logger"
export PATH="$TMP/bin:$PATH"

# Test configuration; thresholds can still be overridden from the environment
export TOOLKIT_TEST_DIR="$TMP"
cat > "$TMP/test.conf" <<'FAKE'
CPU_WARN="${CPU_WARN:-101}"
MEM_WARN="${MEM_WARN:-101}"
DISK_WARN="${DISK_WARN:-101}"
SERVICES=(ssh cron nginx)
LOG_DIR="$TOOLKIT_TEST_DIR/logs"
BACKUP_SOURCES=("$TOOLKIT_TEST_DIR/data")
BACKUP_DIR="$TOOLKIT_TEST_DIR/backups"
BACKUP_RETENTION_DAYS=7
ALERT_COOLDOWN_MIN=30
FAKE
export TOOLKIT_CONF="$TMP/test.conf"

pass=0
fail=0

# check DESCRIPTION COMMAND...   passes when the command succeeds
check() {
    local desc=$1
    shift
    if "$@" > /dev/null 2>&1; then
        echo "  PASS  $desc"
        pass=$((pass + 1))
    else
        echo "  FAIL  $desc"
        fail=$((fail + 1))
    fi
}

# check_fails DESCRIPTION COMMAND...   passes when the command fails
check_fails() {
    local desc=$1
    shift
    if "$@" > /dev/null 2>&1; then
        echo "  FAIL  $desc"
        fail=$((fail + 1))
    else
        echo "  PASS  $desc"
        pass=$((pass + 1))
    fi
}

reset_state() {
    rm -rf "$TMP/logs/.alert-state"
    : > "$TMP/logs/alerts.log"
}

echo "health_check.sh"
reset_state
check "passes when everything is healthy" "$S/health_check.sh" -q
reset_state
check_fails "exits 1 when a service is down" env FAKE_DOWN=nginx "$S/health_check.sh" -q
check "writes an alert for the stopped service" grep -q "Service nginx is not running" "$TMP/logs/alerts.log"
reset_state
check_fails "exits 1 when the CPU threshold is exceeded" env CPU_WARN=0 "$S/health_check.sh" -q

echo "alert.sh"
reset_state
"$S/alert.sh" demo "first" > /dev/null 2>&1
"$S/alert.sh" demo "second" > /dev/null 2>&1
check "cooldown suppresses repeated alerts" test "$(grep -c ALERT "$TMP/logs/alerts.log")" -eq 1

echo "backup.sh"
check "backup run succeeds" "$S/backup.sh" run
check "backup creates an archive" test -n "$(find "$TMP/backups" -name 'backup-*.tar.gz' -print -quit)"
check "backup writes a checksum file" test -n "$(find "$TMP/backups" -name 'backup-*.sha256' -print -quit)"
check "verify passes on a good backup" "$S/backup.sh" verify
check "restore test passes" "$S/backup.sh" restore-test

latest=$(find "$TMP/backups" -name 'backup-*.tar.gz' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
mkdir -p "$TMP/corrupt"
cp "$latest" "$latest.sha256" "$TMP/corrupt/"
printf 'X' >> "$TMP/corrupt/$(basename "$latest")"
check_fails "verify detects a corrupted backup" "$S/backup.sh" verify "$TMP/corrupt/$(basename "$latest")"

flock /tmp/ops-toolkit-backup.lock sleep 3 &
sleep 1
check_fails "a second backup is refused while one is running" "$S/backup.sh" run
wait

touch -d "10 days ago" "$TMP/backups/backup-20200101-000000.tar.gz" "$TMP/backups/backup-20200101-000000.tar.gz.sha256"
"$S/backup.sh" run > /dev/null 2>&1
check "retention removes old backups" test ! -e "$TMP/backups/backup-20200101-000000.tar.gz"

echo "log_report.sh"
"$TESTS_DIR/make_sample_logs.sh" "$TMP/sample" > /dev/null
reset_state
NGINX_ACCESS_LOG="$TMP/sample/access.log" AUTH_LOG="$TMP/sample/auth.log" \
    REPORT_DIR="$TMP/reports" "$S/log_report.sh" -q > /dev/null 2>&1
report=$(find "$TMP/reports" -name 'log-report-*.md' -print -quit)
check "report counts the failed logins" grep -q "Failed password attempts: 48" "$report"
check "report counts the web requests" grep -q "Total requests: 99" "$report"
check "report finds the scanner requests" grep -q "Suspicious scanner requests: 4" "$report"
check "brute-force alert is raised" grep -q "42 failed logins from 198.51.100.7" "$TMP/logs/alerts.log"

echo
echo "Passed: $pass   Failed: $fail"
[ "$fail" -eq 0 ]
