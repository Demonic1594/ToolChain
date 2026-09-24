# Elite Redux toolchain - SETUP guide

> **Modular repo note:** this guide documents the *original flat package*.
> In this repository the same content lives under `modules/`, and the old
> one-shot scripts are replaced by the stage runner:
>
> | Original | Here |
> |---|---|
> | `setup.sh` (source it) | `source scripts/02-env.sh` (done automatically by `./run.sh`) |
> | `restore-exec-bits.sh` | `scripts/01-restore-exec-bits.sh` (stage 1) |
> | manual `make -j1` + `runmake-background.sh` | `scripts/03-build.sh` / `./run.sh --only 4` |
> | `eliteredux-source/` | `modules/06-eliteredux-source/` |
> | `gcc-arm-none-eabi/`, `binutils-arm-none-eabi/`, `jdk-21/`, `kotlinc/`, `python3.11-mgba/`, `tools-notes/`, `reference-roms/` | `modules/02-gcc/`, `modules/01-binutils/`, `modules/03-jdk/`, `modules/04-kotlinc/`, `modules/05-python-mgba/`, `modules/07-tools-notes/`, `modules/09-reference-roms/` |
> | the LZMA zip | `archives/` (split parts; stage 0 rejoins and verifies them) |
>
> Start at the repository root `README.md` for the quick start. Everything
> below (gotchas, toolchain fixes, packaging notes) still applies as written.

Everything about **getting the package running**: extracting it, environment
setup, building, gotchas, and how the archive itself is packaged.
For game changes, cheats, learnset edits, bug-fix notes and the emulator test
harness, see **`README-PROJECT.md`**.

