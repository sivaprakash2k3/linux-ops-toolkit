#!/usr/bin/env bash
# install.sh - set up (or remove) the Linux Ops Toolkit on this machine
#
# Usage: install.sh [install|uninstall|status] [--dry-run]
#   install    create folders, set permissions, add the cron jobs (default)
#   uninstall  remove the cron jobs (logs, reports and backups are kept)
#   status     show the cron jobs and the latest activity
#   --dry-run  show the resulting crontab without changing anything
#
# Override schedules with HEALTH_SCHEDULE, BACKUP_SCHEDULE and REPORT_SCHEDULE.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$ROOT_DIR/scripts"
# shellcheck source=/dev/null
. "$SCRIPTS/common.sh"

BEGIN_MARK="# BEGIN ops-toolkit (managed by install.sh)"
END_MARK="# END ops-toolkit"
HEALTH_SCHEDULE="${HEALTH_SCHEDULE:-*/5 * * * *}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 20 * * *}"
REPORT_SCHEDULE="${REPORT_SCHEDULE:-30 20 * * *}"

usage() {
    echo "Usage: $0 [install|uninstall|status] [--dry-run]" >&2
    exit 2
}

cmd=install
DRY_RUN=0
for arg in "$@"; do
    case $arg in
        install|uninstall|status) cmd=$arg ;;
        --dry-run) DRY_RUN=1 ;;
        *) usage ;;
    esac
done

check_requirements() {
    local missing=0 c
    for c in bash tar gzip sha256sum flock awk sed find crontab logger journalctl systemctl; do
        if ! command -v "$c" > /dev/null 2>&1; then
            echo "Missing required command: $c"
            missing=1
        fi
    done
    if ! command -v curl > /dev/null 2>&1; then
        echo "Note: curl not found (webhook alerts will not work)"
    fi
    return "$missing"
}

current_cron() { crontab -l 2>/dev/null || true; }

# Remove the managed block and any older hand-added lines that run these scripts
strip_toolkit() {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v s="$SCRIPTS/" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip { next }
        index($0, s) { next }
        { print }'
}

toolkit_block() {
    echo "$BEGIN_MARK"
    echo "$HEALTH_SCHEDULE $SCRIPTS/health_check.sh -q >> $ROOT_DIR/logs/cron.log 2>&1"
    echo "$BACKUP_SCHEDULE $SCRIPTS/backup.sh run >> $ROOT_DIR/logs/cron.log 2>&1"
    echo "$REPORT_SCHEDULE $SCRIPTS/log_report.sh -q >> $ROOT_DIR/logs/cron.log 2>&1"
    echo "$END_MARK"
}

# Newest file matching a name pattern in a folder (empty if none)
newest() {
    find "$1" -maxdepth 1 -name "$2" -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -n 1 | cut -d' ' -f2-
}

do_install() {
    check_requirements || exit 1

    local backup_dir=${BACKUP_DIR:-$HOME/toolkit-backups}
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$ROOT_DIR/logs" "$ROOT_DIR/reports" "$backup_dir"
        chmod +x "$ROOT_DIR/install.sh" "$SCRIPTS"/*.sh "$ROOT_DIR"/tests/*.sh
        echo "Folders ready: logs, reports, $backup_dir"
    fi

    local new
    new=$({ current_cron | strip_toolkit; toolkit_block; })

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Crontab that would be installed:"
        echo "$new"
        return
    fi

    echo "$new" | crontab -
    echo "Cron jobs installed:"
    current_cron | grep -F "$SCRIPTS/"
}

do_uninstall() {
    local new
    new=$(current_cron | strip_toolkit)

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Crontab that would remain:"
        echo "$new"
        return
    fi

    if [ -z "$new" ]; then
        crontab -r 2>/dev/null || true
    else
        echo "$new" | crontab -
    fi
    echo "Toolkit cron jobs removed (logs, reports and backups were kept)."
}

do_status() {
    echo "Toolkit folder: $ROOT_DIR"
    echo
    echo "Cron jobs:"
    current_cron | grep -F "$SCRIPTS/" || echo "  (none installed)"
    echo
    echo "Latest activity:"
    local f
    f=$(tail -n 1 "$LOG_DIR/health.log" 2>/dev/null)
    echo "  Health check : ${f:-(none yet)}"
    f=$(newest "${BACKUP_DIR:-$HOME/toolkit-backups}" 'backup-*.tar.gz')
    echo "  Last backup  : ${f:-(none yet)}"
    f=$(newest "$ROOT_DIR/reports" 'log-report-*.md')
    echo "  Last report  : ${f:-(none yet)}"
    f=$(tail -n 1 "$LOG_DIR/alerts.log" 2>/dev/null)
    echo "  Last alert   : ${f:-(none)}"
}

case "$cmd" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    status)    do_status ;;
esac
