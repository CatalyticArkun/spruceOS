#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/09_spruce_logs"
LOG_ROOT="${SD_ROOT:-/mnt/SDCARD}/Saves/spruce"
mkdir -p "$OUT"

safe_name_from_path() {
  p="$1"
  printf '%s' "$p" | sed 's|^/||; s|/|__|g; s|[^A-Za-z0-9_.-]|_|g'
}

[ -f "$LOG_ROOT/spruce.log" ] && tail -n 1200 "$LOG_ROOT/spruce.log" > "$OUT/spruce.log.tail"
[ -f "$LOG_ROOT/spruce1.log" ] && tail -n 800 "$LOG_ROOT/spruce1.log" > "$OUT/spruce1.log.tail"
[ -d /mnt/SDCARD/App/PyUI ] && find /mnt/SDCARD/App/PyUI -maxdepth 2 -type f -name '*.txt' | while read -r f; do
  rel_safe=$(safe_name_from_path "$f")
  tail -n 400 "$f" > "$OUT/pyui_${rel_safe}.tail" 2>/dev/null || true
done
find "$LOG_ROOT" -maxdepth 1 -type f -name '*.log' | while read -r f; do
  base=$(basename "$f")
  [ "$base" = "spruce.log" ] && continue
  tail -n 400 "$f" > "$OUT/${base}.tail" 2>/dev/null || true
done
