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
