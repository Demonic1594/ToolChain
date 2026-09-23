# Elite Redux build toolchain + patched source

Two guides - read the one you need:

- **`README-SETUP.md`** - extracting the (LZMA) archive, restoring exec bits,
  `setup.sh`, building, build gotchas, packaging notes.
- **`README-PROJECT.md`** - what has been changed in the game and source (bug
  fixes, Shedinja/abilities, learnsets), cheat codes, emulator test harness,
  struct/address lookup.

New session shortcut: extract -> `bash restore-exec-bits.sh` (only if you used
Python to extract) -> `bash -c 'source setup.sh'` -> read `README-SETUP.md`.

Note (updated): `eliteredux-source/` was replaced wholesale with a fresh
source drop, **Elite Redux v2.65.2.3b** (see `eliteredux-source/README.md`
for its own changelog - this update reverts Shedinja to its classic Absolute
Guard identity, flattens Mew's base stats to 110 across the board, reworks
Furret's stats/ability, and changes Ogerpon's non-Mega abilities/innates).
This drop shipped source-only, with no prebuilt `pokeemerald_modern.gba`/
`.elf`/`.map` - since built here: `make -j1` **did not build at all** until
`ABILITY_FLUFFIEST_ONE` was added to `proto/AbilityEnum.proto` (see
"Source update notice" in `README-PROJECT.md` for the full root cause). With
that one-line fix applied, the tree **builds, links, and boots cleanly**
(`MAKE_EXIT=0`, Groudon logo renders, no crash). Fixes 5-33 in
`README-PROJECT.md` have now been re-checked against this drop and are
present and correct; **real in-battle playtesting is still outstanding**.
`reference-roms/pkmn-emerald_modern.gba` is unaffected by this swap and is
still the older fixes-5-9-only reference build.

Latest session: the v2.65.2.3b source zip was re-applied as a delta (19 changed
+ 4 new files, everything else left alone), rebuilt (`MAKE_EXIT=0`) and
boot-tested. The `.gba`/`.elf`/`.map` in `eliteredux-source/` are that fresh
build. Details: last section of `README-SETUP.md`.
