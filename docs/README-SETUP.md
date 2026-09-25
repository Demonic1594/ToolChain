# Elite Redux toolchain — SETUP guide

Everything about **getting the toolchain running**: extracting it, environment
setup, building, gotchas, and how the archive is packaged. The original
version of this guide described a flat package; here the same content lives
under `modules/` with `scripts/` stages replacing the old one-shot scripts
(`source scripts/02-env.sh` ≡ old `setup.sh`, etc.).

For game changes and bug-fix notes see **[project/](project/)**; for the
textproto → C data pipeline see **[README-CODEGEN.md](README-CODEGEN.md)**.

Quick pointer for a new session: `./run.sh` (or manually: stages 0-3, then
`cd modules/06-eliteredux-source && make -j3`).

## Contents

- [Extracting (read this first)](#extracting-read-this-first)
- [What's in here](#whats-in-here)
- [The single most important thing to know](#the-single-most-important-thing-to-know)
- [Toolchain fixes applied in this package](#toolchain-fixes-applied-in-this-package)
- [Quick start](#quick-start)
- [Important build gotchas](#important-build-gotchas-all-real-things-that-happened)
- [Packaging notes](#packaging-notes)
- [What `build/` is, and why dropping it is safe](#what-build-is-and-why-dropping-it-is-safe)
- [Historical session logs (condensed)](#historical-session-logs-condensed)

## Extracting (read this first)

The archive is **LZMA-compressed zip (method 14)**. Plain `unzip` cannot read
it. Use `7z x <file>.zip` if available, otherwise Python (no 7z needed):

```bash
python3 -c "import zipfile; zipfile.ZipFile('this.zip').extractall('.')"
```

This archive was built with Unix permission bits recorded in each entry, but
Python's `extractall()` still does NOT restore them. If you extracted with
Python, run the exec-bit restore script that ships in the package:

```bash
bash scripts/01-restore-exec-bits.sh   # stage 1 of run.sh
```

(`7z`/real `unzip` builds preserve permissions, so the script is only needed
for the Python route.) The script also touches the prebuilt host tools so
`make` does not try to rebuild them. In this repository you normally never
do any of this by hand — `./run.sh` runs stages 0-2 for you.

## What's in here

| Folder | What it is |
|---|---|
| `modules/06-eliteredux-source/` | The patched Elite Redux source tree (the `upcoming` branch — see below). **v2.65.2.3b** plus the fix batches documented in [project/fixes.md](project/fixes.md) |
| `modules/02-gcc/` | Modern ARM cross-compiler (GCC 13.2), trimmed to just the parts actually used (removed ~2.7 GB of unused Cortex-M/R multilib variants) |
| `modules/01-binutils/` | ARM assembler/linker/objcopy/etc (matches the gcc version) |
| `modules/08-agbcc/` | The legacy compiler the project's `INSTALL.md` mentions — built from source, but **not what works** for this codebase (see below) |
| `modules/03-jdk/` | JDK 21 (java + javac) for the proto codegen tool; on aarch64 a native host JDK ≥ 17 is preferred instead (see [README-CODEGEN.md](README-CODEGEN.md)) |
| `modules/04-kotlinc/` | Kotlin compiler — also needed for the codegen tool |
| `modules/05-python-mgba/python3.11-mgba/` | Custom-built Python 3.11 with `mgba`, `cffi`, and `capstone` — a full scriptable GBA emulator for testing |
| `modules/05-python-mgba/mgba-libs/` | The actual `libmgba.so` + dependencies the Python bindings need at runtime |
| `modules/07-tools-notes/` | Emulator test scripts, the C stub examples used for cheats / calling game functions (see [project/](project/)), plus `check-compile.sh` — compiles single files with the exact Makefile flags in seconds. Repo-tracked copy (survives `--force` re-extraction): `scripts/check-compile.sh` |
| `modules/09-reference-roms/` | An older reference ROM; carried fixes 5-9 only, useful for historical comparison |
| `scripts/02-env.sh` | Builds the unified toolchain dir + exports all env vars. **Source it, don't execute it.** |
| `scripts/01-restore-exec-bits.sh` | Restores executable bits after a Python-based extraction and touches prebuilt host tools. Run with `bash`, not `source` |

## The single most important thing to know

**Use the `upcoming` branch / this `modules/06-eliteredux-source/` tree, built
with the modern GCC. Do NOT use the `master` branch.**

Why: `master` has no code-generation pipeline (no `proto/`, no
`.gitmodules`). Its data files (abilities, species stats, move data) are
stale, hand-committed placeholders. A ROM built from `master` *compiles
successfully and boots fine* — but plays like vanilla Emerald with broken
Elite Redux mechanics, because the actual current game-balance data was
never wired in. This took a long time to diagnose and produced two
"working" ROMs that were actually wrong before the real cause was found.

`modules/06-eliteredux-source/` (from the `upcoming` branch) has the real
pipeline: `.proto`/`.textproto` files in `proto/` are compiled by the
Kotlin/Java tool (`tools/codegen/`) into the actual C/C++ source data at
build time — see [README-CODEGEN.md](README-CODEGEN.md). It also needs the
modern GCC, not `agbcc` — the codebase uses modern C bitfield syntax that
`agbcc` can't even parse. `modules/08-agbcc/` is kept only for building the
original `master` branch for comparison.

## Toolchain fixes applied in this package

Two build-breaking toolchain issues were found and fixed (game-source fixes
are listed separately in [project/fixes.md](project/fixes.md)):

1. **Bundled JDK was missing its runtime** — `modules/03-jdk/` originally
   shipped with only `jmods/` (module definitions), not a runnable
   `bin/`/`lib/` JDK. Fixed by using the bundled `jdk.jlink` module to link
   a complete JDK-21 runtime image directly from the package's own `jmods/`
   — no download, network, or host JDK required. If this ever regresses,
   the jmods are self-sufficient to rebuild the runtime the same way.

2. **Makefile had a hardcoded, machine-specific library path** — the modern
   build's `LIBPATH` pointed at an absolute path from the machine the
   Makefile was last generated on; on any other host, linking failed with
   `cannot find -lc` / `cannot find -lgcc`. Fixed by deriving the path at
   build time: `LIBPATH` now follows the `arm-none-eabi-gcc` symlink inside
   `$(DEVKITARM)/bin` (the directory `scripts/02-env.sh` builds), so it
   works wherever the package is extracted.

## Quick start

```bash
cd wherever-you-extracted-this
source scripts/02-env.sh   # NOT ./scripts/02-env.sh — it exports into your shell
cd modules/06-eliteredux-source
make -j3
```

That's it, assuming the host already has `build-essential` and `libpng-dev`
(x86_64; aarch64 hosts need the qemu/sysroot setup from the root README
instead). Everything ARM/Java/Kotlin-specific is self-contained in the
package.

## Important build gotchas (all real things that happened)

- **Full builds take time; run them detached.** ~20 min at `-j3` on aarch64
  (~15-30 min native x86-64). If your shell has a command timeout, launch
  detached (`setsid nohup ... > logs/build.log 2>&1 &`) and poll the log —
  or just use `./run.sh --from 4`, which does exactly that. **After any
  killed build, delete 0-byte objects before resuming**:
  `find build -size 0 -name "*.o" -delete` — otherwise you get baffling
  "undefined reference" link errors from a truncated file that looks
  up-to-date to `make`'s timestamp check.
- **On a loaded aarch64 host, `check-compile.sh` on the giant files takes
  minutes each** (`battle_script_commands.c` 13k lines, `battle_util.c`
  9.4k, `abilities.cc` 13k C++). Small files return in ~4 s. Batch the big
  ones detached and poll; compile smallest-first to prove the toolchain
  path before committing to the long ones. An interrupted compile can
  leave a qemu-wrapped `cc1` spinning — check `ps`.
- **`DEVKITARM` must be set** (`scripts/02-env.sh` does this). Without it
  the Makefile's internal PATH construction silently falls through to
  "command not found".
- **A bare `as`/`ld` must resolve to the ARM ones, not the host's.** GCC
  invokes an unprefixed `as` via PATH lookup; without the symlink shim
  `02-env.sh` creates it silently picks the host assembler and produces
  broken output with a confusing `-march=armv4t` error.
- **`CPATH` / `CPLUS_INCLUDE_PATH` must point at the newlib headers** (this
  GCC was built `--without-newlib`). `02-env.sh` sets them.
- Two GCC-version compatibility patches are pre-applied to the Makefile:
  `-std=gnu23`/`gnu++23` downgraded to `gnu2x`/`gnu++2b` (GCC 13.2 doesn't
  know the newer names) and `-Wno-builtin-declaration-mismatch
  -fno-strict-aliasing` added. Reapply both if you ever regenerate the
  Makefile from a fresh source pull.
- **`make tools` tries to `wget` missing pieces** (protoc, poryscript, the
  protobuf jars) — fails with no network. They're prebuilt inside the
  package (`tools/codegen/`, `tools/poryscript/`); only a wiped `tools/`
  needs manual feeding.
- **Python-extracted archives lose every executable bit** (the archive
  format doesn't record them for `extractall()`). Symptom is `Permission
  denied` on `arm-none-eabi-gcc`/`cc1`/`.so`s rather than "command not
  found". Fix: `bash scripts/01-restore-exec-bits.sh`, which also covers
  `libexec`, the game tree's own `tools/` ELFs, and `flips-linux`.
- **Codegen strings are length-checked at build time** — an over-limit move
  description bakes a Java exception into a generated header and cascades
  into bizarre compile errors. Limits table + recovery recipe:
  [README-CODEGEN.md](README-CODEGEN.md).
- **aarch64 + native JDK**: musl loaders *fatal* on wrong-ELF-class libs in
  `LD_LIBRARY_PATH` (unlike glibc, which skips them). `02-env.sh` handles
  this by prefixing `/usr/lib` in native-JDK mode; if you export the env
  by hand, remember it.
- **kotlinc (jar rebuilds) needs `JAVA_OPTS=-Xmx4g`** or it dies of heap
  exhaustion mid-compile. It runs happily on a native JDK 17 — the "needs
  JDK 21" lore applied to the pre-pin jars (class version 65) and is
  obsolete.

## Packaging notes

The toolchain ships as one **LZMA-compressed zip (~447 MB)**, served as the
`toolchain-v1` GitHub Release asset; `scripts/00-extract.sh` downloads it on
demand (`TOOLCHAIN_ARCHIVE_URL` to override) and SHA256-verifies it against
the committed `archives/SHA256SUMS` before extraction. Local parts or a
joined zip are honored when present.

Why LZMA: the raw unpacked toolchain is ~1.3-1.5 GB of already-compiled
ELF binaries, jars and archives; DEFLATE (`zip -9`) bottoms out ~630 MB
(its window handles compiled content poorly) while LZMA lands ~417 MB —
the difference between fitting under a 500 MB transfer limit and not.
Excluding `modules/03-jdk/`+`04-kotlinc/` would have fit DEFLATE, but
ships a toolchain that can't run codegen — never trade them away; split
into two archives instead. `devkitARM/` (pure symlinks, recreated by
`02-env.sh`) and `modules/06-eliteredux-source/build/` (regenerable object
cache) are excluded on purpose.

If you ever rebuild the archive: LZMA compression is slow and
single-threaded; on a constrained host, write it incrementally (append
mode, one top-level component per command, check `zipfile.namelist()` to
avoid double-adding). On an unconstrained host one
`zipfile.ZipFile(path, 'w', compression=ZIP_LZMA)` pass is simpler and
identical.

## What `build/` is, and why dropping it is safe

`modules/06-eliteredux-source/build/` is `make`'s incremental object cache —
one `.o` per source file, timestamped. It is pure build output: fully
regenerable from source + toolchain, and dropping it never changes the ROM,
only the next build's wall time (full rebuild instead of seconds-to-minutes
incremental).

## Historical session logs (condensed)

Lessons preserved from the sessions that built this package; details were
accurate at the time and the underlying causes still apply.

- **Restricted-sandbox first build** (no network, one core, no 7z): Python
  `zipfile` extraction + exec-bit restore + touching prebuilt tools is the
  full bootstrap; `02-env.sh` must be sourced from **bash** (plain `sh` has
  no `source`); background builds must be `setsid nohup`-wrapped with
  `MAKE_EXIT=$?` echoed to a log or completion is ambiguous. First full
  build 15-20 min on one core; learnset-edit incremental ~8 min (generated
  headers touch many translation units).
- **Fixes 28-33 application**: fixes that arrive as written descriptions
  (no diff) grep straight to the site when the symptom text is quoted
  exactly (`hours >= 20 && hours <= 3` et al.); per-file `check-compile.sh`
  before any full build; a full log grep for "error" must exclude
  filenames like `se_rg_help_error.s` (a sound asset, not an error).
- **v2.65.2.3b source swap**: delta-apply only changed files (19 changed, 4
  new of 54k); a fresh full build reproduced EWRAM 250,954 B / IWRAM
  25,960 B / ROM ~23.7 MB and a 4-byte-different ROM vs the shipped one
  (embedded timestamps +, as later understood, JVM-dependent trainer
  symbol names — see [README-CODEGEN.md](README-CODEGEN.md)).
- **Codegen pipeline overhaul** (ships as the `patches/` overlay, applied
  by stage `01c`): the 57 per-file JVM spawns were replaced by one batched
  run (`BatchGenerator` — full regeneration ~330 s → ~13-30 s, and ~4 s on
  a native JVM; per-output make targets kept for dependency tracking, and
  deleting one output forces a single full batch regen;
  `CODEGEN_JAVA_FLAGS ?= -Xmx2g` bounds the batch heap; AppCDS/GC tuning
  measured, no consistent win, not adopted). `TrainerPartyGenerator`'s
  `__sParty_*` names were built from protobuf `List.hashCode()`, which
  mixes in per-JVM descriptor identity hashes — the real root cause of the
  historical "rebuilt ROM differs by 4 bytes" (never just timestamps); now
  a spec-stable `String.hashCode()` over TextForm output, verified
  byte-identical across reruns, batch vs per-file, and JVMs. Clean-build
  fixes in the codegen makefile: `mkdir -p $(dir ...)` before
  descriptor/dependency outputs, `google/` excluded from `PROTO_SRCS` (it
  would regenerate `com.google.protobuf.*` into `src/`, shadowing
  `protobuf-java.jar`), the `protobufkt.jar` classpath typo fixed, and
  `.textproto.bak` leftovers cleaned. Jar-rebuild gotchas: kotlinc needs
  `JAVA_OPTS=-Xmx4g`, and a stray *directory* left where the `-d` jar
  target should be (from a killed run) makes later runs emit loose classes
  instead of a jar — delete it before rebuilding.
