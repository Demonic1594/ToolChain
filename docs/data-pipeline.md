# Data pipeline: `proto/*.textproto` → C code

THE thing to understand before any data edit. Source of truth: the textprotos;
everything else in this pipeline is derived output.

## Flow

```
proto/*.textproto (+ *.proto schemas)      committed source of truth
        │  make tools  →  tools/codegen/makefile
        │   1. protoc: @NEXT id resolution + java/kotlin message classes (cached in timestamp/)
        │   2. preproc: textproto → bin/*.binpb (+ in-place id fixups)
        │   3. er.FileGenerator <type> <out>   (Kotlin; jars prebuilt in-tree)
        ▼
include/generated/**  +  asm/generated/macros/*      OUTPUT — regenerated on demand
        ▼
compiled into the ROM by the Makefile (make_tools.mk builds + runs codegen first)
```

Generators are registered in `FileGenerator.kt` (57 types); output rules in
`tools/codegen/makefile`. Generators parse the textprotos **directly from
`../../proto/`** via lazy-vals in `GeneratorUtils.kt` (TRAINERS_LIST,
ITEMS_LIST, ABILITIES_LIST, MOVES_LIST, FULL_SPECIES_LIST, …) — not from the
binpb files.

## CRITICAL padding rule

- `ability:` list — max 3; **fewer entries are padded by repeating the LAST
  ability** (never `ABILITY_NONE`): 1 ability ⇒ `{A,A,A}`; 2 ⇒ `{A,B,B}`.
- `innate:` list — max 3; **not padded** (missing = `ABILITY_NONE`).
- `>3` of either = hard generator error.
- **Consequence**: giving a species exactly ONE ability locks it — all 3
  slots identical ⇒ summary switcher is a no-op, Ability Capsule blocked,
  Patch/Dream Ball/breeding can only pick the same ability. (Technique used
  for the Shedinja/Mew locks.)
- Multi-headed abilities (MULTI_HEADED, HAND_BARNACLES, HYDRA) require
  `heads > 1` or generation aborts.

## Regeneration matrix (edit → generator type → output)

| You edited | Regen type(s) | Output |
|---|---|---|
| Species stats/types/abilities/innates | `basestats` | `generated/data/pokemon/base_stats.h` |
| Species evolutions | `evos` | `.../evolution.h` |
| Dex info (name/desc/scales) | `speciesnames`, `longnames`, `pokedexentries` | text + dex entries |
| Learnsets | `leveluplearnsets`, `tutorlearnsets` | learnset pointers |
| Forms/megas | `forms`, `undoforms`, `reversemegamap` | form tables |
| Species graphics refs | `monpics`, `monpals`, `icons`, `coords`, `speciesanims`, `frontanimids`, `backanimids`, `gendergraphics`, `elevations` | `pokemon_graphics/*` |
| Ability names/descriptions | `abilitytext`, `abilities` | `ability_text.hh` + enum |
| Move data | `battlemoves`, `movenames`, `movedescriptions`, `movebehaviors`, `moveeffects`, `movescripts`, `moveanims`, `movetypemodifiers`, `recoilfractions`, `movedamage`, `tutors`, `moves` | `battle_moves.h` + text + asm scripts |
| Items | `itemids`, `itemdata`, `itemgfx`, `pockets`, `naturalgift`, `holdeffect` | `item/*` headers |
| Trainers | `trainerparties`, `trainerids`, `trainerfields` | `trainers.h` + enums |
| Battle skills | `battleskills`, `battleskilltemplates`, `battleskilltext` | `battle_skills.h` + text |
| Frontier sets | `battlefrontiermons`, `battlefrontierdefines` | `battle_frontier/*` |
| Mega locations | `nursejoy`, `legendarysage`, `adoptioncenteritems`, `megahints` | `megas/*` |
| Randomizer banned flags | `randomizerbanned` | `randomizer_banned.h` |

Simplest habit: after ANY textproto edit, run `make tools` (regenerates
everything stale) or a full build via `./run.sh --from 4` on `main`.

