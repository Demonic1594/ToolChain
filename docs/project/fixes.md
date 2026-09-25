# Source-code fixes (3-93)

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

| Pass | Fixes | Method | Verified |
|---|---|---|---|
| Present at package assembly | 3-4 | manual review | built |
| Bug-hunt pass | 5-9 | manual review | built + booted |
| Follow-up bug-hunt | 10-27 | manual + warning sweep | compiled per file, linked, booted |
| Warning sweep | 28-33 | `-Wlogical-op` etc. | compiled per file, linked, booted |
| v2.65.2.3b re-verification | all | delta re-apply | linked (`MAKE_EXIT=0`) + boot-tested; **not playtested** |
| Systematic review pass | 34-93 | 5 parallel deep reviews (battle core/script/util/AI/abilities + mon-data subsystem), every finding re-verified by hand against surrounding code and upstream pokeemerald-expansion 1.9.2 | compiled per file (`-Werror`); see verification note at the end |

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

### Fixes added in the systematic review pass (34-93; compile-checked per file with `-Werror`)

A full-tree review of the battle engine, the AI, `abilities.cc`, and the
mon-data subsystem (16 files touched). Every finding below was verified
against its surrounding code (and, where relevant, pokeemerald-expansion
1.9.2 / the ability `textproto` descriptions) before fixing. Grouped by
severity, then file.

#### Gameplay-breaking / memory corruption

34. **Every Poké Ball was an instant guaranteed capture**
    (`Cmd_handleballthrow`, `battle_script_commands.c`) — the caught/uncought
    branch read `if (TRUE)`, making the entire shake/fail path (including
    Critical Capture and the Master Ball shortcut inside it) unreachable dead
    code. Restored the upstream condition `if (odds > 255)` (vanilla formula
    uses `/10` ball multipliers here, where the threshold is 255; Master Ball
    is still guaranteed via `shakes = maxShakes` in the else branch). Also
    hardened the re-enabled shake formula against `odds == 0` (catchRate-0
    species): a 0-odds ball now deterministically shows 0 shakes instead of
    relying on divide-by-zero behavior.
35. **Switch-in queue compaction corrupted memory** (`SwitchInClearSetData`,
    `battle_main.c`) — the "remove queued out-of-turn attacks" loop had the
    "remove queued switches" loop *nested inside it*, reusing the same index
    `i` and never resetting `gQueuedSwitchCount` before compacting. Effects:
    the outer attack loop aborted early (queued attacks of the switched-in
    battler survived), and the switch compaction *appended* duplicated entries
    past the old count — writing past `gQueuedSwitchData[4]` into
    `gQueuedSwitchCount`/`gCurrentActionFuncId`/`gBattleMons[0]` (EWRAM
    adjacency from the `.map`). Also, when the attack queue was empty the
    switch queue was never filtered at all. Now two sequential sibling loops.
36. **Nine abilities indexed side arrays with a battler id** (`abilities.cc`)
    — `gSideStatuses[...]`/`gSideTimers[...]` are `[2]` arrays indexed by
    *side* (`battler & 1`), but `BATTLE_OPPOSITE(battler)` = `battler ^ 1`
    yields a *battler* id: correct only for battlers 0/1, and an **OOB write**
    (Hot Coals, 8875) / OOB reads (the rest) for the right-flank battlers 2/3
    of doubles. Fixed to `GetOppositeSide(battler)` (`= (battler & 1) ^ 1`) in:
    **Hot Coals** (write), **Spider Lair** + **Spider Lair Upgrade**,
    **Scrapyard** + **Drop Blocks** (spikes cap), **Toxic Debris** (toxic
    spikes cap), **Loose Rocks** + **Loose Thorns** (stealth rock), and
    **Overcast** (read `gSideStatuses[battler]` directly while setting via
    `GetBattlerSide` three lines below — check and set could disagree).
