# Elite Redux - PROJECT notes (game changes, fixes, cheats, testing)

Everything about **what has been changed in the game/source** and how to test
it. For extracting the package, environment setup and building, see
**`README-SETUP.md`**.

> **Source update notice (re-verified):** `eliteredux-source/` was swapped
> wholesale to **v2.65.2.3b** - see `eliteredux-source/README.md` for this
> version's own changelog (Shedinja, Mew, Furret, Ogerpon). The fixes log
> below (5-33) has now been checked against this drop: every fix spot-checked
> is present and correct, and the tree has been **built, linked (`MAKE_EXIT=0`),
> and boot-tested** in this exact source state. One build-breaking bug was
> found and fixed in the process (see "Build status" under fixes 28-33 below) -
> the source would not build at all until that was applied. **Still not done:**
> a real in-battle playtest of fixes 5-33 (only boot-tested so far) - see
> "Open findings" at the bottom of this file for the priority list.

## Source-code fixes

### Fixes already present when the package was first assembled

3. **`ABILITY_ABSOLUTE_GUARD` let multi-hit moves kill through it** -
   the survival clamp in `battle_script_commands.c` was gated behind
   `BATTLER_MAX_HP(gBattlerTarget)`, the same guard vanilla Sturdy uses.
   That's correct for Sturdy (it's only ever supposed to fire once, on a
   full-HP target) but wrong for Absolute Guard: after the first hit of a
   multi-hit move (Bullet Seed, Dragon Darts, etc.) dropped the target to
   1 HP, the guard condition is no longer at max HP, so the next hit in
   the same move would go through and KO it. Fixed by dropping the
   `BATTLER_MAX_HP` requirement for `ABILITY_ABSOLUTE_GUARD` specifically
   (Sturdy's own check is untouched) so it clamps every lethal hit to 1
   HP, not just the first:

   ```c
   else if (BATTLER_HAS_ABILITY(gBattlerTarget, ABILITY_ABSOLUTE_GUARD))
       sturdyAbility = ABILITY_ABSOLUTE_GUARD;
   ```

4. **`Impl<ABILITY_ABSOLUTE_GUARD>` in `abilities.cc` didn't compile** -
   found while building the fix above, not related to it. The struct's
   designated initializer list had `.magicGuard` listed before
   `.breakable`/`.unsuppressable`/`.blocksAbilitySuppression`/
   `.randomizerBanned`, which violates C++20's rule that designated
   initializers must appear in the same order the fields are declared in
   the struct (`abilities.hh` declares `magicGuard` after all four of
   those). This GCC enforces it as a hard error, not a warning. Fixed by
   reordering the initializer list to match the struct's field order -
   no behavior change, just unblocks the build.

### Fixes added in the "bug-hunt" pass (applied to this source tree)

These come from a separate session that built a ROM
(`reference-roms/pkmn-emerald_modern.gba`) from this same `upcoming` source
plus the fixes below. That session's source was never saved, so the fixes were
**re-applied to this tree by hand from the session's description** - the edits
are functionally the same but this tree has **not been rebuilt** yet, so
byte-identity with the reference ROM is unverified. To verify: `make -j1`, then
compare against the reference ROM (differences in the header/checksum only
would mean a match; anything else means a fix is missing or differs).

5. **`GetSpeciesName()` off-by-one** (`src/pokemon.c`) - loop was
   `i <= POKEMON_NAME_LENGTH`; on a name with no terminator inside 12 chars it
   wrote `name[13]`, one past a `POKEMON_NAME_LENGTH + 1` buffer. Now
   `i < POKEMON_NAME_LENGTH` (the trailing `EOS` lands at index 12). The
   species guard also changed from `species > NUM_SPECIES` to
   `species >= NUM_SPECIES`, since `NUM_SPECIES` itself is one past the end of
   `gSpeciesNames[]` (`SPECIES_EGG` = `NUM_SPECIES - 1` is a valid entry). The
   original session described this as a "bounds check for SPECIES_EGG"; this is
   the interpretation applied here.
6. **`name[12]` -> `name[POKEMON_NAME_LENGTH + 1]`** in `AddHatchedMonToParty()`
   (`src/egg_hatch.c`) - a 12-char name plus `EOS` needs 13 bytes.
7. **Two `nickname[12]` -> `nickname[POKEMON_NAME_LENGTH + 1]`** buffers in
   `GetMonNicknameWidth()` and `DrawTradeMenuPartyMonInfo()` (`src/trade.c`).
8. **`text[12]` -> `text[POKEMON_NAME_LENGTH + 1]`** in
   `ExpandBattleTextBuffPlaceholders()` (`src/battle_message.c`). This one runs
   on nearly every battle text expansion, so it was the highest-impact of the
   buffer bugs.
9. **`TOTAL_BOXES_COUNT` 26 -> 20** (`include/pokemon_storage_system.h`) - frees
   about 9.4 KB of EWRAM (reported 95.71% used, 250,890 bytes, after the
   change). All other uses are symbolic and `save.c`'s `STATIC_ASSERT` only
   needs the storage to *fit*, so shrinking is safe for it. **Trade-off:** the
   PC has 20 boxes instead of 26, and the save layout changes, so saves from a
   26-box build may not load correctly. Revert to 26 if you need old saves.

### Fixes added in the follow-up bug-hunt (10-27; compile-checked per file, NOT linked or playtested)

10. **Lucky Chant side index** (`CalcCritChanceStage`, `src/battle_script_commands.c`)
    - `gSideStatuses[battlerDef]` indexed a 2-entry array by *battler* id, so in doubles
    battlers 2 and 3 read past the array (and read the wrong side's Lucky Chant for battler 2).
    Now `gSideStatuses[GetBattlerSide(battlerDef)]`. (Also resolves the caveat noted under the
    always-crit cheat.)
11. **Crit chance used globals instead of arguments** (same function) - the High-Crit flag read
    `gBattleMoves[gCurrentMove]` and the Lucky Punch species check read
    `gBattleMons[gBattlerAttacker]`, ignoring the `move`/`battlerAtk` parameters. Real battles
    were unaffected (they match), but the AI's crit estimate (`battle_ai_util.c:620`) used the
    wrong move/attacker. Now uses `move` and `battlerAtk`.
12. **Defog did not clear Smokescreen** (`ClearDefogHazards`) - the entry tested
    `SIDE_STATUS_LIGHTSCREEN` instead of `SIDE_STATUS_SMOKESCREEN`; it was unreachable dead code
    because the earlier Light Screen entry returned first. Now uses `SIDE_STATUS_SMOKESCREEN`.
13. **AI logic data skipped when smart-wild-AI flag is set** (`GetAiLogicData`,
    `src/battle_ai_main.c`) - the early-out was
    `!(flags & X && !IsWildMonSmart())`, so with `FLAG_SMART_AI` on, both trainer and wild battles
    returned before computing hp percents / simulated damage. Now mirrors the opponent
    controller's condition: `flags || FlagGet(FLAG_TOTEM_BATTLE) || IsWildMonSmart()`.
    Behaviour change to be aware of: totem battles now also get AI data.
14. **Off-by-one species/move table guards** - `species > NUM_SPECIES` -> `species >= NUM_SPECIES`
    (`battle_anim_mons.c`, `battle_main.c`, `decompress.c`, `dexnav.c`, `pokemon_icon.c`; 16 sites)
    and `moves[i] > MOVES_COUNT` -> `>= MOVES_COUNT` (`script_pokemon_util.c`). The generated
    tables hold exactly `NUM_SPECIES` / `MOVES_COUNT` entries, so the old check let one invalid
    id read one entry past the end.

15. **Extra-attack queue could overflow** (`gQueuedExtraAttackData`, `battle.h` / `battle_main.c` / `battle_util.c`)
    - the queue had `MAX_BATTLERS_COUNT + 1` (5) slots (slot 0 = in-progress, 1-4 = pending) but
    8 call sites push with `[++gQueuedAttackCount]` and no bounds check. In doubles, several
    abilities/innates (Dancer-style, entry moves, follow-up moves, Sleep Talk/Metronome) can queue
    more than 4 attacks in one turn, writing past the array into neighbouring EWRAM. Now sized
    `MAX_QUEUED_EXTRA_ATTACKS + 1` (12 + 1, about 64 bytes more EWRAM) and the three helpers in
    `battle_util.c` (`UseOutOfTurnAttack`, `UseEntryMove`, `UseAttackerFollowUpMove`) refuse to push when
    full. The 4 direct pushes in `battle_script_commands.c` (Sleep Talk, Metronome, Instruct-style,
    Beak Blast default) rely on the larger size only. Check EWRAM headroom after the next build.

16. **Absolute Guard blocks status moves - DELIBERATE, do not "fix"** (`src/abilities.cc`) - the
    hook nullifies every non-super-effective modifier, including status moves that run `typecalc`
    (Thunder Wave and similar). That is the intended design ("absolute" guard: an over-boosted Wonder
    Guard). An earlier pass of this session briefly added a `power` check and it was reverted; the
    ability now carries a comment saying so. Note `CalcPartyMonTypeEffectivenessMultiplier`
    (`battle_util.c`, used only by AI switch prediction and Battle Dome) still limits its Absolute Guard
    check to moves with power, which is intentionally conservative for status moves that don't run typecalc.
17. **`GetExtraAbilityForBattler` off-by-one** (`src/pokemon.c`) - `> HELL_MODE_EXTRA_ABILITIES` ->
    `>=`; the array has 3 entries, so index 3 read the next struct field (`hp`) as an ability id.
    Not reachable from current callers, defensive only.
18. **Soft-float arithmetic removed from hot code** - `dmg * 0.7` / `0.65` / `1.5` in the monotype
    champion damage modifiers (`battle_util.c`) are now `* 7 / 10`, `* 13 / 20`, `* 3 / 2`; the
    per-frame `* 0.0625` in the Ghost animation (`battle_anim_ghost.c`) is now integer `/ 16`.
    Floating point is emulated in software on GBA (slow, and pulls in libgcc float routines).
    Results are identical except for possible 1-point rounding differences in the damage cases.

19. **Hell mode type chart plumbing** (`battle_util.c`, `include/constants/global.h`) - the values are the
    **original ones (restored on request): 2x -> 1.5x, 4x -> 2.5x, 8x (three types) not reduced**. (The original
    comments said 4x -> 2x but the code has always used 2.5x; the comments now match the code.) Earlier passes had
    tried 3.5x and then a uniform 75% scale (1.5x / 3x / 6x); that was reverted. What was kept: the chart is applied by
    a shared `ApplyHellModeTypeChart()` (change the numbers only there), which is also used by
    `CalcPartyMonTypeEffectivenessMultiplier` (AI switch prediction / Battle Dome previously ignored the hell chart).
20. **"Super effective" checks were hardcoded to 2x, so they never fired in hell mode** (where SE = 1.5x).
    New `GetSuperEffectiveThreshold()` (`battle_util.c`, declared in `battle_util.h`) is now used by:
    Expert Belt, type-resist berries, the SE-boost misc hit, the Ground monotype-champion SE reduction, and
    the move-menu effectiveness label (`battle_controller_player.c`). The Fighting monotype-champion
    "super effective does neutral damage" rule compared against exactly 2.0/4.0; it now divides out the
    actual modifier, so it works with the hell chart.
21. **Zero-division guards** - defense stat in `DoMoveDamageCalcInternal`, and the `maxHP` / `hpSwitchout` /
    opposing-speed divisions in `battle_ai_util.c`, `battle_message.c`, `battle_script_commands.c` and
    `battle_util.c` (run-away odds) now use `max(1, x)`. On this toolchain a divide by zero returns 0 rather
    than crashing, so these produced wrong results rather than hangs.
22. **Overflow / zero-division in move-set stat weighting** (`battle_main.c`, `selectMoves`) - the
    `500 * atk^3 / spAtk^3` chance overflowed 32 bits for base stats above ~203 and divided by zero for a
    stat of 0. Now `GetCubedStatChance()` (64-bit, clamped to 1000); it also drops a dead assignment that
    ran the division unconditionally. Uses 64-bit division (libgcc `__aeabi_uldivmod`); confirm it links.

23. **Metronome ignored its ban list** (`Cmd_metronome`, `battle_script_commands.c`) - the reroll loop was
    `while (!allowed && !metronomeBanned && !twoTurnMove)`, which only rerolled a move that was disallowed
    *and* not banned *and* not two-turn, so banned moves (28 are flagged) and two-turn moves were accepted.
    Now `while (!allowed || metronomeBanned || twoTurnMove)`. **Behaviour change:** Metronome can no longer call
    banned moves or two-turn moves (the original intent of that condition).
24. **AI division guards** - `battle_ai_attack.c`: `defenderHp` is clamped to >= 1 in `ScoreMoveDamage`,
    `CheckSingleHitKo` and `CalculateKoChanceFine`; the Triple Kick branch divided by `requiredHits`, which is 0
    whenever there is no shield to break (`max(1, requiredHits)`). `battle_ai_util.c`: crit-weighted damage
    used `/ critChance` (now treats `<= 0` like the guaranteed-crit case), the powerful-move comparison
    divided by `hp` (clamped), and `GetBattlerSideSpeedAverage` divided by the number of live battlers
    (returns 0 if none). The remaining `/ baseDamageAverage` divisions were checked and are unreachable
    when the divisor is 0 (an earlier early-return handles it).
25. **Direct extra-attack queue pushes guarded** (`battle_script_commands.c`) - Me First, Instruct, Metronome
    and Sleep Talk now fail/skip when the queue (`MAX_QUEUED_EXTRA_ATTACKS`) is full instead of pushing.
26. **`debug.c` species picker** - loop bound `<= NUM_SPECIES` -> `< NUM_SPECIES - 1`.

27. **AI trap-damage precedence bug and two more AI divisors** (`battle_ai_util.c`, `battle_ai_attack.c`) -
    `GetTrapDamage` wrote `maxHP / (B_BINDING_DAMAGE >= GEN_6) ? 6 : 8`, which parses as
    `(maxHP / (cond)) ? 6 : 8`, so the AI estimated trap (Wrap / Fire Spin / Binding Band) damage as a flat 6 or
    8 HP instead of `maxHP / 6` or `/ 8`. Parenthesised the ternary (matches the real damage code in
    `battle_util.c`). Also: `GetBattlerSideSpeedAverage` divisor is `max(1, ...)`, the KO-chance formula's
    `(baseDamage - minDamage)` divisor is `max(1, ...)` (it can be 0 for tiny damage values), and
    `baseDamageAverage` is clamped to >= 1 before the multi-hit divisions. The hell-mode multipliers (fix 19)
    were restored to their original values (fix 19) and left unchanged.

Checked and left alone: `link.c` `strcpy(testTitle, sASCIITestPrint)` copies a 24-byte constant into a 32-byte
buffer (safe, debug-only); the `u8 movePower` parameters are fine because the highest base power in the data is
250 and no caller passes more than 255 (revisit only if you add a move above 255 power).

**Verification:** all files modified in fixes 5-27 pass a real compile (Makefile flags, `-Werror`)
via `tools-notes/check-compile.sh`. They have not been linked into a ROM or playtested.

**Known open items (not fixed yet):** see "Open findings" at the bottom of this file.

Bug classes checked and found clean in that pass: all 83
`MON_DATA_NICKNAME` call sites (no remaining undersized buffers), move-name
copies (`gMoveNames` is a fixed `[MOVES_COUNT][13]` array, so the loop-bound
bug cannot occur), and ability-name text expansion (unbounded copy, but into
256-byte `gStringVar1-3` / 1000-byte `gStringVar4`, so not a bug).

### Fixes added in the warning-sweep pass (28-33; compile-checked per file with `-Werror`, NOT linked, booted, or playtested)

Found by compiling every source file with warnings the Makefile normally leaves
off (`-Wlogical-op`, `-Wduplicated-cond`, `-Wint-in-bool-context`,
`-Wsign-compare`) and reading the hits, rather than more manual grepping for
logic-inversion patterns.

28. **Dusk Ball never got its night bonus** (`battle_script_commands.c`) - the
    time-of-day check was `hours >= 20 && hours <= 3`, which is never true (no
    hour satisfies both at once). Now `||`.
29. **AI form-change scoring used `&&` instead of `&` on a bitfield**
    (`battle_ai_ability.c`, 4 sites) - `status2 && STATUS2_TRANSFORMED` is
    truthy for *any* nonzero `status2` (confusion, Substitute, etc.), not just
    the Transformed bit. Now `status2 & STATUS2_TRANSFORMED`.
30. **`MOVE_EFFECT_NIGHTMARE`** had the identical `&&`-instead-of-`&` mistake
    against a status bitfield, so Nightmare silently failed to apply whenever
    the target already had any other volatile status. Now `&`.
31. **`HasAnyStatusOrAbility`** (`battle_util.c`) had `status1 && STATUS1_ANY`
    - same class of bug: any nonzero `status1`, including leftover
    toxic-counter bits with no actual status set, counted as "has a status."
    Now `status1 & STATUS1_ANY`.
32. **Training Band exp bonus broke for low-level parties**
    (`GetExpShareValue`-style level comparison) - `level < (highestLevel - 4)`
    was evaluated as unsigned; when `highestLevel` is under 4 the subtraction
    wraps to a huge unsigned value, so the comparison is satisfied for every
    level and the party gets the bonus multiplier unconditionally (effectively
    a free 5x exp bug at low levels). Fixed by doing the comparison in signed
    arithmetic.
33. **AI offensive switch-in scoring broke for dual-typed targets**
    (`GetBestMonOffensive`, `battle_ai_switch_items.c`) - it multiplied raw
    fixed-point type-effectiveness modifiers together in a `u32` without
    renormalizing between multiplications; two chained multiplications
    overflow/wrap to exactly 0 for (at least) dual-typed matchups, so the
    type-based score came out 0 for those and the AI always fell back to the
    damage-based pick instead. Fixed by renormalizing with `ApplyModifier`
    after each multiplication. **Behaviour change:** trainer AI will now
    actually use the type-based offensive switch-in pick for dual-typed
    targets instead of silently ignoring it.

Looked at during this pass, left alone (not bugs, or not worth changing):
- `PredictFoesMoveType` has a copy-paste bug (`defType1` referenced twice
  where the second should presumably be `defType2`), but its only call site
  is commented out, so it currently has no effect.
- `cry_table.h` tests `EGG_GROUP_WATER_2` twice where the second occurrence
  looks like it was meant to be `WATER_3` - cosmetic/data-only, and the
  intent wasn't certain enough to change it.
- Every `AI_SCORE_*` macro is a literal `0` - a lot of AI ability scoring is
  simply unfinished (returns no score by design-so-far), not a logic bug to
  fix here.
- `battle_ai_util.c:2151`, `(status1 & STATUS1_SLEEP) == 1` was flagged by the
  sweep but not actually investigated - left as an open item below rather than
  guessed at.

Checked and confirmed clean in this pass (no changes needed):
- Pain Split, Endeavor, and Final Gambit behavior at 1 HP (Shedinja).
- The Absolute Guard clamp and both custom ability (`ABILITY_ABSOLUTE_GUARD`,
  `ABILITY_SOVEREIGN_PROWESS`) definitions, including hell-mode consistency
  between the two.
- The learnset and tutor generators.
- The speed-tie code and the accuracy clamp.

**Verification:** fixes 28-33 pass a real compile (Makefile flags, `-Werror`)
per modified file via `tools-notes/check-compile.sh`, and a subsequent full
`make -j1` with all six applied **linked successfully** (`MAKE_EXIT=0`;
EWRAM 250,954 B / 95.73%, IWRAM 79.22%, ROM 70.73% - identical to the
fixes-5-27 build, since none of 28-33 touch a struct layout) and the
resulting `pokeemerald_modern.gba` **boots** in the mGBA harness (Game Freak
intro -> Groudon logo rendered correctly over 2500 frames, no crash, no black
screen). `gBattleMons`/`gVolatileStructs`/`gSideStatuses` addresses in the
fresh `.map` are unchanged from the fixes-5-27 build (`0x0201C554`,
`0x0201C814`, `0x0201C7A8` respectively), so the cheat tables elsewhere in
this file are still valid for this build too. **Not yet playtested in a real
battle** - the boot check only confirms the ROM starts, not that Dusk Ball,
Nightmare, Training Band, form-change abilities, or the AI switch-in change

> **Note:** the verification paragraph above describes a build of the
> *pre-v2.65.2.3b* source tree. Re-verified fresh against the current
> **v2.65.2.3b** tree: `make -j1` initially **failed to build at all** -
> `proto/AbilityList.textproto` references `ABILITY_FLUFFIEST_ONE`
> (Furret's new ability) but that id was never added to
> `proto/AbilityEnum.proto`, so codegen silently fell back to a stale
> `abilities.h` and `src/abilities.cc` failed to compile. Fixed by adding
> `ABILITY_FLUFFIEST_ONE = 1046;` to the enum. After that, `make -j1`
> **linked successfully** (`MAKE_EXIT=0`; EWRAM 250,954 B / 95.73%, IWRAM
> 79.22%, ROM 70.73% - identical usage) and the ROM **boots** in the mGBA
> harness (Groudon logo, 2500 frames, no crash). `gBattleMons` /
> `gVolatileStructs` / `gSideStatuses` in the fresh `.map` are unchanged
> (`0x0201C554`, `0x0201C814`, `0x0201C7A8`), so every cheat address in this
> file is still valid against v2.65.2.3b too. This means fixes 5-33 had
> **never actually been build-verified against this source tree before now** -
> more was broken than the earlier "has not been re-verified" caveat implied.
> Playtesting in a real battle is still outstanding.
behave correctly in play.

## Testing with the emulator harness

`python3.11-mgba/bin/python3.11` is a full scriptable GBA emulator via
`mgba`'s Python bindings. This is how every change in this project got
verified before being handed over, since asking a human to manually
playtest every iteration wasn't practical.

```bash
export LD_LIBRARY_PATH=/path/to/package/mgba-libs:$LD_LIBRARY_PATH
/path/to/package/python3.11-mgba/bin/python3.11
```

```python
import mgba.core, mgba.image, mgba.log
mgba.log.silence()

core = mgba.core.load_path('/path/to/rom.gba')
core.autoload_save()   # needs a matching .sav next to the .gba,
                        # AND the directory must be WRITABLE - a read-only
                        # mount makes autoload_save() silently return False
w, h = core.desired_video_dimensions()
img = mgba.image.Image(w, h)
core.set_video_buffer(img)
core.reset()

for i in range(4000):
    core.run_frame()

with open('screenshot.png', 'wb') as f:
    img.save_png(f)
```

Key button-input gotcha: `core.add_keys(core.KEY_START)` - the binding
auto-shifts by the key's raw index internally. Do NOT pre-shift it
yourself (`1 << 3`) or you'll press the wrong button entirely (this
specific mistake once pressed R instead of START for an entire debugging
session).

For save-state manipulation (jumping straight to a specific game state
instead of replaying the boot sequence every time):
```python
state = core.save_raw_state()  # returns cffi buffer, save with open(...).write(bytes(state))

# to load one back:
from mgba._pylib import ffi
with open('state.ss', 'rb') as f:
    state_bytes = f.read()
buf = ffi.new('unsigned char[%i]' % len(state_bytes), state_bytes)
core.load_raw_state(buf)
```

Direct memory read/write (for finding cheat addresses, verifying struct
layouts, etc.) via `core.memory.wram` (EWRAM, base `0x02000000`):
```python
core.memory.wram.u8[offset]       # read/write a byte
core.memory.wram.u16[offset]      # read/write a halfword
```

## Getting exact struct offsets / addresses without guessing

Don't guess memory addresses by trial and error if you don't have to -
the compiled ELF has full DWARF debug info (built with `-g`), and the
`.map` file has every global symbol's real linked address. This is how
the `gBattleMons` address and `statStages` field offset were found for a
"stat-boost/weaken" cheat code, with zero address-hunting:

```bash
# exact linked address of any global symbol:
grep -w "gBattleMons" eliteredux-source/pokeemerald_modern.map

# exact byte offset of any struct field:
arm-none-eabi-readelf --debug-dump=info eliteredux-source/pokeemerald_modern.elf \
  | grep -B5 -A5 "statStages"
```

This is dramatically more reliable than RAM-searching in a live emulator,
and it's the only approach that's guaranteed correct after a rebuild -
raw hardcoded cheat addresses from someone else's ROM build (even a very
similar one) will NOT match this build's memory layout, and using them
anyway causes exactly the kind of crash that started this whole
investigation in the first place.


## Summary of game changes already applied in this source

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


## The easy-battle cheat (verified against this exact build)

Writes all 8 `statStages` bytes (one signed byte per stat: Atk/Def/
Speed/SpAtk/SpDef/Acc/Evasion + 1) to 12 (max stage) for your side and 0
(min stage) for the opponent's, covering both battler slots per side so
it works in singles AND doubles. Confirmed via actual battle simulation
(damage output changed correctly, no crash) - not just derived from
struct offsets.

RetroArch cheat format:

| Address | Size | Value |
|---|---|---|
| `0x0201C550`, `0x0201C552`, `0x0201C554`, `0x0201C556` | 2-byte | `0x0C0C` |
| `0x0201C5B8`, `0x0201C5BA`, `0x0201C5BC`, `0x0201C5BE` | 2-byte | `0x0000` |
| `0x0201C620`, `0x0201C622`, `0x0201C624`, `0x0201C626` | 2-byte | `0x0C0C` |
| `0x0201C688`, `0x0201C68A`, `0x0201C68C`, `0x0201C68E` | 2-byte | `0x0000` |

### Same cheat as CodeBreaker-style slide codes (emulator-tested)

The four blocks above written as a slide code (`4aaaaaaa vvvv` then
`nnnnnnnn ssss` = repeat count, byte step). The first version of this code
used count 2 / step 4, which only wrote stat bytes 0-1 and 4-5, i.e. **Atk,
Sp.Atk and Sp.Def only** - Def and Speed were never set. The stat stage bytes
are `HP(unused) Atk Def Spe SpA SpD Acc Eva` (`STAT_*` in `include/constants/pokemon.h`),
one byte each, so 2-byte writes need step 2, not 4.

Atk/Def/Spe/SpA/SpD (count 3, leaves Accuracy/Evasion alone):
```
4201C550 0C0C
00000003 0002
4201C5B8 0000
00000003 0002
4201C620 0C0C
00000003 0002
4201C688 0000
00000003 0002
```
Use `00000004 0002` on every second line instead to also pin Accuracy and
Evasion (this matches the full 8-byte table above). Verified in the bundled
mGBA harness by prefilling all four blocks with 6 and checking the result
after the cheat ran; addresses re-checked against the current build
(`gBattleMons` = `0x0201C514`, `statStages` offset 60 -> `0x0201C550`).

**These addresses are only valid for a build with this exact
`gBattleMons` layout.** If you rebuild after changing anything that
touches the `BattlePokemon` struct definition in `include/pokemon.h`,
re-derive the address/offset using the DWARF/`.map` method above rather
than assuming these still work.

## Always-crit cheat (ignores crit immunity) - emulator-tested against the real game function

Crits are decided by `CalcCritChanceStage()` in `src/battle_script_commands.c`.
It returns `NEVER_CRIT` (-2) first if the defender's side has Lucky Chant, or
if any active ability has `onCrit` returning `NEVER_CRIT` (Battle Armor, Bad
Luck, Stalwart in this source), and only then checks the crit stage. So there
are two separate pieces: force the stage to always-crit, and remove the
immunity sources. Codes are CodeBreaker-style (`2` = 16-bit OR, `4` = slide,
`6` = 16-bit AND), addresses valid for THIS build only.

**1. Force always-crit for your side** (sets `critBoost` = 3 = `ALWAYS_CRIT` in
`gVolatileStructs[battler]`, byte 73 bits 0-1; the OR leaves the neighbouring
bits `fear/onTheProwl/trickOrTreat/skyDropped` alone):
```
2201C81C 0300
2201C8B4 0300
```
**2. Remove crit-immune abilities on the enemy side** (zeroes all 4 ability/innate
slots plus the 3 hell-mode extra slots = 14 bytes at `gBattleMons[b]+40`, for
battlers 1 and 3; stops before `hp`):
```
4201C5A4 0000
00000007 0002
4201C674 0000
00000007 0002
```
Side effect: the enemy has no abilities or innates at all while this is on.

**3. Remove Lucky Chant from the enemy side** (clears bit 12 of
`gSideStatuses[1]`):
```
6201C76C EFFF
```
Only codes 1+2+3 together crit through Battle Armor + Lucky Chant. Code 1
alone still respects immunities. Note: in doubles the game indexes
`gSideStatuses[battlerDef]` by battler id (not side), so the Lucky Chant
check for battler 3 reads past the 2-entry array; code 3 only covers the
normal singles/first-slot case.

Verified by calling the real `CalcCritChanceStage` in the emulator with a
crafted RAM state: baseline stage 0; `critBoost=3` -> ALWAYS_CRIT; Battle
Armor defender -> NEVER_CRIT even with the boost; with the three codes
running (Battle Armor + Lucky Chant + neighbouring bits seeded) -> ALWAYS_CRIT,
neighbouring bits and the defender's HP untouched. Not yet watched in a
live battle. Files: `tools-notes/`.

**Multi-hit: no safe plain cheat.** The engine already loops any move through
`MOVEEND_MULTIHIT_MOVE` while `gTurnStructs[attacker].multiHitCounter`
(4-bit field) is non-zero, decrementing once per hit. A constant RAM write
re-arms it every frame so it never reaches 0 (repeats until someone faints),
and status moves would loop forever. Doing it properly needs a source change
(e.g. hook `GetParentalBondCount()`), not a cheat.

### Harness technique: call a game function from the emulator
Compile a tiny Thumb stub (`tools-notes/call_stub_example.c`) with
`arm-none-eabi-gcc -mthumb -mcpu=arm7tdmi -nostdlib -ffreestanding`, link at
free EWRAM (`0x0203FA00`; the last real EWRAM symbol ends at `0x0203F8D6`),
copy the bytes into `core.memory.wram`, then set `gMain.callback2`
(`0x03003424`) to the stub address |1 for one `run_frame()` and restore it.
Args/results go through a small mailbox at `0x0203FF00`. Get the function
address from `readelf -s` (Thumb functions have bit 0 set; `.map` hides it).
Gotcha: `core.memory.wram.u16[x]` / `u32[x]` take BYTE offsets, not element
indices - indexing them like arrays silently reads/writes the wrong place.

## Noclip (walk through walls/NPCs) - source patch + auto-off cheat

A pure RAM cheat cannot do noclip in this build: the game's own
`FLAG_SYS_NO_COLLISION` check in `GetCollisionAtCoords()`
(`src/event_object_movement.c`) is compiled out (`B_ENABLE_DEBUG` is only TRUE
for `DEBUG_BUILD`), the flag would live in the save block whose address moves
(`gSaveBlock1Ptr`), and the map grid's collision bit shares a halfword with the
metatile id, so a CodeBreaker slide/fill code would corrupt the map instead of
clearing collision.

So the source has two tiny hooks, both using raw addresses in the unused tail
of EWRAM (the last linked EWRAM symbol ends at `0x0203F8D6`) so no symbol moved
and every other cheat address in this README is unchanged (re-checked against
the map after each rebuild):

- `src/main.c`, in the `AgbMain()` loop right after `ReadKeys()` - a per-frame
  "heartbeat" latch:
  ```c
  *(vu8 *)0x0203FFF1 = (*(vu8 *)0x0203FFF0 == 1);   // latch the cheat byte
  *(vu8 *)0x0203FFF0 = 0;                            // consume it
  ```
- `src/event_object_movement.c`, top of `GetCollisionAtCoords()`:
  ```c
  if (objectEvent->isPlayer && *(vu8 *)0x0203FFF1 == 1)
      return COLLISION_NONE;
  ```

Because the cheat byte is consumed every frame, noclip only stays on while the
cheat keeps rewriting it (cheat engines rewrite every frame). **Enable the
cheat = noclip on; disable the cheat = collisions are back within one frame**,
no second code needed. Only the player is affected; NPCs and trainers still
collide. The bytes are 0 on boot, so the ROM is normal until the cheat is on.

Cheat (CodeBreaker `3` = 8-bit write; RetroArch: address `0x0203FFF0`,
1 byte, value `1`):
```
3203FFF0 0001
```
Only the value exactly 1 enables it.

Tested against the real functions in the emulator: real cheat on for 200
frames -> latch stays 1 every frame, player passes, NPC still blocked; byte
left at 1 with the cheat engine off -> used for one frame then cleared, player
blocked again; simulated on -> off -> on -> collisions return 1 frame after
the cheat stops and noclip re-enables 1 frame after it resumes. NOT tested in
a live overworld. Known behaviour (same as the stock debug noclip): you can
walk onto water/cliffs without Surf, and you can walk off the edge of a map
into the void - save first and don't wander past the border.

Build/test gotchas learned here:
- Match the file's whitespace exactly when patching (`GetCollisionAtCoords`
  mixes tabs and spaces). A failed Python `assert old in text` means nothing was
  patched, and `make` will still "succeed" with nothing to do.
