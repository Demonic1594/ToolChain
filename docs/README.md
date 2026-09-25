# Documentation

Guides shipped with the Elite Redux toolchain package, reorganized for the
modular repository. Start at the [repository root README](../README.md) for
the pipeline itself (`run.sh`, stages, archive layout).

## Index

| Doc | What it covers |
|---|---|
| [README-SETUP.md](README-SETUP.md) | Getting the toolchain running: extraction, environment, building, every build gotcha that actually happened, packaging notes |
| [README-CODEGEN.md](README-CODEGEN.md) | The textproto → C data pipeline: where to edit game data, string length limits, jar targets, determinism, failure modes + recovery |
| [project/](project/) | Everything about the game changes themselves — start at its [index](project/README.md) |
| [project/fixes.md](project/fixes.md) | Source fixes 3-93, grouped by discovery pass, with verification status |
| [project/game-changes.md](project/game-changes.md) | Shedinja + SabreVoir reworks, custom abilities, Wonder Guard hardening, learnset tables + editing gotchas |
| [project/cheats.md](project/cheats.md) | Emulator-verified cheat codes (stat stages, always-crit, noclip) |
| [project/testing.md](project/testing.md) | mGBA harness: boot tests, save states, memory R/W, struct-offset derivation, calling game functions |
| [project/open-findings.md](project/open-findings.md) | Open/closed investigation items and the playtest priority list |

Also maintained alongside the docs: `scripts/selftest.sh` (one-command
toolchain smoke test) and `.github/workflows/build.yml` (CI: extract →
selftest → build → boot test → ROM artifact on every push).

## Reading order for a new session

1. Root [README](../README.md) — run `./run.sh`, done.
2. [README-SETUP.md](README-SETUP.md) — when something doesn't behave; the
   gotchas section explains most failure modes (wrong `as`, missing
   `DEVKITARM`, 0-byte `.o` files after a killed build, exec bits after
   Python extraction).
3. [README-CODEGEN.md](README-CODEGEN.md) — before editing any
   `proto/*.textproto` data (stats, moves, abilities, descriptions); the
   string length limits there are enforced by the build and failing them
   produces confusing errors.
4. [project/](project/) — before editing game source, so you know which
   behaviors are already fixed or deliberately left alone.

## Historical note

The three original package READMEs (`README.md`, `README-SETUP.md`,
`README-PROJECT.md`) documented a flat directory layout. They were
reorganized: SETUP stays (modernized), PROJECT was split into the `project/`
folder, CODEGEN was split out of SETUP, and the short package overview is
superseded by the root README. Root-cause notes and hard-won lessons were
preserved — condensed where the details had aged, kept verbatim where they
still teach.
