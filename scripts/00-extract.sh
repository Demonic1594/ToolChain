#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$ROOT/archives"
STAGING="$ROOT/modules/.staging"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -d "$ROOT/modules/06-eliteredux-source" ] && [ "$FORCE" -eq 0 ]; then
    echo "[00] modules/ already populated - skipping (use --force to re-extract)"
    exit 0
fi

EXPECT=$(sed -n 's/^# joined-sha256=//p' "$ARCH/SHA256SUMS")
ZIP="$ARCH/pkmn-ER-toolchain.zip"
if [ -f "$ZIP" ]; then
    echo "[00] Using existing joined archive: $ZIP"
elif ls "$ARCH"/pkmn-ER-toolchain.zip.part-* >/dev/null 2>&1; then
    echo "[00] Verifying part checksums..."
    (cd "$ARCH" && grep 'part-' SHA256SUMS | sha256sum -c -)
    echo "[00] Joining parts..."
    cat "$ARCH"/pkmn-ER-toolchain.zip.part-* > "$ZIP"
else
    URL="${TOOLCHAIN_ARCHIVE_URL:-https://github.com/Demonic1594/ToolChain/releases/download/toolchain-v1/pkmn-ER-toolchain.zip}"
    echo "[00] No local archive - downloading $URL"
    command -v curl >/dev/null || { echo "[00] ERROR: curl needed to download the toolchain (or provide archives/ parts)"; exit 1; }
    mkdir -p "$ARCH"
    curl -fL --retry 3 --retry-delay 5 -o "$ZIP.tmp" "$URL" || { echo "[00] ERROR: download failed"; rm -f "$ZIP.tmp"; exit 1; }
    mv "$ZIP.tmp" "$ZIP"
fi

echo "[00] Verifying joined archive hash..."
GOT=$(sha256sum "$ZIP" | cut -d' ' -f1)
[ "$EXPECT" = "$GOT" ] || { echo "[00] ERROR: joined hash mismatch"; exit 1; }

[ -d "$ROOT/modules/.backup" ] && echo "[00] NOTE: backups from a previous --force live in modules/.backup/"
mkdir -p "$STAGING"

echo "[00] Extracting (python3 LZMA-capable)..."
python3 - "$ZIP" "$STAGING/x" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
z.extractall(sys.argv[2])
print(f"[00] extracted {len(z.namelist())} entries")
PY

SRC="$STAGING/x/pkmn-ER-toolchain-slim"
map_dir() {
    if [ -d "$SRC/$1" ]; then
        if [ -e "$ROOT/modules/$2" ] || [ -L "$ROOT/modules/$2" ]; then
            # keep exactly one backup generation: --force must not silently
            # destroy local edits (modules/ is gitignored, no git safety net)
            rm -rf "$ROOT/modules/.backup/$2".* 2>/dev/null
            BK="$ROOT/modules/.backup/$2.$(date +%s)"
            mkdir -p "$(dirname "$BK")"
            mv "$ROOT/modules/$2" "$BK"
            echo "[00] --force: existing modules/$2 moved to $BK"
        fi
        mv "$SRC/$1" "$ROOT/modules/$2"
        echo "[00] $1 -> modules/$2"
    fi
}
map_dir binutils-arm-none-eabi 01-binutils
map_dir gcc-arm-none-eabi 02-gcc
map_dir jdk-21 03-jdk
map_dir kotlinc 04-kotlinc
mkdir -p "$ROOT/modules/05-python-mgba"
map_dir python3.11-mgba 05-python-mgba/python3.11-mgba
map_dir mgba-libs 05-python-mgba/mgba-libs
map_dir eliteredux-source 06-eliteredux-source
map_dir tools-notes 07-tools-notes
map_dir agbcc 08-agbcc
map_dir reference-roms 09-reference-roms

# NOTE: the archive also ships flat-layout README*.md; intentionally NOT copied
# over docs/ - that would clobber the repo's restructured documentation.
rm -rf "$STAGING"
echo "[00] done"
