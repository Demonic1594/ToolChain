# Game systems: how Elite Redux works

Runtime behavior notes needed before changing gameplay code. Line refs are
approximate (drift).

## Ability system

A species carries **3 ability slots + 3 innate abilities**
(`NUM_ABILITY_SLOTS`, `NUM_INNATE_PER_SPECIES` in `constants/pokemon.h`); in
battle a mon shows 4: 1 selected ability + 3 innates.

**Where things live**

1. Implementation + behavior flags: `src/abilities.cc` —
   `constexpr Ability Impl<ABILITY_X> = { … }`; flags: `randomizerBanned`,
   `unsuppressable`, `breakable`, `blocksAbilitySuppression`.
2. Names/descriptions (UI text): `proto/AbilityList.textproto`.
3. Which species gets what: `proto/SpeciesList.textproto` → generated
   `base_stats.h` (`.abilities`, `.innates`).
4. Runtime lookup: `GetAbilityBySpecies` (`src/pokemon.c`).

**Every system that can permanently change a mon's ability**

| System | Location | Behavior / guard |
|---|---|---|
| Summary-screen switcher | `pokemon_summary_screen.c` ~1653 | DPAD cycles the 3 slots, skips `ABILITY_NONE` |
| Ability Capsule | `party_menu.c` `Task_AbilityCapsule` | Toggles slot 0↔1; **blocked if abilities[0]==abilities[1]** |
| Ability Patch | same task | Slot 0↔2 ("hidden"); with `{A,A,A}` it's a no-op (item still consumed!) |
| Dream Ball capture | `battle_script_commands.c` ~12715 | Forces slot 2 on catch |
| Breeding/eggs | `daycare.c` ~367, `egg_hatch.c` ~348 | 60% HA (slot 2) inherit, else mother's slot, else random |
| Debug give-mon | `debug.c` ~3316 | Random `%3` or specified slot |
| Scripted wild mons | `scrcmd.c` ~2626 | Chosen/random slot |
| Mon creation | `pokemon.c` ~584 | slot = personality&1 if abilities[1] set |
| Frontier/rental import | battle_main/factory/pyramid/pike/tower | Slot picks per facility rules |
| DexNav | `dexnav.c` ~1172 | Encounter-gen slot pick |

**Locking an ability**: give the species exactly one `ability:` in
`SpeciesList.textproto` — codegen pads to `{A,A,A}` and every system above
degenerates to that ability. No C changes needed (used for Shedinja/Mew).

## Randomizer (built-in "limited randomizer")

Toggles are new-game options in `src/ui_intro_options.c` (Encounter
Randomizer Disabled/Normal/Legendary/Scaled, Ability/Innate/Move/Type
randomizer settings); save flags in `include/global.h` ~591; debug re-seed
in `src/debug.c` ~1662; script access via `scrcmd.c` ~2549.

**Key property: the randomizer NEVER mutates stored data.**
`RandomizeAbility/Innate/Type` (`pokemon.c` ~5000–5043) are deterministic
display/battle-time overlays keyed on `ability ^ species ^ personality`;
they never write `MON_DATA_ABILITY_NUM`. Protecting content from the
randomizer means `.randomizerBanned` flags, not save guards (~38 abilities
flagged: NONE, TRACE, MULTITYPE, IMPOSTER-family, transformation gimmicks,
ABSOLUTE_GUARD, …).

## Battle engine

**State** (`include/battle.h`): `gBattleStruct` (per-battler `BattleMon`
copies, move history, `AI_ThinkingStruct`, turn/round trackers, stacks,
`BattleResources`), `gBattleMons[MAX_BATTLERS_COUNT]`, weather/field
statuses (terrain + secrets), side/field timers, `gBattleResults`,
`gBattleTypeFlags`. Volatiles have "began this turn" mirrors for
end-of-turn tick semantics.

