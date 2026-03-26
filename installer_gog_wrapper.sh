#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/openclaw-tools"
CONFIG_DIR="${HOME}/.config/openclaw-tools"
CONFIG_FILE="${CONFIG_DIR}/config.env"
SOUL_RULES_FILE="${CONFIG_DIR}/SOUL_WRAPPER_RULES.md"
BASHRC="${HOME}/.bashrc"

WORKSPACE_DEFAULT_SOUL="${HOME}/.openclaw/workspace/default/SOUL.md"

mkdir -p "$BASE_DIR"
mkdir -p "$CONFIG_DIR"

write_file() {
  local path="$1"
  cat > "$path"
}

append_path_if_missing() {
  if [[ -f "$BASHRC" ]]; then
    if ! grep -Fq 'export PATH="$HOME/.openclaw/workspace/openclaw-tools:$PATH"' "$BASHRC"; then
      {
        echo
        echo 'export PATH="$HOME/.openclaw/workspace/openclaw-tools:$PATH"'
      } >> "$BASHRC"
    fi
  else
    echo 'export PATH="$HOME/.openclaw/workspace/openclaw-tools:$PATH"' > "$BASHRC"
  fi
}

install_config() {
  write_file "$CONFIG_FILE" <<'EOF'
# Core
GOG_BIN="/usr/local/bin/gog"

# Defaults
DEFAULT_TIMEZONE="Asia/Taipei"
DEFAULT_CALENDAR_ID="primary"

# Gmail defaults
DEFAULT_GMAIL_LIMIT="10"

# Sheets defaults
DEFAULT_SHEET_ID=""
DEFAULT_SHEET_RANGE="Sheet1!A:Z"

# Logging
OPENCLAW_TOOLS_LOG="${HOME}/.config/openclaw-tools/tools.log"
EOF
}

install_common() {
  write_file "${BASE_DIR}/_oc_common.sh" <<'EOF'
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
EOF
}

install_gcal_create() {
  write_file "${BASE_DIR}/gcal_create" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/bin/openclaw-tools/_oc_common.sh"

require_cmd "$GOG_BIN"

show_help() {
  cat <<'HELP'
Usage:
  gcal_create --summary "TITLE" --from "RFC3339" --to "RFC3339" [options]

Required:
  --summary       Event title
  --from          Start time in RFC3339, e.g. 2026-03-26T14:00:00+08:00
  --to            End time in RFC3339, e.g. 2026-03-26T15:00:00+08:00

Optional:
  --calendar      Calendar ID (default: primary)
  --description   Event description
  --location      Event location
  --help          Show this help

Example:
  gcal_create \
    --summary "Hop team" \
    --from "2026-03-26T14:00:00+08:00" \
    --to "2026-03-26T15:00:00+08:00" \
    --description "Review cong viec" \
    --location "Google Meet"
HELP
}

CAL_ID="${DEFAULT_CALENDAR_ID:-primary}"
SUMMARY=""
FROM_TS=""
TO_TS=""
DESCRIPTION=""
LOCATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --calendar)
      CAL_ID="${2:-}"; shift 2 ;;
    --summary)
      SUMMARY="${2:-}"; shift 2 ;;
    --from)
      FROM_TS="${2:-}"; shift 2 ;;
    --to)
      TO_TS="${2:-}"; shift 2 ;;
    --description)
      DESCRIPTION="${2:-}"; shift 2 ;;
    --location)
      LOCATION="${2:-}"; shift 2 ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

validate_nonempty "summary" "$SUMMARY"
validate_nonempty "from" "$FROM_TS"
validate_nonempty "to" "$TO_TS"
validate_rfc3339 "$FROM_TS"
validate_rfc3339 "$TO_TS"

cmd=(
  "$GOG_BIN" calendar create "$CAL_ID"
  --summary "$SUMMARY"
  --from "$FROM_TS"
  --to "$TO_TS"
)

[[ -n "$DESCRIPTION" ]] && cmd+=(--description "$DESCRIPTION")
[[ -n "$LOCATION" ]] && cmd+=(--location "$LOCATION")

run_cmd "${cmd[@]}"
EOF
}

install_gcal_list() {
  write_file "${BASE_DIR}/gcal_list" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/bin/openclaw-tools/_oc_common.sh"

require_cmd "$GOG_BIN"

show_help() {
  cat <<'HELP'
Usage:
  gcal_list [options]

Optional:
  --calendar   Calendar ID (default: primary)
  --help       Show this help

Example:
  gcal_list
  gcal_list --calendar primary
HELP
}

CAL_ID="${DEFAULT_CALENDAR_ID:-primary}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --calendar)
      CAL_ID="${2:-}"; shift 2 ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

run_cmd "$GOG_BIN" calendar list "$CAL_ID"
EOF
}

