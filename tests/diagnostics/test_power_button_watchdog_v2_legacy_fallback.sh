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

touch /tmp/power_watchdog_suspended
handle_suppressed_watchdog_window
rc=$?
[ "$rc" -eq 0 ] || {
    echo "expected legacy suspended marker fallback to suppress"
    exit 1
}

echo "test_power_button_watchdog_v2_legacy_fallback: PASS"
