#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.config/openclaw-tools/config.env"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

GOG_BIN="${GOG_BIN:-gog}"
DEFAULT_TIMEZONE="${DEFAULT_TIMEZONE:-Asia/Taipei}"
DEFAULT_CALENDAR_ID="${DEFAULT_CALENDAR_ID:-primary}"
DEFAULT_GMAIL_LIMIT="${DEFAULT_GMAIL_LIMIT:-10}"
DEFAULT_SHEET_RANGE="${DEFAULT_SHEET_RANGE:-Sheet1!A:Z}"
OPENCLAW_TOOLS_LOG="${OPENCLAW_TOOLS_LOG:-${HOME}/.config/openclaw-tools/tools.log}"

mkdir -p "$(dirname "$OPENCLAW_TOOLS_LOG")"

log() {
  local msg="$*"
  printf '[%s] %s\n' "$(date '+%F %T')" "$msg" >> "$OPENCLAW_TOOLS_LOG"
}

die() {
  log "ERROR: $*"
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

validate_nonempty() {
  local name="${1:-arg}"
  local value="${2:-}"
  [[ -n "$value" ]] || die "missing required value: $name"
}

validate_rfc3339() {
  local ts="${1:-}"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z)$ ]] \
    || die "invalid RFC3339 timestamp: $ts"
}

run_cmd() {
  log "RUN: $*"
  "$@"
}
