# Source-code fixes (3-33)

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

| Pass | Fixes | Method | Verified |
|---|---|---|---|
| Present at package assembly | 3-4 | manual review | built |
| Bug-hunt pass | 5-9 | manual review | built + booted |
| Follow-up bug-hunt | 10-27 | manual + warning sweep | compiled per file, linked, booted |
| Warning sweep | 28-33 | `-Wlogical-op` etc. | compiled per file, linked, booted |
| v2.65.2.3b re-verification | all | delta re-apply | linked (`MAKE_EXIT=0`) + boot-tested; **not playtested** |

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
(`modules/09-reference-roms/pkmn-emerald_modern.gba`) from this same `upcoming` source
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
via `modules/07-tools-notes/check-compile.sh`. They have not been linked into a ROM or playtested.

**Known open items (not fixed yet):** see [open-findings.md](open-findings.md).

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
per modified file via `modules/07-tools-notes/check-compile.sh`, and a subsequent full
`make -j1` with all six applied **linked successfully** (`MAKE_EXIT=0`;
EWRAM 250,954 B / 95.73%, IWRAM 79.22%, ROM 70.73% - identical to the
fixes-5-27 build, since none of 28-33 touch a struct layout) and the
resulting `pokeemerald_modern.gba` **boots** in the mGBA harness (Game Freak
intro -> Groudon logo rendered correctly over 2500 frames, no crash, no black
screen). `gBattleMons`/`gVolatileStructs`/`gSideStatuses` addresses in the
fresh `.map` are unchanged from the fixes-5-27 build (`0x0201C554`,
`0x0201C814`, `0x0201C7A8` respectively), so the cheat tables in
[cheats.md](cheats.md) are still valid for this build too. **Not yet playtested in a real
battle** - the boot check only confirms the ROM starts, not that Dusk Ball,
Nightmare, Training Band, form-change abilities, or the AI switch-in change behave correctly in play.

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
