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

## The blocker

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