## Running a generator directly

From `tools/codegen/`:

```bash
<modules/03-jdk>/bin/java \
  -cp codegen.jar:codegenkt.jar:protobuf-java.jar:protobuf-kotlin.jar \
  er.FileGenerator <type> <output-path>
```

- `<type>` = any key in the `FileGenerator.kt` GENERATORS map (see matrix).
- **Must use the bundled JDK 21** (`modules/03-jdk`) — system Java 17 fails
  with `UnsupportedClassVersionError`.
- Rebuilding the Kotlin side (only after `.kt` edits): `make codegenkt.jar`
  (needs `modules/04-kotlinc` on PATH; `scripts/02-env.sh` on `main` sets
  the whole environment).

## How the build actually runs (tools/codegen/makefile stages)

1. **protos**: perl rewrites `@NEXT` → sequential ids from 10000000;
   vendored `protoc` (v29.2) generates java/kotlin message classes;
   `preproc.ProtoProcessor` rewrites any number ≥ 1e7 back to the first
   free value — so **`NEW_NAME = @NEXT;` in an `*Enum.proto` auto-picks
   the next free id at build time**.
2. **jars**: `preproc.jar`, `codegen.jar` (javac), `codegenkt.jar`
   (kotlinc) — prebuilt in-tree; rebuilt only when sources change.
3. **textprotos**: perl `@NEXT` → `protoc --encode` → `bin/*.binpb` →
   `TextprotoProcessor` rewrites big ids **in the textproto in place** to
   first-free values (numeric ids auto-assign; symbolic refs like
   `SPECIES_FOO` unaffected).
4. **generate**: each GENERATE rule runs `er.FileGenerator <type> <out>`.

Staleness is **file mtime** based — touching a textproto re-runs preproc +
generators. Useful targets: `make regenerate` (wipe
`../../include/generated`, regen all), `make cleanlocal` (also jars,
timestamps, proto classes), `make binary` (encode to binpb only).

## Schema conventions (`proto/*.proto`, package `er`)

- Every textproto starts with the required header comments — keep them:
  ```
  # proto-file: <Name>.proto
  # proto-message: er.<Name>
  ```
- Enums are referenced by symbol (`SPECIES_GARDEVOIR`,
  `ABILITY_INTIMIDATE`); proto3 default-0 values are omitted in output.
- New enum entries: append `NEW_NAME = @NEXT;` (works in `*Enum.proto`).
- Strings: UTF-8 escaped bytes (`\303\251` for é); the GBA font mapping is
  applied by codegen (`FontMapping.kt`).
- Schemas are editable (source of truth) — but enum/field changes force
  a jar rebuild first.
- `SpeciesList.proto` species message: identity (`id`,
  `randomizer_banned` levels), `oneof form_of` (is a form) vs `dex`
  block (name, category, description, dex nums, body color, egg groups,
  height/weight, scales), stats, `ability:` ×≤3, `innate:` ×≤3,
  learnsets, evolutions, graphics refs, `percent_female`, `bp_cost`.

## Gotchas

- **Enum/proto edits require a jar rebuild**: changing `proto/*Enum.proto`
  does nothing until the codegen jars are rebuilt (`make` in
  `tools/codegen`: protoc → javac → kotlinc). Symptom otherwise:
  `ParseException: has no value named …` from every generator.
- **Stale generated output**: `include/generated/` may be from an older
  build — regenerate before trusting greps of generated headers.
- **Textprotos are rewritten in place** by the build (id fixups) — expect
  diffs after `make tools`; review before committing.
- Item protos are preprocessed into `tools/codegen/bin/*.binpb` (perl
  `@NEXT` counter rewriting) — item edits are best done via `make tools`,
  not direct java calls.
- **Hand-made patches with mixed CRLF/LF**: `git apply` exits 0 but applies
  nothing ("0 files changed"). Use GNU `patch -p1` (offset-tolerant).
- Edit only the plain `*.textproto`; ignore `*.textproto.bak` and
  `.l2s.*` copies.
