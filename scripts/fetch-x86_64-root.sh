#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/modules/90-x86_64-root"
MIRROR="${DEB_MIRROR:-https://deb.debian.org/debian}"
SUITE="${DEB_SUITE:-trixie}"

if [ "$(uname -m)" = "x86_64" ]; then
  echo "[fetch-root] x86_64 host - sysroot not needed"
  exit 0
fi
command -v qemu-x86_64 >/dev/null || { echo "[fetch-root] ERROR: apk add qemu-x86_64 first"; exit 1; }

if [ -d "$OUT" ]; then
  OLD="$OUT.old.$$"
  mv "$OUT" "$OLD"
  rm -rf "$OLD" 2>/dev/null || true
fi
mkdir -p "$OUT"
python3 - "$MIRROR" "$SUITE" "$OUT" <<'PY'
import sys, gzip, io, os, re, tarfile, urllib.request

mirror, suite, out = sys.argv[1], sys.argv[2], sys.argv[3]
pkgs = ["libc6", "libgcc-s1", "libstdc++6", "zlib1g", "libzstd1",
        "libpng16-16", "bash", "libtinfo6", "make", "coreutils",
        "findutils", "sed", "grep", "diffutils", "perl-base", "debianutils",
        "libisl23", "libmpc3", "libmpfr6", "libgmp10", "libgomp1", "libcrypt1",
        "libedit2", "libbz2-1.0", "libssl3", "libsqlite3-0", "liblua5.4-0",
        "libelf1", "libgl1", "libavcodec61", "libavfilter10", "libavformat61",
        "libavutil59", "libswresample5", "libswscale8", "libblas3", "liblapack3"]
aliases = {"libpng16-16": ["libpng16-16t64"], "libsqlite3-0": ["libsqlite3-0t64"],
           "libelf1": ["libelf1t64"], "libbz2-1.0": ["libbz2-1.0.2"],
           "libssl3": ["libssl3t64"]}

idx_url = f"{mirror}/dists/{suite}/main/binary-amd64/Packages.gz"
print(f"[fetch-root] downloading {idx_url}")
raw = gzip.decompress(urllib.request.urlopen(idx_url).read()).decode()

index = {}
for stanza in raw.split("\n\n"):
    fields = {}
    key = None
    for line in stanza.splitlines():
        if line.startswith(" ") and key:
            fields[key] += "\n" + line
        elif ":" in line:
            key, val = line.split(":", 1)
            fields[key] = val.strip()
    p = fields.get("Package")
    if p and p not in index:
        index[p] = fields

def canon(name):
    for c, al in aliases.items():
        if name == c or name in al:
            return c
    return name

want = {}
def add(name):
    c = canon(name)
    if c not in index:
        for al in aliases.get(c, []):
            if al in index:
                c = al
                break
    if c in want or c not in index:
        return
    want[canon(name)] = index[c]["Filename"]
    for dep in index[c].get("Depends", "").split(","):
        dep = dep.strip()
        if not dep:
            continue
        first = dep.split("|")[0].strip()
        base = re.split(r"\s*\(", first)[0].strip()
        if not base:
            continue
        if canon(base) in index:
            add(base)

for p in pkgs:
    add(p)

missing = [p for p in pkgs if p not in want]
if missing:
    sys.exit(f"[fetch-root] missing in index: {missing}")
print(f"[fetch-root] resolved {len(want)} packages (with dependency closure)")

def extract_deb(deb_bytes, dest):
    assert deb_bytes[:8] == b"!<arch>\n", "not an ar archive"
    off = 8
    while off + 60 <= len(deb_bytes):
        hdr = deb_bytes[off:off + 60]
        name = hdr[0:16].decode().rstrip()
        size = int(hdr[48:58].decode().strip())
        body = deb_bytes[off + 60:off + 60 + size]
        off += 60 + size + (size % 2)
        if name.startswith("data.tar"):
            tf = tarfile.open(fileobj=io.BytesIO(body))
            tf.extractall(dest, filter="tar")
            return name
    raise RuntimeError("no data.tar member")

