# EliteRedux — modular build pipeline

Self-contained build system for the patched **Pokémon Elite Redux** source
(v2.65.2.3b, `upcoming` branch): toolchain, codegen tooling, emulator test
harness, and a stage runner that takes you from archive to boot-tested GBA ROM
with one command.

Runs **natively on x86-64** (any Claude/ChatGPT-style Linux sandbox, a PC,
CI) and **transparently under qemu emulation on aarch64** (e.g. an Android
phone in a PRoot/Alpine environment) with the exact same verified GCC 13.2
toolchain — no compiler-version drift between machines.

## Quick start

```bash
./run.sh                # full pipeline: extract -> prep -> env -> build -> verify
```

That is all. The ROM lands in `modules/06-eliteredux-source/pokeemerald_modern.gba`
and stage 5 boot-tests it in the bundled scriptable mGBA (2500 frames).

One-time prerequisites by host arch:

| Host | Setup |
|---|---|
| x86_64 | `apt install build-essential libpng-dev` (or distro equivalent). Stages 0-3 then run natively. |
| aarch64 | `apk add qemu-x86_64 make perl zstd` (or distro equivalent), then `./scripts/fetch-x86_64-root.sh` once (needs network, ~250 MB). Stage 2 auto-detects the arch and wraps every x86-64 binary in a qemu shim. |

## Stages

`./run.sh` executes these in order; each stage is also a standalone script in
`scripts/` and can be re-run or resumed individually.

| # | Stage | What it does |
|---|---|---|
| 0 | `00-extract` | Rejoin `archives/` parts (SHA256-verified), extract into `modules/` |
| 1 | `01-restore-exec-bits` | `chmod +x` every ELF/script/binary, touch prebuilt host tools |
| 2 | `01b-wrap-x86_64` | *aarch64 only:* rename each x86-64 binary to `*.x86_64` and leave a qemu-launching shim at its original path |
| 3 | `02-env` | Build the unified `devkitARM/` bin dir (symlink shim incl. bare `as`/`ld`), export `PATH`/`CPATH`/`CPLUS_INCLUDE_PATH`, verify the toolchain |
| 4 | `03-build` | Detached (`setsid nohup`) `make -j1` with `MAKE_EXIT=` recorded in `logs/build.log`; cleans 0-byte `.o` first, waits and reports |
| 5 | `04-verify` | Copy the fresh ROM, run it 2500 frames in mGBA via the bundled Python 3.11 |

Runner options:

```
./run.sh --from 4       # resume at a stage (e.g. rebuild + verify only)
./run.sh --only 0       # run a single stage
./run.sh --force        # wipe modules/ and re-extract (DESTROYS local edits!)
./run.sh --list         # list stages
```

Useful after editing game source (incremental build, then boot test):

```bash
./run.sh --from 4
tail -f logs/build.log          # watch progress; grep MAKE_EXIT for completion
```

## Repository layout

```
run.sh                  stage runner
archives/               the complete x86-64 toolchain package, split into
                        5 parts of <=90 MB (GitHub's per-file limit), with
                        SHA256SUMS (per part + joined archive)
scripts/                one stage per script + fetch-x86_64-root.sh
docs/                   the package guides (SETUP, PROJECT) — path mapping
                        notes at the top of each file
modules/                (extracted, gitignored) versioned components:
  01-binutils           ARM assembler/linker (matches the gcc)
  02-gcc                arm-none-eabi GCC 13.2 (the "modern" build — required;
                        agbcc cannot parse this source)
  03-jdk / 04-kotlinc   Java/Kotlin toolchain for the proto codegen pipeline
  05-python-mgba        scriptable mGBA emulator harness + libmgba
  06-eliteredux-source  the game source — edit here
  07-tools-notes        upstream test scripts, cheat harnesses, check-compile
  08-agbcc              legacy compiler (kept for reference, unused)
  09-reference-roms     older reference build
```

`modules/` is fully regenerable from `archives/`, which is why it is not
committed. Everything the toolchain produces (ROM, `.elf`, `.map`, `build/`
object cache) lives under `modules/06-eliteredux-source/`.

## How the aarch64 (qemu) mode works

The bundled toolchain is x86-64 ELF. On an aarch64 host stage 2:

1. Renames every x86-64 executable to `<name>.x86_64`.
2. Writes a tiny `#!/bin/sh` shim at the original path that exports
   `QEMU_LD_PREFIX`/`LD_LIBRARY_PATH` (pointing at a Debian trixie glibc
   sysroot in `modules/90-x86_64-root`) and `exec`s
   `qemu-x86_64 -L <sysroot> <name>.x86_64`.

Because the shim sits at the original path, *every* invocation style works —
PATH lookup, GCC's internal `cc1`/`collect2` execs, even this Makefile's
`$(shell PATH=<broken> gcc --print-prog-name=cc1)` trick (the shims are
deliberately PATH-independent). `scripts/fetch-x86_64-root.sh` builds the
sysroot: Debian trixie base with dependency closure, plus the Ubuntu noble
ffmpeg 6.1 libraries the mGBA harness needs, resolved iteratively until
`import mgba` succeeds.

Verified end-to-end on aarch64/PRoot: full build `MAKE_EXIT=0` in ~70 min
(vs 15-30 min native) and a clean mGBA boot test.

## Editing and building elsewhere

Two supported workflows:

- **Edit + build locally** — change files under `modules/06-eliteredux-source/`,
  then `./run.sh --from 4`.
- **Edit here, build remotely** — the repo is self-describing: push your
  commits, then on any x86-64 Linux box (Claude/ChatGPT sandbox, CI) clone,
  `./run.sh`, done. Stage 2 is a no-op there; everything runs natively.

To move local source edits into the repo (they are gitignored via `modules/`),
copy the changed files out of `modules/06-eliteredux-source/` and commit them
wherever you keep your source drop, or re-package the module.

## Integrity and verification

- `archives/SHA256SUMS` covers every part and the joined archive; stage 0
  refuses to extract on mismatch.
- Stage 5 is a real boot test (mGBA runs 2500 frames; a crash fails the
  pipeline). It is not a gameplay playtest — see `docs/README-PROJECT.md`
  for what remains untested.

## Known quirks

- On aarch64, host processes that inherit the exported `LD_LIBRARY_PATH` may
  print musl `Error relocating ... libz.so.1` noise — harmless (they fall
  back to native libs) and never affected the build result.
- `flips-linux` links GTK 3, which the sysroot intentionally omits; it is not
  used by the build. Apply `.bps` patches with flips on a desktop if needed.
- Fresh builds differ from the shipped reference ROM by a few bytes
  (embedded timestamps), which matches the upstream package's own notes.

## Documentation

- `docs/README.md` — documentation index + reading order
- `docs/README-SETUP.md` — deep dive: extraction format, toolchain fixes,
  build gotchas (all still true), packaging history
- `docs/project/` — the game-side docs, split by topic:
  `fixes.md` (source fixes 3-33 with verification status),
  `game-changes.md` (Shedinja, custom abilities, learnsets),
  `cheats.md` (emulator-verified cheat codes),
  `testing.md` (mGBA harness usage, struct-offset derivation),
  `open-findings.md` (open items + playtest priorities)
