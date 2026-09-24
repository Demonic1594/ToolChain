#!/bin/bash
# Repo-tracked twin of modules/07-tools-notes/check-compile.sh (the archive
# copy is gitignored and lost on --force re-extraction).
# Compile-check individual source files (no link, no full build) using the
# exact Makefile flags incl. -Werror.
# Usage: bash scripts/check-compile.sh src/battle_util.c src/abilities.cc ...   (prints OK or the first errors)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/02-env.sh" >/dev/null 2>&1
cd "$ROOT/modules/06-eliteredux-source"
P=arm-none-eabi-
CPPF="-iquote include -iquote gflib -Wno-trigraphs -DMODERN=1"
CF="-Wall -Wextra -Werror -Wno-int-in-bool-context -Wno-missing-braces -Wno-unused-parameter -Wno-switch -Wno-unused-local-typedefs -Wno-missing-field-initializers -Wno-ignored-qualifiers -Wno-sign-compare -mthumb -mthumb-interwork -O2 -mabi=apcs-gnu -mtune=arm7tdmi -march=armv4t -fshort-enums -fno-toplevel-reorder -Wno-unused-function -Wno-pointer-sign -Wno-unused-label -std=gnu2x -Wno-builtin-declaration-mismatch -fno-strict-aliasing"
CPPF2="-Wall -Wextra -Werror -fno-exceptions -Wno-sign-compare -Wno-switch -Wno-missing-field-initializers -fno-rtti -mthumb -mthumb-interwork -O2 -mabi=apcs-gnu -mtune=arm7tdmi -march=armv4t -fshort-enums -Wunreachable-code -std=gnu++2b -Wno-builtin-declaration-mismatch -fno-strict-aliasing"
CC1=$(${P}gcc --print-prog-name=cc1); CC1P=$(${P}gcc --print-prog-name=cc1plus)
for f in "$@"; do
  if [[ $f == *.cc ]]; then C="$CC1P -quiet $CPPF2"; else C="$CC1 -quiet $CF"; fi
  out=$( ( ${P}cpp $CPPF $f | tools/preproc/preproc $f charmap.txt -i | $C -o /dev/null - ) 2>&1 | grep -E "error|Error" | head -4)
  echo "$f: ${out:-OK}"
done
