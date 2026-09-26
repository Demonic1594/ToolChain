# Termux native-build bridge

The and-code environment runs behind PRoot, where the native aarch64
compiler cannot exec (see [NATIVE-GCC-STATUS.md](../NATIVE-GCC-STATUS.md)).
Termux runs natively on the same kernel - and both share the device's
loopback network. This bridge lets and-code drive native builds inside
Termux over `127.0.0.1` and get byte-identical ROMs in ~2-3 minutes
(lane proven identical by the `native-arm64` CI job).

```
[and-code PRoot]  curl 127.0.0.1:8042 (token)  ->  [Termux bridge-server.py]
        ^                                                    |
        +-------- ROM via /sdcard or GET /file <-------------+   ER_ARM_TC=native build
```

## One-time setup (in Termux, ~15 min incl. downloads)

```bash
# Termux from F-Droid, storage permission granted, then:
pkg install -y git python
git clone -b native-gcc https://github.com/Demonic1594/ToolChain.git ~/ToolChain
bash ~/ToolChain/scripts/termux/setup-native-lane.sh
```

The setup script installs everything (Arm's aarch64-hosted GCC 13.2.rel1,
the glibc runtime it needs on bionic, patchelf, arm64 protoc, poryscript
from source, native host tools) and runs a compile smoke test.

## Start the bridge (keep Termux alive)

```bash
termux-wake-lock                      # optional: avoid Android killing it
python ~/ToolChain/scripts/termux/bridge-server.py
# token is written to /sdcard/ToolChain-bridge/token (shared with and-code)
```

## Drive it from and-code

```bash
bash scripts/termux/termux-client.sh health
bash scripts/termux/termux-client.sh build            # sync branch + build + ROM to /sdcard
bash scripts/termux/termux-client.sh run 'uname -m'   # any command in the workspace
bash scripts/termux/termux-client.sh put local.c rel/path.c
bash scripts/termux/termux-client.sh get rel/path out
```

`build` checks out `native-gcc`, builds at `-j4` with
`ER_ARM_TC=native`, and copies the ROM to
`/sdcard/GameBoy/Pokemon - Elite Redux (v2.65.2.3b).gba`.

## Security model (deliberately narrow)

- Listens on `127.0.0.1` only - unreachable from other devices
- Every request needs the shared token from `/sdcard/ToolChain-bridge/token`
  (create that file with your own token to pin it)
- File endpoints are confined to the Termux workspace; `/run` executes
  with Termux user rights - treat the token like a local password
- One job at a time (409 `busy` otherwise)

## Notes

- Uncommitted local changes do NOT ride along - commit and push first
  (or `put` individual files into the Termux workspace).
- The build uses Termux clang for the host tools (preproc, gbagfx, ...)
  and Arm's GCC 13.2.rel1 for the game itself; target-side newlib/libgcc
  come from the bundled toolchain (no armv4t multilib in Arm's release).
- Boot testing stays on the and-code/CI side; the lane's ROM is
  byte-identical to the verified x86_64 build by construction.
