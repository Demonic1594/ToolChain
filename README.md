# Elite Redux — source overlay (`eliteredux-source` branch)

This branch carries **the game source** for the ToolChain repo: a maintained,
heavily fixed fork of **Pokémon Elite Redux v2.65.2.3b** (upstream
[`Elite-Redux/eliteredux-source`](https://github.com/Elite-Redux/eliteredux-source),
`upcoming` branch), a ROM hack of Pokémon Emerald built on the
[pret/pokeemerald](https://github.com/pret/pokeemerald) decompilation.

The branch contains **only** the source overlay: 543 modified or new files at
their real paths under `modules/06-eliteredux-source/`, plus a minimal root
`.gitattributes`. All ToolChain scaffolding (build pipeline, scripts, docs,
CI) lives on `main`.

- Baseline: Elite Redux **v2.65.2.3b** (`upcoming`)
- Carries source fixes **3–164** (complete code review: rounds 1–3 + batches
  A/B/C/E + gflib stdlib + final sweep — every file with executable logic)
- Adds **SabreVoir**, a custom species with a Sword forme, 5 abilities and 2
  signature moves
- Build lane: ToolChain `run.sh` on `main` (full ROM ~20 min on aarch64/qemu,
  ~4 min in CI); CI attaches a working ROM on every push

## How the overlay model works

`modules/` is gitignored in the ToolChain repo (the full tree, ~62k files /
433 MB of source plus regenerable build outputs, is unpacked from
`archives/`). Only files **we changed or added** are force-tracked here at
their real paths. Applying the branch on top of a fresh extraction therefore
reproduces our exact source:

```bash
# from a ToolChain checkout after stage 1 extraction:
git checkout eliteredux-source -- modules/06-eliteredux-source/
```

Build after overlaying (see `main`: `README.md`, `docs/README-SETUP.md`):

```bash
./run.sh            # extract -> env -> build -> verify, or --from 4 to skip ahead
```

## What's in the overlay (543 files)

| Path | Files | What |
|---|---|---|
| `include/` | 400 | Headers & constants touched by the fixes: 252 root headers, 81 `constants/`, 55 codegen-`generated/` (tracked so fresh trees + CI compile before running codegen), 10 `gba/`, 2 `mgba_printf/` |
| `src/` | 85 | Game-logic fixes: battle engine/script VM, AI stack, abilities, Pokémon/party/summary, frontier facilities, DexNav, minigames, TV/Easy Chat, contests, nuzlocke/quests, string/UI overflows |
| `graphics/pokemon/` | 44 | SabreVoir art (base + Sword forme: front/back/anim icons, 4bpp & 8bpp, palettes, LZ) and dedicated menu-icon palettes `pal7`–`pal9` (shiny icon system) |
| `gflib/` | 4 | Hardened pret stdlib: `sprite.c/.h`, `text.c`, `window.c` |
| `proto/` | 3 | `SpeciesList` / `AbilityList` / `MoveList` textprotos — SabreVoir species/forms/abilities/moves data |
| `asm/` | 3 | `battle_script.inc` macro + 2 codegen'd macro files (incl. the live `waitse` opcode fix that restored ExtraSkill popups) |
| `tools/codegen/` | 2 | `makefile`, `MoveNameGenerator.kt` (codegen fixes) |
| `data/` | 1 | `battle_scripts_1.s` |
| `.gitattributes` | 1 | Nested rules: EOL + `*.pal` stored with literal CRLF (gbagfx requirement; smudging proved flaky) |

Root `.gitattributes` (this branch): `*.pal -text`, `*.gbapal binary` — keeps
palette assets byte-exact.

## The modifications

**Fixes 3–164** — the authoritative per-fix writeup is
`docs/project/fixes.md` on `main`. Highlights:

- **Live bugs**: Absolute Guard multi-hit KO hole, Factory rental-mon save
  corruption (sev-1), `waitse` wrong opcode suppressing ExtraSkill popups,
  Mystic Aegis re-execution hard-lock, Match Call heap overflow + Steven
  flag collision, Union Room Chat stack smash, mevent code-exec fallthrough
- **Hardening**: ~150 OOB/overflow/UAF/leak/div-0 fixes across battle,
  frontier, minigames (blender/crush/jump/dodrio), TV/EasyChat, contests,
  summary/dex screens, wild encounters, quests, DexNav
- **Performance**: soft-float elimination (turn order, 31 ability sites),
  literal-divisor stage ratios, crit-roll masks, lazy AI crit passes,
  hold-effect/lookup hoists
- **ER-specific**: Shedinja Absolute Guard identity + HP=1 lock, ability
  slot switcher, IV-garbage write fixes, 6v6 swap/select fixes, nuzlocke
  unlisted-map tracking, roamers never consumed

**SabreVoir** (custom content, see `proto/SpeciesList.textproto` @
`SPECIES_SABREVOIR`):

- Steel/Fairy consort, dex #1223, base + **Sword forme** (atk/def/spatk
  swapped; forme shift via its signature moves)
- Abilities: **Arcane Stance**, **Promised Victory**, **Prophetic Destiny**,
  **Beast of Gluttony**, **Mystic Aegis**
- Signature moves: **Mystique Armament** (shift to Sword forme + strike both
  foes with best type) and **Mystic Aegis** (return to base forme / raise
  defenses)
- Full art set incl. 8bpp battle sprites and dedicated icon palettes
  (normal = pal8, shiny = pal9); `ScriptGiveMon` adoption features: forced
  shiny, signature moves in slots 0/1, always-female roll

## Source tree guide (`modules/06-eliteredux-source/`)

**Golden rules**

1. `proto/*.textproto` is the source of truth for game data. C headers in
   `include/generated/` are derived — never hand-edit; edit the textproto and
   regenerate (`tools/codegen`, entry `er.FileGenerator`, needs a JDK ≥ 17).
2. Edit `.pory` scripts, not the built `.inc`.
3. Every ability is an `Impl<ABILITY_X>` in `src/abilities.cc` (~12.9k lines,
   C++) — logic lives in `src/*.c|cc`, never in headers.

**Layout**

| Path | What |
|---|---|
| `src/` | All game logic (~324 files, ~494k lines): battle engine, AI stack (classic + dormant "new"), abilities.cc, field/overworld, debug menus, ER systems (nuzlocke, quests, day/night, battle skills) |
| `include/` | `global.h`, `battle.h`, `pokemon.h` (`SpeciesInfo`: 3 ability slots + 3 innates), `constants/` (flags/vars/species…), `generated/` (codegen output) |
| `proto/` | Textproto data + schemas: species, abilities, moves, items, trainers, battle skills, randomizer config |
| `tools/codegen/` | Kotlin+Java textproto→C generators (jars prebuilt in-tree) |
| `data/` | Porymap data: 570 maps, 491 layouts, tilesets, `.pory` scripts, text blobs, battle/anim scripts |
| `asm/` | Hand-written asm + macros; `asm/generated/` from codegen |
| `gflib/` | pret GBA stdlib (bg/window/text/sprite/malloc/DMA) |
| `graphics/` | ~168 MB art: `pokemon/` (1130 species dirs incl. mega/redux variants), fonts, UI, object events |
| `sound/` | m4a: MIDI songs, samples, cries, voicegroups |
| `Makefile`, `*_rules.mk`, `build_tools.sh`, `ld_script_modern.txt` | Build (modern lane forced: `MODERN=1`, arm-none-eabi GCC 13.2 — agbcc cannot parse this source) |
| `wiki/`, `INSTALL.md`, `AGENTS.md`, `README.md` | Upstream docs; `AGENTS.md` = repo safety rules |
| `build/`, `*.elf/.gba/.map`, `output.txt` | Build outputs — never committed |

**Most edit-relevant files**

| File | Role |
|---|---|
| `src/abilities.cc` | Every ability impl (`Impl<ABILITY_X>` + flags: `randomizerBanned`, `unsuppressable`, `breakable`) |
| `src/pokemon.c` | Mon creation/stats/evolutions, ability/innate randomization |
| `src/battle_script_commands.c` | Battle script VM — every command |
| `src/battle_util.c` | Mechanics resolution + ability hook dispatch |
| `src/battle_main.c` | Turn loop |
| `src/battle_ai_*.c` | AI stack (7 files) |
| `src/pokemon_summary_screen.c` | Summary UI incl. ability slot switcher |
| `src/party_menu.c` | Item use; Ability Capsule/Patch; Candy Box |
| `src/{battle_dome,factory,pyramid,pike,tower,arena,palace,tent}.c` | Frontier facilities |
| `src/dexnav.c`, `src/starter_choose.c` | Encounter systems |
| `src/nuzlocke.c`, `src/quests.c`, `src/battle_skills.cc` | ER-specific systems |

## Build lanes

| Lane | Speed | Playable ROM? | Use |
|---|---|---|---|
| ToolChain qemu (aarch64 host) | ~20 min full, 1–2 min incremental | yes (identical) | local builds |
| GitHub CI (`main`) | ~4 min | yes (attached artifact) | every push |
| Termux clang bridge | ~1–2 s per file | **no** (ABI mismatch) | compile-check only |

## Provenance & verification

- Baseline: upstream `Elite-Redux/eliteredux-source`, `upcoming` branch,
  v2.65.2.3b (Sept 2026). All deltas beyond it are ours and tracked here.
- Fixes verified per pass by compile-check, link (`MAKE_EXIT=0`), mGBA boot
  test; latest delivered ROM reproduced byte-identically locally and
  runtime-verified against the cheat tables (`docs/project/cheats.md` on
  `main`). Released as ToolChain **v1.1.0** (tag on `main`).
- Deeper docs on `main`: `docs/project/fixes.md` (numbered writeup),
  `open-findings.md`, `game-changes.md`, `testing.md`, `cheats.md`;
  `docs/README-CODEGEN.md` for the proto pipeline.
