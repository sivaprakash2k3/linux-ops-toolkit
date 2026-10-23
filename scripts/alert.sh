#!/usr/bin/env bash
# alert.sh KEY MESSAGE - record an alert, with a cooldown to avoid repeats

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/common.sh"

STATE_DIR="$LOG_DIR/.alert-state"
COOLDOWN_MIN="${ALERT_COOLDOWN_MIN:-30}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 KEY MESSAGE" >&2
    exit 2
fi
key=$1
shift
message=$*

mkdir -p "$STATE_DIR"
stamp="$STATE_DIR/$key"

# Skip if the same alert was sent recently
if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin -"$COOLDOWN_MIN" 2>/dev/null)" ]; then
    exit 0
fi
touch "$stamp"

line="$(timestamp) ALERT [$(hostname)] $message"
echo "$line" >> "$LOG_DIR/alerts.log"
logger -t ops-toolkit -p user.warning "$message"

if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    curl -fsS -m 10 -H 'Content-Type: application/json' \
        -d "{\"${ALERT_WEBHOOK_FIELD:-content}\": \"$line\"}" \
        "$ALERT_WEBHOOK_URL" > /dev/null \
        || echo "$(timestamp) webhook delivery failed" >> "$LOG_DIR/alerts.log"
fi