for p in sorted(want):
    fn = want[p]
    url = f"{mirror}/{fn}"
    data = urllib.request.urlopen(url).read()
    member = extract_deb(data, out)
    print(f"[fetch-root] {p}: {os.path.basename(fn)} ({member})")

print("[fetch-root] all packages extracted")
PY

mkdir -p "$OUT/lib64"
SRC_LD="$OUT/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
[ -f "$SRC_LD" ] || SRC_LD="$OUT/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
[ -f "$SRC_LD" ] || { echo "[fetch-root] ERROR: interpreter not found"; exit 1; }
rm -f "$OUT/lib64/ld-linux-x86-64.so.2"
cp "$SRC_LD" "$OUT/lib64/ld-linux-x86-64.so.2"

L="$OUT/usr/lib/x86_64-linux-gnu"
[ -e "$L/libblas.so.3" ] || ln -sf blas/libblas.so.3 "$L/libblas.so.3"
[ -e "$L/liblapack.so.3" ] || ln -sf lapack/liblapack.so.3 "$L/liblapack.so.3"

python3 - "$OUT" <<'PY'
import os, re, sys
out = sys.argv[1]
n = 0
for base in ("lib/x86_64-linux-gnu", "usr/lib/x86_64-linux-gnu"):
    d = os.path.join(out, base)
    if not os.path.isdir(d):
        continue
    for f in list(os.listdir(d)):
        m = re.fullmatch(r"(.+\.so)((?:\.\d+){2,})", f)
        if not m or os.path.islink(os.path.join(d, f)):
            continue
        stem, ver = m.group(1), m.group(2).lstrip(".").split(".")
        prev = f
        for i in range(len(ver) - 1, 0, -1):
            link = stem + "." + ".".join(ver[:i])
            lp = os.path.join(d, link)
            if not os.path.lexists(lp):
                os.symlink(prev, lp)
                n += 1
            prev = link
print(f"[fetch-root] created {n} soname symlinks")
PY

X64LIBS="$OUT/lib/x86_64-linux-gnu:$OUT/usr/lib/x86_64-linux-gnu"
GUEST_BASH="$OUT/usr/bin/bash"
[ -x "$GUEST_BASH" ] || GUEST_BASH="$OUT/bin/bash"
echo "[fetch-root] smoke test: qemu guest bash ($GUEST_BASH)..."
LD_LIBRARY_PATH="$X64LIBS" qemu-x86_64 -L "$OUT" "$GUEST_BASH" -c 'echo guest-bash-ok' \
  || { echo "[fetch-root] ERROR: guest bash smoke test failed"; exit 1; }
LD_LIBRARY_PATH="$X64LIBS" qemu-x86_64 -L "$OUT" "$OUT/usr/bin/perl" -e 'print "perl-ok\n"' \
  || { echo "[fetch-root] ERROR: perl smoke test failed"; exit 1; }
LD_LIBRARY_PATH="$X64LIBS" qemu-x86_64 -L "$OUT" "$OUT/usr/bin/make" --version | head -1 \
  || { echo "[fetch-root] ERROR: make smoke test failed"; exit 1; }

MGBA_LIBS="$ROOT/modules/05-python-mgba/mgba-libs"
PYMT="$ROOT/modules/05-python-mgba/python3.11-mgba/bin/python3.11"
if [ -x "$PYMT" ]; then
  echo "[fetch-root] phase 2: ffmpeg 6.1 (noble) for the mgba harness..."
  python3 - "$OUT" "$MGBA_LIBS" "$PYMT" <<'PY'
import gzip, io, os, re, subprocess, sys, tarfile, urllib.request

out, mgba, pymt = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])

idx = {}
def load(root, url):
    raw = gzip.decompress(urllib.request.urlopen(url).read()).decode()
    for stanza in raw.split("\n\n"):
        p = fn = None
        for l in stanza.splitlines():
            if l.startswith("Package: "): p = l[9:].strip()
            elif l.startswith("Filename: "): fn = l[10:].strip()
            if p and fn: break
        if p and fn and p not in idx: idx[p] = root + fn
