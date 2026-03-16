#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
PORT_FILE="$TMP_DIR/port"
SERVER_LOG="$TMP_DIR/server.log"
EXPECTED_AUTH="Bearer master-test"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

python3 -u - "$PORT_FILE" "$EXPECTED_AUTH" >"$SERVER_LOG" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]
expected_auth = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.headers.get("Authorization") != expected_auth:
            self._send(401, {"error": "bad auth"})
            return

        payload = self._read_json()
        if self.path == "/search":
            self._send(200, {
                "ok": "search",
                "query": payload.get("query"),
                "results": [{"title": "ok", "url": "https://example.com"}]
            })
            return
        if self.path == "/map":
            self._send(200, {
                "ok": "map",
                "links": ["https://example.com/docs"]
            })
            return
        if self.path == "/extract":
            urls = payload.get("urls", [])
            self._send(200, {
                "results": [{"url": url, "raw_content": "fetched"} for url in urls]
            })
            return

        self._send(404, {"error": "not found"})

    def log_message(self, *_args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as fh:
    fh.write(str(server.server_port))
server.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  if [[ -f "$PORT_FILE" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -f "$PORT_FILE" ]]; then
  echo "test server did not start" >&2
  exit 1
fi

PORT="$(cat "$PORT_FILE")"
API_URL="http://127.0.0.1:$PORT"
ISOLATED_SCRIPTS="$TMP_DIR/scripts"
mkdir -p "$ISOLATED_SCRIPTS"
cp "$ROOT_DIR/scripts/tavily-search.sh" "$ISOLATED_SCRIPTS/"
cp "$ROOT_DIR/scripts/web-map.sh" "$ISOLATED_SCRIPTS/"
cp "$ROOT_DIR/scripts/web-fetch.sh" "$ISOLATED_SCRIPTS/"
chmod +x "$ISOLATED_SCRIPTS/"*.sh

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"$'\n'"actual: $haystack"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"$'\n'"actual: $haystack"
}

run_expect_success_with_master() {
  local script_name="$1"
  shift
  local output
  if ! output=$(env -i PATH="$PATH" TAVILY_API_URL="$API_URL" TAVILY_MASTER_KEY="master-test" \
    "$ISOLATED_SCRIPTS/$script_name" "$@" 2>&1); then
    fail "$script_name should succeed with TAVILY_MASTER_KEY"$'\n'"output: $output"
  fi
  printf '%s' "$output"
}

run_expect_fail_with_legacy_key() {
  local script_name="$1"
  shift
  local output
  if output=$(env -i PATH="$PATH" TAVILY_API_URL="$API_URL" TAVILY_API_KEY="master-test" \
    "$ISOLATED_SCRIPTS/$script_name" "$@" 2>&1); then
    fail "$script_name should reject legacy TAVILY_API_KEY"$'\n'"output: $output"
  fi
  printf '%s' "$output"
}

search_output="$(run_expect_success_with_master tavily-search.sh --query test)"
assert_contains "$search_output" '"ok": "search"'
assert_not_contains "$search_output" 'TAVILY_API_KEY'

map_output="$(run_expect_success_with_master web-map.sh --url https://example.com)"
assert_contains "$map_output" '"ok": "map"'
assert_not_contains "$map_output" 'TAVILY_API_KEY'

fetch_output="$(run_expect_success_with_master web-fetch.sh --url https://example.com)"
assert_contains "$fetch_output" '"source": "tavily"'
assert_contains "$fetch_output" '"raw_content": "fetched"'

legacy_search_output="$(run_expect_fail_with_legacy_key tavily-search.sh --query test)"
assert_contains "$legacy_search_output" '未设置 TAVILY_MASTER_KEY'

legacy_map_output="$(run_expect_fail_with_legacy_key web-map.sh --url https://example.com)"
assert_contains "$legacy_map_output" '未设置 TAVILY_MASTER_KEY'

legacy_fetch_output="$(run_expect_fail_with_legacy_key web-fetch.sh --url https://example.com)"
assert_contains "$legacy_fetch_output" '未设置 TAVILY_MASTER_KEY'

echo "PASS: tavily master key migration"
