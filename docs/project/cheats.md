# Cheat codes (verified against this exact build)

> Paths are relative to `modules/06-eliteredux-source/` unless they start with `modules/`.
> [Back to project index](README.md)

> **Address validity:** every address below is only valid for a build with
> this exact `gBattleMons` layout (`gBattleMons` = `0x0201C514`,
> `statStages` offset 60). After any rebuild that touches
> `include/pokemon.h`'s `BattlePokemon` struct, re-derive them with the
> DWARF/`.map` method in [testing.md](testing.md) — someone else's cheat
> addresses will silently corrupt this build's memory.

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
live battle. Files: `modules/07-tools-notes/`.

**Multi-hit: no safe plain cheat.** The engine already loops any move through
`MOVEEND_MULTIHIT_MOVE` while `gTurnStructs[attacker].multiHitCounter`
(4-bit field) is non-zero, decrementing once per hit. A constant RAM write
re-arms it every frame so it never reaches 0 (repeats until someone faints),
and status moves would loop forever. Doing it properly needs a source change
(e.g. hook `GetParentalBondCount()`), not a cheat.

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
and every cheat address in [cheats.md](cheats.md) is unchanged (re-checked against
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
  this too (`modules/07-tools-notes/main_loop_stall_probe.py`). Stub calls made then
  silently do not run and you read a STALE result. The harness now asserts the
  stub's call counter advanced; warm up past frame ~350 before testing.
