#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

EVENTS_FILE="$POWER_LOG_ROOT/events.jsonl"
SUMMARY_FILE="$POWER_LOG_ROOT/summary.txt"

if [ -f "$EVENTS_FILE" ]; then
    recent_file=$(mktemp)
    trap 'rm -f "$recent_file"' EXIT INT TERM
    tail -n 50 "$EVENTS_FILE" > "$recent_file"

    total_count=$(wc -l < "$recent_file" | tr -d ' ')
    valid_count=$(grep -Ec '"subsystem":"power".*"current_state":".+".*"requested_state":".+".*"source":".+".*"context":"' "$recent_file" 2>/dev/null || true)

    if [ "$total_count" -gt 0 ] && [ "$valid_count" -ne "$total_count" ]; then
        echo "RESULT id=GEN-04 verdict=WARN severity=P2 confidence=high evidence=power_trace_malformed_record_count_$((total_count - valid_count))"
        exit 0
    fi

    if [ ! -f "$SUMMARY_FILE" ]; then
        echo "RESULT id=GEN-04 verdict=WARN severity=P3 confidence=medium evidence=power_trace_summary_missing"
        exit 0
    fi

    echo "RESULT id=GEN-04 verdict=PASS severity=P4 confidence=high evidence=power_trace_records_well_formed"
    exit 0
fi

echo "RESULT id=GEN-04 verdict=INFO severity=P3 confidence=low evidence=power_trace_unavailable"