Quick pointer for a new session: `./run.sh` (or, manually: stages 0-3, then
`cd modules/06-eliteredux-source && make -j1`).

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
bash restore-exec-bits.sh      # from the package root
```

(`7z`/real `unzip` builds preserve permissions, so the script is only needed
for the Python route.) Then `touch` the prebuilt host tools so `make` does not
try to rebuild them (details under the session log below).

## What's in here

| Folder | What it is |
|---|---|
| `eliteredux-source/` | The patched Elite Redux source tree (the "upcoming" branch, not "master" - see below). Updated to **v2.65.2.3b**; `pokeemerald_modern.gba`/`.elf`/`.map` in the tree root are a fresh `make -j1` build of exactly this source (`build/` object cache is not shipped, so the next `make` is a full ~8-20 min build) |
| `gcc-arm-none-eabi/` | Modern ARM cross-compiler (GCC 13.2), trimmed to just the parts actually used (removed ~2.7GB of unused Cortex-M/R multilib variants) |
| `binutils-arm-none-eabi/` | ARM assembler/linker/objcopy/etc (matches the gcc version) |
| `agbcc/` | The legacy compiler this project's `INSTALL.md` mentions - built from source, but **not what actually works** for this codebase (see below) |
| `jdk-21/` | Java JDK (javac + runtime) - needed to compile the proto codegen tool |
| `kotlinc/` | Kotlin compiler - also needed for the codegen tool (part of it is Kotlin) |
| `python3.11-mgba/` | Custom-built Python 3.11 (the system only had 3.12) with `mgba`, `cffi`, and `capstone` installed - a full scriptable GBA emulator for testing |
| `mgba-libs/` | The actual `libmgba.so` + dependencies (`libinih`, `libzip`) that the Python bindings need at runtime |
| `setup.sh` | Sets up a unified toolchain directory + exports all the env vars below. **Source it, don't execute it.** |
| `restore-exec-bits.sh` | Restores executable bits after a Python-based extraction and touches prebuilt host tools. Run with `bash`, not `source` |
| `tools-notes/` | Emulator test scripts and the C stub examples used for cheats / calling game functions (see `README-PROJECT.md`), plus `check-compile.sh` - compiles single files with the exact Makefile flags in seconds (much faster than a full build) |
| `reference-roms/` | `pkmn-emerald_modern.gba`: ROM built from this source plus the bug-hunt fixes (5-9 in `README-PROJECT.md`; fixes 10-27 were added after it, so it will differ) by an earlier session; for comparison only |

## The single most important thing to know

**Use the `upcoming` branch / this `eliteredux-source/` tree, built with
`gcc-arm-none-eabi` (the "modern" build). Do NOT use the `master` branch.**

Why: `master` has no code-generation pipeline (no `proto/`, no
`.gitmodules`). Its data files (abilities, species stats, move data) are
stale, hand-committed placeholders. A ROM built from `master` *compiles
successfully and boots fine* - but plays like vanilla Emerald with broken
Elite Redux mechanics, because the actual current game-balance data was
never wired in. This took a long time to figure out and produced two
"working" ROMs that were actually wrong before the real cause was found.

`eliteredux-source/` (from the `upcoming` branch) has a real pipeline:
`.proto`/`.textproto` files in `proto/` get compiled by a Kotlin/Java tool
(`tools/codegen/`) into the actual C/C++ source data (`src/abilities.cc`,
generated headers, etc.) at build time. This is the one that's actually
correct. It also needs `gcc-arm-none-eabi`, not `agbcc` - the codebase
uses modern C bitfield syntax that `agbcc` can't even parse.

The `agbcc/` folder is included because the project's own `INSTALL.md`
tells you to use it, and it's needed if you ever want to build the
*original* `master` branch for comparison - but for this patched source
tree, ignore it and use the modern toolchain instead.


## Toolchain fixes applied in this package version

Two build-breaking toolchain issues were found and fixed in this version of
the package (game-source fixes are listed in `README-PROJECT.md`):

1. **Bundled JDK was missing its runtime** - `jdk-21/` originally shipped
   with only `jmods/` (module definitions), not an actual runnable
   `bin/`/`lib/` JDK - so `java`/`javac` didn't exist. Fixed by using the
   `jdk.jlink` module (itself one of the bundled jmods) to link a real,
   complete JDK-21 runtime image directly from the bundled `jmods/`
   folder - no download, network, or host JDK required:

   ```bash
   # bootstrap jlink using any JDK-21+-compatible `java` on the host,
   # then have it link a full runtime from this package's own jmods
   java -p <exploded-jdk.jlink-and-deps-classes> \
     -m jdk.jlink/jdk.tools.jlink.internal.Main \
     --module-path jdk-21/jmods --add-modules ALL-MODULE-PATH \
     --output jdk-21-runtime
   ```

   `jdk-21/` now contains a genuine full JDK (`bin/java`, `bin/javac`,
   `lib/server/libjvm.so`, etc.) built straight from the jmods that were
   already in the package, alongside the original `jmods/` folder (kept
   for reference / future custom images). If this ever regresses again,
   the jmods are self-sufficient to rebuild the runtime the same way -
   no need to hunt down a matching JDK install elsewhere.

2. **Makefile had a hardcoded, machine-specific library path** -
   `eliteredux-source/Makefile`'s modern-build `LIBPATH` pointed at
   `/home/claude/toolchain/gcc_arm_extract/...`, an absolute path from
   the machine the Makefile was last generated on. On any other
   machine/session this doesn't exist, so linking fails with `cannot
   find -lc` / `cannot find -lgcc`. Fixed by deriving the path at build
   time instead of hardcoding it again: `LIBPATH` now resolves the real
   `gcc-arm-none-eabi` install location by following the
   `arm-none-eabi-gcc` symlink inside `$(DEVKITARM)/bin` (the directory
   `setup.sh` builds), so it works no matter where this package gets
   extracted:

   ```make
   GCC_ARM_ROOT := $(shell dirname $$(dirname $$(readlink -f $(TOOLCHAIN)/bin/arm-none-eabi-gcc)))
   LIBPATH := -L "$(GCC_ARM_ROOT)/lib/gcc/arm-none-eabi/13.2.1" -L "$(GCC_ARM_ROOT)/lib/arm-none-eabi/newlib"
   ```

   No `setup.sh` changes were needed for this one - it only relies on
   `DEVKITARM`, which was already being exported. Both fixes were
   verified directly (a full JDK compile-and-run round-trip, and a real
   `arm-none-eabi-gcc` compile+link using the new `LIBPATH`) rather than
   just inspected.


## Quick start

```bash
cd wherever-you-extracted-this
source setup.sh          # NOT ./setup.sh - it needs to export into your shell
cd eliteredux-source
make -j1
```

That's it, assuming your machine already has `build-essential` and
`libpng-dev` (very standard packages, `apt install build-essential
libpng-dev` if not). Everything ARM/Java/Kotlin-specific is self-contained
in this package.

### Important build gotchas (all real things that happened)

- **`make` can take 15-30+ minutes on a single core.** If your tool/shell
  has a timeout shorter than that (ours was 300 seconds per command), you
  cannot run it in one shot. Run `make -j1` repeatedly - it's incremental
  and will resume where it left off. **But check for 0-byte object files
  first if a run got killed mid-compile**: `find build -size 0 -name
  "*.o" -delete` before resuming, or you'll get baffling "undefined
  reference" link errors from a truncated file that looks up-to-date to
  `make`'s timestamp check.
- **`DEVKITARM` env var must be set** (setup.sh does this). The
  Makefile's internal `PATH_MODERNCC` construction is broken without it -
  it builds a nonsense PATH string and silently falls through to
  "command not found" for the compiler.
- **A bare `as`/`ld` must resolve to the ARM ones, not the host's.** GCC
  invokes a plain unprefixed `as` internally via PATH lookup rather than
  `arm-none-eabi-as`. Without the symlink shim setup.sh creates, it
  silently picks up the host x86_64 assembler and produces broken output
  with a confusing `-march=armv4t` error that looks like the ARM
  assembler is broken (it isn't - it's not even being called).
- **`CPATH` / `CPLUS_INCLUDE_PATH` must point at the newlib headers.**
  This GCC was built `--without-newlib`, so it doesn't auto-discover
  `string.h` etc. via the usual relative path trick. setup.sh sets these.
- Two GCC-version compatibility patches are already applied to the
  Makefile in `eliteredux-source/`: `-std=gnu23`/`gnu++23` were downgraded
  to `-std=gnu2x`/`gnu++2b` (this GCC is 13.2; the newer flag names only
  exist in GCC 14+), and `-Wno-builtin-declaration-mismatch
  -fno-strict-aliasing` were added (real ABI-assumption mismatches and
  aliasing warnings that are otherwise fatal under `-Werror`). If you ever
  regenerate the Makefile from a fresh source pull, you'll need to
  reapply these.
- **`make tools` will try to `wget` a few things** (protoc, poryscript,
  the Kotlin protobuf plugin) if they're missing - this fails with no
  network. They're already built/placed correctly inside
  `eliteredux-source/tools/` in this package, so this shouldn't trigger,
  but if you ever wipe `tools/` and start over, you'll need to feed those
  binaries back in manually (same sources as this package: `protoc`,
  `protobuf-java.jar`, `protobuf-kotlin.jar` are all sitting in
  `eliteredux-source/tools/codegen/`; `poryscript` is in
  `eliteredux-source/tools/poryscript/`).
- **If this package was ever unzipped with Python's `zipfile` module
  instead of a real `unzip`/`7z`, every binary loses its executable
  bit.** This bit us directly: the toolchain was originally shipped as
  an LZMA-compressed zip (compression method 14), which the `unzip`
  CLI can't read at all (`error in EOCD` / silently refuses it) even
  though `unzip -l` lists the contents fine. Python's `zipfile` *can*
  decompress method 14, but `ZipFile.extractall()` does not restore
  Unix permission bits by default - it can't even by reading
  `external_attr`, since this particular archive had no permission
  bits recorded in it at all (0 for every entry). Net effect: a clean,
  intact-looking extraction where `arm-none-eabi-gcc`, `cc1`, `cc1plus`,
  `java`, every `.so`, etc. are all present but not executable, which
  shows up as a confusing `Permission denied` rather than a `command
  not found`. Fix if you hit this: `find <toolchain-dir> -type f
  \( -path "*/bin/*" -o -name "*.so*" -o -name "cc1*" \) -exec chmod +x
  {} \;` (or just re-extract with real `unzip`/`7z`, which preserve
  permissions correctly).
- **`ZIP_LZMA` still needs `unzip`/`7z` on the extracting end, same as
  the original archive this package started from.** Plain `unzip` reads
  standard DEFLATE zips fine but chokes on LZMA-compressed ones
  (`error in EOCD signature` or a silent refusal, even though `unzip -l`
  lists the contents correctly). If you only have `unzip` available,
  extract with Python instead: `python3 -c "import zipfile;
  zipfile.ZipFile('this.zip').extractall('.')"` - it reads LZMA fine,
  but (per the point above) won't restore executable bits, so
  `chmod +x` the `bin/`/`lib*.so`/`cc1`/`cc1plus` files afterward.

