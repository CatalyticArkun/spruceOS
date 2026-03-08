#!/bin/sh
RUN_DIR="$1"
RAW="$RUN_DIR/raw/dmesg.tail"

alloc_count=$(grep -Eic 'mma.*alloc.*fail|out of memory|page allocation failure' "$RAW" 2>/dev/null || true)
mem_avail_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)

if [ -n "$mem_avail_kb" ] && [ "$mem_avail_kb" -lt 32768 ]; then
  echo "RESULT id=M-15 verdict=FAIL severity=P1 confidence=high evidence=alloc_count_${alloc_count}_memavailable_lt_32mb"
  exit 0
fi

if [ "$alloc_count" -gt 0 ]; then
  if [ -n "$mem_avail_kb" ] && [ "$mem_avail_kb" -lt 65536 ]; then
    echo "RESULT id=M-15 verdict=FAIL severity=P1 confidence=high evidence=alloc_count_${alloc_count}_memavailable_lt_64mb"
  else
    echo "RESULT id=M-15 verdict=WARN severity=P1 confidence=medium evidence=alloc_failure_count_${alloc_count}"
  fi
  exit 0
fi

if [ -n "$mem_avail_kb" ] && [ "$mem_avail_kb" -lt 65536 ]; then
  echo "RESULT id=M-15 verdict=WARN severity=P2 confidence=high evidence=memavailable_lt_64mb"
else
  echo "RESULT id=M-15 verdict=PASS severity=P4 confidence=high evidence=no_allocator_failures"
fi