37. **`CanTargetFaintAi` indexed `simulatedDmg` by move id**
    (`battle_ai_util.c`) — `simulatedDmg[def][atk][moves[i]]` used the move
    *id* (up to ~900) as the third index of a `[4][4][4]` array; any foe move
    id ≥ 4 read far out of bounds, corrupting the "can the foe KO me" check
    that feeds the AI_TryToFaint-family scoring every AI turn. Now indexes by
    slot `i` (as the sibling `CanAIFaintTarget` correctly does).
38. **`CanTargetFaintAiWithMod` had attacker/defender swapped**
    (same file) — it read the AI's *own* damage output and compared it to the
    AI's own HP while filtering by the AI's own move limitations; with the AI
    at low HP it concluded "foe can KO me" exactly when its own attack
    outdamaged its own HP (heal-refusal). Indices and limitations fixed to the
    defender's.

#### Wrong results in normal play

39. **Unnerve only detected from one opponent slot**
    (`IsUnnerveAbilityOnOpposingSide`, `battle_util.c`) — after
    `opponent = BATTLE_PARTNER(opponent)` the second ability check still
    tested `BATTLE_OPPOSITE(battlerId)`, i.e. the *first* opponent again
    (including a fainted one). Partner's Unnerve never suppressed berries.
40. **Instruct read `gBattleMoves[0xFFFF]` before its own guard**
    (`VARIOUS_TRY_INSTRUCT`, `battle_script_commands.c`) — the ban-list loop
    indexed `gBattleMoves[gLastMoves[gActiveBattler]].effect` *before* the
    `== 0xFFFF` check on the next line; a failed/none move read ~1.3 MB past
    the table. Guard moved before the loop (same pattern as the Copycat
    sibling above it).
