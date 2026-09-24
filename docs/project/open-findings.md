# Open findings (not fixed - candidates for a future session)

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

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
  Compile-checked clean (`modules/07-tools-notes/check-compile.sh`, `-Werror`) against
  v2.65.2.3b. Previously harmless (both branches returned the same
  `CRY_FISH_SMALL`), but Water-3-group mons were silently falling through to
  unrelated branches for their cry category.
- **Fixes 5-33: built, linked and booted.** `make -j1` with all of fixes 5-33 applied links cleanly (`MAKE_EXIT=0`) and the resulting `pokeemerald_modern.gba` boots in the mGBA harness. Not yet compared byte-for-byte against `modules/09-reference-roms/pkmn-emerald_modern.gba` (that reference only carries fixes 5-9, so a diff would show mostly expected divergence, not a useful check anymore - a fresh reference build would need to also carry 10-27 to be a meaningful comparison).
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
  so every cheat table in [cheats.md](cheats.md) is still valid. `cry_table.h`'s fix was
  re-verified compiling clean under `-Werror` via `src/pokemon.c` (its only
  includer). **Still true, not re-attempted this session:** no fix from 5-33 has
  been played through an actual multi-turn battle - the playtest-priority list two
  bullets up is unchanged and is the next thing to do, not a stub-callable check
  like the hell-mode threshold or the performance pass were.