install_gmail_send_safe() {
  write_file "${BASE_DIR}/gmail_send_safe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/bin/openclaw-tools/_oc_common.sh"

require_cmd "$GOG_BIN"

show_help() {
  cat <<'HELP'
Usage:
  gmail_send_safe --to "EMAIL" --subject "TEXT" --body-file "/path/body.txt"

Required:
  --to          Recipient email
  --subject     Email subject
  --body-file   Path to plain text body file

Optional:
  --help        Show this help

Notes:
  This wrapper assumes gog supports:
    gog gmail send --to ... --subject ... --body-file ...
  If your gog version differs, only this wrapper needs adjustment.
HELP
}

TO_ADDR=""
SUBJECT=""
BODY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      TO_ADDR="${2:-}"; shift 2 ;;
    --subject)
      SUBJECT="${2:-}"; shift 2 ;;
    --body-file)
      BODY_FILE="${2:-}"; shift 2 ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

validate_nonempty "to" "$TO_ADDR"
validate_nonempty "subject" "$SUBJECT"
validate_nonempty "body_file" "$BODY_FILE"
require_file "$BODY_FILE"

run_cmd "$GOG_BIN" gmail send \
  --to "$TO_ADDR" \
  --subject "$SUBJECT" \
  --body-file "$BODY_FILE"
EOF
}

install_gmail_read() {
  write_file "${BASE_DIR}/gmail_read" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/bin/openclaw-tools/_oc_common.sh"

require_cmd "$GOG_BIN"

show_help() {
  cat <<'HELP'
Usage:
  gmail_read --query "GMAIL_QUERY" [options]

Required:
  --query       Gmail search query

Optional:
  --limit       Max results (default from config, usually 10)
  --help        Show this help

Example:
  gmail_read --query 'from:boss@example.com newer_than:7d' --limit 5
HELP
}

QUERY=""
LIMIT="${DEFAULT_GMAIL_LIMIT:-10}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="${2:-}"; shift 2 ;;
    --limit)
      LIMIT="${2:-}"; shift 2 ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

validate_nonempty "query" "$QUERY"

run_cmd "$GOG_BIN" gmail list \
  --query "$QUERY" \
  --limit "$LIMIT"
EOF
}

install_gsheet_append_safe() {
  write_file "${BASE_DIR}/gsheet_append_safe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/bin/openclaw-tools/_oc_common.sh"

require_cmd "$GOG_BIN"

show_help() {
  cat <<'HELP'
Usage:
  gsheet_append_safe --sheet-id "ID" --range "Sheet1!A:D" --values-file "/path/row.json"

Required:
  --sheet-id      Spreadsheet ID
  --range         Range name, e.g. Sheet1!A:D
  --values-file   Path to JSON file

Optional:
  --help          Show this help

Example values file:
  [["2026-03-25","Lunch","-120","TWD"]]
HELP
}

SHEET_ID="${DEFAULT_SHEET_ID:-}"
RANGE_NAME="${DEFAULT_SHEET_RANGE:-Sheet1!A:Z}"
VALUES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sheet-id)
      SHEET_ID="${2:-}"; shift 2 ;;
    --range)
      RANGE_NAME="${2:-}"; shift 2 ;;
    --values-file)
      VALUES_FILE="${2:-}"; shift 2 ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

validate_nonempty "sheet_id" "$SHEET_ID"
validate_nonempty "range" "$RANGE_NAME"
validate_nonempty "values_file" "$VALUES_FILE"
require_file "$VALUES_FILE"

run_cmd "$GOG_BIN" sheets append "$SHEET_ID" \
  --range "$RANGE_NAME" \
  --values-file "$VALUES_FILE"
EOF
}