41. **Fury Cutter never powered up** (`Cmd_handlefurycutter`) — the
    "don't increment on Parental Bond second hit" exception was AND-ed into
    the *increment* condition, so a normal mon (both PB fields 0) never
    incremented at all: Fury Cutter stayed at 40 base power forever. Now
    increments unless a PB continuation hit is in progress (matches upstream
    1.9.2's `!= PARENTAL_BOND_2ND_HIT`).
42. **`sameMoveTurns` never accrued** (`Cmd_ppreduce`) — same inverted
    exception shape: the increment required an active PB continuation, which
    can never be true at PP-deduction time (it runs once per move, on the
    first hit). The Metronome-item boost, the ability multiplier in
    `abilities.cc` and `script_conditions.cc` were all permanently dead.
    Exception removed (ppreduce runs once per turn; no double-increment risk).
43. **Psycho Shift's poison branch used the paralysis immunity check**
    (`VARIOUS_PSYCHO_SHIFT`) — copy-paste; poison could be shifted onto
    Poison/Steel types and Electric types wrongly blocked it. Now
    `CanBePoisoned(gBattlerAttacker, gBattlerTarget, gCurrentMove)`.
44. **Terrain Seed hold-effect lookup keyed by battler id**
    (`VARIOUS_TERRAIN_SEED`) — `ItemId_GetSecondaryId(gActiveBattler)` passed
    a battler id (0-3) to an item-id-keyed lookup; the seed-eaten-by-bug path
    could never match. Now passes the held `item` (which was already read
    into a local one line above).
45. **Future Sight side flag desynced on swap moves** (`VARIOUS_SWAP_WITH`)
    — both XORs toggled `gActiveBattler`'s side (the second undid the first)
    while the per-battler counter/move/power/attacker data *was* swapped
    below; the side flag then never matched the swapped state. Second XOR now
    toggles the attacker's side.
46. **Swallow restored SpDef with the Def stockpile count**
    (`Cmd_stockpiletohpheal`) — copy-paste from the Def line; SpDef could be
    lowered by the wrong amount and `stockpileSpDef` never consumed. Now uses
    `stockpileSpDef` (matches `TryUseStockpile`/`Cmd_stockpiletobasedamage`).
47. **Lansat-style crit berry only eaten when useless**
    (`ItemBattleEffects`, `HOLD_EFFECT_CRITICAL_UP`) — the end-turn case
    tested `!(critBoost < 3)`, i.e. eat only at cap, where the computed
    increase is zero stages. Inverted to `critBoost < 3` (matches its own
    switch-in twin).
48. **Sky Drop victim never released early when the user's move is
    cancelled** (`CancelMultiTurnMoves`, `battle_util.c`) — the filter tested
    `gVolatileStructs[battler].skyDroppedBy == battler` (self-dropped:
    impossible, the setter requires target ≠ user), so `shouldClearSkyDrop`
    was never set and the `ENDTURN_SKY_DROP` release path was dead: flinching/
    falling asleep mid-Sky-Drop left the target semi-invulnerable in the air.
    Also made that end-turn consumer clear `STATUS3_ON_AIR` like the two
    battle_main.c release paths do.
49. **Wrap "broke free" cleared `wrapAbility` on a stale battler**
    (`ENDTURN_WRAP`) — used `gEffectBattler` (stale global) instead of
    `gActiveBattler` (the freed mon, used by every other line in the block):
    an unrelated battler's wrap bookkeeping was zeroed and the freed mon kept
    a stale `wrapAbility` for the next wrap announcement.
50. **HP-based form changes remapped ability state for the wrong battler**
    (`ShouldChangeFormHpBased`, `battle_util.c`, 7 sites) — species was
    changed on the `battler` parameter but
    `UpdateAbilityStateIndicesForNewSpecies(gActiveBattler, ...)` read the
    *acting* battler's personality/level and clobbered the wrong battler's
    tracking. Called from defender-side ability hooks where `gActiveBattler`
    is typically the attacker. All sites now pass `battler`.
51. **Poison monotype-champion end-turn effect only fired for battler 0**
    (`ENDTURN_TOXIC_WASTE_DAMAGE`) — `gActiveBattler == B_SIDE_PLAYER`
    compared a battler id to a side constant (0). The player's right-slot mon
    (battler 2) never got the Toxic Spill damage. Now
    `GET_BATTLER_SIDE(gActiveBattler) == B_SIDE_PLAYER` (as the Rock and Bug
    champion cases in the same function already did).
52. **`ENDTURN_COILED_UP`/`CUTTHROAT` indexed `gBattleMoves` with an
    unguarded `gLastMoves`** (`battle_util.c`) — `gLastMoves[battler]` is set
    to `0xFFFF` when a move records without `HITMARKER_OBEYS`; both checks now
    skip when the last move is 0/0xFFFF instead of reading ~1.3 MB past the
    move table.
53. **Illusion detection seeded the ability randomizer with the species**
    (`SetIllusionMon`, `battle_util.c`) — `personality` was read with
    `MON_DATA_SPECIES` (copy-paste). In Ability-Randomizer mode the Illusion
    check computed a different ability than the mon actually had (false
    positives and negatives). Now `MON_DATA_PERSONALITY`.
54. **Magic Room lost a turn of duration on the cast turn**
    (`ENDTURN_MAGIC_ROOM`) — the only room/terrain end-turn case missing the
    `!gFieldTimers.started.magicRoom` guard its siblings have (the flag *is*
    set on creation and cleared by `ZERO(gFieldTimers.started)` each turn).
55. **Fling base power read the flung item from the wrong battler**
    (`CalcMoveBasePower`, `EFFECT_FLING`) — used `gTurnStructs[gActiveBattler]`
    where the rest of the function uses the `battlerAtk` parameter; the AI /
    damage preview computed Fling power from the wrong mon's item.
56. **Heal Bell checked Soundproof with a party index**
    (`Cmd_healpartystatus`) — `IsSoundproof(i)` was called with the party
    slot (0-5) where the function expects a *battler* id: slots 4-5 read
    past `gBattleMons[4]`, and slots 0-3 checked the wrong battler's
    abilities whenever party index ≠ battler id. Field mons now check their
    actual battler (`gBattlerAttacker` / partner, doubles-gated); bench mons
    keep the species/innate lookup path.
57. **Leech-Seed-on-hit seeded exactly the immune targets**
    (`SetMoveEffect`, `MOVE_EFFECT_LEECH_SEED`, used by Fertile Fangs /
    Bramble Blast) — the gate *required* the target to be Grass (the type
    immune to Leech Seed) unless the attacker had Mycelium Might. Now mirrors
    `Cmd_setseeded`: fails on Grass, applies otherwise.
58. **Switch-in item effects ran for the wrong battlers / read OOB on the
    last slot** (`TryDoEventsBeforeFirstTurn`, `battle_main.c`) —
    `if (!IsBattlerAlive(counter++)) continue;` then indexed
    `gBattlerByTurnOrder[counter]` with the *already-incremented* counter:
    items were processed for the next battler in speed order (Amulet Coin
    prize doubling / White Herb / instant berries silently misapplied at
    battle start), and the final iteration read `gBattlerByTurnOrder[4]`,
    one past the array. Now mirrors the sibling abilities loop.
59. **AI spikes-danger check was inverted** (`CalculateHazardDamage`,
    `battle_ai_switch_items.c`) — `spikesAmount > 0 && !IsBattlerGrounded`:
    the AI computed spikes damage for *airborne* mons and none for grounded
    ones, switching doomed grounded mons into spikes and refusing to switch
    fliers. Now `&& IsBattlerGrounded(...)`.
60. **Candy Box granted one level less than the menu showed**
    (`PokemonUseItemEffects` + `ShowLevelUpSelectWindow`) — cursor k displayed
    "Lv {level+k}" but the effect applied `level + k - 1` (the first numeric
    option granted zero levels). Fixed to `levelUp = k`, and the party menu
    now offers 6 entries (Level Cap + 5 levels) matching the PC's
    `MAX_LEVEL_UP_OPTIONS = 6` and the `CANDY_BOX_LEVELS = 5` clamp — the 7th
    entry previously displayed a level the clamp would silently cap.
61. **Form Change menu badge gate was always open** (`party_menu.c`) —
    `VarGet(FLAG_BADGE02_GET)` passes a *flag* id to a *var* getter, which
    returns the id itself (always nonzero): the Badge-2 requirement never
    gated anything. Now `FlagGet(FLAG_BADGE02_GET)`. Same block's loop bound
    `i < gFormChangeTable[species][i].method` compared the counter to the
    method *value* — changed to the standard `.method;` terminator idiom used
    everywhere else.
62. **PC mon options menu could drop Cancel** (`SetMenuText`,
    `pokemon_storage_system.c`) — MOVE_MONS mode can qualify for 8 entries
    (Move/Summary/Withdraw/Level Up/Evolve/Mark/Release/Cancel) into the
    7-slot menu (the layout `15 - 2*count` caps at 7), and the overflow guard
    silently dropped the last item: Cancel. Now Cancel replaces the last slot
    instead of being lost (B-button cancel was always available). Trade-off:
    Release is the entry dropped in that 8-entry case.
63. **Daycare nature inheritance read `daycare->mons[-1]`**
    (`GetParentToInheritNature`, `daycare.c`) — with no Everstone held (the
    common case) `parent == -1` and the trailing re-check dereferenced
    `mons[-1]` ~100 bytes before the array. Benign on GBA (result invariant)
    but a real OOB read on every egg trigger; now guarded with `parent < 0`.

#### AI evaluation bugs (live old AI)

64. **`AI_MoveMakesContact` inverted Long Reach** (`battle_ai_util.c`) —
    returned "makes contact" only for Long Reach holders (the ability that
    *prevents* contact). Rocky Helmet danger scoring was exactly backwards.
65. **Ally-absorb scoring inverted** (`AI_HPAware`, `battle_ai_main.c`) —
    the "beneficial hit on my partner" branch required the partner to *lack*
    Volt Absorb / Earth Eater / (Dry Skin *and* Water Absorb), encouraging
    the AI to blast its own injured partner and skipping the one good case.
    Affirmative tests now; water is Dry Skin *or* Water Absorb.
66. **Snore / Sleep Talk penalized when usable** (`AI_CheckBadMove`) —
    `!asleep || !comatose` is true for nearly every mon (asleep XOR comatose);
    now `!asleep && !comatose` per the comment.
67. **Teeter Dance partner-ability checks inverted** (same function) — the
    target's Own Tempo/Discipline clauses tested positive but the partner's
    were negated, so in doubles the "neither foe can be confused" gate
    required the partner to *lack* immunity. Partner clauses now match the
    target's, wrapped in an alive-guard so singles behavior (decided by the
    sole foe) is unchanged.
