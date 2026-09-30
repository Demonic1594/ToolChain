# Building & verification

How this source becomes a ROM, which lanes exist, and how results are
verified.

## Build lanes

| Lane | Speed | Playable ROM? | Use |
|---|---|---|---|
| ToolChain qemu (aarch64/PRoot host) | ~20 min full (`make -j3`), 1–2 min incremental | yes (identical) | local builds |
| GitHub CI (`main` branch workflow) | ~4 min | yes (artifact attached) | every push |
| x86-64 native (`./run.sh` elsewhere) | minutes | yes | any normal Linux box |
| Termux clang bridge | ~1–2 s per file | **no** (ABI mismatch) | compile-check only |

The bundled toolchain is x86-64 ELF; on aarch64 hosts stage 2 wraps every
executable in a qemu-x86_64 shim (see `main`: README "How the aarch64 (qemu)
mode works"). Codegen avoids the qemu tax when a native JDK ≥ 17 starts.

## Building

From a ToolChain checkout (`main`) with this overlay applied:

```bash
./run.sh              # stages 0-4: verify archive → extract → env → build → verify
./run.sh --from 4     # skip straight to build+verify after editing
```

- Build output: `modules/06-eliteredux-source/pokeemerald_modern.gba`
  (+ `.elf`, `.map` for address lookup).
- `MODERN=1` is forced: arm-none-eabi GCC 13.2 (`modules/02-gcc`) — the
  modern toolchain is **required**; agbcc cannot parse this source
  (C++ abilities, designated initializers, proto codegen output).
- `make -j1` by design in the qemu lane (RAM-constrained); `-j3` verified
  on-device.
- Free ~99 MB of object cache with `make tidymodern` inside the source dir.

## Codegen environment

The proto → C generators need the bundled JDK **21** (`modules/03-jdk`;
system Java 17 fails on class version) and `modules/04-kotlinc` for Kotlin
rebuilds. `scripts/02-env.sh` (on `main`) sets the full environment; see
[data-pipeline.md](data-pipeline.md) for direct invocation.

## Verification levels

Each fix pass was verified progressively, worst-case first:

1. **Compile-check** — per-file (`check-compile.sh`, Termux lane ~1 s).
2. **Link** — full build, `MAKE_EXIT=0`.
3. **Boot test** — mGBA harness (`scripts/boottest.py` + `modules/05-python-mgba`),
   screenshot-verified title/game load.
4. **Runtime verification** — cheat tables (stat stages, always-crit,
   noclip, godmode, catch helper, money/BP/coins) exercised against the
   delivered ROM (`docs/project/cheats.md` on `main`); memory struct offsets
   derived exactly via the harness.
5. **Reproducibility** — latest delivered ROM reproduced byte-identically
   on-device; released as ToolChain **v1.1.0** (tag on `main`).

Not everything is playtested: fixes 10–27 were compile-checked only at
landing; a full playtest of the current tree is the open follow-up
(`docs/project/open-findings.md` on `main`).

## Provenance

- Baseline: upstream
  [`Elite-Redux/eliteredux-source`](https://github.com/Elite-Redux/eliteredux-source),
  `upcoming` branch, **v2.65.2.3b** — the only upstream branch with the real
  proto→C codegen pipeline (`master` builds a wrong-but-booting ROM).
- All deltas beyond it are ours, tracked in this branch at real paths (see
  [overlay.md](overlay.md) and [modifications.md](modifications.md)).
- Upstream credits, contacts and the v2.65.2.3b changelog ship untouched in
  `modules/06-eliteredux-source/README.md` + `wiki/` after extraction.
