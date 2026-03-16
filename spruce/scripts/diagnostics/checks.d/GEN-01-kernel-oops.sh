#!/bin/sh
RUN_DIR="$1"
RAW="$RUN_DIR/raw/08_kernel/dmesg.tail"
[ -f "$RAW" ] || RAW="$RUN_DIR/raw/dmesg.tail"

count=$(grep -Eic 'kernel panic|Oops:|BUG:' "$RAW" 2>/dev/null || true)

if [ "$count" -gt 0 ]; then
    echo "RESULT id=GEN-01 verdict=FAIL severity=P0 confidence=high evidence=kernel_oops_count_${count}"
else
    echo "RESULT id=GEN-01 verdict=PASS severity=P4 confidence=high evidence=no_kernel_oops"
fi