68. **Recycle berry scoring divided by a zero hold-effect param**
    (`AI_CheckViability`) — Lum/Chesto/Persim have `holdEffectParam == 0`;
    `maxHP / 0` executed on the AI's turn for Ripen mons. Param fetched once,
    zero-guarded.
69. **AI query advanced the real toxic counter** (`GetPoisonDamage`,
    `battle_ai_util.c`) — the "estimate end-turn poison damage" helper did
    `status1 += STATUS1_TOXIC_TURN(1)` on the *real* battler state (including
    the player's mon), permanently inflating toxic damage after a few AI
    turns. Now computes the next tick locally.
70. **`IsBattlerTrapped` read the acting battler's Commanded/fear state**
    (`battle_ai_util.c`) — two of the clauses used `gActiveBattler` instead of
    the `battler` parameter; during AI thinking every foe inherited the AI's
    own mon's trap state.
71. **u8 truncation of u16 stats in AI scoring** — Power Split / Guard Split
    (`battle_ai_main.c`) and `IncreaseParalyzeScore` speeds
    (`battle_ai_util.c`) stuffed 300+ stats into `u8` locals (300→44,
    260→4), making split-or-not and will-paralysis-flip-speed decisions
    garbage for level-100 mons. Locals widened to `u16`.
72. **Seismic Toss / level-damage AI read `gBattlerAttacker`'s level**
    (`battle_ai_attack.c`, dormant new AI) — now the `battlerAtk` parameter.

#### Latent / dormant code fixes

73. **`B_TXT_BUFF4` expanded into `gStringVar3` but printed `gStringVar4`**
    (`battle_message.c`) — copy-paste; currently masked because the only
    buff4 producers write plain digits, but any future placeholder buff4
    would print stale memory.
74. **`{B_ACTIVE_NAME2}` read the species from `gPlayerParty` in the
    opponent branch** (`battle_message.c`) — copy-paste; a non-nicknamed
    opponent would be named after the player's party member at the same
    index. (String currently unused, but fixed for when it returns.)
75. **Battle Palace target flags used the player's move cursor**
    (`battle_gfx_sfx_util.c`) — `moveInfo->moves[gMoveSelectionCursor[...]]`
    instead of the AI-chosen `moves[chosenMoveId]` (vanilla behavior).
76. **`TRAINER_OLDPLAYER` debug party could roll `SPECIES_NONE`**
    (`battle_main.c`) — `Random() % 500` has a 1/500 chance of 0; now
    `1 + Random() % 499`.
77. **`CreateMonWithEVSpread` divided by zero for an empty EV spread**
    (`pokemon.c`, 2 sites) — `statCount` is 0 when `evSpread == 0`; guarded
    (no current caller passes 0, defensive).
78. **`GetMoveRelearnerMoves(..., disableLearned = FALSE)` collected
    nothing** (`pokemon.c`) — `j` stayed 0 so the "not already known" gate
    never passed; `j = MAX_MON_MOVES` when learning isn't disabled. (Only
    caller passes TRUE today.)
