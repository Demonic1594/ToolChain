# Known issues & deferred items

Source-relevant open/deferred items, carried from the working registry.
Closed items are omitted. Tagged by class: design decision, upstream
WIP, cosmetic, or genuine gap.

## Design decisions (by design — revisit only deliberately)

- **BaseStats data gap**: catchRate / expYield / evYield / growthRate /
  eggCycles / item1-2 / safariZoneFleeRate / numShinies are 0 for all
  species (no proto fields; generator never emits). Flat 1-EXP +
  candy-based progression is the shipped design. Fixing = proto fields +
  `BaseStatsGenerator.kt` + jar rebuild.
- **Safari catching effectively dead**: `safariCatchFactor =
  catchRate*100/1275` = 0 for everything → safari balls near-uncatchable
  after fix 34 restored the vanilla formula. Sub-item of the data gap.
- **Adoption features keyed to species**: SabreVoir's forced-shiny /
  female / signature-moves treatment fires in `ScriptGiveMon` — any
  future acquisition path through that opcode gets the same treatment.
- **Nuzlocke map coverage**: unlisted wild maps share sentinel bits
  (Route111 caves/desert, Victory Road rework cross-suppress); roamer
  land encounters never mark the route.

## Upstream-class (inherited from Elite Redux, not our bugs)

- **Egg moves are stubbed**: `GetEggMoves` returns 0 — hatchlings use
  level-up learnsets only.
- **Dormant new AI**: `battle_ai_new*.c` ships but is unwired
  (WIP-by-design; `AI_CALC_DAMAGE` empty macro). Don't wire it without
  addressing its score paths.
- **Anim sprite hazards**: unchecked `GetAnimBattlerSpriteId` results →
  `gSprites[255]` writes in ~8 affine tasks; `CreateTask(0)` clobber on
  task exhaustion; 8-tag sprite-index cap leaks. Candidate for one
  batched sweep.
- Positional id regressions (hell-events write side ids to battler-indexed
  arrays; doubles only affects left slots; leech-seed seeder bit hard-codes
  battler 1) — semantic change, playtest first.
- Misc deferred from round 3: item-icon MAX_SPRITES store, `ScrCmd_random
  %0`, `GetVarPointer/GetFlagPointer` bounds (vanilla-inherited).

## Cosmetic / polish debt

- **6v6 Factory** (from fix 97): chosen-mon pics 4–6 share OBJ palette
  slots 13–15 (possible wrong colors, no corruption); swap ball-cascade
  uses 3v6 spacing heuristics (slightly janky).
- **Shiny icons not covered**: PSS multi-move BG icons (fixed species
  slots), battle_debug + Dome info-card icons. Extend
  `SpeciesHasShinyIconPalette` per-species if wanted.
- **8bpp menu icons** for SabreVoir: battle sprites keep 8bpp; menus use
  the 4bpp icon — detailed menu icons need 8bpp support in every icon
  consumer.

## Gaps awaiting assets / decisions

- **SabreVoir back sprites** are placeholder copies of the fronts —
  awaiting real back art.
- `proto/` clutter: `.l2s.*` sync artifacts, `*.bak`,
  `SpeciesList.textproto.orig` — never edit; candidate cleanup.
- `LimitedRandomizerConfig.textproto` is vestigial (parsed by
  GeneratorUtils, no generator or C consumer) — confirm intent before
  deleting or reusing.

## Playtest backlog (user-owned)

Fixes 94–114 (Factory 3v3 BP / 6v6 draft+swap, Arena Mind points,
partner exp, move-info %), SabreVoir adoption path (shiny + female +
both signature moves), shiny icons across screens, catch/queue
reproduction from the 34–93 list. Cheat toolkit for playtesting:
`docs/project/cheats.md` on `main`.
