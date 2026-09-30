# Elite Redux — source overlay (`eliteredux-source` branch)

This branch carries **the game source** for the ToolChain repo: a maintained,
heavily fixed fork of **Pokémon Elite Redux v2.65.2.3b** (upstream
[`Elite-Redux/eliteredux-source`](https://github.com/Elite-Redux/eliteredux-source),
`upcoming` branch), a ROM hack of Pokémon Emerald built on the
[pret/pokeemerald](https://github.com/pret/pokeemerald) decompilation.

The branch contains **only** the source overlay — the 543 modified or new
files at their real paths under `modules/06-eliteredux-source/` — plus this
documentation. All ToolChain scaffolding (build pipeline, scripts, CI) lives
on `main`.

| Quick facts | |
|---|---|
| Baseline | Elite Redux **v2.65.2.3b**, upstream `upcoming` branch (Sept 2026) |
| Our changes | Source fixes **3–164** (complete code review) + design changes + SabreVoir |
| Custom content | **SabreVoir** — Steel/Fairy species with Sword forme, 5 abilities, 2 signature moves |
| Build | `./run.sh` from `main` (or `--from 4` to skip extraction); CI attaches a ROM per push |
| Compiler | arm-none-eabi GCC 13.2 (`modules/02-gcc`), `MODERN=1` forced — agbcc cannot parse this source |

## Quick start

```bash
# apply the overlay onto a fresh stage-1 extraction (from a ToolChain checkout):
git checkout eliteredux-source -- modules/06-eliteredux-source/

# then build (extract -> env -> build -> verify):
./run.sh
```

## Documentation index

| Doc | What's in it |
|---|---|
| [docs/overlay.md](docs/overlay.md) | How the overlay model works, full file inventory, how to update it, binary/palette handling |
| [docs/modifications.md](docs/modifications.md) | Everything changed vs upstream: fixes 3–164 by pass, design changes, SabreVoir deep dive, shiny icon system |
| [docs/source-map.md](docs/source-map.md) | Source tree guide: golden rules, layout, most edit-relevant files |
| [docs/data-pipeline.md](docs/data-pipeline.md) | The `proto/*.textproto` → C codegen pipeline: flow, rules, regeneration matrix, gotchas |
| [docs/game-systems.md](docs/game-systems.md) | How the game works: ability slots, randomizer, battle engine, ER-specific quirks |
| [docs/building.md](docs/building.md) | Build lanes (qemu / CI / Termux), codegen environment, verification & provenance |

ToolChain-side docs (setup, codegen, project writeups, cheats, testing) are on
`main` under `docs/`.