79. **`HoennToNationalOrder` off-by-one** (`pokemon.c`) — allowed
    `hoennNum == ARRAY_COUNT(...)`, reading one entry past the table
    (vanilla-identical quirk, fixed anyway).
80. **Moody's stat RNG could draw `STAT_HP`** (`abilities.cc`) —
    `(Random() % NUM_STATS - STAT_ATK) + STAT_ATK` parses as
    `Random() % NUM_STATS` (the ± cancels); rejected by the validity masks,
    so only the retry distribution was skewed. Parenthesized correctly.
81. **Beads of Ruin lowered Def instead of SpDef** (`abilities.cc`) — the
    impl was a copy of Sword of Ruin (`STAT_DEF` in both `.onStat` and
    `.ruinStat`); the ability's own description says Special Defense. Now
    `STAT_SPDEF`.
82. **Archmage's Grass branch set Misty terrain** (`abilities.cc`) —
    copy-paste from the Fairy branch; the description says Grass sets
    *grassy* terrain. Now `STATUS_FIELD_GRASSY_TERRAIN`.
83. **Let's Roll clobbered the whole `status2` word** (`abilities.cc`) —
    `status2 = STATUS2_DEFENSE_CURL` (assignment) wiped every other volatile
    bookkeeping bit on entry; now `|=`.
