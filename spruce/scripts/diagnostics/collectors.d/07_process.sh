#!/bin/sh
RUN_DIR="$1"
PHASE="${2:-A}"
OUT="$RUN_DIR/raw/07_process"
mkdir -p "$OUT"

ps -ef > "$OUT/ps.log" 2>/dev/null || true
if [ "$PHASE" = "B" ]; then
  top -b -n 3 -d 1 > "$OUT/top.log" 2>/dev/null || true
else
  top -b -n 1 > "$OUT/top.log" 2>/dev/null || true
fi
