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

trap 'rm -f "$FAKE_SD_ROOT/helperFunctions.sh"' EXIT INT TERM

POWER_BUTTON_WATCHDOG_TEST_MODE=1
# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

power_hold_pid=""
power_mode_watchdog_reconcile_after_rearm() { :; }
power_mode_watchdog_may_handle_input() { return 1; }
power_mode_is_shutdown_pending() { return 0; }
shutdown_pending_now() { power_mode_is_shutdown_pending; }

handle_suppressed_watchdog_window
rc=$?
[ "$rc" -eq 0 ] || {
    echo "expected watchdog suppression while canonical shutdown_pending"
    exit 1
}

echo "test_power_button_watchdog_v2_shutdown_pending: PASS"
