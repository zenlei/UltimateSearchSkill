#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# import-multi-keys.sh — batch import Grok SSO tokens into grok2api
#
# Why:
# - export_sso.txt can be huge (thousands of tokens)
# - a single POST may exceed request/body limits or time out
# - this script imports in batches and (safely) merges with existing pool
#
# Dependencies: bash, curl, jq
# =========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

die() { error "$*"; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  bash scripts/import-multi-keys.sh [options]

Options:
  --file PATH           Path to export_sso.txt (default: ./export_sso.txt)
  --pool NAME           Token pool name: ssoBasic | ssoSuper (default: ssoBasic)
  --batch-size N        Tokens per batch (default: 100)
  --url URL             grok2api base URL (default: http://127.0.0.1:${GROK2API_PORT:-8100})
  --app-key KEY         grok2api admin key (default: GROK2API_APP_KEY from .env)
  --no-merge            Do NOT merge with existing pool (risk: may overwrite depending on grok2api behavior)
  --dry-run             Parse tokens and show counts only; do not call API
  --help                Show help

Examples:
  bash scripts/import-multi-keys.sh
  bash scripts/import-multi-keys.sh --batch-size 50
  bash scripts/import-multi-keys.sh --pool ssoSuper --file ./export_sso_super.txt
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

trim() {
  # shellcheck disable=SC2001
  echo "$1" | sed -e 's/^\s\+//;s/\s\+$//'
}

# -------------------------
# Load .env
# -------------------------
if [[ -f "$PROJECT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$PROJECT_DIR/.env"; set +a
else
  warn ".env not found at $PROJECT_DIR/.env — will rely on CLI args/env vars"
fi

# -------------------------
# Args
# -------------------------
TOKEN_FILE="$PROJECT_DIR/export_sso.txt"
POOL="ssoBasic"
BATCH_SIZE=100
BASE_URL=""
APP_KEY="${GROK2API_APP_KEY:-}"
MERGE_MODE=1
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      TOKEN_FILE="$2"; shift 2 ;;
    --pool)
      POOL="$2"; shift 2 ;;
    --batch-size)
      BATCH_SIZE="$2"; shift 2 ;;
    --url)
      BASE_URL="$2"; shift 2 ;;
    --app-key)
      APP_KEY="$2"; shift 2 ;;
    --no-merge)
      MERGE_MODE=0; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ "$POOL" == "ssoBasic" || "$POOL" == "ssoSuper" ]] || die "--pool must be ssoBasic or ssoSuper"
[[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || die "--batch-size must be an integer"
(( BATCH_SIZE > 0 )) || die "--batch-size must be > 0"

PORT="${GROK2API_PORT:-8100}"
BASE_URL="${BASE_URL:-http://127.0.0.1:${PORT}}"

[[ -f "$TOKEN_FILE" ]] || die "Token file not found: $TOKEN_FILE"
[[ -n "$APP_KEY" ]] || die "Missing grok2api admin key. Set GROK2API_APP_KEY in .env or pass --app-key"

need_cmd curl
need_cmd jq

# -------------------------
# Helpers for API
# -------------------------
api_get_tokens() {
  curl -sS \
    -H "Authorization: Bearer $APP_KEY" \
    "$BASE_URL/v1/admin/tokens"
}

api_post_tokens() {
  # NOTE: body can be very large (thousands of tokens). Passing it as a command-line
  # argument will hit Linux ARG_MAX => "/usr/bin/curl: argument list too long".
  # So we always write JSON to a temp file and use --data-binary @file.
  local body="$1"
  local resp http body_only tmp curl_rc

  tmp="$(mktemp)"
  printf '%s' "$body" > "$tmp"

  set +e
  resp=$(curl -sS -w "\n%{http_code}" \
    -X POST "$BASE_URL/v1/admin/tokens" \
    -H "Authorization: Bearer $APP_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "@$tmp")
  curl_rc=$?
  set -e

  rm -f -- "$tmp"

  if [[ "$curl_rc" -ne 0 ]]; then
    die "curl failed with exit code $curl_rc"
  fi

  http=$(echo "$resp" | tail -1)
  body_only=$(echo "$resp" | sed '$d')

  if [[ "$http" != "200" ]]; then
    # Do not echo request content
    die "Import failed (HTTP $http): $body_only"
  fi
}

pool_count() {
  api_get_tokens | jq -r --arg pool "$POOL" '.[$pool] | length // 0'
}

# -------------------------
# Parse token file in batches
# -------------------------
TOTAL_LINES=$(grep -vE '^(\s*#|\s*$)' "$TOKEN_FILE" | wc -l | tr -d ' ')
info "Token file: $TOKEN_FILE"
info "Non-empty lines: $TOTAL_LINES"
info "Pool: $POOL"
info "Batch size: $BATCH_SIZE"
info "grok2api: $BASE_URL"

if [[ "$DRY_RUN" == "1" ]]; then
  ok "Dry run: no API calls."
  exit 0
fi

# Basic connectivity check
api_get_tokens >/dev/null || die "Cannot reach grok2api at $BASE_URL (or auth failed)"

START_COUNT=$(pool_count)
info "Current pool count: $START_COUNT"

batch_tmp="$(mktemp)"
trap 'rm -f "$batch_tmp"' EXIT

BATCH_NO=0
BATCH_ITEMS=0
IMPORTED=0

flush_batch() {
  if (( BATCH_ITEMS == 0 )); then
    return
  fi

  BATCH_NO=$((BATCH_NO + 1))
  info "Importing batch #$BATCH_NO (items=$BATCH_ITEMS)..."

  # Convert batch tmp file -> JSON array
  local new_json existing_json merged_json body
  new_json=$(jq -R 'select(length>0)' "$batch_tmp" | jq -s '.')

  if [[ "$MERGE_MODE" == "1" ]]; then
    existing_json=$(api_get_tokens | jq -c --arg pool "$POOL" '.[$pool] // []')
    merged_json=$(jq -n --argjson a "$existing_json" --argjson b "$new_json" '$a + $b | unique')
  else
    merged_json="$new_json"
  fi

  body=$(jq -n --arg pool "$POOL" --argjson arr "$merged_json" '{($pool): $arr}')
  api_post_tokens "$body"

  local now
  now=$(pool_count)
  ok "Batch #$BATCH_NO done. Current pool count: $now"

  IMPORTED=$((IMPORTED + BATCH_ITEMS))
  : > "$batch_tmp"
  BATCH_ITEMS=0
}

while IFS= read -r raw || [[ -n "$raw" ]]; do
  raw="$(trim "$raw")"
  [[ -z "$raw" || "$raw" == \#* ]] && continue

  # strip optional prefix
  raw="${raw#sso=}"

  # write token as-is (no logging)
  printf '%s\n' "$raw" >> "$batch_tmp"
  BATCH_ITEMS=$((BATCH_ITEMS + 1))

  if (( BATCH_ITEMS >= BATCH_SIZE )); then
    flush_batch
  fi

done < "$TOKEN_FILE"

flush_batch

END_COUNT=$(pool_count)
ok "All done. Imported lines processed: $IMPORTED"
ok "Pool count: $START_COUNT -> $END_COUNT"

if (( END_COUNT < START_COUNT )); then
  warn "Pool count decreased. If grok2api treats POST as overwrite, use merge mode (default) and re-run."
fi
