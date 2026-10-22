#!/usr/bin/env bash
# health_check.sh - basic server health report (v1)

set -U

CPU_WARN=80
MEM_WARN=80
DISK_WARN=80
SERVICES=(ssh cron nginx)

problems=0

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

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

# report LABEL VALUE UNIT WARN_LEVEL
report() {
    local label=$1 value=$2 unit=$3 warn=$4 state=OK
    if [ "$value" -ge "$warn" ]; then
        state=WARN
        problems=$((problems + 1))
    fi
    printf '%-12s %5s%s  [%s]\n' "$label" "$value" "$unit" "$state"
}

echo "=== Health check: $(hostname) at $(timestamp) ==="
report "CPU"    "$(cpu_usage)"  "%" "$CPU_WARN"
report "Memory" "$(mem_usage)"  "%" "$MEM_WARN"
report "Disk /" "$(disk_usage)" "%" "$DISK_WARN"
echo "Load average: $(cut -d' ' -f1-3 /proc/loadavg) (cores: $(nproc))"

echo "--- Services ---"
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        printf '%-12s [OK]\n' "$svc"
    else
        printf '%-12s [DOWN]\n' "$svc"
        problems=$((problems + 1))
    fi
done

if [ "$problems" -gt 0 ]; then
    echo "Result: $problems problem(s) found"
    exit 1
fi
echo "Result: all checks passed"
