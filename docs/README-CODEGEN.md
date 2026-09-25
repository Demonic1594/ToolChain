# The codegen pipeline (textproto → C)

How `proto/*.textproto` becomes C/C++ game data, and everything you need to
know before editing it. Paths are relative to `modules/06-eliteredux-source/`.

For the build-environment side (JDKs, qemu, native paths), see
[README-SETUP.md](README-SETUP.md); for *which* data was changed deliberately,
see [project/game-changes.md](project/game-changes.md).

## The golden rule

**`proto/*.textproto` is the source of truth for game data.** The C headers
in `include/generated/` are derived and disposable. Never hand-edit generated
files; edit the textproto and rebuild (`make` regenerates everything).

- Species (stats/typings/abilities/learnsets): `proto/SpeciesList.textproto`
- Moves: `proto/MoveList.textproto`
- Abilities (names/descriptions): `proto/AbilityList.textproto`
- Trainers, items, battle skills: same pattern
- Enum ids: `proto/*Enum.proto` (changing these requires a codegen jar
  rebuild — see below)

`tools/codegen/` holds the Kotlin/Java generators (`src/er/**.kt`, ~57 of
them) invoked through `er.FileGenerator`. The jars are prebuilt and
committed in-tree (`preproc.jar`, `codegen.jar`, `codegenkt.jar`,
`protobuf-*.jar`); `make` only rebuilds them when their sources change.

## Build stages (what `make` does)

1. **protos**: `protoc` compiles each `.proto`; `@NEXT` in an Enum.proto
   auto-picks the next free id at build time (numeric `@NEXT` in textprotos
   likewise auto-assign on first build).
2. **jars**: `preproc.jar`/`codegen.jar`/`codegenkt.jar` — rebuilt only when
   `tools/codegen/src` changes (a one-time ~3 min with the native JVM;
   `JAVA_OPTS=-Xmx4g` is required or kotlinc dies of heap exhaustion).
3. **textprotos**: each is encoded to `bin/*.binpb` and id-normalized
   **in place** (the preprocessor rewrites large ids to first-free values —
   don't be surprised when a textproto changes under your feet during a
   build).
4. **generate**: one `er.FileGenerator <type> <output>` per generated file
   (55 of them: headers, `.inc`, `.s`).

Jar targets are pinned to **class version 61** (`javac --release 17`,
`kotlinc -jvm-target 17`): every jar runs on any JVM ≥ 17 — the native
aarch64 JDK, the bundled x86-64 JDK 21, or CI. Before the pin, jars
defaulted to the building JDK's version (65) and could *only* run on the
bundled JDK.

## Text length limits — enforced by the build

`FontMapping.kt breakString()` wraps text by **pixel width** and throws when
the result exceeds a line count. Narrow font ≈ 5.5 px/char; treat ~27
chars/line as the practical budget:

| Field | maxPixels × maxLines | Practical budget |
|---|---|---|
| Move `short_description` | 154 × 2 | ~56 chars |
| Move `description` | 108 × 4 | ~80 chars |
| Ability `description` | 150 × 2 | ~54 chars |
| Ability `expanded_description` | 150 × 11 | ~290 chars |
| Pokédex entry description | 224 × 4 | ~160 chars |
| Mega hint | 152 × 2 | ~55 chars |

Ability names cap at `ABILITY_NAME_LENGTH` (20 chars).

### Failure mode and recovery (read this before panicking)

A failing **move** description aborts mid-write: the Java exception text
gets baked into the generated header (e.g.
`include/generated/data/text/move_descriptions.h` line 4 *is* the stack
trace), and every file including it fails with baffling cascades
(`sHardyNatureName undeclared` etc.). Ability descriptions are validated
batched instead, so they fail with a clean list at the end.

Recovery:

```bash
# 1. fix the over-limit strings in the textproto
# 2. delete the poisoned header(s)
rm modules/06-eliteredux-source/include/generated/data/text/move_descriptions.h
# 3. clean any truncated objects (killed builds leave 0-byte .o)
find modules/06-eliteredux-source/build -size 0 -name '*.o' -delete
# 4. rebuild — codegen re-runs because the textproto mtime is newer
```

## Speed: native JVM vs qemu

Under the qemu-wrapped bundled JDK each generator invocation costs ~21 s
(JIT-compiled code actually runs *well* under qemu — the cost is sheer
emulated compute; `-Xint` is 15× *slower*, don't try). On a native JVM ≥ 17
the same runs take 0.7-2.7 s, and a full regeneration drops from ~20 min to
~2.5 min. `scripts/02-env.sh` handles the preference automatically on
aarch64 hosts (probing `-version` exit codes — some Alpine JDK 21 builds
fail to start under PRoot with "Failed to mark memory page as executable";
that's upstream JDK 21 W^X behavior, not a broken install, and JDK 17
works fine).

A pull request currently pending (batching all 57 generators into one JVM
invocation + deterministic trainer symbol names) reduces the same
regeneration to ~4 s; it is validated against this tree but not yet merged.

## Determinism

- Same jars + same JVM ⇒ byte-identical generated output (verified).
- `trainers.h` historically embedded JVM-instance-dependent symbol names
  (`__sParty_<n>` from `List.hashCode()` over protobuf messages, which mix
  in identity hashes): trainer *data* was always identical, only names and
  ordering shifted between JVM builds. This is the main historical cause of
  "fresh builds differ by a few bytes". The pending PR replaces the hash
  with a spec-stable one, making cross-JVM output byte-identical.

## Practical recipes

```bash
# sanity-check a single generator by hand (run from tools/codegen):
cd modules/06-eliteredux-source/tools/codegen
java -cp codegen.jar:codegenkt.jar:protobuf-java.jar:protobuf-kotlin.jar \
     er.FileGenerator trainerparties ../../include/generated/data/trainers.h

# force a full regeneration:
rm -rf ../../include/generated && make regenerate
```

Gotchas worth remembering:

- Generators read `../../proto/*` and `../../graphics/fonts/*` **relative to
  `tools/codegen/`** — always run from that directory.
- The `proto/*.textproto.bak` files and `.l2s.*` artifacts are sync-tool
  leftovers; ignore them.
- `MoveList.textproto` uses CRLF line endings, `SpeciesList.textproto` LF —
  preserve whichever a file uses when scripting edits.
- Deleting one generated file forces regeneration of everything (the
  pipeline stamps as a unit) — cheap now, expensive under qemu.
