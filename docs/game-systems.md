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

- **Flat 1 EXP floor**: exp gain = `expYield*level/5`, clamped to a minimum
  of 1 per battle — zero-yield species still give something.
- **catchRate is 0 for ALL species** (generator never emits it): capture
  odds come only from ball multipliers/additions (`battle_script_commands.c`
  ~12680: `catchRate<21 && ballAddition==−20 → 1`, then shake checks).
  Safari: `safariCatchFactor = 0` → same multiplier-only path.
- **Tutor moves use a bitmask** field, not a learnset list.
- Megas/forms are first-class species entries (`mega/`, `redux/` graphics
  dirs) with forme-shift machinery (`forms`, `undoforms`,
  `reversemegamap` generators).
- Battle Skills (AI trainer skills) are an ER-only system layered on the
  classic AI; a dormant "new" AI engine also exists in `battle_ai_*.c`.

## Related systems (quick pointers)

- Breeding ability-slot inheritance: `daycare.c` / `egg_hatch.c` (table above).
- Items & hold effects: `item_use.c`, `items-and-holds` generators; ER adds
  Candy Box, Ability Capsule/Patch, Dream Ball behavior.
- Overworld: 570 maps/491 layouts via Porymap data in `data/`; scripts as
  `.pory` compiled to `.inc`.
- Nuzlocke/quests/day-night: ER additions in `src/nuzlocke.c`, `src/quests.c`,
  `src/day_night.c`.
