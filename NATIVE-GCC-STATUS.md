# Native aarch64 GCC fast lane — status

Goal: replace the qemu-wrapped x86-64 GCC with Arm's official
**aarch64-hosted arm-none-eabi 13.2.rel1** (same compiler snapshot as the
bundled x86-64 build) so the C-compile phase stops paying emulation.
Expected: full rebuild ~20 min → ~6-8 min.

## What's in place (verified)

- `scripts/fetch-arm64-glibc-root.sh` → `modules/91-arm64-glibc-root/`:
  minimal trixie arm64 glibc runtime (loader + libc/libstdc++/gmp/mpfr/
  mpc/isl/zlib, dependency-closed, ~40 MB). Works.
- `modules/10-native-gcc/`: Arm's aarch64-hosted arm-none-eabi 13.2.rel1,
  all 42 ELFs patchelf'd (interpreter + forced rpath into the glibc root).
- The **driver and binutils run natively at full speed**:
  `arm-none-eabi-gcc --version`, `readelf`, `strip` all work.

## RESULT (2026-09-26): PROVEN BYTE-IDENTICAL on arm64 CI

GitHub `ubuntu-24.04-arm` (job `native-arm64` in build.yml, this branch):
full build with Arm's aarch64-hosted 13.2.rel1 (`ER_ARM_TC=native`,
target-side newlib/libgcc symlinked from the bundled toolchain — Arm's
release has no armv4t multilib) produced a ROM with sha1
`cea43568995096706a404ea96492b5accb52d429` — identical to the same
commit's x86_64-toolchain build. Same-snapshot/different-host GCC emits
identical ARM code. EWRAM/IWRAM/ROM usages match exactly. The lane is
proven; promotion on any real arm64 glibc host is a default flip.

CI timing reference: whole arm job 3m51s including toolchain download,
poryscript-from-source, `make tools`, codegen and full build at -j4
(x86 job: 3m17s on a 4-core runner).

## The blocker (local PRoot only)

`cc1` (and by extension `cc1plus`, `lto1`, `collect2`-adjacent binaries)
dies with SIGSEGV **at exec time** under PRoot — before the dynamic loader
prints anything, even with `LD_DEBUG=libs`, `GLIBC_TUNABLES` hwcap
masking, loader-explicit invocation, or stripping. The driver (small, C)
runs; cc1 (34 MB, C++, EXEC at base 0x3e0000) does not. Every path on
this device goes through PRoot, so there is no local escape hatch.

Verdict: a PRoot↔large-glibc-EXEC incompatibility, not a toolchain defect.
The exact same layout should run fine on any non-PRoot aarch64 Linux.

## Where to pick this up

1. **GitHub arm64 runners** (free for public repos: `ubuntu-24.04-arm`):
   extract the toolchain, run `scripts/fetch-arm64-glibc-root.sh`, patchelf
   as in this branch, and add a CI job that builds with the native lane.
   If the resulting ROM is byte-identical to the x86-64 build (same 13.2
   .rel1 snapshot — plausible), the lane is proven and this branch can
   wire it into `02-env.sh` behind `ER_ARM_TC=native`.
2. **Real aarch64 hardware** (a Linux box/VM, not Android+PRoot).
3. Not worth doing locally: a hybrid with native driver/as but qemu cc1 —
   cc1 dominates compile time, the win is marginal.

## Artifacts left in the working tree (untracked)

- `modules/10-native-gcc/` — patched toolchain (~1.5 GB)
- `modules/91-arm64-glibc-root/` — glibc runtime (~40 MB)
- `/tmp/opencode/baseline-qemu-132.gba` — 13.2 baseline ROM (sha1
  `1bd6ad8f…`) for the future byte-comparison


## Termux experiment (2026-09-26, later): CLOSED - device cannot host cc1

The full bridge was built and works (token-gated localhost HTTP from the
PRoot side, file exchange, remote exec). Every supporting layer was made
to run natively in Termux: the Arm 13.2 driver + binutils (glibc-root +
patchelf), all 11 host tools (Termux clang; needed CPATH scrubbing -
02-env exports the ARM newlib headers globally, which poisons host-tool
compilation), codegen (musl protoc 31.1 + shipped v61 jars behind a new
CODEGEN_PREBUILT_JARS=1 makefile switch), poryscript (Go, builds fine).

The one thing that cannot run on this device, in ANY configuration:

| cc1 variant | Execution layer | Result |
|---|---|---|
| Arm 13.2 (glibc) | direct exec | SIGSYS - Android app-domain seccomp kills `set_robust_list` at loader startup (strace-confirmed) |
| Arm 13.2 (glibc) | and-code PRoot | SIGSEGV at exec (34 MB EXEC) |
| Arm 13.2 (glibc) | Termux proot-distro Debian | SIGSEGV - identical |
| Alpine 16.1 (musl) | direct + loader trick | SIGSEGV |

