#!/usr/bin/env bash
# common.sh - shared helpers, sourced by the other scripts

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${TOOLKIT_CONF:-$ROOT_DIR/config/toolkit.conf}"
LOCAL_CONFIG_FILE="${CONFIG_FILE%.conf}.local.conf"

# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
# shellcheck source=/dev/null
[ -f "$LOCAL_CONFIG_FILE" ] && . "$LOCAL_CONFIG_FILE"

LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
mkdir -p "$LOG_DIR"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
