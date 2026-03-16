#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export TRACE_ROOT="$TMP"
export TRACE_DIR="$TMP/trace"
export TRACE_EVENTS_FILE="$TRACE_DIR/events.jsonl"
export TRACE_SUMMARY_FILE="$TRACE_DIR/summary.txt"
export TRACE_STATE_FILE="$TRACE_DIR/state.env"
export POWER_TRACE_DIR="$TMP/power"
export PLATFORM="test-platform"
export TRACE_CORE_SCRIPT="$ROOT/spruce/scripts/trace.sh"

. "$ROOT/spruce/scripts/trace.sh"

assert_file_contains() {
    file="$1"
    pattern="$2"
    grep -q "$pattern" "$file" || {
        echo "expected $file to contain pattern: $pattern"
        exit 1
    }
}

assert_line_count() {
    file="$1"
    expected="$2"
    count="$(wc -l < "$file" | tr -d ' ')"
    [ "$count" -eq "$expected" ] || {
        echo "expected $file to have $expected lines, got $count"
        exit 1
    }
}

system_emit "power" "BOOTING" "RUNNING" "test_power_trace.sh:boot" "boot sequence entered"
power_trace_emit "RUNNING" "OFF" "test_power_trace.sh:shutdown" "shutdown requested"
system_emit "networking" "DISABLED" "ENABLED" "test_power_trace.sh:network" "wifi enable requested"
system_emit "audio" "VOL_8" "VOL_0" "test_power_trace.sh:audio" "mute on sleep"
system_emit "brightness" "BL_7" "BL_3" "test_power_trace.sh:brightness" "dim for sleep"

[ -f "$TRACE_EVENTS_FILE" ] || {
    echo "expected global trace events file"
    exit 1
}
[ -f "$POWER_TRACE_EVENTS_FILE" ] || {
    echo "expected power trace events file"
    exit 1
}
[ -f "$TMP/networking/events.jsonl" ] || {
    echo "expected networking trace events file"
    exit 1
}
[ -f "$TMP/audio/events.jsonl" ] || {
    echo "expected audio trace events file"
    exit 1
}
[ -f "$TMP/brightness/events.jsonl" ] || {
    echo "expected brightness trace events file"
    exit 1
}

assert_line_count "$POWER_TRACE_EVENTS_FILE" 2
assert_file_contains "$POWER_TRACE_EVENTS_FILE" '"subsystem":"power"'
assert_file_contains "$POWER_TRACE_EVENTS_FILE" '"current_state":"BOOTING"'
assert_file_contains "$POWER_TRACE_EVENTS_FILE" '"requested_state":"RUNNING"'
assert_file_contains "$POWER_TRACE_EVENTS_FILE" '"source":"test_power_trace.sh:shutdown"'
assert_file_contains "$POWER_TRACE_EVENTS_FILE" '"context":"shutdown requested"'

assert_file_contains "$TRACE_EVENTS_FILE" '"subsystem":"networking"'
assert_file_contains "$TRACE_EVENTS_FILE" '"subsystem":"audio"'
assert_file_contains "$TRACE_EVENTS_FILE" '"subsystem":"brightness"'

before_noop_count="$(wc -l < "$POWER_TRACE_EVENTS_FILE" | tr -d ' ')"
power_trace_boot_reconcile_pending
after_noop_count="$(wc -l < "$POWER_TRACE_EVENTS_FILE" | tr -d ' ')"
[ "$before_noop_count" -eq "$after_noop_count" ] || {
    echo "expected boot reconcile shim to remain passive"
    exit 1
}

echo "test_power_trace: PASS"
