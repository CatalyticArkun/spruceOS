#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/08_kernel"
mkdir -p "$OUT"

dmesg > "$OUT/dmesg.full" 2>/dev/null || true
tail -n 1200 "$OUT/dmesg.full" > "$OUT/dmesg.tail" 2>/dev/null || true
