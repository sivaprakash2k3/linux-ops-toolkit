#!/usr/bin/env bash
# backup.sh - compressed backups with checksum, retention and restore test
#
# Usage: backup.sh [run|list|verify [FILE]|restore-test [FILE]]
#   run           create a new backup (default)
#   list          show existing backups
#   verify        check a backup's checksum and archive integrity (default: newest)
#   restore-test  extract a backup to a temp folder and compare it with the sources

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/common.sh"

BACKUP_DIR="${BACKUP_DIR:-$HOME/toolkit-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
[ -z "${BACKUP_SOURCES+x}" ] && BACKUP_SOURCES=("$HOME/demo-data")
LOG_FILE="$LOG_DIR/backup.log"
LOCK_FILE=/tmp/ops-toolkit-backup.lock

log() { echo "$(timestamp) $*" | tee -a "$LOG_FILE"; }

# Log the error, raise an alert, and stop
fail() {
    log "ERROR: $*"
    "$SCRIPT_DIR/alert.sh" backup-failed "Backup problem: $*"
    exit 1
}

# Path of the newest backup archive (empty if there is none)
latest_backup() {
    find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -n 1 | cut -d' ' -f2-
}

do_backup() {
    # Only one backup at a time
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log "ERROR: another backup is already running"
        exit 1
    fi

    mkdir -p "$BACKUP_DIR" || fail "cannot create $BACKUP_DIR"

    local src
    for src in "${BACKUP_SOURCES[@]}"; do
        [ -e "$src" ] || fail "source not found: $src"
    done

    local name archive rc size
    name="backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    archive="$BACKUP_DIR/$name"

    log "Backing up: ${BACKUP_SOURCES[*]}"
    tar -czf "$archive" "${BACKUP_SOURCES[@]}" 2>> "$LOG_FILE"
    rc=$?
    # tar exits 1 when a file changed while it was read; that is only a warning
    if [ "$rc" -gt 1 ]; then
        rm -f "$archive"
        fail "tar failed with exit code $rc"
    fi

    ( cd "$BACKUP_DIR" && sha256sum "$name" > "$name.sha256" ) \
        || fail "could not write checksum for $name"
    tar -tzf "$archive" > /dev/null 2>&1 || fail "archive $name failed its integrity test"

    size=$(du -h "$archive" | cut -f1)
    log "Created $name ($size) with checksum"

    # Retention: delete backups (and checksums) older than N days
    local removed
    removed=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
        \( -name 'backup-*.tar.gz' -o -name 'backup-*.tar.gz.sha256' \) \
        -mtime +"$BACKUP_RETENTION_DAYS" -print -delete | wc -l)
    log "Retention: removed $removed old file(s) (older than $BACKUP_RETENTION_DAYS days)"
    log "Backup complete"
}

do_list() {
    find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' \
        -printf '%TY-%Tm-%Td %TH:%TM  %10s bytes  %f\n' 2>/dev/null | sort
}

do_verify() {
    local archive=${1:-}
    [ -n "$archive" ] || archive=$(latest_backup)
    [ -n "$archive" ] && [ -f "$archive" ] || fail "no backup file to verify"

    local dir base
    dir=$(dirname "$archive")
    base=$(basename "$archive")
    log "Verifying $base"

    [ -f "$dir/$base.sha256" ] || fail "checksum file missing for $base"
    if ! ( cd "$dir" && sha256sum -c --quiet "$base.sha256" ); then
        fail "checksum mismatch for $base (the file is corrupted)"
    fi
    tar -tzf "$archive" > /dev/null 2>&1 || fail "archive $base cannot be read"
    log "OK: $base passed the checksum and archive test"
}

do_restore_test() {
    local archive=${1:-}
    [ -n "$archive" ] || archive=$(latest_backup)
    [ -n "$archive" ] && [ -f "$archive" ] || fail "no backup file to test"

    local tmp
    tmp=$(mktemp -d)
    log "Restore test: extracting $(basename "$archive") to a temporary folder"
    if ! tar -xzf "$archive" -C "$tmp"; then
        rm -rf "$tmp"
        fail "restore test failed: could not extract $(basename "$archive")"
    fi

    local src failed=0
    for src in "${BACKUP_SOURCES[@]}"; do
        if diff -rq --no-dereference "$src" "$tmp$src" > /dev/null 2>&1; then
            log "  OK    $src matches the backup"
        else
            log "  DIFF  $src differs from the backup (it may have changed since)"
            failed=1
        fi
    done
    rm -rf "$tmp"

    if [ "$failed" -ne 0 ]; then
        log "Restore test finished with differences"
        exit 1
    fi
    log "Restore test passed"
}

cmd=${1:-run}
case "$cmd" in
    run)          do_backup ;;
    list)         do_list ;;
    verify)       shift; do_verify "${1:-}" ;;
    restore-test) shift; do_restore_test "${1:-}" ;;
    *)            echo "Usage: $0 [run|list|verify [FILE]|restore-test [FILE]]" >&2; exit 2 ;;
esac