- After a reset the game's intro has a ~30-frame busy stretch (frames 316-345)
  where the main loop does not iterate at all - the original prebuilt ROM does
  this too (`tools-notes/main_loop_stall_probe.py`). Stub calls made then
  silently do not run and you read a STALE result. The harness now asserts the
  stub's call counter advanced; warm up past frame ~350 before testing.

## Open findings (not fixed - candidates for a future session)

- `CalcCritChanceStage` still reads `gBattleMoves[move]` / hold-effect data without bounds checks on `move`; fine for valid ids.
- Performance was reviewed by reading only; no profiling was possible. Ideas not attempted: caching `IsBattlerAlive` in the ability-iteration macros (`ON_ABILITY`, ~39 battler loops in `battle_util.c`) and reducing repeated `GetBattlerHoldEffect` calls in AI damage simulation.
- ~~`battle_ai_util.c:2151` - `(status1 & STATUS1_SLEEP) == 1`~~ - **investigated,
  not a bug.** `STATUS1_SLEEP` is a 3-bit turn-counter mask (`1<<0 | 1<<1 | 1<<2`),
  not a single flag bit, so `== 1` means "exactly one sleep turn left" - which is
  exactly what `IsWakeupTurn()` is checking for (it also requires Rest was used 2
  turns ago). Different from the fix-31-adjacent bugs, which compared a
  multi-bit-or'd flag mask against `TRUE`/`1` where any nonzero value should have
  passed. Closing this open item.
