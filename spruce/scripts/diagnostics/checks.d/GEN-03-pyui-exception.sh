#!/bin/sh
RUN_DIR="$1"
LOG_A="$RUN_DIR/raw/09_spruce_logs/spruce.log.tail"
LOG_B="$RUN_DIR/raw/09_spruce_logs/pyui_run.txt.tail"
count=0

[ -f "$LOG_A" ] && count=$((count + $(grep -Eic 'Unhandled exception|Traceback' "$LOG_A" 2>/dev/null || true)))
[ -f "$LOG_B" ] && count=$((count + $(grep -Eic 'Unhandled exception|Traceback' "$LOG_B" 2>/dev/null || true)))

if [ "$count" -gt 0 ]; then
    echo "RESULT id=GEN-03 verdict=WARN severity=P1 confidence=medium evidence=pyui_exception_markers_${count}"
else
    echo "RESULT id=GEN-03 verdict=PASS severity=P4 confidence=high evidence=no_pyui_exception_markers"
fi
