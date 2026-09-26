#!/data/data/com.termux/files/usr/bin/bash
# One-shot native-lane setup, run INSIDE TERMUX (not under any PRoot).
#
#   pkg install -y git python
#   git clone -b native-gcc https://github.com/Demonic1594/ToolChain.git ~/ToolChain
#   bash ~/ToolChain/scripts/termux/setup-native-lane.sh
#
# After it completes, start the bridge (from a second Termux session or &):
#   python ~/ToolChain/scripts/termux/bridge-server.py --workspace ~/ToolChain
# and drive everything from and-code via scripts/termux/termux-client.sh.
set -euo pipefail

TC_HOME="${TC_HOME:-$HOME/ToolChain}"
cd "$TC_HOME"

echo "[setup] packages"
pkg install -y -q git python make libpng patchelf zstd xz-utils openjdk-17 unzip wget which || {
  pkg update -y && pkg install -y git python make libpng patchelf zstd xz-utils openjdk-17 unzip wget; }

echo "[setup] toolchain archive (stage 0-1-3)"
bash ./run.sh --only extract
bash ./run.sh --only exec-bits
bash ./run.sh --only patches

echo "[setup] Arm aarch64-hosted GCC 13.2.rel1"
if [ ! -x modules/10-native-gcc/bin/arm-none-eabi-gcc ]; then
  curl -sL -o /tmp/arm-tc.tar.xz \
    "https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-aarch64-arm-none-eabi.tar.xz"
  mkdir -p modules/10-native-gcc
  tar -xJf /tmp/arm-tc.tar.xz -C modules/10-native-gcc --strip-components=1
  rm -f /tmp/arm-tc.tar.xz
fi
modules/10-native-gcc/bin/arm-none-eabi-gcc --version | head -1

echo "[setup] glibc runtime for the glibc-built toolchain (Termux is bionic)"
if [ ! -e modules/91-arm64-glibc-root/usr/lib/ld-linux-aarch64.so.1 ]; then
  python3 scripts/fetch-arm64-glibc-root.py
fi
LOADER="$TC_HOME/modules/91-arm64-glibc-root/usr/lib/ld-linux-aarch64.so.1"
LIBS="$TC_HOME/modules/91-arm64-glibc-root/usr/lib/aarch64-linux-gnu:$TC_HOME/modules/91-arm64-glibc-root/lib/aarch64-linux-gnu"

echo "[setup] patchelf the toolchain ELFs (interpreter + rpath; no PRoot, so this works)"
n=0
cd modules/10-native-gcc
for f in $(find bin libexec -type f); do
  if head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' && patchelf --print-interpreter "$f" >/dev/null 2>&1; then
    patchelf --set-interpreter "$LOADER" --force-rpath --set-rpath "$LIBS" "$f"
    n=$((n+1))
  fi
done
cd "$TC_HOME"
echo "[setup] patched $n ELFs"

echo "[setup] rebuild the x86-only host tools natively (Termux clang)"
cd modules/06-eliteredux-source
rm -f tools/preproc/preproc tools/gbagfx/gbagfx tools/scaninc/scaninc \
      tools/mapjson/mapjson tools/mid2agb/mid2agb tools/bin2c/bin2c \
      tools/jsonproc/jsonproc tools/ramscrgen/ramscrgen \
      tools/rsfont/rsfont tools/gbafix/gbafix
# arm64 protoc 29.2 (official prebuilt - a static binary, runs anywhere)
if ! file tools/codegen/protoc 2>/dev/null | grep -q aarch64; then
  curl -sL -o /tmp/protoc.zip \
    "https://github.com/protocolbuffers/protobuf/releases/download/v29.2/protoc-29.2-linux-aarch_64.zip"
  unzip -qo /tmp/protoc.zip -d /tmp/protoc bin/protoc
  cp /tmp/protoc/bin/protoc tools/codegen/protoc && chmod +x tools/codegen/protoc
fi
tools/codegen/protoc --version
# poryscript from source (no arm64 release)
if [ ! -x tools/poryscript/poryscript ]; then
  rm -f tools/poryscript/poryscript tools/poryscript/poryscript.zip
  git clone -q --depth 1 --branch 3.6.1 https://github.com/huderlem/poryscript /tmp/porysrc
  make -C /tmp/porysrc -j"$(nproc)" > /dev/null
  cp /tmp/porysrc/poryscript tools/poryscript/poryscript
fi
tools/poryscript/poryscript -v || true
make tools
cd "$TC_HOME"

echo "[setup] smoke: native env + one-file compile"
export ER_ARM_TC=native
bash ./run.sh --only env | tail -3
cd modules/06-eliteredux-source
echo 'int bridge_smoke(void){return 42;}' > /tmp/bridge_smoke.c
arm-none-eabi-gcc -mthumb -mcpu=arm7tdmi -O2 -c /tmp/bridge_smoke.c -o /tmp/bridge_smoke.o
arm-none-eabi-objdump -d /tmp/bridge_smoke.o | tail -3
cd "$TC_HOME"

echo
echo "[setup] DONE. Start the bridge in a second Termux session:"
echo "  python $TC_HOME/scripts/termux/bridge-server.py --workspace $TC_HOME"
echo "Then from and-code:  bash scripts/termux/termux-client.sh health"