## Packaging for delivery through a chat interface

This package has to pass through Claude's chat upload/download path at
some point, which enforces a **500 MB per-file limit** - a file over
that silently shows "downloading" and then "no longer available" when
clicked, with no clearer error. That constraint, plus wanting to keep
`jdk-21/` and `kotlinc/` in the package rather than cut them, is why
this archive is `ZIP_LZMA`-compressed instead of a plain `zip -9`:

- **A first pass with standard DEFLATE (`zip -9`) couldn't fit
  everything.** The raw unpacked toolchain is ~1.3-1.5 GB depending on
  whether `eliteredux-source/build/`'s object-file cache is included.
  `zip -9` of the whole thing (including `jdk-21/`/`kotlinc/`) came out
  around 630 MB even at max DEFLATE effort - over the limit - because
  most of the bulk is already-compiled ELF binaries, `.jar`s, and
  archives (`cc1`, `cc1plus`, `libstdc++.a`, the JVM's module image,
  Kotlin's compiler jars) that DEFLATE's window size doesn't handle
  well. Dropping `jdk-21/`+`kotlinc/` entirely got a DEFLATE build down
  to ~295 MB, but that meant shipping a toolchain that can't run the
  `tools/codegen/` proto pipeline at all.
- **Switching to LZMA (`compression=zipfile.ZIP_LZMA` via Python's
  `zipfile` module - the same compression method, and the same reason,
  as the very first version of this package) got everything back in
  under budget: ~417 MB for the complete toolchain, `jdk-21/`,
  `kotlinc/`, and all.** LZMA's larger dictionary window compresses
  this kind of content meaningfully better than DEFLATE - e.g. `jdk-21/`
  alone: 261 MB raw -> 146 MB with `zip -9` DEFLATE, but only 120 MB
  with LZMA. It's not a universal win (`kotlinc/`'s jars barely
  shrink either way, they're already DEFLATE-compressed internally),
  but combined across the whole tree it was the difference between
  fitting and not.
- **One real cost: LZMA compression is slow, and single-threaded here
  (`nproc` = 1) hits a 300-second-per-command wall.** Compressing the
  whole package in one `zipfile.ZipFile(...).write()` loop timed out
  partway through with no output captured (writes may have been
  incomplete). The fix was to build the archive incrementally: open in
  append mode (`'a'`), write one top-level component per command
  (`agbcc`, then `python3.11-mgba`, then `gcc-arm-none-eabi/lib`
  separately from the rest of `gcc-arm-none-eabi`, etc., checking
  `zipfile.namelist()` first each time so nothing gets double-added),
  and let the file accumulate across multiple calls rather than one
  giant one. If you need to rebuild this archive fully and have more
  than one core or a longer per-command budget available, a single
  `zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_LZMA)` pass over
  the whole tree is simpler and gives the same result - the chunking is
  a workaround for this environment's limits, not a requirement of the
  format.
- `devkitARM/` is still excluded from the delivered zip on purpose, not
  for size - it's nothing but the symlinks `setup.sh` recreates
  automatically, so shipping it is redundant. `eliteredux-source/build/`
  (the ~100 MB incremental object-file cache) is also still excluded -
  regenerable by just running `make` again (see "What is
  `eliteredux-source/build/`" below for what that costs you).
- If a future edit ever needs to ship the `build/` cache too (e.g. to
  hand off mid-build across sessions) and that pushes back over budget
  even with LZMA, split the delivery into two archives rather than
  dropping `jdk-21`/`kotlinc` again - losing the codegen pipeline is a
  bigger loss than a second download.

## What `eliteredux-source/build/` is, and why dropping it from a
## delivered package is safe

`build/` is `make`'s incremental object-file cache - one `.o` per
source file, timestamped, so a re-run of `make` only recompiles files
that changed since the last build instead of starting over. It is pure
build output, not source: everything in it is fully and deterministically
regenerable from what's already in `eliteredux-source/` (source files +
the toolchain), so a package that omits it isn't missing anything - the
already-built `pokeemerald_modern.gba`/`.elf`/`.map` sitting in the repo
root are proof the source + toolchain combination in this package
produces a working ROM.

**The only actual effect of omitting `build/` is build speed on the
next session**, not correctness: with it, `make -j1` only rebuilds
files touched since the cache was made (seconds to a couple minutes
for a small edit); without it, the very next `make -j1` has to compile
every single translation unit from scratch, which is the 15-30+ minute
full build mentioned under "Important build gotchas" above. There's no
scenario where a missing `build/` produces a *different* or *broken*
ROM compared to having it - worst case is just paying the full-build
time again instead of an incremental one.


## Session log: extracting and building in a restricted sandbox

Everything below actually happened when this package was rebuilt in a sandbox
with no network, one core, and no `7z`:

- No `7z`/`7zz`, and `unzip` refuses the LZMA archive. Extract with
  `python3 -c "import zipfile; zipfile.ZipFile('pkmn-ER-toolchain-full.zip').extractall('.')"`.
- Then restore exec bits (Python does not): the toolchain binaries **and** the
  project's own tools. The one-liners from the gotchas above cover
  `bin/`, `*.so*` and `cc1*`; also do
  `gcc-arm-none-eabi/libexec` and every ELF/script under
  `eliteredux-source/tools/` (`scaninc`, `mapjson`, `gbagfx`, `protoc`, ...) plus
  `eliteredux-source/flips-linux`. Symptom of missing bits:
  `tools/scaninc/scaninc: Permission denied` and
  `mapjson: Permission denied` (make error 126).
- **Touch the prebuilt host tools after extracting.** Extraction gives every file
  a fresh timestamp in arbitrary order, so `make` sometimes decides a tool
  such as `tools/aif2pcm/aif2pcm` is older than its `.c` and tries to rebuild
  it with the host `cc`. With `setup.sh` sourced that fails (ARM newlib headers
  via `CPATH`, and the ARM `as` shim: `as: unrecognized option '--64'`).
  Fix: `touch` the tool binaries so make leaves them alone.
- `setup.sh` must be sourced from **bash** (`bash -c 'source setup.sh; ...'`);
  in a plain `sh` shell `source` does not exist.
- A background `nohup make &` launched from a tool call can be killed when the
  call returns (empty log, no make process). Use a wrapper script plus
  `setsid nohup ./runmake.sh >/dev/null 2>&1 < /dev/null &` and write
  `MAKE_EXIT=$?` to the log so completion is unambiguous. The first full build
  from an empty `build/` took roughly 15-20 minutes on one core; incremental
  rebuilds after a learnset edit took about 8 minutes (the generated headers
  touch many translation units).
- Verified after building: the ROM boots in the bundled mGBA harness
  (2500 frames, intro scene renders). The moves have not been playtested in
  a real battle.

## Session log: applying and building fixes 28-33 (warning-sweep pass)

- Fixes 28-33 (see `README-PROJECT.md`) arrived as a written description
  only - no diff/patch file - from a session that had run out of tool calls
  before finishing. Each fix's file and described symptom was specific enough
  to grep straight to the exact line (`hours >= 20 && hours <= 3`,
  `status2 && STATUS2_TRANSFORMED`, etc.); all six matched the description
  exactly on the first grep, with no guessing needed about which site was
  meant.
- Fix 33 (`GetBestMonOffensive`) needed slightly more than a one-line change:
  fixing "renormalize with `ApplyModifier`" required finding the project's
  own convention for chaining fixed-point (`UQ_4_12`) multiplications
  (`val = ApplyModifier(modifier, val)`, used throughout `battle_ai_attack.c`)
  rather than inventing a shift-and-round by hand.
- All four touched files passed `tools-notes/check-compile.sh` (`-Werror`)
  before attempting a full build.
- Ran the background-build pattern from the section above via the new
  `tools-notes/runmake-background.sh` wrapper (`setsid nohup bash -c '...'`
  writing `MAKE_EXIT=$?` to a log). This build was faster than the
  first-ever full build described above (~8 minutes here vs. 15-20 minutes
  for an empty `build/`), since `build/`'s object cache from the earlier
  session was still present going in and only files touched by fixes 28-33
  (plus their dependents) needed recompiling.
- `MAKE_EXIT=0`, no errors anywhere in the log outside of filenames
  containing the word "error" (e.g. `se_rg_help_error.s`, a sound-effect
  asset name, not an actual error). EWRAM/IWRAM/ROM usage percentages came
  out identical to the pre-28-33 build, as expected - none of these six
  fixes touch a struct layout.
- Booted the resulting ROM in the mGBA harness the same way as before: 2500
  frames, Groudon logo renders, no crash. Not a real playtest.
- Re-checked `gBattleMons`/`gVolatileStructs`/`gSideStatuses` in the fresh
  `.map` against the previously re-derived addresses - unchanged, confirming
  the cheat tables in `README-PROJECT.md` don't need another update.

## Session log: source drop swap + rebuild (v2.65.2.3b, delta-only)

- Outer zip held `README*.md` plus the inner `pkmn-ER-toolchain__LZMA__.zip`.
  Inner zip extracted with Python `zipfile` (no `7z`; `unzip` can't read LZMA),
  then `bash restore-exec-bits.sh` (354 files chmod +x).
- The new source zip was extracted to a scratch dir and compared file-by-file
  (MD5) against the toolchain's `eliteredux-source/`. Only differences were
  applied: **19 changed files** (`proto/AbilityEnum.proto` with
  `ABILITY_FLUFFIEST_ONE`, the generated ability/species headers,
  `src/abilities.cc`, `cry_table.h`, and the regenerated codegen
  `.binpb`/`.jar`/`.class`/`.java` outputs) and **4 new files** (the prebuilt
  `.gba`/`.elf`/`.map`/`.sav`). 54,464 unchanged files were left untouched.
  The three `README*.md` files were taken from the source zip too
  (`README-SETUP.md` was identical).
- `tools-notes/runmake-background.sh` -> `MAKE_EXIT=0`, full build from an
  empty `build/` took about 8 minutes on one core. EWRAM 250,954 B (95.73%),
  IWRAM 25,960 B (79.22%), ROM 23,733,792 B (70.73%) - same as the shipped
  build. The rebuilt `.gba` differs from the one in the source zip by only 4
  bytes.
- Booted in the mGBA harness for 2500 frames with no crash (Groudon intro
  renders). Not playtested in battle.
- Repackaged: inner zip re-created with `ZIP_LZMA`, excluding `devkitARM/`
  (setup.sh recreates it) and `eliteredux-source/build/`.
