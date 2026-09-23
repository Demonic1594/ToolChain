#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/02-env.sh"

ROM_SRC="$MOD_SRC/pokeemerald_modern.gba"
[ -f "$ROM_SRC" ] || { echo "[04] ERROR: $ROM_SRC not found (run 03-build first)"; exit 1; }
ROM="$ROOT/logs/verify.gba"
cp "$ROM_SRC" "$ROM"
TITLE=$(python3 -c "print(open('$ROM','rb').read(0xB0)[0xA0:0xAC].decode('ascii',errors='replace').rstrip())")
echo "[04] ROM title: '$TITLE'"

FRAMES="${FRAMES:-2500}"
echo "[04] Running mGBA boot test ($FRAMES frames)..."
"$MOD_PY/bin/python3.11" - "$ROM" "$FRAMES" <<'PY'
import sys
import mgba.core, mgba.log
mgba.log.silence()
rom, frames = sys.argv[1], int(sys.argv[2])
core = mgba.core.load_path(rom)
core.autoload_save()
core.reset()
for i in range(frames):
    core.run_frame()
print(f"[04] ran {frames} frames without crash")
PY

ROM_END=$(stat -c %s "$ROM")
echo "[04] VERIFY OK - ROM boots ($ROM_END bytes, $FRAMES frames)"
