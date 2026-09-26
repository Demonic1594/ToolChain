#!/bin/bash
# Source this file, don't execute it: source scripts/02-env.sh
PKGROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MOD_BINUTILS="$PKGROOT/modules/01-binutils"
MOD_GCC="$PKGROOT/modules/02-gcc"
MOD_JDK="$PKGROOT/modules/03-jdk"
MOD_KOTLINC="$PKGROOT/modules/04-kotlinc"
MOD_PY="$PKGROOT/modules/05-python-mgba/python3.11-mgba"
MOD_MGBA_LIBS="$PKGROOT/modules/05-python-mgba/mgba-libs"
MOD_SRC="$PKGROOT/modules/06-eliteredux-source"

# ER_ARM_TC=native: use an aarch64-hosted arm-none-eabi toolchain from
# modules/10-native-gcc/ (e.g. Arm's official 13.2.rel1 aarch64 build) instead
# of the bundled x86_64 one. On a glibc aarch64 host (CI arm runners, real
# hardware) this is the fast lane - no qemu, no x86_64 sysroot. On a musl/PRoot
# host it additionally needs patchelf + the arm64 glibc root (see
# NATIVE-GCC-STATUS.md; cc1 does not exec under PRoot).
NATIVE_GCC="$PKGROOT/modules/10-native-gcc"
if [ "${ER_ARM_TC:-}" = "native" ]; then
  if [ ! -x "$NATIVE_GCC/bin/arm-none-eabi-gcc" ]; then
    echo "[02] ERROR: ER_ARM_TC=native but $NATIVE_GCC/bin/arm-none-eabi-gcc missing."
    return 1 2>/dev/null || exit 1
  fi
  export ER_ARM_TC NATIVE_GCC
else
  unset NATIVE_GCC
fi

