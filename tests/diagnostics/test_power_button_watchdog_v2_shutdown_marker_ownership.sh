#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" /tmp/powerbtn /tmp/powerbtn_cancelled /tmp/power_shutdown_requested /tmp/power_button_watchdog_pre_mark_called' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
system_emit() { :; }
vibrate() { :; }
invoke_save_poweroff_singleflight() { echo "$1" > /tmp/power_button_watchdog_marker_owner_invoked; }
STUB

POWER_BUTTON_WATCHDOG_TEST_MODE=1
# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

power_hold_pid=""
power_mode_mark_shutdown_pending() { echo "$1" > /tmp/power_button_watchdog_pre_mark_called; }
killall() { :; }
# Speed up long-press helper in test mode.
sleep() { :; }

rm -f /tmp/power_shutdown_requested /tmp/power_button_watchdog_marker_owner_invoked
power_key_down
wait "$power_hold_pid"

[ ! -e /tmp/power_shutdown_requested ] || {
    echo "did not expect watchdog long-press path to write /tmp/power_shutdown_requested directly"
    exit 1
}

[ -e /tmp/power_button_watchdog_marker_owner_invoked ] || {
    echo "expected long-press path to hand off to save_poweroff singleflight"
    exit 1
}

[ ! -e /tmp/power_button_watchdog_pre_mark_called ] || {
    echo "did not expect watchdog long-press path to pre-mark shutdown pending before singleflight handoff"
    exit 1
}

echo "test_power_button_watchdog_v2_shutdown_marker_ownership: PASS"