84. **Download / Spyware fallback liveness tested the wrong battler**
    (`abilities.cc`) — `if (!IsBattlerAlive(battler))` tested the ability
    *owner* (always alive on entry) where `gBattlerTarget` (just selected the
    line above) was meant; in doubles with the opposite slot fainted both
    abilities read a fainted mon's stats. Matches the Forewarn pattern.
85. **`PredictFoesMoveType` used `defType1` twice** (`battle_ai_switch_items.c`,
    3 sites) — the documented open item: effectiveness was computed as
    atk×defType1². Still dead code (sole caller commented out), but now fixed
    for whenever it is revived.
86. **Dormant new-AI fixes** (`battle_ai_new.c` / `_util.c` / `_attack.c`)
    — `GetAiDecision` computed every battler's move limitations from the
    function's `battler` argument instead of the loop's `battlerAtk`;
    `BelowHalfHp` compared `hp <= maxHP` (missing `/ 2`); `CheckSingleHitKo`
    discarded `ApplyModifier`'s return value (crit/×2 multiplier never
    applied); `sCritChance[critChance - 1]` was unbounded for the 3-bit
    field (clamped to the guaranteed-crit entry); Seismic Toss/level damage
    used `gBattlerAttacker`'s level. None reachable today (the new AI has no
    callers), fixed so wiring it up later starts from a clean base.

**Deliberately NOT changed** (verified design, do not "fix"): ER's Gluttony
intentionally includes the Cheek Pouch-style 1/3-max-HP heal on berry use and
ER's Cheek Pouch ability is intentionally "no effect" (see their
`AbilityList.textproto` descriptions); Absolute Guard still blocks status
moves (fix 16); the `SetActionsAndBattlersTurnOrder` pre-sort is inert
(`except` excludes every battler) but harmless because
`RecalculateMoveOrder` re-sorts after every action — left alone as a hazard
note; the link-revive loop `battler += 2` in `HandleEndTurn_BattleWon` is
correct because player-side battlers are ids 0/2 on every console.

**Verification:** every modified file passes a real per-file compile
(Makefile flags, `-Werror`) via `modules/07-tools-notes/check-compile.sh` /
`scripts/check-compile.sh`: battle_script_commands.c, battle_util.c,
battle_main.c, battle_message.c, battle_gfx_sfx_util.c, abilities.cc, all
five live-AI files, the three dormant-AI files, pokemon.c, party_menu.c,
pokemon_storage_system.c, daycare.c. Full `make -j1` + mGBA boot test: see
the build-status table in [README.md](README.md) for the latest result.
**None of 34-93 have been playtested in a real battle** — same caveat as
fixes 5-33; the playtest priority list in
[open-findings.md](open-findings.md) was extended accordingly.
