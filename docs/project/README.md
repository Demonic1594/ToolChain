# Project docs — game changes, fixes, cheats, testing

Everything about **what has been changed in the game and source**, and how to
test it. For extracting the package, environment setup and building, see
[README-SETUP.md](../README-SETUP.md); for the repository itself, start at the
[root README](../../README.md).

> Paths in these docs are relative to `modules/06-eliteredux-source/` unless
> they start with `modules/`. `tools-notes/` below maps to
> `modules/07-tools-notes/`.

## Contents

| File | What's in it |
|---|---|
| [fixes.md](fixes.md) | Source-code fixes 3-33, grouped by the pass that found them, with verification status per pass |
| [game-changes.md](game-changes.md) | Design-level changes already applied: Shedinja rework, custom abilities, Wonder Guard hardening, learnset overhaul + learnset-editing gotchas |
| [cheats.md](cheats.md) | Emulator-verified cheat codes (stat stages, always-crit, noclip) and the source hooks that enable them |
| [testing.md](testing.md) | The mGBA Python harness: boot tests, save states, memory R/W, exact struct-offset derivation, calling game functions from the emulator |
| [open-findings.md](open-findings.md) | Known-unfixed items, closed items with their conclusions, and the playtest priority list |

## Source version & build status

The source tree is **Elite Redux v2.65.2.3b** (`upcoming` branch — the only
branch with the real proto→C codegen pipeline; `master` builds a
wrong-but-booting ROM, see README-SETUP). This drop reverts Shedinja to its
classic Absolute Guard identity, flattens Mew's base stats to 110 across the
board, reworks Furret's stats/ability, and changes Ogerpon's non-Mega
abilities/innates — its own changelog ships as
`modules/06-eliteredux-source/README.md`.

Current state of the tree, in one table:

| What | Status |
|---|---|
| Fixes 3-33 present in source | yes (re-checked against v2.65.2.3b) |
| Full build (`make -j1`) | `MAKE_EXIT=0` — EWRAM 250,954 B (95.73%), IWRAM 79.22%, ROM 23.7 MB (70.73%) |
| Boot test (mGBA, 2500 frames) | passes — Groudon logo renders, no crash |
| Symbol addresses vs cheat tables | unchanged (`gBattleMons` `0x0201C554`, `gVolatileStructs` `0x0201C814`, `gSideStatuses` `0x0201C7A8`) |
| **In-battle playtest of fixes 5-33** | **still outstanding** — see the priority list in [open-findings.md](open-findings.md) |

One build-breaking quirk of this source drop, for the record:
`proto/AbilityList.textproto` references `ABILITY_FLUFFIEST_ONE` (Furret's
new ability) but the id was missing from `proto/AbilityEnum.proto`, so
codegen silently fell back to a stale `abilities.h` and the compile failed.
Adding `ABILITY_FLUFFIEST_ONE = 1046;` to the enum fixed it — without that
one line, the tree does not build at all.

## House rules for edits

- Edit `proto/*.textproto` (species, moves, abilities), not the generated
  headers — `make` regenerates them.
- Tutor moves need a `tutor:` value in `MoveList.textproto` before a species
  can list them as tutors (full list of learnset gotchas in
  [game-changes.md](game-changes.md)).
- Verify single-file edits in seconds with
  `modules/07-tools-notes/check-compile.sh` before committing to a full
  build.
- After any struct-layout change, re-derive cheat addresses via the
  DWARF/`.map` method in [testing.md](testing.md) — never reuse hardcoded
  addresses across builds.
