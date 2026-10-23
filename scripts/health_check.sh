#!/usr/bin/env bash
# health_check.sh - server health report with thresholds, logging and alerts (v2)
#
# Usage: health_check.sh [-q]
#   -q  quiet: write only to the log file (use this from cron)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/common.sh"

CPU_WARN="${CPU_WARN:-80}"
MEM_WARN="${MEM_WARN:-80}"
DISK_WARN="${DISK_WARN:-80}"
[ -z "${SERVICES+x}" ] && SERVICES=(ssh cron)

QUIET=0
while getopts "q" opt; do
    case $opt in
        q) QUIET=1 ;;
        *) echo "Usage: $0 [-q]" >&2; exit 2 ;;
    esac
done

LOG_FILE="$LOG_DIR/health.log"
problems=()

# Print to the screen (unless quiet) and append to the log file
emit() {
    [ "$QUIET" -eq 1 ] || echo "$*"
    echo "$(timestamp) $*" >> "$LOG_FILE"
}

# Average CPU busy percentage over one second, read from /proc/stat
cpu_usage() {
    local u1 n1 s1 i1 w1 q1 sq1 u2 n2 s2 i2 w2 q2 sq2
    read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < /proc/stat
    sleep 1
    read -r _ u2 n2 s2 i2 w2 q2 sq2 _ < /proc/stat
    local total=$(( (u2+n2+s2+i2+w2+q2+sq2) - (u1+n1+s1+i1+w1+q1+sq1) ))
    local idle=$(( (i2+w2) - (i1+w1) ))
    if [ "$total" -le 0 ]; then
        echo 0
        return
    fi
    echo $(( 100 * (total - idle) / total ))
}

# Memory in use (excluding cache), as a percentage
mem_usage() { free | awk '/^Mem:/ {printf "%d", ($2-$7)*100/$2}'; }

# Percentage of the root filesystem that is used
disk_usage() { df -P / | awk 'NR==2 {gsub("%","",$5); print $5}'; }

# check_threshold KEY LABEL VALUE UNIT WARN_LEVEL
check_threshold() {
    local key=$1 label=$2 value=$3 unit=$4 warn=$5 state=OK
    if [ "$value" -ge "$warn" ]; then
        state=WARN
        problems+=("$key|$label at ${value}${unit} (threshold ${warn}${unit})")
    fi
    emit "$(printf '%-12s %5s%s  [%s]' "$label" "$value" "$unit" "$state")"
}

emit "=== Health check on $(hostname) at $(timestamp) ==="
check_threshold cpu  "CPU"    "$(cpu_usage)"  "%" "$CPU_WARN"
check_threshold mem  "Memory" "$(mem_usage)"  "%" "$MEM_WARN"
check_threshold disk "Disk /" "$(disk_usage)" "%" "$DISK_WARN"
emit "Load average: $(cut -d' ' -f1-3 /proc/loadavg) (cores: $(nproc))"

emit "--- Services ---"
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        emit "$(printf '%-12s [OK]' "$svc")"
    else
        emit "$(printf '%-12s [DOWN]' "$svc")"
        problems+=("service-$svc|Service $svc is not running")
    fi
done

if [ "${#problems[@]}" -gt 0 ]; then
    emit "Result: ${#problems[@]} problem(s) found"
    for entry in "${problems[@]}"; do
        "$SCRIPT_DIR/alert.sh" "${entry%%|*}" "${entry#*|}"
    done
    exit 1
fi
emit "Result: all checks passed"
