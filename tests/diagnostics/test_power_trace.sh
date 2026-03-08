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

reset_trace_state() {
    rm -rf "$POWER_TRACE_DIR"
    mkdir -p "$POWER_TRACE_DIR"
}

event_count() {
    event="$1"
    if [ ! -f "$POWER_TRACE_EVENTS_FILE" ]; then
        echo 0
        return
    fi
    grep -o "\"event\":\"${event}\"" "$POWER_TRACE_EVENTS_FILE" | wc -l | tr -d ' '
}

assert_event_count() {
    event="$1"
    expected="$2"
    count="$(event_count "$event")"
    [ "$count" -eq "$expected" ] || {
        echo "expected ${expected} occurrences of ${event}, got ${count}"
        exit 1
    }
}

assert_no_invalid_transition() {
    if [ -f "$POWER_TRACE_EVENTS_FILE" ] && grep -q '"event":"INVALID_TRANSITION"' "$POWER_TRACE_EVENTS_FILE"; then
        echo "did not expect INVALID_TRANSITION in regression test"
        exit 1
    fi
}

# 1) shutdown -> power loss -> boot reconcile
reset_trace_state
power_trace_emit "BOOT_BEGIN" "UNKNOWN" "BOOTING" "BOOTING" "test" "test_power_trace.sh" "booting" "" "" "" "" "" ""
power_trace_emit "BOOT_COMPLETE" "BOOTING" "RUNNING" "RUNNING" "test" "test_power_trace.sh" "boot complete" "" "" "" "" "" ""
power_trace_emit "SHUTDOWN_BEGIN" "RUNNING" "OFF" "RUNNING" "test" "test_power_trace.sh" "shutdown begin" "" "normal" "" "" "" ""
power_trace_emit "SHUTDOWN_HANDOFF" "SHUTDOWN_PENDING" "OFF" "OFF" "test" "test_power_trace.sh" "handoff" "" "normal" "" "" "" ""
power_trace_boot_reconcile_pending
assert_event_count "SHUTDOWN_RECOVERED" 1

# 2) duplicate reconcile no-op (assert semantic count unchanged)
before_count="$(event_count "SHUTDOWN_RECOVERED")"
power_trace_boot_reconcile_pending
after_count="$(event_count "SHUTDOWN_RECOVERED")"
[ "$before_count" -eq "$after_count" ] || {
    echo "duplicate reconcile should not emit additional SHUTDOWN_RECOVERED"
    exit 1
}

# 3) sleep -> wake -> resume
reset_trace_state
power_trace_emit "BOOT_BEGIN" "UNKNOWN" "BOOTING" "BOOTING" "test" "test_power_trace.sh" "booting" "" "" "" "" "" ""
power_trace_emit "BOOT_COMPLETE" "BOOTING" "RUNNING" "RUNNING" "test" "test_power_trace.sh" "boot complete" "" "" "" "" "" ""
power_trace_emit "SLEEP_PREPARE_BEGIN" "RUNNING" "SLEEPING" "RUNNING" "test" "test_power_trace.sh" "prep" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_BEGIN" "SLEEP_PREP" "SLEEPING" "RUNNING" "test" "test_power_trace.sh" "enter" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_COMPLETE" "SLEEP_PREP" "SLEEPING" "SLEEPING" "test" "test_power_trace.sh" "entered" "" "" "" "" "" ""
power_trace_emit "WAKE_DETECTED" "SLEEPING" "RUNNING" "WAKING" "test" "test_power_trace.sh" "wake" "power" "" "" "" "" ""
power_trace_emit "WAKE_RESUME_BEGIN" "WAKING" "RUNNING" "WAKING" "test" "test_power_trace.sh" "resume begin" "power" "" "" "" "" ""
power_trace_emit "WAKE_RESUME_COMPLETE" "WAKING" "RUNNING" "RUNNING" "test" "test_power_trace.sh" "resume complete" "power" "" "" "" "" ""
assert_event_count "WAKE_RESUME_COMPLETE" 1

# 4) sleep timeout -> shutdown -> next boot reconcile
power_trace_emit "SLEEP_PREPARE_BEGIN" "RUNNING" "SLEEPING" "RUNNING" "test" "test_power_trace.sh" "prep2" "" "" "" "" "" ""
power_trace_emit "SLEEP_ENTER_COMPLETE" "SLEEP_PREP" "SLEEPING" "SLEEPING" "test" "test_power_trace.sh" "entered2" "" "" "" "" "" ""
power_trace_emit "TRANSITION_TIMEOUT" "SLEEPING" "RUNNING" "SLEEPING" "test" "test_power_trace.sh" "timeout" "rtc" "idle_timeout" "" "" "" "1000"
power_trace_emit "SHUTDOWN_BEGIN" "RUNNING" "OFF" "RUNNING" "test" "test_power_trace.sh" "shutdown after timeout" "" "normal" "" "" "" ""
power_trace_emit "SHUTDOWN_HANDOFF" "SHUTDOWN_PENDING" "OFF" "OFF" "test" "test_power_trace.sh" "handoff2" "" "normal" "" "" "" ""
power_trace_boot_reconcile_pending
assert_event_count "SHUTDOWN_RECOVERED" 1

# 5) reboot reconcile (semantic assertion, not specific event name)
power_trace_emit "REBOOT_BEGIN" "RUNNING" "BOOTING" "RUNNING" "test" "test_power_trace.sh" "reboot begin" "" "reboot" "" "" "" ""
power_trace_boot_reconcile_pending
if [ -f "$POWER_TRACE_PENDING_FILE" ]; then
    echo "reboot reconcile should clear pending marker"
    exit 1
fi
if ! grep -q '^pt_last_state="BOOTING"' "$POWER_TRACE_STATE_FILE"; then
    echo "expected reboot reconcile to leave canonical BOOTING state"
    exit 1
fi

# 6) stale persisted sleeping fields normalized
cat > "$POWER_TRACE_STATE_FILE" <<STATE
pt_last_state="RUNNING"
pt_intended_state="RUNNING"
pt_requested_state="RUNNING"
pt_observed_state="SLEEPING"
pt_completed_state="RUNNING"
pt_active_transition_id=""
pt_event_seq="99"
pt_last_reconciled_pending_key=""
STATE

cat > "$POWER_TRACE_PENDING_FILE" <<PENDING
pending_kind="SHUTDOWN"
pending_correlation_id="seed-pending"
pending_source="seed"
PENDING

power_trace_boot_reconcile_pending
if ! grep -q '^pt_observed_state="OFF"' "$POWER_TRACE_STATE_FILE"; then
    echo "expected stale observed_state to normalize to OFF after recovered shutdown"
    exit 1
fi
assert_event_count "SHUTDOWN_RECOVERED" 2

# global guard: this regression should not emit invalid transitions
assert_no_invalid_transition

echo "test_power_trace: PASS"
