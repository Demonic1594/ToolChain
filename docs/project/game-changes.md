# Game changes applied in this source

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

- Shedinja (as actually defined in `proto/SpeciesList.textproto`): Bug/Ghost,
  1/150/0/100/0/90, abilities Absolute Guard / Sovereign Prowess, innates
  Prismatic Fur / Wonder Skin / Dazzling
- Mega Shedinja: Bug/Ghost, 1/230/0/150/0/170, same abilities/innates as base.
  (An earlier version of this README claimed Normal/Ghost/Dark typing and
  Wonder Guard as a locked ability; the source tree in this package does NOT
  match that, so the description was corrected to what the source really
  contains. If you expected the older values, they have to be re-applied.)
- Shedinja/Mega Shedinja competitive learnset overhaul - see "Shedinja moveset
  changes" below
- Wonder Guard is now unconditionally unbypassable: immune to Mold
  Breaker/Teravolt/Turboblaze, Neutralizing Gas, Gastro Acid/Core
  Enforcer, and can't be removed via Skill Swap/Role Play/Worry
  Seed/Entrainment/Simple Beam. Implemented via three ability flags
  (`unsuppressable`, `blocksAbilitySuppression`, and removing
  `breakable`) on its entry in `src/abilities.cc` - this codebase
  centralizes ability-suppression checks through `IsSuppressed()`
  rather than the scattered per-move banned-ability arrays `master`
  branch uses, so it only took one edit instead of six.
- Two new custom abilities added: `ABILITY_ABSOLUTE_GUARD` (id 1044,
  Magic Guard + Clueless + Sturdy behavior - the Sturdy part required
  extending a hardcoded ability check in
  `src/battle_script_commands.c`, not just a flag) and
  `ABILITY_SOVEREIGN_PROWESS` (id 1045, Equinox + Huge Power + Feline
  Prowess behavior)
- `DEBUG_BUILD` disabled (`include/global.h`) - removes the debug menu
  and the "Beta2.1 Debug" watermark text from the Hall of Fame/save-info
  screens
- A "stat-boost/weaken" battle cheat verified working for this exact
  build (see below)

## SabreVoir (custom species, id 2682/2683)

Steel/Fairy stance-dancing duo built in two passes: creation (sprites,
codegen, composite innates) then a balance pass. Full session detail lives
in the repo's local knowledge notes; the shipped state:

**Base stats (BST 600 both formes, speed-mirror design):**

| Forme | HP | Atk | Def | SpA | SpD | Spe |
|---|---|---|---|---|---|---|
| Shield (`SPECIES_SABREVOIR`) | 76 | 80 | 148 | 81 | 148 | 67 |
| Sword (`SPECIES_SABREVOIR_SWORD`) | 76 | 148 | 81 | 148 | 80 | 67 |

**Slots:** ability **Arcane Stance** (both formes); innates **Promised
Victory**, **Prophetic Destiny**, **Beast of Gluttony**.

**Arcane Stance** = Mystique Armament's type recalculates to the most
effective one vs the target (gate requires the declared type — currently
Fairy, display-only), and switches Shield→Sword; Mystic Aegis switches
Sword→Shield, or raises Def/SpDef if already Shield. Sovereign Prowess was
removed from it *and* from Promised Victory — the doubling previously
existed in both and could stack.

**Signature moves** (both 10 PP):

- **Mystique Armament** — 70 BP special, declared Fairy (display), keen
  edge, strikes **both foes** (the engine's ×0.75 spread modifier only
  applies at 2+ targets, so singles keeps full power).
- **Mystic Aegis** — Steel status, priority +2, `EFFECT_PROTECT`-based but
  **never fails on consecutive use** (`ProtectSucceeds` special-case).

**Innate contents** (verified against the delegations, descriptions in
`AbilityList.textproto` are prose, not component lists):

- *Promised Victory*: Crowned Sword (+1 Atk on entry/when struck) + Pinnacle
  Blade (keen-edge moves never miss, pierce protection/substitutes/screens)
  + Blademaster (keen edge ×1.2 + crit stage)
