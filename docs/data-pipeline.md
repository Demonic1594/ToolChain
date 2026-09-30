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
