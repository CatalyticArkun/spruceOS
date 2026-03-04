#!/bin/sh
RUN_DIR="$1"
TARGET="/mnt/SDCARD/Saves/spruce/diag/verifier_write_probe.txt"
if echo "probe $(date +%s)" >> "$TARGET" 2>/dev/null; then
  sync
  echo "RESULT id=V-01 verdict=PASS severity=P3 confidence=medium evidence=sd_write_probe_ok"
else
  echo "RESULT id=V-01 verdict=FAIL severity=P1 confidence=high evidence=sd_write_probe_failed"
fi
