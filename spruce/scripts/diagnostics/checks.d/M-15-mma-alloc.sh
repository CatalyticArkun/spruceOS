#!/bin/sh
RUN_DIR="$1"
RAW="$RUN_DIR/raw/dmesg.tail"
count=$(grep -Eic 'mma.*alloc.*fail|out of memory|page allocation failure' "$RAW" 2>/dev/null || true)
if [ "$count" -gt 0 ]; then
  echo "RESULT id=M-15 verdict=WARN severity=P1 confidence=medium evidence=alloc_failure_count_${count}"
else
  echo "RESULT id=M-15 verdict=PASS severity=P4 confidence=high evidence=no_allocator_failures"
fi
