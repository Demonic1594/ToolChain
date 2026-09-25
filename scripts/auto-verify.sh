#!/bin/bash
# Watches logs/build.log for MAKE_EXIT, then runs stage 5 (mGBA boot test).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/logs/auto-verify.log"
echo "watcher started $(date -u '+%H:%M:%S')" >> "$LOG"
while ! grep -q "MAKE_EXIT=" "$ROOT/logs/build.log" 2>/dev/null; do
  sleep 30
done
CODE=$(grep -o "MAKE_EXIT=[0-9]*" "$ROOT/logs/build.log" | tail -1 | cut -d= -f2)
echo "build finished MAKE_EXIT=$CODE at $(date -u '+%H:%M:%S')" >> "$LOG"
if [ "$CODE" = "0" ]; then
  ./run.sh --only verify >> "$LOG" 2>&1
  echo "verify exit=$? at $(date -u '+%H:%M:%S')" >> "$LOG"
else
  echo "build failed - skipping verify" >> "$LOG"
fi