mkdir -p "$PKGROOT/devkitARM/bin"
if [ "${ER_ARM_TC:-}" = "native" ]; then
  ln -sfn "$NATIVE_GCC"/bin/* "$PKGROOT/devkitARM/bin/" 2>/dev/null
  for tool in as ld ar nm objcopy objdump ranlib strip; do
    ln -sfn "$NATIVE_GCC/bin/arm-none-eabi-$tool" "$PKGROOT/devkitARM/bin/$tool"
  done
  CXXVER="$(ls "$MOD_GCC/include/newlib/c++/" 2>/dev/null | head -n1)"
else
  ln -sfn "$MOD_GCC"/bin/* "$PKGROOT/devkitARM/bin/" 2>/dev/null
  ln -sfn "$MOD_BINUTILS"/bin/* "$PKGROOT/devkitARM/bin/" 2>/dev/null
  for tool in as ld ar nm objcopy objdump ranlib strip; do
    ln -sfn "$MOD_BINUTILS/bin/arm-none-eabi-$tool" "$PKGROOT/devkitARM/bin/$tool"
  done
  CXXVER="$(ls "$MOD_GCC/include/newlib/c++/" 2>/dev/null | head -n1)"
fi
export DEVKITARM="$PKGROOT/devkitARM"

ARCH="$(uname -m)"
if [ "${ER_ARM_TC:-}" = "native" ]; then
  # Native lane: no qemu sysroot, no x86_64 libs in LD_LIBRARY_PATH.
  unset ER_X86_ROOT ER_X86_LIBS
elif [ "$ARCH" != "x86_64" ]; then
  ER_X86_ROOT="$PKGROOT/modules/90-x86_64-root"
  if [ ! -x "$ER_X86_ROOT/usr/bin/bash" ] && [ ! -x "$ER_X86_ROOT/bin/bash" ]; then
    echo "[02] ERROR: aarch64 host: x86_64 sysroot missing."
    echo "[02]        Run: scripts/fetch-x86_64-root.sh   (needs network + apk add qemu-x86_64)"
    return 1 2>/dev/null || exit 1
  fi
  if ! head -2 "$PKGROOT/modules/02-gcc/bin/arm-none-eabi-gcc" 2>/dev/null | grep -q 'er-qemu-shim'; then
    echo "[02] ERROR: aarch64 host: x86_64 binaries not wrapped."
    echo "[02]        Run: scripts/01b-wrap-x86_64.sh"
    return 1 2>/dev/null || exit 1
  fi
  export ER_X86_ROOT
  export ER_X86_LIBS="$ER_X86_ROOT/lib/x86_64-linux-gnu:$ER_X86_ROOT/usr/lib/x86_64-linux-gnu"
else
  unset ER_X86_ROOT ER_X86_LIBS
fi

# aarch64: prefer a NATIVE JDK (>=17) for codegen when one actually runs.
# The bundled JDK is x86_64 (qemu-wrapped here) and the 57 generator JVM runs
# dominate the codegen phase (~21s each under qemu vs <1s native). The codegen
# jars are now pinned to class version 61 (tools/codegen/makefile: javac
# --release 17 / kotlinc -jvm-target 17), so any JVM >= 17 loads them and the
# generated output is byte-identical. Some Alpine JDK 21 builds fail to start
# under PRoot ("Failed to mark memory page as executable") - probing -version's
# exit code skips those automatically. The C toolchain stays qemu-wrapped.
NATIVE_JDK=""
if [ "$ARCH" != "x86_64" ]; then
  for cand in /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/*-openjdk; do
    if [ -x "$cand/bin/java" ] && "$cand/bin/java" -version >/dev/null 2>&1; then
      NATIVE_JDK="$(cd "$cand" && pwd)"
      break
    fi
  done
fi
if [ -n "$NATIVE_JDK" ]; then
  export PATH="$DEVKITARM/bin:$NATIVE_JDK/bin:$MOD_JDK/bin:$MOD_KOTLINC/bin:$PATH"
  export JAVACMD="$NATIVE_JDK/bin/java"
  # Native (musl) consumers fatal on the x86_64 libs in LD_LIBRARY_PATH (no
  # ELF-class skipping like glibc); /usr/lib first lets them resolve natively,
  # while glibc/x86_64 loaders just skip the aarch64 entries.
  export LD_LIBRARY_PATH="/usr/lib:$MOD_MGBA_LIBS:${ER_X86_LIBS:-}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
  export PATH="$DEVKITARM/bin:$MOD_JDK/bin:$MOD_KOTLINC/bin:$PATH"
  export JAVACMD="$MOD_JDK/bin/java"  # kotlinc launcher ignores PATH; without this it exits 127 on non-Debian hosts
  export LD_LIBRARY_PATH="$MOD_MGBA_LIBS:${ER_X86_LIBS:-}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export NATIVE_JDK
export CPATH="$MOD_GCC/include/newlib"
export CPLUS_INCLUDE_PATH="$MOD_GCC/include/newlib/c++/$CXXVER:$MOD_GCC/include/newlib/c++/$CXXVER/arm-none-eabi/thumb/nofp"
export JAVA_OPTS="-Xmx4g"
export MOD_PY MOD_SRC MOD_MGBA_LIBS

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  fail=0
  for d in 01-binutils 02-gcc 03-jdk 04-kotlinc 05-python-mgba 06-eliteredux-source; do
    [ -d "$PKGROOT/modules/$d" ] || { echo "[02] ERROR: modules/$d missing (run 00-extract)"; fail=1; }
  done
  [ "$fail" -eq 0 ] || exit 1
  echo "[02] arm-none-eabi-gcc: $( "$DEVKITARM/bin/arm-none-eabi-gcc" --version 2>/dev/null | head -1 || echo NOT FOUND)"
  echo "[02] as -> $(readlink -f "$DEVKITARM/bin/as" 2>/dev/null)"
  echo "[02] java: $( "$MOD_JDK/bin/java" -version 2>&1 | head -1)"
  [ -n "$NATIVE_JDK" ] && echo "[02] codegen java (native): $( "$NATIVE_JDK/bin/java" -version 2>&1 | head -1)"
  echo "[02] python3.11 w/ mgba: $MOD_PY/bin/python3.11"
  echo "[02] Environment OK (${ARCH}${ER_X86_ROOT:+, qemu-shimmed})"
fi
