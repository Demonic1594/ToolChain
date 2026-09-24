# Testing with the emulator harness

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

`modules/05-python-mgba/python3.11-mgba/bin/python3.11` is a full scriptable GBA emulator via
`mgba`'s Python bindings. This is how every change in this project got
verified before being handed over, since asking a human to manually
playtest every iteration wasn't practical.

```bash
export LD_LIBRARY_PATH=modules/05-python-mgba/mgba-libs:$LD_LIBRARY_PATH
/path/to/package/modules/05-python-mgba/python3.11-mgba/bin/python3.11
```

```python
import mgba.core, mgba.image, mgba.log
mgba.log.silence()

core = mgba.core.load_path('modules/06-eliteredux-source/pokeemerald_modern.gba')
core.autoload_save()   # needs a matching .sav next to the .gba,
                        # AND the directory must be WRITABLE - a read-only
                        # mount makes autoload_save() silently return False
w, h = core.desired_video_dimensions()
img = mgba.image.Image(w, h)
core.set_video_buffer(img)
core.reset()

for i in range(4000):
    core.run_frame()

with open('screenshot.png', 'wb') as f:
    img.save_png(f)
```

Key button-input gotcha: `core.add_keys(core.KEY_START)` - the binding
auto-shifts by the key's raw index internally. Do NOT pre-shift it
yourself (`1 << 3`) or you'll press the wrong button entirely (this
specific mistake once pressed R instead of START for an entire debugging
session).

For save-state manipulation (jumping straight to a specific game state
instead of replaying the boot sequence every time):
```python
state = core.save_raw_state()  # returns cffi buffer, save with open(...).write(bytes(state))

# to load one back:
from mgba._pylib import ffi
with open('state.ss', 'rb') as f:
    state_bytes = f.read()
buf = ffi.new('unsigned char[%i]' % len(state_bytes), state_bytes)
core.load_raw_state(buf)
```

Direct memory read/write (for finding cheat addresses, verifying struct
layouts, etc.) via `core.memory.wram` (EWRAM, base `0x02000000`):
```python
core.memory.wram.u8[offset]       # read/write a byte
core.memory.wram.u16[offset]      # read/write a halfword
```

## Getting exact struct offsets / addresses without guessing

Don't guess memory addresses by trial and error if you don't have to -
the compiled ELF has full DWARF debug info (built with `-g`), and the
`.map` file has every global symbol's real linked address. This is how
the `gBattleMons` address and `statStages` field offset were found for a
"stat-boost/weaken" cheat code, with zero address-hunting:

```bash
# exact linked address of any global symbol:
grep -w "gBattleMons" modules/06-eliteredux-source/pokeemerald_modern.map

# exact byte offset of any struct field:
arm-none-eabi-readelf --debug-dump=info modules/06-eliteredux-source/pokeemerald_modern.elf \
  | grep -B5 -A5 "statStages"
```

This is dramatically more reliable than RAM-searching in a live emulator,
and it's the only approach that's guaranteed correct after a rebuild -
raw hardcoded cheat addresses from someone else's ROM build (even a very
similar one) will NOT match this build's memory layout, and using them
anyway causes exactly the kind of crash that started this whole
investigation in the first place.

### Harness technique: call a game function from the emulator
Compile a tiny Thumb stub (`modules/07-tools-notes/call_stub_example.c`) with
`arm-none-eabi-gcc -mthumb -mcpu=arm7tdmi -nostdlib -ffreestanding`, link at
free EWRAM (`0x0203FA00`; the last real EWRAM symbol ends at `0x0203F8D6`),
copy the bytes into `core.memory.wram`, then set `gMain.callback2`
(`0x03003424`) to the stub address |1 for one `run_frame()` and restore it.
Args/results go through a small mailbox at `0x0203FF00`. Get the function
address from `readelf -s` (Thumb functions have bit 0 set; `.map` hides it).
Gotcha: `core.memory.wram.u16[x]` / `u32[x]` take BYTE offsets, not element
indices - indexing them like arrays silently reads/writes the wrong place.