**Flow**: `BattleMainCB2` (`battle_main.c` ~1604) → per-controller pumps
(`battle_controller_*.c`; player menu in `ui_battle_menu.c`) → turn
resolution: switch-ins → speed order → per-battler script execution →
end-of-turn timelines (`battle_events.c`).

**Script VM**: `RunBattleScriptCommands` (`battle_script_commands.c` ~4996)
steps the VM; `BattleScriptCall/Push` implement call/return incl. the
**ability-popup re-entry pattern** — a command returning TRUE re-executes
after the popup and must self-limit (the Mystic Aegis hard-lock was exactly
this going wrong).

## ER-specific quirks (vs vanilla pokeemerald)

- **Tutor moves use a bitmask** field, not a learnset list.
- Megas/forms are first-class species entries (`mega/`, `redux/` graphics
  dirs) with forme-shift machinery (`forms`, `undoforms`,
  `reversemegamap` generators).
- Battle Skills (AI trainer skills) are an ER-only system layered on the
  classic AI; a dormant "new" AI engine also exists in `battle_ai_new*.c`
  (upstream WIP, unwired — don't wire it up without addressing its score
  paths).
- Flat 1 EXP / catchRate 0 / growthRate 0: see the BaseStats data gap
  under "Pokémon lifecycle" — data-gap consequences, not mechanics bugs.

## Runtime architecture

- **Boot**: `crt0.s` → `AgbMain()` (`src/main.c`): GPU reg manager, keys,
  IRQ table, m4a init, RTC, flash check, `InitHeap(gHeap, HEAP_SIZE)`,
  then the frame loop.
- **Frame loop** (once per VBlank): `ReadKeys()` → soft-reset check →
  `UpdateLinkAndCallCallbacks()` → playtime/music → `WaitForVBlank`.
- **Game modes**: `CallCallbacks()` runs `gMain.callback1()` then
  `callback2` — CB2 **is** the current game mode (title, overworld,
  battle…); `SetMainCallback2(fn)` switches, each mode installs its own
  CB2 state machine.
- **Concurrency**: no threads. Main work = CB2 state machines + the
  **task scheduler** (`src/task.c`, 16 slots, `CreateTask`) — tasks are
  the standard "async" primitive. Interrupts: VBlank (frame), HBlank
  (scanline FX), VCount, Serial (link), Timer3 (sound DMA). DMA channel 3
  is queued for VRAM-safe copies (gflib `dma3_manager`).
- **Memory map**: ROM 0x08000000 (32 MB, expanded); EWRAM 0x02000000
  (256 KB: `gHeap` + save staging); IWRAM 0x03000000 (32 KB: `gMain`,
  IRQ stack, globals via `common_syms`); palette/VRAM/OAM written through
  shadow registers at VBlank.

## Pokémon lifecycle (creation, stats, EXP, evolution)

- `CreateMon*` family → `CreateMonInner`: species, level, personality
  (u32 — gender/nature/shiny derive from it), ability slot
  (slot = `personality&1` if abilities[1] present; explicit override via
  `CreateMonWithAbilityNum`), IVs/nature, then `CalculateMonStats`.
- `CalculateMonStatsMaster` (`pokemon.c` ~970) computes stats; nature
  ±10%; Shedinja-style HP=1 lock ~line 1000.
- Evolution methods: `constants/pokemon.h` (~390–455); Shedinja's
  EVO_LEVEL_SHEDINJA = 14 is a special case.
