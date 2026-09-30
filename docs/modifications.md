# Modifications vs upstream

Everything this fork changes relative to Elite Redux v2.65.2.3b `upcoming`.
Organized by the pass/batch that produced it; all work landed Sept 2026.

## Change passes at a glance

| Pass / batch | Fixes | Scope |
|---|---|---|
| Present at package assembly | 3–4 | Manual review found during first build |
| Bug-hunt + follow-up | 5–27 | Manual review, per-file compile checks |
| Warning sweep | 28–33 | `-Wlogical-op` & friends |
| Systematic review | 34–93 | 60 fixes across 16 battle/mon files |
| Frontier + controllers hardening | 94–114 | Factory save corruption (sev-1), 6v6 OOB/leaks, IV-garbage writes, div-0 guards |
| Round-3 deep pass (7 agents) | ~40 | Quest SaveBlock2 corruption, DexNav crash/UAF/leak, wild-encounter OOB, summary/dex overflows, soft-float opt |
| Batches A/C/E | 159–161 | Anim hardening, perf structural, design decisions (nuzlocke maps, roamers, DexNav) |
| gflib stdlib review | 163 | Text-printer starvation, Bard desync, InitWindows OOB read |
| Batch B: final subsystem sweep | 162 | Contests, minigames, link, TV/Easy Chat, Pokenav, Match Call, Union Room Chat, mevent |
| Final sweep | 164 | `waitse` live bug + m4a/codegen/data verification |

Full per-fix writeup for 3–33: `docs/project/fixes.md` on `main`. Later
fixes are described in their commit messages here (`git log`), grouped by
the batches above.

## Live bugs fixed (highest impact)

- **Absolute Guard multi-hit KO hole** (fix 3): the survival clamp was gated
  on `BATTLER_MAX_HP` like vanilla Sturdy, so hit #2 of a multi-hit move
  killed through it.
- **Battle Factory rentalMons save corruption** (sev-1, fix 94-era): frontier
  rental import wrote outside its save fields.
- **`waitse` wrong opcode** (fix 164, LIVE): suppressed ExtraSkill popups.
- **Mystic Aegis hard-lock**: `onBeforeAttack` re-execution loop after the
  ability popup + wrong `SET_STATCHANGER2` `goesDown` argument.
- **Match Call heap overflow + Steven flag collision**; **Union Room Chat
  stack smash**; **mevent code-exec fallthrough** (batch B).

## Hardening themes (~150 fixes)

- OOB reads/writes: battle menus, frontier swap/select screens, Arena
  `sMindRatings`, blender/crush/jump/dodrio minigames, TV/Easy Chat, summary
  & Pokédex screens, wild-encounter table indexing, var/flag bounds.
- UAF/leaks: DexNav, animation tasks, sprite/gfx tracking (8→16-bit where
  counts warranted), task-exhaustion guards.
- Division-by-zero guards across UI and stat math.
- IV-garbage writes (8 sites), partner 16-bit exp overflow, Mycelium dead
  branch, Mimic/Encore OOB reads.
- Quest SaveBlock2 corruption; nuzlocke now tracks 15 previously unlisted
  maps; roamers never consumed on encounter.

## Performance

- Soft-float elimination: turn-order comparisons, 31 ability hot sites,
  lookup hoists — replaced with integer math.
- Literal-divisor stage ratios, crit-roll masks, lazy AI crit passes,
  hold-effect hoists (batches C).

## Design-level changes (ours, on top of v2.65.2.3b)

- **Shedinja**: locked to classic Absolute Guard identity via the single
  `{A,A,A}` ability-list technique (base + Mega); HP=1 lock enforced in
  `pokemon.c` max-HP calc.
- **Mystic Aegis popup pattern** documented & hardened (self-limiting
  re-entry — pattern now safe for any future popup abilities).
- **Shiny icon system**: dedicated icon palettes — pal7 common, pal8 normal
  shiny-capable, pal9 shiny; `CreateMonIconWithShiny/FromMon` wired through
  party/summary/battle menus, trade screens, PSS + start menu.
- **ScriptGiveMon adoption features**: forced shiny (FLAG_SHINY_CREATION),
  signature moves in slots 0/1, always-female personality roll.

Note: the upstream v2.65.2.3b changelog (Shedinja/Mew/Furret/Ogerpon
changes) ships in `modules/06-eliteredux-source/README.md` from upstream —
those are the baseline's, not ours.

## SabreVoir (custom species)

`proto/SpeciesList.textproto` @ `SPECIES_SABREVOIR` (dex #1223, "Consort"):

| | Base (Shield) | Sword forme |
|---|---|---|
| Typing | Steel/Fairy | Steel/Fairy |
| Stats | 76/80/148/81/148/67 | 76/148/81/148/80/67 (def↔atk, spdef↔spatk swapped) |
| Ability | Arcane Stance | Arcane Stance |
| Innates | Promised Victory, Prophetic Destiny, Beast of Gluttony | same |

- **Forme shifting via signature moves**: **Mystique Armament** (shift to
  Sword forme, strikes both opponents with the most effective type) and
  **Mystic Aegis** (returns to base forme, or raises Defenses if already
  base). Mystic Aegis is also an innate-triggered ability behavior.
- **5 custom abilities**: Arcane Stance, Promised Victory, Prophetic
  Destiny, Beast of Gluttony, Mystic Aegis — implemented as
  `Impl<ABILITY_*>` entries in `src/abilities.cc`.
- **Art**: full sprite set for both formes — front/back battle sprites
  (4bpp and 8bpp variants), animated fronts, menu icons, normal + shiny
  palettes (`.pal`/`.gbapal` + LZ-compressed), sword-forme variants of all.
- **Provenance**: pristine user-supplied art and the original integration
  patch were md5-recorded before integration; balance pass reworked BST and
  Mystique Armament after playtesting.