- *Prophetic Destiny*: Queenly Majesty (blocks priority vs self **and
  ally**) + Dragon's Ritual (KO → +1 Atk/+1 Spe) + ER-Long Reach (×1.2
  physical) + Droideka (half Fire, no crits)
- *Beast of Gluttony*: Prismatic Fur (×0.5 all damage + Protean/Color
  Change) + Resilience (¼ heal once per switch-in below half) + Craving
  (random berry each end turn) + Gluttony

**Counterplay by design** (the "solid in doubles, okay-ish in singles"
target): Corrosion Toxic (35 carriers; poison chips at full rate — the ×0.5
never applies to residual damage), Mold Breaker family, Mycelium Might
status, Encore/Taunt (breaks the stance dance), PP pressure (10+10), and
its single real weakness (Ground) nets ~×1 after the halving — status, not
damage, is the intended lane. ER's Long Reach being a physical ×1.2 (not
the no-contact ability) and Resilience being once-per-switch-in are both
verified engine facts worth remembering when reading its kit.

An 8bpp front-sprite system for it (256-color detailed opponent sprites)
is a separate in-progress workstream.

## Shedinja moveset changes (latest session)

Mega Shedinja has no learnset of its own: `findLearnsetForSpecies()` in
`tools/codegen/src/er/GeneratorUtils.kt` resolves any mega back to its base
form, so **editing base `SPECIES_SHEDINJA` changes Mega Shedinja too**
(confirmed in the generated `level_up_learnset_pointers.h`, where both map to the
same `__sLevelUpMoveset_281`). Edit only `proto/SpeciesList.textproto`; the
generated headers are rebuilt from it by `make`.

Level-up learnset now (all previous good moves kept; Harden, Mud Sport, Scratch,
Fury Swipes, Sharpen, Gust and Mind Reader were removed as outclassed):

| Lv | Moves |
|---|---|
| 1 | Final Gambit, Mud Slap, Shadow Sneak, Double Team, Hone Claws, Astonish |
| 17 | Detect, Dual Wingbeat, Lunge, Skitter Smack |
| 20 | First Impression |
| 24 | Ominous Wind, Silver Wind, Slash, Ally Switch, Shadow Claw, Fell Stinger |
| 30 | Extreme Speed |
| 37 | Feint Attack, Fury Cutter, Phantom Force, Sucker Punch |
| 42 | Knock Off |
| 44 | Quiver Dance |
| 46 | Assurance, Poltergeist, Whirling Strikes, Insect Impact |
| 48 | Megahorn, Spectral Thief |
| 50 | Close Combat |
| 51 | Baton Pass, Last Respects |
| 52 | Shadow Force, Destiny Bond |
| 56 | Guillotine |

Tutor list additions: Knock Off, Earthquake, U-turn, Shadow Punch, Play Rough,
Iron Head, Stone Edge (on top of the existing tutors such as Swords Dance,
Shadow Ball, Hex, X-Scissor, Bug Buzz, Will-O-Wisp, Nasty Plot). Protect,
Substitute and Endure come from the universal tutors automatically.

Things that will bite you when editing learnsets:

- **Tutor moves need a slot.** `tutor_learnsets.h` is a generated bitfield
  (`struct TutorStruct`) with one `TUTOR_FIELD_MOVE_*` member per move that has
  a `tutor:` value in `proto/MoveList.textproto`. Listing a move as `tutor:`
  in a species when the move has no tutor value fails to compile with
  `'struct TutorStruct' has no member named 'TUTOR_FIELD_MOVE_...'` (this
  happened with Extreme Speed, Close Combat, First Impression, Ice Shard and
  Psychic Fangs). Either put such moves in the level-up list (no restriction)
  or give the move a `tutor:` value in `MoveList.textproto`.
- **Placeholder moves are rejected.** `LevelUpLearnsetGenerator` fails the
  build if a learnset uses a move whose name ends in `)` or whose effect is
  `EFFECT_PLACEHOLDER`.
- `proto/MoveList.textproto` uses CRLF line endings; `SpeciesList.textproto`
  uses LF. Preserve whichever a file already uses (`open(p, newline='')` in
  Python) when scripting edits.
- Only the base species needs editing; do not add a `learnset` block to a mega.
