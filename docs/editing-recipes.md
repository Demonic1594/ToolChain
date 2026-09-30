# Editing recipes

Condensed, verified recipes for common edits. Paths relative to
`modules/06-eliteredux-source/`. Status tags: **VERIFIED** (executed in a
session), **PARTIALLY** (parts executed), **DERIVED** (code-verified path,
run once before trusting).

Universal rules: enums use `@NEXT`; enum edits require a jar rebuild;
never hand-edit generated output; after any textproto edit run
`make tools` or `./run.sh --from 4`.

## Edit a species' abilities/innates — VERIFIED

```bash
grep -n "id: SPECIES_<NAME>" proto/SpeciesList.textproto        # base
grep -n "form_of: SPECIES_<NAME>" proto/SpeciesList.textproto   # forms/megas (separate blocks!)
```

Edit `ability:` (max 3) / `innate:` (max 3) lines. Exactly ONE ability
line ⇒ auto-pads to `{A,A,A}` ⇒ slot-locked (summary switcher no-op,
Capsule blocked). Regen: `basestats`. Verify the multi-line block is
unique before replacing.

## Edit species stats / typing / learnset / evolution / dex text — PARTIALLY

Same species block as above. Regen types: stats/typing → `basestats`;
evolutions → `evos`; dex text → `speciesnames` / `longnames` /
`pokedexentries`; learnsets → `leveluplearnsets` / `tutorlearnsets`;
graphics refs → `monpics` / `monpals` / `icons` / `coords` /
`speciesanims`.

## Add a custom ability — PARTIALLY (SabreVoir set verified)

1. `ABILITY_<NAME> = @NEXT;` in `proto/AbilityEnum.proto` (**CRLF** endings;
   customs continue ~1047+). Jar rebuild required.
2. **Mandatory** text entry in `proto/AbilityList.textproto` (name ≤ 20
   chars, description + expanded_description) — the game crashes on an
   ability id without text.
3. Impl in `src/abilities.cc`: `template <> constexpr Ability
   Impl<ABILITY_X> = { … }`. Composite abilities = per-hook delegation to
   other `Impl<>` (merge same hooks via a lambda calling each;
   `DELEGATE_HOOK` macro). **Designated initializers must follow the
   field order in `abilities.hh`** (GCC hard error otherwise). Regen:
   `abilities` + `abilitytext`.

## Add a custom move — DERIVED (parts executed for SabreVoir)

1. `MOVE_<NAME> = @NEXT;` in `proto/MoveEnum.proto` (customs ~1032+;
   CRLF). Jar rebuild.
2. Entry in `proto/MoveList.textproto` (id, name, short_name, description
   ≤ 4 lines @108px, short_description ≤ 2 lines, effect/battle-script
   refs). Regen: `moves`, `battlemoves`, `movenames`,
   `movedescriptions`, … (see the matrix in data-pipeline.md).
3. New battle behavior ⇒ script in `data/battle_scripts_1.s` /
   `asm/macros/battle_script.inc` territory — only for genuinely new
   effects.

## Add a custom species — VERIFIED (SabreVoir is the worked example)

Checklist, in order: species/move/ability enums (`@NEXT`) → ability text
entries → ability impls in `abilities.cc` → `SpeciesList.textproto`
block (dex info, stats, types, abilities/innates, learnset, evolutions,
graphics refs, `percent_female`) → art under `graphics/pokemon/<name>/`
(front/back/anim/icon ×4bpp/8bpp + normal/shiny palettes, both formes)
→ regen `basestats`/`monpics`/`monpals`/`icons`/`coords`/`speciesanims`
→ force-add everything to this branch. Keep custom species ids before
SLATE/EGG sentinel ids.

## Edit an item — PARTIALLY

`proto/items/<Pocket>List.textproto` (pocket = filename). Existing:
`grep -n "id: ITEM_<NAME>"`. `field_use_func: "<name>"` wires
`ItemUseOutOfBattle_<name>` by name. Regen: `itemids`, `itemdata`,
`itemgfx`, `pockets`, `holdeffect`, `naturalgift`.

## Edit trainers / parties — DERIVED

`proto/TrainerList.textproto`, one `trainer {}` block: AI flags
(`risky`, `prefer_status`, `prefer_stall`, `no_switching`,
`forced_double`), THREE parties by difficulty tier: `ace {}` (normal),
`elite {}`, `hell {}`. TrainerMon: species, item, nature, **explicit
ability slot pick (bypasses species slots)**, EVs, moves,
`hidden_power_type`. Party-level `skill: BATTLE_SKILL_X` list = AI
battle skills. Regen: `trainerparties`, `trainerids`, `trainerfields`.

## Edit wild encounters — DERIVED

**Not proto-driven**: `src/data/wild_encounters.json` (groups →
per-map headers: land 12 slots / water / rock smash / fishing rows).
jsonproc runs from the Makefile (`json_data_rules.mk`). Rebuild via
`./run.sh --from 4`.

## Edit map scripts / add a Special — DERIVED

- Scripts: `data/maps/<Map>/scripts.pory` (mapscripts blocks, `script`,
  `special Special_X`, msgbox, movement) — never edit built `.inc`.
  Compiled during the ROM build by poryscript.
- Map events (NPCs/warps/triggers/signs): the map's `map.json`.
- New Special: implement in `field_specials.c`, register in the Special
  table (`constants/field_specials.h`), call from `.pory` via `special`.
- Flags/vars: never renumber (save compat); take the next free id in
  `constants/flags.h` / `constants/vars.h`.

## Make a C source fix — VERIFIED (the fixes 34–164 workflow)

1. **Verify the bug by reading** — surrounding code, upstream
   pokeemerald-expansion semantics, textproto descriptions for intent.
   High false-positive rate here (dormant AI code, intentional ER
   changes).
2. Minimal fix in the right file; match surrounding style; guard
   clauses over restructuring.
3. `scripts/check-compile.sh <file>` — instant `-Werror` feedback.
4. Batch done → `./run.sh --from 4` (full build + boot verify).
5. Force-add each touched file to this branch (`git add -f`).

## Build / regenerate / verify — the golden paths

```bash
./run.sh                     # full pipeline (extract → … → verify)
./run.sh --from 4            # skip extract/env (typical after edits)
./run.sh --only verify       # boot-test the current ROM only
make tools                   # regenerate all generated headers, no ROM
make regenerate              # wipe include/generated + regen everything
```
