#!/data/data/com.termux/files/usr/bin/bash
# Fast single-file compile-check via Termux clang (bridge side)
# Reads a .c file, runs the full preproc|cc1 pipeline, reports errors in seconds.
# Usage: echo 'path/to/file.c' | this-script  OR  this-script path/to/file.c
set -u
TC="$HOME/ToolChain"
W="$TC/clang-llvm/bin"
SRC="${1:-}"

if [ -z "$SRC" ]; then
    echo "usage: $0 <path relative to modules/06-eliteredux-source/>"
    exit 1
fi

cd "$TC/modules/06-eliteredux-source"

unset LD_PRELOAD LD_LIBRARY_PATH
export PATH="$TC/devkitARM/bin:$PATH"

T0=$(date +%s)

# Full pipeline: cpp | preproc | cc1 (compile only, no assembly needed for checking)
arm-none-eabi-cpp -iquote include -iquote gflib -Wno-trigraphs -DMODERN=1 "$SRC" 2>/dev/null \
  | tools/preproc/preproc "$SRC" charmap.txt -i 2>/dev/null \
  | "$W/cc1" -quiet -Wall -Wextra -Wno-int-in-bool-context -Wno-missing-braces \
      -Wno-unused-parameter -Wno-switch -Wno-unused-local-typedefs \
      -Wno-missing-field-initializers -Wno-ignored-qualifiers -Wno-sign-compare \
      -mthumb -O2 -march=armv4t -fshort-enums -g -std=gnu2x \
      -fno-strict-aliasing -o /dev/null - 2>&1 | head -20

RC=$?
ELAPSED=$(( $(date +%s) - T0 ))

if [ $RC -eq 0 ]; then
    echo "OK ($ELAPSED s)"
else
    echo "FAILED ($ELAPSED s)"
fi
exit $RC
