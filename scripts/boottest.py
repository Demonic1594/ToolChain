#!/usr/bin/env python3
"""Standalone mGBA boot test with screenshot capture.

Complements the inline boot test in 04-verify.sh: same "run N frames without
crashing" check, plus per-milestone screenshots (BMP in the output dir, plus a
final distinct-color sanity check that catches the "runs but renders nothing"
failure mode).

Run it with the bundled interpreter so `import mgba` resolves (same as
04-verify.sh does):

    "$MOD_PY/bin/python3.11" scripts/boottest.py ROM [OUTDIR] [FRAMES]

Screenshots land in OUTDIR (default: logs/) as boot_fNNNNN.bmp.
"""
import os
import struct
import sys

rom = sys.argv[1] if len(sys.argv) > 1 else None
if not rom or not os.path.exists(rom):
    sys.exit("usage: boottest.py ROM [OUTDIR] [FRAMES]")
outdir = sys.argv[2] if len(sys.argv) > 2 else "logs"
frames = int(sys.argv[3]) if len(sys.argv) > 3 else 2500
os.makedirs(outdir, exist_ok=True)

import mgba.core  # noqa: E402  (needs the bundled python / LD_LIBRARY_PATH)
import mgba.image  # noqa: E402


def save_bmp(path, buf, w, h):
    """buf: sequence of 0x00BBGGRR uint32 per pixel (mgba native)."""
    row_size = (w * 3 + 3) & ~3
    img_size = row_size * h
    fh = struct.pack('<2sIHHI', b'BM', 54 + img_size, 0, 0, 54)
    ih = struct.pack('<IiiHHIIiiII', 40, w, h, 1, 24, 0, img_size, 2835, 2835, 0, 0)
    rows = []
    for y in range(h - 1, -1, -1):
        base = y * w
        row = bytearray()
        for x in range(w):
            c = buf[base + x]
            row += bytes((c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF))
        rows.append(bytes(row).ljust(row_size, b'\x00'))
    with open(path, 'wb') as f:
        f.write(fh + ih + b''.join(rows))


core = mgba.core.load_path(rom)
w, h = core.desired_video_dimensions()
img = mgba.image.Image(w, h)
# The video buffer must be attached BEFORE reset() - afterwards the core
# renders into its internal buffer and the attached image stays blank.
core.set_video_buffer(img)
core.reset()

snaps = {120, 900, 1500, 2100, frames}
for f in range(1, frames + 1):
    core.run_frame()
    if f in snaps:
        buf = list(img.buffer)
        distinct = len(set(buf))
        path = os.path.join(outdir, f"boot_f{f:05d}.bmp")
        save_bmp(path, buf, w, h)
        print(f"[boot] frame {f:5d}: distinct colors={distinct:6d} -> {path}")

buf = list(img.buffer)
distinct = len(set(buf))
# The boot sequence ends on the deliberately minimal-palette Groudon logo
# screen (~7 colors); anything below this suggests a blank/failed render.
if distinct < 4:
    sys.exit(f"[boot] FAIL: only {distinct} distinct colors on final frame - blank render?")
print(f"[boot] OK: {frames} frames, final frame has {distinct} distinct colors")
