# The overlay model

How this branch stores the game source, what's in it, and how to maintain it.

## Why an overlay

The ToolChain repo gitignores `modules/` — the full tree (~62k files / 433 MB
of source plus regenerable build outputs) is unpacked from `archives/` by
`run.sh` stage 1. Committing the whole tree would bloat the repo with
unchanged upstream files.

Instead, **only files we changed or added** are force-tracked (`git add -f`)
at their real paths under `modules/06-eliteredux-source/`. Applying this
branch on a fresh extraction reproduces our exact source; everything not
tracked here is byte-identical to upstream v2.65.2.3b.

```bash
git checkout eliteredux-source -- modules/06-eliteredux-source/
```

## Inventory (543 files)

| Path | Files | What |
|---|---|---|
| `include/` | 400 | Headers & constants touched by our work: 252 root headers, 81 `constants/`, 55 codegen-`generated/` (tracked so fresh trees and CI compile before running codegen), 10 `gba/`, 2 `mgba_printf/` |
| `src/` | 85 | Game-logic fixes: battle engine & script VM, AI stack, abilities, Pokémon/party/summary, frontier facilities, DexNav, minigames, TV/Easy Chat, contests, nuzlocke/quests, string & UI overflows |
| `graphics/pokemon/` | 44 | SabreVoir art (base + Sword forme: front/back/anim/icons, 4bpp & 8bpp, palettes, LZ) and dedicated menu-icon palettes `pal7`–`pal9` |
| `gflib/` | 4 | Hardened pret stdlib: `sprite.c/.h`, `text.c`, `window.c` |
| `proto/` | 3 | `SpeciesList` / `AbilityList` / `MoveList` textprotos — SabreVoir species/forms/abilities/moves data |
| `asm/` | 3 | `battle_script.inc` macro + 2 codegen'd macro files (incl. the live `waitse` opcode fix) |
| `tools/codegen/` | 2 | `makefile`, `MoveNameGenerator.kt` (codegen fixes) |
| `data/` | 1 | `battle_scripts_1.s` |
| `.gitattributes` | 1 | Nested rules: EOL normalization + `*.pal` stored with literal CRLF |

## Updating the overlay

After editing files under `modules/06-eliteredux-source/` (the dir is
gitignored, so changes are invisible to `git status`):

```bash
git add -f modules/06-eliteredux-source/<path>   # track each changed file
git commit -m "<what and why>"
git push origin eliteredux-source
```

Rules of thumb:

- Force-add **only files that differ from upstream** — never the whole tree.
- Never commit build outputs: `build/`, `*.elf`, `*.gba`, `*.map`,
  `output.txt` are regenerable and excluded.
- Regenerated `include/generated/` files belong here only when needed for
  CI/fresh-tree compilation (the existing 55 are that set).

## Binary & palette handling

- Root `.gitattributes` (this branch): `*.pal -text`, `*.gbapal binary` —
  palettes are stored byte-exact.
- Nested `modules/06-eliteredux-source/.gitattributes` handles text EOL
  rules and stores `*.pal` with **literal CRLF**: gbagfx requires CRLF input,
  and git's eol smudging proved flaky on CI (15-of-16-colors bug root cause).
  Don't "fix" CRLF warnings in `.pal` files — they are intentional.
- SabreVoir palettes/icons deliberately include both `.pal`/`.gbapal` source
  forms and `.4bpp`/`.8bpp`/`.lz` intermediates used by the build.
