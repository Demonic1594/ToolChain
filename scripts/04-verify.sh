#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/02-env.sh"

ROM_SRC="$MOD_SRC/pokeemerald_modern.gba"
[ -f "$ROM_SRC" ] || { echo "[04] ERROR: $ROM_SRC not found (run 03-build first)"; exit 1; }

# Data-pipeline sanity: a ROM can boot fine while missing generated game data
# (the stale-master failure mode in docs/README-SETUP.md - it compiled, booted,
# and was silently wrong). Assert the codegen output actually landed.
ABILITIES="$MOD_SRC/src/abilities.cc"
if grep -q "FLUFFIEST_ONE" "$ABILITIES" 2>/dev/null; then
    echo "[04] generated ability data present in src/abilities.cc"
else
    echo "[04] ERROR: generated data marker missing from $ABILITIES - codegen pipeline did not run?"
    exit 1
fi
ROM_SZ=$(stat -c %s "$ROM_SRC")
# ~23.7 MB of content, padded on disk to 32 MiB - both are healthy shapes
if [ "$ROM_SZ" -ge 23000000 ] && [ "$ROM_SZ" -le 33554432 ]; then
    echo "[04] ROM size in expected range ($ROM_SZ bytes)"
else
    echo "[04] ERROR: ROM size $ROM_SZ outside sane range (23-33.5 MB) - truncated or wrong build?"
    exit 1
fi
[ -f "$MOD_SRC/pokeemerald_modern.map" ] || { echo "[04] ERROR: pokeemerald_modern.map missing - build incomplete?"; exit 1; }

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
