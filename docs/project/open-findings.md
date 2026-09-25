# Open findings (not fixed - candidates for a future session)

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

- `CalcCritChanceStage` still reads `gBattleMoves[move]` / hold-effect data without bounds checks on `move`; fine for valid ids.
- **Safari zone catch rate is 0 across the board (follow-up to fix 34)** —
  `battle_main.c` derives `safariCatchFactor` from
  `gBaseStats[].catchRate`, which the codegen never emits (no proto
  field exists; 0 for every species). With fix 34 restoring the vanilla
  `odds > 255` formula, regular balls still catch via ball
  multipliers/additions, but Safari Balls (multiplier path keyed off
  the factor) are effectively dead. Same data gap also zeroes
  `expYield` (battles give the clamped flat 1 exp - intended candy
  progression), `growthRate` (all species MEDIUM_FAST), wild held
  items, and EV yields. Revisit if any of those need real values:
  proto schema + `BaseStatsGenerator.kt` + codegen jar rebuild.

Closed items (kept for the record):

- ~~`battle_ai_util.c:2151` - `(status1 & STATUS1_SLEEP) == 1`~~ - **investigated,
  not a bug**: `STATUS1_SLEEP` is a 3-bit turn-counter mask, `== 1` means "exactly
  one sleep turn left", which is what `IsWakeupTurn()` wants.
- ~~`cry_table.h`'s duplicate `EGG_GROUP_WATER_2` test~~ - **fixed** (now
  `EGG_GROUP_WATER_3` in `GetSpeciesCry()`); previously harmless but Water-3 mons
  fell through to unrelated cry branches.
- ~~`PredictFoesMoveType`'s `defType1`-referenced-twice copy-paste bug~~ - **fixed
  in the systematic review pass (fix 85)**, three sites now use `defType2` for the
  second factor. Still dead code (only call site commented out), but correct if
  revived.
- ~~Performance: `IsBattlerAlive` caching / repeated `GetBattlerHoldEffect`~~ -
  **done, not worth it**: disassembled from the v2.65.2.3b ELF, `IsBattlerAlive`
  is ~17 Thumb instructions and worst-case totals are microseconds against a
  16.7 ms frame budget, once per turn.
- **Fixes 5-93: compiled per file with `-Werror`.** All 16 files touched by fixes
  34-93 pass `check-compile.sh`. Full-build + boot-test status for the combined
  tree: see the table in [README.md](README.md) (updated per build).
- **None of fixes 5-93 have been playtested in a real battle yet** - only
  cold-boot-to-title smoke tests. Do this before adding more (priority list below).
- **`SetActionsAndBattlersTurnOrder`'s pre-sort is inert** (`battle_main.c`): the
  `except` mask accumulates `1 << gActiveBattler` in *both* loops, so every battler
  is excluded and `SortBattlersExcept` writes nothing; turn order is rescued by
  `RecalculateMoveOrder` running after every action. Left alone deliberately
  (deleting it is behavior-neutral, "fixing" the except-mask or the destination
  array could change ordering); noted as a hazard if anyone touches that function.
- **New AI (`battle_ai_new*.c`, parts of `battle_ai_attack.c`) is still dormant**
  and its scoring macros are still stubbed to `0`. Fixes 86 hardened the clear
  wrong-variable/math defects in it, but `ScoreMoveHit` still returns uninitialized
  `score` on several paths (`AI_CALC_DAMAGE` is an empty macro) — that is WIP-by-
  design, not fixed. Do not wire `GetAiDecision` up without addressing it.
- Playtest priorities, fixes 5-33: Metronome (fix 23), hell-mode Expert Belt / resist
  berries / effectiveness labels (fixes 19-20), doubles with several follow-up
  abilities (fix 15), Dusk Ball night-catch bonus (fix 28), a form-change ability
  (Shields Down/Gulp Missile) while the user's mon has a non-Transformed volatile
  status like confusion (fix 29), Nightmare against a target with another volatile
  status (fix 30), Training Band with the party's highest level under 4 (fix 32),
  and the AI dual-type switch-in behavior change (fix 33).
- Playtest priorities, fixes 34-93 (new): catching anything with any ball (34 -
  the single highest-impact change; confirm shakes/fail/crit-capture all work),
  doubles with an out-of-turn ability (Dancer) + a queued Eject Pack/Button/Red
  Card on 3+ battlers (35 - the queue-corruption repro), Hot Coals / Scrapyard /
  Toxic Debris / Spider Lair / Loose Rocks holders in the player's *right* doubles
  slot (36), Unnerve on the right opponent (39), Fury Cutter across 3+ turns (41),
  Metronome item consecutive-use boost (42), Psycho Shift poison onto a Steel type
  (43), Future Sight + a swap move (45), Swallow after Stockpile ×2+ (46), Lansat
  berry at +0 crit stages (47), Sky Drop when the user flinches on turn 2 (48),
  Zen-mode/Groudon-style HP form changes in doubles (50), AI heal/pivot decisions
  at low HP (38, 65), AI vs Rocky Helmet contact moves (64), Candy Box +1 level
  pick (60), Form Change menu before Badge 2 (61), 8-entry PC menu on an
  Evolve-eligible under-cap mon (62 - Cancel must remain, Release is dropped).
- Next places to hunt: the frontier facilities (battle_dome/pike/pyramid/arena
  scoring were only spot-checked), `battle_controller_*.c` (not deeply reviewed),
  `script_conditions.cc` / `battle_skills.cc` (not reviewed at all), and the
  remaining wrong-variable patterns in the dormant new AI once it gets wired up.
  The systematic pass covered: battle_util, battle_script_commands, battle_main,
  battle_message, battle_interface, battle_util2, battle_gfx_sfx_util,
  battle_controllers (spot), abilities.cc (full), all battle_ai_* (full), pokemon,
  pokemon_storage_system, daycare, party_menu, egg_hatch, trade.
