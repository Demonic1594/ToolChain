#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${LOG:-$ROOT/logs/build.log}"
WAIT=0
for a in "$@"; do
  case "$a" in
    --wait) WAIT=1 ;;
    *) LOG="$a" ;;
  esac
done

[ -d "$ROOT/modules/06-eliteredux-source" ] || { echo "[03] ERROR: run 00-extract first"; exit 1; }
mkdir -p "$ROOT/logs"
: > "$LOG"

setsid nohup bash -c "
  source '$ROOT/scripts/02-env.sh' >/dev/null 2>&1
  cd '$ROOT/modules/06-eliteredux-source' || exit 1
  find build -size 0 -name '*.o' -delete 2>/dev/null
  echo '=== make -j3 starting: '\$(date)' ==='
  make -j3
  echo MAKE_EXIT=\$?
  echo '=== make -j3 finished: '\$(date)' ==='
" > "$LOG" 2>&1 < /dev/null &
BUILD_PID=$!
disown -a 2>/dev/null || true

echo "[03] Background build launched (pid $BUILD_PID), logging to $LOG"

if [ "$WAIT" -eq 1 ]; then
  echo "[03] Waiting for build to finish..."
  START=$(date +%s)
  while ! grep -q '^MAKE_EXIT=' "$LOG" 2>/dev/null; do
    sleep 15
    NOW=$(date +%s); ELAPSED=$(( NOW - START ))
    printf '\r[03] %d:%02d elapsed' $((ELAPSED/60)) $((ELAPSED%60))
    if ! kill -0 $BUILD_PID 2>/dev/null && ! grep -q '^MAKE_EXIT=' "$LOG"; then
      sleep 5
      grep -q '^MAKE_EXIT=' "$LOG" || { echo; echo "[03] ERROR: build process died"; exit 1; }
    fi
  done
  echo
  EXIT_CODE=$(grep '^MAKE_EXIT=' "$LOG" | cut -d= -f2)
  tail -5 "$LOG"
  if [ "$EXIT_CODE" = "0" ]; then
    echo "[03] BUILD OK (MAKE_EXIT=0)"
  else
    echo "[03] BUILD FAILED (MAKE_EXIT=$EXIT_CODE)"
    exit 1
  fi
fi
