#!/usr/bin/env python3
# One-shot: fetch the arm64 glibc runtime for the native GCC fast lane.
import gzip, io, lzma, os, re, subprocess, sys, tarfile, time, urllib.request

MIRROR = "https://deb.debian.org/debian"
SUITE = "trixie"
OUT = "/workspace/ToolChain/modules/91-arm64-glibc-root"
PKGS = ["libc6", "libgcc-s1", "libstdc++6", "zlib1g", "libzstd1",
        "libisl23", "libmpc3", "libmpfr6", "libgmp10"]

t0 = time.time()
raw = gzip.decompress(urllib.request.urlopen(
    f"{MIRROR}/dists/{SUITE}/main/binary-arm64/Packages.gz").read()).decode()
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
print(f"index: {len(index)} packages in {time.time()-t0:.1f}s", flush=True)

want = {}
def add(name):
    if name not in index or name in want:
        return
    want[name] = index[name]["Filename"]
    for dep in index[name].get("Depends", "").split(","):
        first = dep.strip().split("|")[0].strip()
        base = re.split(r"\s*\(", first)[0].strip()
        if base:
            add(base)
for p in PKGS:
    add(p)
print(f"closure: {len(want)} packages: {sorted(want)}", flush=True)

os.makedirs(OUT, exist_ok=True)

def extract_deb(deb, dest):
    assert deb[:8] == b"!<arch>\n", "not an ar archive"
    off = 8
    while off + 60 <= len(deb):
        hdr = deb[off:off + 60]
        name = hdr[0:16].decode().rstrip()
        size = int(hdr[48:58].decode().strip())
        body = deb[off + 60:off + 60 + size]
        if name.startswith("data.tar"):
            if name.endswith(".zst"):
                body = subprocess.run(["zstd", "-dc"], input=body,
                                      stdout=subprocess.PIPE, check=True).stdout
            elif name.endswith(".xz"):
                body = lzma.decompress(body)
            tar = tarfile.open(fileobj=io.BytesIO(body), mode="r:")
            members = [m for m in tar.getmembers()
                       if m.name.startswith(("./usr/lib", "./lib"))]
            tar.extractall(dest, members=members, filter="data")
        off += 60 + size + (size & 1)

for name in sorted(want):
    print(f"fetch {name}", flush=True)
    extract_deb(urllib.request.urlopen(f"{MIRROR}/{want[name]}").read(), OUT)

for root, _, files in os.walk(OUT):
    for f in files:
        if f.startswith("ld-linux-aarch64"):
            print(f"DONE loader: {os.path.join(root, f)}", flush=True)
            sys.exit(0)
print("ERROR: loader not found", flush=True)
sys.exit(1)
