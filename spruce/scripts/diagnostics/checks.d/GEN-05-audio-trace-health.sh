#!/bin/sh
# GEN-05 — Audio trace health: large jumps and unprompted state changes.
#
# Scans the most recent audio subsystem trace events for FSM inconsistency
# records written by trace_fsm_check (large_jump or continuity failures).
# Either condition suggests the hardware volume changed outside normal software
# control paths, or the software applied an unexpectedly large step.
#
# Verdict logic:
#   WARN P2  — one or more large-jump inconsistencies detected  (high confidence)
#   WARN P3  — one or more unprompted-change inconsistencies    (medium confidence)
#   PASS P4  — trace present and no anomalies found             (high confidence)
#   INFO P4  — audio trace not yet collected                    (low confidence)

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

EVENTS_FILE="$LOG_ROOT/audio/events.jsonl"

if [ -f "$EVENTS_FILE" ]; then
    recent_file=$(mktemp)
    trap 'rm -f "$recent_file"' EXIT INT TERM
    tail -n 100 "$EVENTS_FILE" > "$recent_file"

    large_jump_count=$(grep -c 'FSM_INCONSISTENCY reason=large_jump:' "$recent_file" 2>/dev/null || true)
    continuity_fail_count=$(grep -c 'FSM_INCONSISTENCY reason=continuity:' "$recent_file" 2>/dev/null || true)

    if [ "${large_jump_count:-0}" -gt 0 ]; then
        echo "RESULT id=GEN-05 verdict=WARN severity=P2 confidence=high evidence=audio_large_jump_count_${large_jump_count}"
        exit 0
    fi

    if [ "${continuity_fail_count:-0}" -gt 0 ]; then
        echo "RESULT id=GEN-05 verdict=WARN severity=P3 confidence=medium evidence=audio_unprompted_change_count_${continuity_fail_count}"
        exit 0
    fi

    echo "RESULT id=GEN-05 verdict=PASS severity=P4 confidence=high evidence=audio_trace_no_anomalies"
    exit 0
fi

echo "RESULT id=GEN-05 verdict=INFO severity=P4 confidence=low evidence=audio_trace_unavailable"
