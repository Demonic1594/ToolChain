#!/bin/bash
set -u -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"

STAGES=(00-extract 01-restore-exec-bits 01b-wrap-x86_64 02-env 03-build 04-verify)
FROM=0
ONLY=""
FORCE=""

usage() {
  cat <<EOF
Elite Redux modular build pipeline

Usage: ./run.sh [options]

Options:
  --from N    start at stage N (0-4 or 00-04)
  --only N    run only stage N
  --force     force re-extraction (passes --force to 00-extract; WIPES modules/)
  --list      list stages and exit

Stages:
  0  00-extract           rejoin archive parts, extract into modules/
  1  01-restore-exec-bits chmod +x ELF/scripts/binaries, touch prebuilt tools
  2  01b-wrap-x86_64      aarch64 hosts only: qemu shim-wrap x86_64 binaries
  3  02-env               build devkitARM shim, verify toolchain env
  4  03-build             make -j1 in eliteredux-source (waits, 15-30+ min)
  5  04-verify            mGBA boot test of the built ROM

Default: run all stages sequentially.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM=$((10#$2)); shift 2 ;;
    --only) ONLY=$((10#$2)); shift 2 ;;
    --force) FORCE="--force"; shift ;;
    --list|-l)
      for i in "${!STAGES[@]}"; do echo "$i  ${STAGES[$i]}"; done; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

norm() { echo $((10#$1)); }

declare -A RESULT
FAILED=0
for i in "${!STAGES[@]}"; do
  N=$(norm "$i")
  if [ -n "$ONLY" ]; then
    [ "$N" -ne "$ONLY" ] && continue
  else
    [ "$N" -lt "$FROM" ] && { RESULT[$i]="skipped"; continue; }
  fi
  STAGE="${STAGES[$i]}"
  EXTRA=""
  [ "$STAGE" = "00-extract" ] && [ -n "$FORCE" ] && EXTRA="--force"
  [ "$STAGE" = "03-build" ] && EXTRA="--wait"
  echo "=== [$STAGE] starting $(date '+%H:%M:%S') ==="
  T0=$(date +%s)
  if bash "$ROOT/scripts/$STAGE.sh" $EXTRA 2>&1 | tee "$LOGDIR/stage-$STAGE.log"; then
    RESULT[$i]="ok"
  else
    RESULT[$i]="FAILED"
    FAILED=1
    echo "=== [$STAGE] FAILED - stopping ==="
    break
  fi
  T1=$(date +%s)
  echo "=== [$STAGE] finished in $((T1-T0))s ==="
  [ -n "$ONLY" ] && break
done

echo ""
echo "=== Summary ==="
for i in "${!STAGES[@]}"; do
  printf '  %-22s %s\n' "${STAGES[$i]}" "${RESULT[$i]:-not run}"
done
exit $FAILED
