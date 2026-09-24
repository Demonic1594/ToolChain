#!/bin/bash
# Standalone toolchain smoke test - not part of run.sh stages. Verifies every
# component with tiny inputs after extraction/wrapping (or on CI), catching
# breakage like missing JAVACMD, unwrapped binaries, or a broken sysroot in
# seconds instead of at minute 40 of a build.
set -u -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "[selftest] PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "[selftest] FAIL: $1"; }

echo "[selftest] --- environment ---"
if (source "$ROOT/scripts/02-env.sh" >/dev/null 2>&1); then ok "02-env.sh sources cleanly"; else bad "02-env.sh fails to source"; fi
source "$ROOT/scripts/02-env.sh" >/dev/null 2>&1

[ -n "${DEVKITARM:-}" ] && ok "DEVKITARM exported" || bad "DEVKITARM not exported"
[ -n "${CPATH:-}" ] && ok "CPATH (newlib headers) exported" || bad "CPATH missing"

V="$(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
case "$V" in *"13.2"*) ok "arm-none-eabi-gcc 13.2 ($V)";; *) bad "arm-none-eabi-gcc: got '$V'";; esac

# The classic silent-breakage gotchas from docs/README-SETUP.md: PATH lookup
# of bare as/ld must land on the devkitARM links, never the host's
AS_PATH="$(command -v as 2>/dev/null)"
case "$AS_PATH" in "$DEVKITARM"/bin/*) ok "bare 'as' resolves via DEVKITARM ($AS_PATH)";; *) bad "bare 'as' resolves outside DEVKITARM: ${AS_PATH:-not found} - host assembler would corrupt output";; esac
LD_PATH="$(command -v ld 2>/dev/null)"
case "$LD_PATH" in "$DEVKITARM"/bin/*) ok "bare 'ld' resolves via DEVKITARM ($LD_PATH)";; *) bad "bare 'ld' resolves outside DEVKITARM: ${LD_PATH:-not found}";; esac
[ "$(readlink -f "$AS_PATH" 2>/dev/null)" = "$(readlink -f "$ROOT/modules/01-binutils/bin/arm-none-eabi-as" 2>/dev/null)" ] \
  && ok "'as' link chain ends at the ARM assembler" || bad "'as' chain does not end at arm-none-eabi-as"

CC1="$(arm-none-eabi-gcc --print-prog-name=cc1)"
[ -x "$CC1" ] && ok "gcc --print-prog-name=cc1 finds executable ($CC1)" || bad "cc1 not executable: $CC1"

echo "[selftest] --- ARM compile+link end-to-end ---"
cat > "$TMP/hello.c" <<'EOF'
int main(void){return 42;}
EOF
cat > "$TMP/stub.c" <<'EOF'
void _exit(int s){for(;;);}
int _write(int f,const void*b,unsigned n){return n;}
int _close(int f){return 0;}
int _read(int f,void*b,unsigned n){return 0;}
int _sbrk(void){return 0;}
int _lseek(int f,int o,int w){return 0;}
EOF
if arm-none-eabi-gcc -mthumb -mcpu=arm7tdmi -O2 \
     -B "$MOD_GCC/lib/arm-none-eabi/newlib/" \
     -L "$MOD_GCC/lib/gcc/arm-none-eabi/13.2.1" \
     "$TMP/hello.c" "$TMP/stub.c" -o "$TMP/hello.elf" 2>"$TMP/gcc.err" \
   && arm-none-eabi-objcopy -O binary "$TMP/hello.elf" "$TMP/hello.gba" \
   && arm-none-eabi-objdump -f "$TMP/hello.elf" | grep -q arm; then
  ok "compile + newlib link + objcopy (ARM ELF + GBA binary)"
else
  bad "ARM end-to-end compile/link"; sed 's/^/    /' "$TMP/gcc.err" | head -8
fi

echo "[selftest] --- JDK ---"
printf 'public class T{public static void main(String[] a){System.out.println("java-ok");}}\n' > "$TMP/T.java"
if (cd "$TMP" && javac T.java && [ "$(java -cp . T)" = "java-ok" ]); then ok "javac + java round trip"; else bad "javac/java round trip"; fi

echo "[selftest] --- Kotlin ---"
if [ "${SELFTEST_FAST:-0}" = "1" ]; then
  echo "[selftest] SKIP: kotlinc (SELFTEST_FAST=1)"
else
  printf 'fun main(){ println("kotlin-ok") }\n' > "$TMP/k.kt"
  if (cd "$TMP" && kotlinc k.kt -include-runtime -d k.jar >/dev/null 2>&1 && [ "$(java -jar k.jar 2>/dev/null)" = "kotlin-ok" ]); then
    ok "kotlinc compile + run"
  else
    bad "kotlinc compile/run (is JAVACMD set? see 02-env.sh)"
  fi
fi

echo "[selftest] --- mGBA harness ---"
if "$MOD_PY/bin/python3.11" -c "import mgba.core" 2>/dev/null; then ok "python3.11 imports mgba"; else bad "python3.11 import mgba (sysroot libs missing? run scripts/fetch-x86_64-root.sh)"; fi

echo "[selftest] --- summary: $PASS passed, $FAIL failed ---"
exit $((FAIL > 0))
