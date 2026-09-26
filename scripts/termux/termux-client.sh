#!/bin/bash
# Client for the Termux build bridge (run from the and-code PRoot side).
#
#   termux-client.sh health
#   termux-client.sh run  '<shell command>' [cwd]
#   termux-client.sh put  <local-file> <workspace-relative-path>
#   termux-client.sh get  <workspace-relative-path> <local-file>
#   termux-client.sh build [git-ref]     # convenience: native-lane build
#
# Token + port are shared via /sdcard/ToolChain-bridge/token (written by the
# server on first start). Requires: Termux running bridge-server.py.
set -u
PORT="${TERMUX_BRIDGE_PORT:-8042}"
TOKEN_FILE="/sdcard/ToolChain-bridge/token"

die() { echo "[t-client] $*" >&2; exit 1; }
[ -f "$TOKEN_FILE" ] || die "no token file - is the Termux bridge running?"
TOKEN="$(head -1 "$TOKEN_FILE" | tr -d '[:space:]')"
[ -n "$TOKEN" ] || die "empty token file"

req() { curl -s -m "${CURL_TIMEOUT:-7200}" -H "X-Bridge-Token: $TOKEN" "$@"; }

cmd_health() {
  req "http://127.0.0.1:$PORT/health" && echo
}

cmd_run() {
  local command="$1" cwd="${2:-.}"
  req -X POST "http://127.0.0.1:$PORT/run" \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c 'import json,sys; print(json.dumps({"cmd": sys.argv[1], "cwd": sys.argv[2]}))' "$command" "$cwd")" \
    | python3 -c '
import json, sys
r = json.load(sys.stdin)
print(f"[t-client] exit={r.get("exit_code")} duration={r.get("duration_s")}s")
print(r.get("tail", r.get("error", "")))
sys.exit(r.get("exit_code", 1))'
}

cmd_put() {
  local local="$1" rel="$2"
  local b64 size
  size=$(stat -c '%s' "$local" 2>/dev/null) || die "cannot stat $local"
  # stream large files through python to avoid argv limits
  python3 - "$local" "$rel" "$TOKEN" "$PORT" <<'EOF'
import base64, json, sys, urllib.request
local, rel, token, port = sys.argv[1:5]
data = open(local, "rb").read()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/file",
    data=json.dumps({"path": rel, "b64": base64.b64encode(data).decode()}).encode(),
    headers={"Content-Type": "application/json", "X-Bridge-Token": token},
    method="POST")
print(urllib.request.urlopen(req, timeout=600).read().decode())
EOF
}

cmd_get() {
  local rel="$1" local="$2"
  req "http://127.0.0.1:$PORT/file?path=$rel" -o "$local" && \
    echo "[t-client] saved $local ($(stat -c '%s' "$local") bytes)"
}

cmd_build() {
  local ref="${1:-native-gcc}"
  echo "[t-client] native-lane build (ref: $ref)"
  cmd_run "git fetch origin '$ref' && git checkout -q FETCH_HEAD 2>/dev/null || git checkout -q '$ref' && git pull -q origin '$ref' 2>/dev/null; true" "."
  cmd_run "test -d modules/06-eliteredux-source || (./run.sh --only extract && ./run.sh --only exec-bits && ./run.sh --only patches)" "."
  cmd_run "export ER_ARM_TC=native ER_BUILD_JOBS=4; ./run.sh --only env && ./run.sh --only build" "."
  echo "[t-client] fetching ROM..."
  cmd_get "modules/06-eliteredux-source/pokeemerald_modern.gba" \
          "/sdcard/GameBoy/Pokemon - Elite Redux (v2.65.2.3b).gba"
}

case "${1:-}" in
  health) cmd_health ;;
  run)    shift; cmd_run "$@" ;;
  put)    shift; cmd_put "$@" ;;
  get)    shift; cmd_get "$@" ;;
  build)  shift; cmd_build "$@" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