- **BaseStats data gap (ER reality, BY DESIGN)**: `BaseStatsGenerator`
  emits only base stats/types/abilities/innates/eggGroups/bodyColor/
  tier/flags/genderRatio. The `struct BaseStats` fields `catchRate`,
  `expYield`, `evYield_*`, `eggCycles`, `friendship`, `growthRate`,
  `item1/item2`, `safariZoneFleeRate`, `numShinies` are **zero for every
  species** (no proto fields exist). Consequences:
  - Exp gain clamped to **flat 1 EXP per victory** (+1 exp-share);
    progression is candy-based (Candy Box) by design.
  - `growthRate` 0 ⇒ everyone uses experience table 0 (MEDIUM_FAST).
  - EV yields 0 ⇒ `MonGainEVs` no-ops; wild held items never roll;
    DexNav item preview empty; `numShinies` shiny-palette gating dead.
  - **catchRate 0 ⇒ capture odds come only from ball multipliers/
    additions** (`battle_script_commands.c` ~12680 guards odds==0;
    fix 34 restored the vanilla formula). Safari:
    `safariCatchFactor = 0` → same multiplier-only path (known issue:
    safari catching is effectively dead — see known-issues.md).
  - If real values are ever needed: add proto fields + extend
    `BaseStatsGenerator.kt` + rebuild jars.

## Breeding (daycare, eggs, inheritance)

- Two daycare slots in `gSaveBlock1Ptr->daycare`; XP per step on
  withdrawal; egg trigger scored by `GetDaycareCompatibilityScore`
  (same species/different OT best; shared egg group mid; Oval Charm
  boosts).
- Offspring = mother's base line (or non-Ditto parent); form
  inheritance for Nidoran/Manaphy in `DetermineEggSpecies`; Incense
  babies gated by held item.
- **Egg moves are STUBBED**: `GetEggMoves` returns 0 (`daycare.c:511`).
  Hatchlings get the final base form's level-up learnset (+TM/tutor
  availability) — classic egg-move lists don't exist in ER.
- Ability slot inheritance: 60% hidden slot if a parent has it, else
  mother's current slot, else random among species slots — degenerates
  safely under `{A,A,A}` locks.

## Items, bag, hold effects

- Source of truth: `proto/items/<Pocket>List.textproto` (pockets =
  filenames: Battle, Berries, Items, KeyItems, Medicine, MegaStones,
  PokeBalls, TmHm, Unused) → `itemids`/`itemdata`/`itemgfx`/`pockets`/
  `naturalgift`/`holdeffect` generators.
- `struct Item` wires `fieldUseFunc`/`battleUseFunc` **by name** from
  proto (e.g. `field_use_func: "AbilityCapsule"` →
  `ItemUseOutOfBattle_AbilityCapsule`); hold-effect fields merge into
  `holdEffect` + param; mega-location oneof feeds the `megas/*`
  generators.
- Field use: bag menu → `ItemUseOutOfBattle_*` callbacks (`item_use.c`);
  party-targeted items route to `party_menu.c` task handlers (Ability
  Capsule/Patch, Candy Box, evo stones → `EVO_MODE_ITEM_USE`). Key items
  are often Special-only (grep `data/scripts` + `field_specials.c`).

## Overworld (scripts, flags/vars, encounters)

- Script VM: `script.c` `RunScriptCommand`; two contexts (map script +
  nested). 232 `ScrCmd_*` opcodes in `scrcmd.c`. Specials dispatched via
  the `field_specials.c` table (~5k lines — the ER hook kitchen).
- Scripts live in `data/maps/<Map>/scripts.pory` + `data/scripts/*.pory`
  (67 globals), compiled by poryscript to `.inc`. Map events
  (NPCs/warps/triggers/signs) in each map's `map.json`.
- Flags: **1507 `FLAG_*`** ids (`constants/flags.h`); vars: **281
  `VAR_*`** (`constants/vars.h`); stored in `gSaveBlock1`, accessors in
  `event_data.c`. **Never renumber existing ids** (save compat) — always
  take the next free one.
- Wild encounters: NOT proto-driven — `src/data/wild_encounters.json` →
  jsonproc → headers (land 12 slots / water / rock smash / fishing rows
  per map); flow: overworld step → `StandardWildEncounter` →
  `TryGenerateWildMon` (repel/keen-eye checks); pike/pyramid inject
  their own headers.

## Related systems (quick pointers)

- Frontier rental/import slot rules: `battle_main/factory/pyramid/pike/tower`.