- `PredictFoesMoveType`'s `defType1`-referenced-twice copy-paste bug is real but currently dead code (only call site is commented out) - fix it properly if that call site is ever re-enabled.
- ~~`cry_table.h`'s duplicate `EGG_GROUP_WATER_2` test~~ - **fixed.** The second
  occurrence in `GetSpeciesCry()` (~line 1091) is now `EGG_GROUP_WATER_3`.
  Compile-checked clean (`tools-notes/check-compile.sh`, `-Werror`) against
  v2.65.2.3b. Previously harmless (both branches returned the same
  `CRY_FISH_SMALL`), but Water-3-group mons were silently falling through to
  unrelated branches for their cry category.
- **Fixes 5-33: built, linked and booted.** `make -j1` with all of fixes 5-33 applied links cleanly (`MAKE_EXIT=0`) and the resulting `pokeemerald_modern.gba` boots in the mGBA harness. Not yet compared byte-for-byte against `reference-roms/pkmn-emerald_modern.gba` (that reference only carries fixes 5-9, so a diff would show mostly expected divergence, not a useful check anymore - a fresh reference build would need to also carry 10-27 to be a meaningful comparison).
- **None of fixes 5-33 have been playtested in a real battle yet** - only a cold-boot-to-title-screen smoke test has been done (now confirmed against v2.65.2.3b itself, not just the pre-swap tree). Do this before adding more.
- **Performance check (`IsBattlerAlive` caching / repeated `GetBattlerHoldEffect` calls) - done, not worth it.** Disassembled the actual compiled functions from the v2.65.2.3b ELF: `IsBattlerAlive` is ~17 Thumb instructions, `GetBattlerHoldEffect` ~45 (including its ability-lookup calls on the slow path). Even worst-case - all ~80 combined `ON_ABILITY`/AI call sites firing every single turn, uncached - that's on the order of a few hundred microseconds of ARM7TDMI time against a 16.7ms frame budget, and it runs once per turn, not per frame. Not worth caching; closing this open item.
- Playtest priorities: Metronome (fix 23), hell-mode Expert Belt / resist berries / effectiveness labels (fixes 19-20), doubles with several follow-up abilities (fix 15), Dusk Ball night-catch bonus (fix 28), a form-change ability (Shields Down/Gulp Missile) while the user's mon has a non-Transformed volatile status like confusion (fix 29), Nightmare against a target with another volatile status (fix 30), Training Band with the party's highest level under 4 (fix 32), and the AI dual-type switch-in behavior change (fix 33).
- Next places to hunt: level-up and tutor learnset generators (`proto/` -> generated data), switch-in ability ordering in doubles, other instances of the same bug families just found (bitfield checked with `&&`/`||` instead of `&`/`|`, a masked flag compared to `TRUE`, unsigned wraparound in a subtraction) elsewhere in the source, since finding six in one sweep suggests more are likely still there.
- **Re-confirmed in a fresh session on this exact package:** `make -j1` from this
  source tree links cleanly (`MAKE_EXIT=0`, EWRAM 250,954 B/95.73%, IWRAM 79.22%,
  ROM 70.73% - unchanged from the numbers above), the resulting
  `pokeemerald_modern.gba` boots clean in the mGBA harness (Groudon logo renders
  over 2500 frames, no crash), and `gBattleMons`/`gVolatileStructs`/`gSideStatuses`
  in the fresh `.map` are still `0x0201C554`/`0x0201C814`/`0x0201C7A8` - unchanged,
  so every cheat table in this file is still valid. `cry_table.h`'s fix was
  re-verified compiling clean under `-Werror` via `src/pokemon.c` (its only
  includer). **Still true, not re-attempted this session:** no fix from 5-33 has
  been played through an actual multi-turn battle - the playtest-priority list two
  bullets up is unchanged and is the next thing to do, not a stub-callable check
  like the hell-mode threshold or the performance pass were.