Small native binaries (gcc driver, protoc, binutils) all run fine; only
the large compiler image dies everywhere. Conclusion: no software layer
on this phone can host the game compiler; the native lane is CI/arm64-
hardware only. The Termux lane was closed and the Termux-side modules
restored (Arm 13.2 preserved at modules/10-native-gcc for reference).

Deliverables that DO work and stay: the CI `native-arm64` job
(byte-identical, ~4 min), the bridge (general Termux remote-exec),
fetch-arm64-glibc-root.py, and the Termux quirk catalogue below.

### Termux quirks catalogue (hard-won, do not rediscover)

- No /tmp; use $TMPDIR (=$PREFIX/tmp)
- No /bin, /usr/bin: absolute-shebang scripts and Makefile
  `SHELL := /bin/bash` need patching; termux-exec (LD_PRELOAD) normally
  translates but must be scrubbed for glibc/musl binaries (it drags in
  bionic libc.so and breaks foreign loaders)
- tar extraction: hardlinks unsupported (EPERM) - extract with a
  copy-converting Python extractor; symlinks cannot be extracted in
  tarfile stream mode - defer them
- Termux clang defaults to compiling host tools against the CPATH the
  toolchain env exports (ARM newlib) -> scrub CPATH/CPLUS_INCLUDE_PATH
  for host-tool builds
- poryscript is Go, not C++; `pkg install` needs no cmake
- Alpine musl binaries run via patchelf'd bundled musl loader + rpath
  (protoc precedent), but large ones (cc1) do not survive
- cc1 death mechanism (final strace, unpatched binary via explicit
  musl loader): kernel maps all LOADs, then SIGSEGV ACCERR on the first
  write into the executable image (0x68fef0, inside the RX text
  mapping). Not patchelf, not DT_RELR, not page size (kernel is 4k,
  confirmed via `-4k` suffix + getconf). This Android build enforces a
  write-vs-execute policy on file-backed mappings in the app domain
  that small binaries never trip but the ~27 MB compiler image does -
  no userspace workaround exists without relinking cc1

## TERMUX CLANG LANE: WORKING (2026-09-26, final)

After the glibc/musl GCC lanes were ruled impossible on this device, a
clang-based lane was built and verified:

- **Compiler**: Termux's native bionic clang 21.1.8 (--target=arm-none-eabi)
- **Assembler**: clang integrated-as (with -Wa,-defsym and syntax patches)
- **Linker**: Alpine musl GNU ld 2.45.1 (ld.bfd) with bundled newlib/libgcc
- **Speed**: C-compile rebuild in **105 s** at -j4 (vs ~18 min qemu = ~10x)
- **Verification**: MAKE_EXIT=0, ROM boots in mGBA 2500 frames, memory
  usage sane (EWRAM 95.44%, ROM 69.87%)

### Hybrid architecture (what compiles where)

| Component | Compiled by | Where |
|---|---|---|
| ~320 C files (src/*.c, gflib/*.c) | **Termux clang** | phone, native |
| 3 C++ files (abilities.cc, battle_skills.cc, script_conditions.cc) | qemu GCC | phone (prebuilt .o) |
| m4a_1.s + 3 battle script .s files | qemu GCC | phone (prebuilt .o) |
| 16 data .o (battle_anim, event_scripts, etc.) | qemu GCC | phone (prebuilt .o) |
| ~716 sound/song .o | qemu GCC | phone (prebuilt .o) |
| Link (GNU ld + newlib/libgcc) | **musl GNU ld** | phone, native |

Prebuilt objects are controlled by HYBRID_OBJS=1 (empty-recipe in Makefile);
they are deterministic given unchanged sources and only need re-shipping
when their sources change.

### Clang-GCC compatibility shims (scripts/termux/clang-lane-final.sh)

- Flag translation: strips -fno-toplevel-reorder, -mabi=apcs-gnu,
  -mtune=arm7tdmi, -mthumb-interwork, -fhex-asm, -Wno-builtin-declaration-
  mismatch (all GCC-only)
- Warning suppression (~28 flags, all appended AFTER incoming args to
  survive clang's -Wall re-enabling)
- .syntax divided -> .syntax unified (include/global.h, one-line patch)
- .set symbols in Thumb imm5 slots: add # prefix (libgcnmultiboot.s)
- GNU-as lax movs in thumb: mov -> movs (libagbsyscall.s)
- as shim: -Wa,-defsym syntax + -o/stdin handling
- ld shim: musl GNU ld with -L to bundled newlib/libgcc
- C++ (-Wno-error + -D_LIBCPP_HAS_NO_THREADS to avoid libc++ trap)

### NOT byte-identical

The ROM differs from the GCC build (~62% of bytes) due to clang codegen.
It boots and behaves correctly, but is a **different toolchain's output**.
The byte-identical lane remains CI (native-arm64 job) or real arm64
hardware with the glibc GCC 13.2 lane.
