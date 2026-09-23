#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(uname -m)" = "x86_64" ]; then
  echo "[wrap] x86_64 host - no wrapping needed"
  exit 0
fi
ER_X86_ROOT="$ROOT/modules/90-x86_64-root"
GUEST_BASH="$ER_X86_ROOT/usr/bin/bash"
[ -x "$GUEST_BASH" ] || GUEST_BASH="$ER_X86_ROOT/bin/bash"
[ -x "$GUEST_BASH" ] || { echo "[wrap] ERROR: run scripts/fetch-x86_64-root.sh first"; exit 1; }
command -v qemu-x86_64 >/dev/null || { echo "[wrap] ERROR: apk add qemu-x86_64"; exit 1; }
QEMU="$(command -v qemu-x86_64)"
X64LIBS="$ER_X86_ROOT/lib/x86_64-linux-gnu:$ER_X86_ROOT/usr/lib/x86_64-linux-gnu"
MARKER="# er-qemu-shim"

python3 - "$ROOT" "$ER_X86_ROOT" "$QEMU" "$X64LIBS" "$MARKER" <<'PY'
import os, struct, sys

root, sysroot, qemu, x64libs, marker = sys.argv[1:6]

WRAP_DIRS = [
    f"{root}/modules/01-binutils",
    f"{root}/modules/02-gcc",
    f"{root}/modules/03-jdk",
    f"{root}/modules/04-kotlinc",
    f"{root}/modules/05-python-mgba",
    f"{root}/modules/06-eliteredux-source/tools",
    f"{root}/modules/06-eliteredux-source/flips-linux",
]

def is_exec_elf(path):
    try:
        with open(path, "rb") as f:
            head = f.read(64)
    except OSError:
        return False
    if head[:4] != b"\x7fELF" or len(head) < 64:
        return False
    if head[4] != 2 or head[5] != 1:
        return False
    e_type = struct.unpack_from("<H", head, 16)[0]
    e_machine = struct.unpack_from("<H", head, 18)[0]
    if e_machine != 62:
        return False
    if e_type == 2:
        return True
    if e_type != 3:
        return False
    e_phoff = struct.unpack_from("<Q", head, 32)[0]
    e_phentsize = struct.unpack_from("<H", head, 54)[0]
    e_phnum = struct.unpack_from("<H", head, 56)[0]
    with open(path, "rb") as f:
        f.seek(e_phoff)
        ph = f.read(e_phentsize * e_phnum)
    for i in range(e_phnum):
        off = i * e_phentsize
        p_type = struct.unpack_from("<I", ph, off)[0]
        if p_type == 3:
            return True
    return False

targets = []
def scan(base):
    if os.path.isfile(base):
        targets.append(base)
        return
    for dirpath, dirnames, filenames in os.walk(base):
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if fn.endswith(".x86_64"):
                targets.append(p)
                continue
            if os.path.islink(p):
                continue
            if is_exec_elf(p):
                targets.append(p)

for d in WRAP_DIRS:
    scan(d)

wrapped = skipped = 0
for real in sorted(targets):
    if real.endswith(".x86_64"):
        p = real[:-len(".x86_64")]
        skipped += 1
    else:
        p = real
        real = p + ".x86_64"
        with open(p, "rb") as f:
            if f.read(2) == b"#!":
                continue
        os.rename(p, real)
        wrapped += 1
    shim = ("#!/bin/sh\n"
            f"{marker}\n"
            f"QEMU_LD_PREFIX='{sysroot}'\n"
            f"LD_LIBRARY_PATH='{x64libs}':$LD_LIBRARY_PATH\n"
            "export QEMU_LD_PREFIX LD_LIBRARY_PATH\n"
            f"exec '{qemu}' -L '{sysroot}' '{real}' \"$@\"\n")
    with open(p, "w") as f:
        f.write(shim)
    os.chmod(p, 0o755)

print(f"[wrap] wrapped {wrapped} x86_64 binaries ({skipped} shims refreshed)")
PY

echo "[wrap] smoke test..."
"$ROOT/modules/02-gcc/bin/arm-none-eabi-gcc" --version | head -1
"$ROOT/modules/03-jdk/bin/java" -version 2>&1 | head -1
echo "[wrap] done"
