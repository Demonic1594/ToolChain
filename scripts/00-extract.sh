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

ls "$ARCH"/pkmn-ER-toolchain.zip.part-* >/dev/null 2>&1 || { echo "[00] ERROR: no archive parts in $ARCH"; exit 1; }

echo "[00] Verifying part checksums..."
(cd "$ARCH" && grep 'part-' SHA256SUMS | sha256sum -c -)

echo "[00] Verifying joined archive hash..."
EXPECT=$(sed -n 's/^# joined-sha256=//p' "$ARCH/SHA256SUMS")
GOT=$(cat "$ARCH"/pkmn-ER-toolchain.zip.part-* | sha256sum | cut -d' ' -f1)
[ "$EXPECT" = "$GOT" ] || { echo "[00] ERROR: joined hash mismatch"; exit 1; }

mkdir -p "$STAGING"
cat "$ARCH"/pkmn-ER-toolchain.zip.part-* > "$STAGING/toolchain.zip"

echo "[00] Extracting (python3 LZMA-capable)..."
python3 - "$STAGING/toolchain.zip" "$STAGING/x" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
z.extractall(sys.argv[2])
print(f"[00] extracted {len(z.namelist())} entries")
PY

SRC="$STAGING/x/pkmn-ER-toolchain-slim"
map_dir() {
    if [ -d "$SRC/$1" ]; then
        rm -rf "$ROOT/modules/$2"
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

for f in README.md README-SETUP.md README-PROJECT.md; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$ROOT/docs/$f"
done

rm -rf "$STAGING"
echo "[00] done"
