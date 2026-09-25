#!/bin/bash
# Stage 01c: apply source overlay(s) from patches/ onto the extracted modules.
#
# patches/eliteredux-source/** mirrors paths inside
# modules/06-eliteredux-source/ and is copied over it after extraction.
# This is how source-level fixes (e.g. the codegen batching/determinism
# work) travel with this repo while modules/ stays a pristine, regenerable
# extraction of the release archive.
#
# Idempotent: re-running just re-copies the same files. Removing a file from
# patches/ does NOT restore the module original - use ./run.sh --force to
# re-extract.
set -u -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$ROOT/patches"
SRC="$ROOT/modules/06-eliteredux-source"

[ -d "$SRC" ] || { echo "[01c] ERROR: $SRC not found - run 00-extract first"; exit 1; }

if [ ! -d "$PATCHES" ] || [ -z "$(find "$PATCHES" -type f -print -quit 2>/dev/null)" ]; then
    echo "[01c] no patches present, nothing to apply"
    exit 0
fi

count=0
( cd "$PATCHES/eliteredux-source" 2>/dev/null || exit 0
  find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    mkdir -p "$SRC/$(dirname "$rel")"
    cp -f "$PATCHES/eliteredux-source/$rel" "$SRC/$rel"
    echo "[01c] applied: $rel"
    count=$((count+1))
done

# Verify the overlay actually landed (marker from the codegen fixes)
if grep -q "BatchGenerator" "$SRC/tools/codegen/makefile" 2>/dev/null; then
    echo "[01c] codegen overlay verified (batched GENERATE present)"
else
    echo "[01c] WARNING: expected codegen overlay marker not found"
fi
echo "[01c] patches applied"
