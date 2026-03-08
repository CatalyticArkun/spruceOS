#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export POWER_TRACE_DIR="$TMP/power"
export PLATFORM="test-platform"

. "$ROOT/spruce/scripts/power_trace.sh"

device_power_trace_capabilities() {
    echo "sleep_signal=test wake_source=test lid_sensor=test rtc_alarm=test"
}

device_power_trace_notes() {
    echo "test-adapter"
}

power_trace_emit "BOOT_BEGIN" "UNKNOWN" "BOOTING" "BOOTING" "test" "test_power_trace.sh" "booting" "" "" "" "" "" ""
power_trace_emit "BOOT_COMPLETE" "BOOTING" "RUNNING" "RUNNING" "test" "test_power_trace.sh" "boot complete" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_COMPLETE" "RUNNING" "SLEEPING" "SLEEPING" "test" "test_power_trace.sh" "invalid from running" "" "" "" "" "" ""
power_trace_emit "SLEEP_PREPARE_BEGIN" "RUNNING" "SLEEPING" "RUNNING" "test" "test_power_trace.sh" "prep" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_BEGIN" "SLEEP_PREP" "SLEEPING" "RUNNING" "test" "test_power_trace.sh" "enter" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_COMPLETE" "SLEEP_PREP" "SLEEPING" "SLEEPING" "test" "test_power_trace.sh" "entered" "" "" "" "" "" ""
power_trace_emit "WAKE_DETECTED" "SLEEPING" "RUNNING" "WAKING" "test" "test_power_trace.sh" "wake" "power" "" "" "" "" ""
power_trace_emit "WAKE_RESUME_COMPLETE" "WAKING" "RUNNING" "RUNNING" "test" "test_power_trace.sh" "resume complete" "power" "" "" "" "" ""
power_trace_emit "SHUTDOWN_BEGIN" "RUNNING" "OFF" "RUNNING" "test" "test_power_trace.sh" "shutdown begin" "" "normal" "" "" "" ""
power_trace_emit "SHUTDOWN_HANDOFF" "SHUTDOWN_PENDING" "OFF" "OFF" "test" "test_power_trace.sh" "handoff" "" "normal" "" "" "" ""

[ -f "$POWER_TRACE_EVENTS_FILE" ]
[ -f "$POWER_TRACE_SUMMARY_FILE" ]

if ! rg -q '"event":"INVALID_TRANSITION"' "$POWER_TRACE_EVENTS_FILE"; then
    echo "expected INVALID_TRANSITION in events"
    exit 1
fi

if ! rg -q '"event":"WAKE_RESUME_COMPLETE"' "$POWER_TRACE_EVENTS_FILE"; then
    echo "expected WAKE_RESUME_COMPLETE in events"
    exit 1
fi

if ! rg -q '"event":"SHUTDOWN_HANDOFF"' "$POWER_TRACE_EVENTS_FILE"; then
    echo "expected SHUTDOWN_HANDOFF in events"
    exit 1
fi

if rg -q 'event=SHUTDOWN_HANDOFF' "$POWER_TRACE_EVENTS_FILE"; then
    echo "did not expect INVALID_TRANSITION note for SHUTDOWN_HANDOFF"
    exit 1
fi

if ! tail -n 1 "$POWER_TRACE_STATE_FILE" | rg -q 'pt_event_seq='; then
    echo "expected saved state with event sequence"
    exit 1
fi

echo "test_power_trace: PASS"
