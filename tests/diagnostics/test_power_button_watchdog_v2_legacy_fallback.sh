#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
power_trace_emit() { :; }
vibrate() { :; }
invoke_save_poweroff_singleflight() { :; }
STUB

trap 'rm -f "$FAKE_SD_ROOT/helperFunctions.sh" /tmp/power_watchdog_suspended' EXIT INT TERM

POWER_BUTTON_WATCHDOG_TEST_MODE=1
# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

power_hold_pid=""
# Simulate unavailable canonical helpers
unset -f power_mode_watchdog_may_handle_input 2>/dev/null || true
unset -f power_mode_is_shutdown_pending 2>/dev/null || true
unset -f power_mode_watchdog_reconcile_after_rearm 2>/dev/null || true

marker_pid_test_proc=""

# live PID marker suppresses input
sleep 30 &
marker_pid_test_proc=$!
printf '%s\n' "$marker_pid_test_proc" > /tmp/power_watchdog_suspended
handle_suppressed_watchdog_window
rc=$?
[ "$rc" -eq 0 ] || {
    echo "expected legacy suspended marker fallback to suppress for live pid"
    exit 1
}
[ -f /tmp/power_watchdog_suspended ] || {
    echo "expected live legacy marker to remain"
    exit 1
}

kill "$marker_pid_test_proc" 2>/dev/null || true
wait "$marker_pid_test_proc" 2>/dev/null || true
marker_pid_test_proc=""

# stale PID marker should be cleaned and stop suppressing
printf '%s\n' "999999" > /tmp/power_watchdog_suspended
set +e
handle_suppressed_watchdog_window
rc=$?
set -e
[ "$rc" -eq 1 ] || {
    echo "expected stale legacy marker fallback to stop suppressing"
    exit 1
}
[ ! -e /tmp/power_watchdog_suspended ] || {
    echo "expected stale legacy marker cleanup"
    exit 1
}

# malformed marker should also be cleaned
printf '%s\n' "not_a_pid" > /tmp/power_watchdog_suspended
set +e
handle_suppressed_watchdog_window
rc=$?
set -e
[ "$rc" -eq 1 ] || {
    echo "expected malformed legacy marker fallback to stop suppressing"
    exit 1
}
[ ! -e /tmp/power_watchdog_suspended ] || {
    echo "expected malformed legacy marker cleanup"
    exit 1
}

echo "test_power_button_watchdog_v2_legacy_fallback: PASS"
