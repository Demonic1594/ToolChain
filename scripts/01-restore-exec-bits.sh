#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$ROOT/modules/06-eliteredux-source" ] || { echo "[01] ERROR: run 00-extract first"; exit 1; }

echo "[01] Restoring executable bits across modules/..."
cd "$ROOT/modules"
python3 - <<'PY'
import os
n = 0
bindirs = {"bin", "libexec", "sbin", "05-python-mgba"}
for root, dirs, files in os.walk("."):
    if ".staging" in root:
        continue
    parts = set(root.split(os.sep))
    for f in files:
        p = os.path.join(root, f)
        if os.path.islink(p):
            continue
        try:
            with open(p, "rb") as fh:
                head = fh.read(4)
        except OSError:
            continue
        is_elf = head == b"\x7fELF"
        is_script = head[:2] == b"#!"
        in_bin = bool(parts & bindirs)
        is_so = ".so" in f
        if is_elf or is_script or (in_bin and not f.endswith((".txt", ".md", ".h", ".a", ".o"))) or is_so:
            os.chmod(p, os.stat(p).st_mode | 0o111)
            n += 1
print(f"[01] chmod +x applied to {n} files")
PY

echo "[01] Touching prebuilt host tools so make leaves them alone..."
find "$ROOT/modules/06-eliteredux-source/tools" -type f -perm -u+x ! -name '*.c' ! -name '*.h' ! -name '*.py' -exec touch {} + 2>/dev/null || true
touch "$ROOT/modules/06-eliteredux-source/flips-linux" 2>/dev/null || true
echo "[01] done"