install_soul_rules() {
  write_file "$SOUL_RULES_FILE" <<'EOF'
## Wrapper Mode - Google Workspace

Always use local wrappers. Never call raw gog directly unless debugging.

Allowed wrapper commands:
- gcal_create
- gcal_list
- gmail_send_safe
- gmail_read
- gsheet_append_safe

### Calendar
Always use this exact command shape:

gcal_create --summary "TITLE" --from "RFC3339" --to "RFC3339" [--description "TEXT"] [--location "TEXT"] [--calendar "ID"]

Rules:
- Do not use positional arguments for gcal_create.
- Default timezone is Asia/Taipei.
- Timed events must use RFC3339 with +08:00.
- Default calendar is primary.
- Prefer omitting --calendar unless a non-default calendar is needed.
- Never call gog calendar create directly.

Correct examples:
gcal_create --summary "Hop team" --from "2026-03-26T14:00:00+08:00" --to "2026-03-26T15:00:00+08:00"
gcal_create --summary "Hop khach hang" --from "2026-03-28T14:00:00+08:00" --to "2026-03-28T15:30:00+08:00" --location "Google Meet"
gcal_create --summary "Kham benh" --from "2026-03-27T09:00:00+08:00" --to "2026-03-27T10:00:00+08:00" --description "Mang theo the BHYT"

Incorrect examples:
gcal_create primary "Hop" "2026-03-28T14:00:00+08:00" "2026-03-28T15:00:00+08:00"
gog calendar create primary --summary "Hop" --from "2026-03-28T14:00:00+08:00" --to "2026-03-28T15:00:00+08:00"

### Calendar list
Use:
gcal_list [--calendar "ID"]

### Gmail send
Always use:
gmail_send_safe --to "EMAIL" --subject "TEXT" --body-file "/tmp/body.txt"

Rules:
- First write email content to a plain text temp file.
- Then call gmail_send_safe.
- Never send raw gog gmail commands unless debugging.

### Gmail read
Always use:
gmail_read --query "GMAIL_QUERY" [--limit "N"]

### Sheets append
Always use:
gsheet_append_safe --sheet-id "ID" --range "Sheet1!A:D" --values-file "/tmp/row.json"

Rules:
- First write row data to a JSON temp file.
- Then call gsheet_append_safe.
- Never call raw gog sheets append directly.

### Response style
Keep responses concise:
- action taken
- target used
- result

### Error style
If a wrapper returns an error:
- report the raw error briefly
- do not invent a fix
- do not switch to raw gog automatically
EOF
}

apply_soul_rules() {
  local soul_path=""
  if [[ -f "$WORKSPACE_DEFAULT_SOUL" ]]; then
    soul_path="$WORKSPACE_DEFAULT_SOUL"
  fi

  if [[ -n "$soul_path" ]]; then
    if ! grep -Fq "## Wrapper Mode - Google Workspace" "$soul_path"; then
      {
        echo
        echo "---"
        echo
        cat "$SOUL_RULES_FILE"
      } >> "$soul_path"
      echo "Applied wrapper rules to: $soul_path"
    else
      echo "SOUL.md already contains wrapper rules: $soul_path"
    fi
  else
    echo "WARNING: default SOUL.md not found at: $WORKSPACE_DEFAULT_SOUL"
    echo "You can manually append:"
    echo "  cat \"$SOUL_RULES_FILE\" >> /path/to/SOUL.md"
  fi
}

set_exec() {
  chmod +x "${BASE_DIR}/_oc_common.sh"
  chmod +x "${BASE_DIR}/gcal_create"
  chmod +x "${BASE_DIR}/gcal_list"
  chmod +x "${BASE_DIR}/gmail_send_safe"
  chmod +x "${BASE_DIR}/gmail_read"
  chmod +x "${BASE_DIR}/gsheet_append_safe"
}

print_done() {
  echo
  echo "Done."
  echo "Created:"
  echo "  ${BASE_DIR}/_oc_common.sh"
  echo "  ${BASE_DIR}/gcal_create"
  echo "  ${BASE_DIR}/gcal_list"
  echo "  ${BASE_DIR}/gmail_send_safe"
  echo "  ${BASE_DIR}/gmail_read"
  echo "  ${BASE_DIR}/gsheet_append_safe"
  echo "  ${CONFIG_FILE}"
  echo "  ${SOUL_RULES_FILE}"
  echo
  echo "Next:"
  echo "  1) source ~/.bashrc"
  echo "  2) kiểm tra config: ${CONFIG_FILE}"
  echo "  3) restart OpenClaw / gateway"
  echo "  4) test:"
  echo '     gcal_create --help'
  echo '     gcal_list --help'
  echo '     gmail_send_safe --help'
  echo '     gmail_read --help'
  echo '     gsheet_append_safe --help'
  echo
  echo "Quick tests:"
  echo '  gcal_list'
  echo '  gcal_create --summary "Test" --from "2026-03-26T10:00:00+08:00" --to "2026-03-26T10:30:00+08:00"'
  echo
  echo "Note:"
  echo "  Gmail/Sheets flags may need slight adjustment depending on your gog version."
}

install_config
install_common
install_gcal_create
install_gcal_list
install_gmail_send_safe
install_gmail_read
install_gsheet_append_safe
install_soul_rules
set_exec
append_path_if_missing
export PATH="$HOME/bin/openclaw-tools:$PATH"
apply_soul_rules
print_done