load("https://deb.debian.org/debian/", "https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.gz")
load("http://archive.ubuntu.com/ubuntu/", "http://archive.ubuntu.com/ubuntu/dists/noble/main/binary-amd64/Packages.gz")
load("http://archive.ubuntu.com/ubuntu/", "http://archive.ubuntu.com/ubuntu/dists/noble/universe/binary-amd64/Packages.gz")

def ex(url):
    deb = urllib.request.urlopen(url).read()
    off = 8
    while off + 60 <= len(deb):
        hdr = deb[off:off + 60]
        name = hdr[0:16].decode().rstrip()
        size = int(hdr[48:58].decode().strip())
        body = deb[off + 60:off + 60 + size]
        off += 60 + size + (size % 2)
        if name.startswith("data.tar"):
            if name.endswith(".zst"):
                body = subprocess.run(["zstd", "-dc", "-"], input=body, capture_output=True, check=True).stdout
            tf = tarfile.open(fileobj=io.BytesIO(body))
            for m in tf.getmembers():
                if m.isfile() and ("/lib/" in m.name or "/libs/" in m.name) and re.search(r"\.so[\.\d]*$", os.path.basename(m.name)):
                    tf.extract(m, out, filter="tar")
            return
    raise RuntimeError("no data.tar in " + url)

def sonames():
    for base in ("lib/x86_64-linux-gnu", "usr/lib/x86_64-linux-gnu"):
        d = os.path.join(out, base)
        if not os.path.isdir(d): continue
        for f in list(os.listdir(d)):
            m = re.fullmatch(r"(.+\.so)((?:\.\d+){2,})", f)
            if not m or os.path.islink(os.path.join(d, f)): continue
            stem, ver = m.group(1), m.group(2).lstrip(".").split(".")
            prev = f
            for i in range(len(ver) - 1, 0, -1):
                link = stem + "." + ".".join(ver[:i])
                lp = os.path.join(d, link)
                if not os.path.lexists(lp): os.symlink(prev, lp)
                prev = link

for p in ["libavcodec60", "libavfilter9", "libavformat60", "libavutil58",
          "libswresample4", "libswscale7", "libpostproc57", "libavdevice60"]:
    if p in idx:
        ex(idx[p])
sonames()

local_first = set(os.listdir(mgba)) if os.path.isdir(mgba) else set()
def resolve(soname):
    if soname in local_first: return None
    m = re.fullmatch(r"(lib[^.]*)\.so[.\d]*", soname)
    base = m.group(1) if m else soname
    num = re.search(r"\.so\.(\d+)", soname)
    n = num.group(1) if num else ""
    for c in (f"{base}{n}", f"{base}{n}t64", f"{base}-{n}", f"{base}-{n}t64", f"{base}0", base):
        if c in idx: return c
    for p in idx:
        if p.startswith(base) and n in p and len(p) < len(base) + 8: return p
    return None

env = dict(os.environ)
env["LD_LIBRARY_PATH"] = mgba + ":" + out + "/lib/x86_64-linux-gnu:" + out + "/usr/lib/x86_64-linux-gnu"
for rnd in range(25):
    r = subprocess.run(["/usr/bin/qemu-x86_64", "-L", out, pymt, "-c", "import mgba.core"],
                       capture_output=True, text=True, env=env)
    if r.returncode == 0:
        print(f"[fetch-root] mgba import OK after {rnd} resolver rounds")
        break
    m = re.search(r"(?:ImportError|symbol lookup error|error while loading shared libraries):[^\n]*?([A-Za-z0-9_+.-]+\.so[.\d]*)", r.stderr)
    if not m:
        print("[fetch-root] WARN: unparsed import error:", r.stderr.strip().splitlines()[-1][:200])
        break
    soname = m.group(1)
    pkg = resolve(soname)
    print(f"[fetch-root] resolver: {soname} -> {pkg}")
    if not pkg:
        print("[fetch-root] WARN: cannot resolve", soname)
        break
    ex(idx[pkg])
    sonames()
PY
fi
echo "[fetch-root] done: $OUT"
