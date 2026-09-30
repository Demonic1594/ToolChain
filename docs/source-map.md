# Source tree guide

Map of `modules/06-eliteredux-source/` — where everything lives and which
files matter for which edit. Line references drift; re-grep when precision
matters.

## Golden rules

1. **`proto/*.textproto` is the source of truth for game data.** The C
   headers in `include/generated/` are derived. Never hand-edit generated
   files; edit the textproto and regenerate (see
   [data-pipeline.md](data-pipeline.md)).
2. **Edit `.pory`, not the built `.inc`** — map/event scripts are compiled
   from Poryscript sources in `data/`.
3. **Every ability is an `Impl<ABILITY_X>`** in `src/abilities.cc` (~12.9k
   lines, C++). Game logic lives in `src/*.c|cc`, never in headers.

## Top-level layout

| Path | What |
|---|---|
| `src/` | All game logic (~324 files, ~494k lines): battle engine, AI stack, abilities.cc, field/overworld, debug menus, ER systems (nuzlocke, quests, day/night, battle skills) |
| `include/` | `global.h` (shared structs), `battle.h`, `pokemon.h` (`SpeciesInfo`: 3 ability slots + 3 innates), `constants/` (81 files: flags, vars, species…), `generated/` (codegen output) |
| `proto/` | Textproto data + `.proto` schemas: species, abilities, moves, items, trainers, battle skills, randomizer config. **Edit here for data changes.** (`.bak` and `.l2s.*` files are tool artifacts — ignore) |
| `tools/codegen/` | Kotlin+Java generators turning textprotos into C (entry `er.FileGenerator`; jars prebuilt in-tree) |
| `data/` | Porymap data: 570 maps, 491 layouts, tilesets, 67 global `.pory` scripts, text blobs, battle/anim script `.s` |
| `asm/` | Hand-written asm + macros; `asm/generated/` produced by codegen |
| `gflib/` | pret GBA stdlib: bg/window/text/sprite/malloc/DMA |
| `graphics/` | ~168 MB art: `pokemon/` (1130 species dirs incl. `mega/` + `redux/` variants), object events, fonts, battle UI |
| `sound/` | m4a engine: `songs/midi/*.mid`, direct samples, cries, voicegroups |
| `common_syms/`, `sym_bss/common/ewram.txt` | RAM symbol placement for linking |
| `constants/` | asm-side includes (`gba_constants.inc`, `m4a_constants.inc`, …) |
| `Makefile`, `make_tools.mk`, `*_rules.mk`, `songs.mk`, `build_tools.sh` | Build system (see [building.md](building.md)) |
| `ld_script.txt`, `ld_script_modern.txt` | Linker scripts (modern is used; `MODERN=1` forced) |
| `libagbsyscall/` | BIOS swi wrapper lib |
| `wiki/`, `INSTALL.md`, `AGENTS.md`, `README.md` | Upstream docs; `AGENTS.md` = upstream repo safety rules + debug/versioning skills |
| `build/`, `*.elf/.gba/.map`, `output.txt` | Build outputs — regenerable, never committed |

## Most edit-relevant files

| File | Role |
|---|---|
| `src/abilities.cc` | Every ability impl + flags: `randomizerBanned`, `unsuppressable`, `breakable`, `blocksAbilitySuppression` |
| `src/pokemon.c` | Mon creation/stats/evolution checks; max-HP calc (Shedinja HP=1 lock ~line 1000); `RandomizeAbility/Innate/Type` (~5000–5043); `GetAbilityBySpecies` (~2148) |
| `src/battle_script_commands.c` | Battle script VM — every command impl (Dream Ball hidden-ability set ~12715) |
| `src/battle_util.c` | Mechanics resolution + ability hook dispatch |
| `src/battle_main.c` | Battle loop `BattleMainCB2` (~1604), turn flow |
| `src/battle_ai_*.c` | AI stack (7 files; classic + dormant "new" engine) |
| `src/pokemon_summary_screen.c` | Summary UI incl. **ability slot switcher** (~1653–1762) |
| `src/party_menu.c` | Item use on party mons; Ability Capsule/Patch (`Task_AbilityCapsule` ~4304–4403); Candy Box |
| `src/item_use.c` | Field item-use dispatch |
| `src/daycare.c`, `src/egg_hatch.c` | Breeding incl. ability slot inheritance |
| `src/battle_{dome,factory,pyramid,pike,tower,arena,palace,tent}.c` | Frontier facilities (import mons with ability slots) |
| `src/dexnav.c` | DexNav encounter generation |
| `src/starter_choose.c` | Starter selection (randomizer-aware) |
| `src/nuzlocke.c`, `src/quests.c`, `src/day_night.c`, `src/ui_battle_menu.c`, `src/battle_skills.cc` | ER-specific additions |
| `src/debug.c`, `src/pokemon_debug.c`, `src/battle_debug.c` | Debug menus (randomizer toggles, give-mon) |
| `src/scrcmd.c`, `src/field_specials.c` | Script opcodes / Special bodies |
| `src/pokedex.c`, `src/strings.c` | Dex UI + text strings |
| `src/evolution_scene.c` | Evolution cutscene (Shedinja ball requirement ~505–532) |

## Key `include/` files

| File | Role |
|---|---|
| `pokemon.h` | `SpeciesInfo`: `abilities[NUM_ABILITY_SLOTS=3]`, `innates[3]` (~238–243) |
| `constants/pokemon.h` | `NUM_ABILITY_SLOTS`, `NUM_INNATE_PER_SPECIES`, `EVO_LEVEL_SHEDINJA` (=14 special) |
| `abilities.hh` | C++ `Ability` struct (`randomizerBanned` ~253) + hook order |
| `constants/flags.h`, `constants/vars.h` | Story/system flags, script variables |
| `global.h`, `battle.h`, `main.h` | Core structs: `gMain`, battle state |

## Key `proto/` files

| File | Data |
|---|---|
| `SpeciesList.textproto` | All species incl. megas/forms: stats, types, abilities, innates, learnsets, evolutions, `randomizer_banned` |
| `AbilityList.textproto` | Ability names/descriptions (in-game text) |
| `MoveList.textproto`, `TrainerList.textproto` | Moves, trainers/parties |
| `BattleSkillList.textproto`, `TrainerBattleSkillList.textproto` | AI battle skills (ER system) |
| `items/*.textproto` | Items by category (`MegaStonesList`, `UnusedList` holds Ability Capsule/Patch) |
| `LimitedRandomizerConfig.textproto` | Climate weights — parsed by codegen utils but currently vestigial (no C consumer) |
