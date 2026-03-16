#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" /tmp/sleep_helper_started /tmp/power_watchdog_suspended /tmp/power_pressed_flag' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
TEST_TMP="/tmp/sleep_helper_lifecycle_gate_test"
mkdir -p "$TEST_TMP"

log_message() { :; }
system_emit() { :; }
get_current_app() { echo "test-app"; }
log_activity_event() { echo "$*" >> "$TEST_TMP/log_activity_event"; }
power_mode_may_accept_sleep_requests() { return 1; }
power_mode_is_shutdown_pending() { return 1; }
sleep_requests_allowed_now() { return 1; }
STUB

rm -rf /tmp/sleep_helper_lifecycle_gate_test
/bin/sh "$ROOT/spruce/scripts/sleep_helper.sh" lifecycle_gate_test

[ ! -e /tmp/sleep_helper_started ] || {
    echo "did not expect sleep helper startup marker when lifecycle gate denies"
    exit 1
}

[ ! -e /tmp/sleep_helper_lifecycle_gate_test/log_activity_event ] || {
    echo "did not expect activity STOP/START when invocation is gate-suppressed"
    exit 1
}

echo "test_sleep_helper_lifecycle_gate: PASS"
