#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/03_cpumem_thermal"
mkdir -p "$OUT"

cat /proc/cpuinfo > "$OUT/cpuinfo.log" 2>/dev/null || true
cat /proc/meminfo > "$OUT/meminfo.log" 2>/dev/null || true

for z in /sys/class/thermal/thermal_zone*; do
  [ -d "$z" ] || continue
  base=$(basename "$z")
  {
    echo "type=$(cat "$z/type" 2>/dev/null || echo unknown)"
    echo "temp=$(cat "$z/temp" 2>/dev/null || echo unknown)"
  } > "$OUT/${base}.log"
done
