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

POWER_BUTTON_WATCHDOG_TEST_MODE=1

# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

reset_calls=0
suspended_sequence="1 1 0"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh"' EXIT INT TERM

watchdog_suspended_or_not_rearmed() {
    state=${suspended_sequence%% *}
    if [ "$suspended_sequence" = "$state" ]; then
        suspended_sequence=""
    else
        suspended_sequence=${suspended_sequence#* }
    fi

    [ "$state" = "1" ]
}

reset_power_button_state() {
    reset_calls=$((reset_calls + 1))
}

# First suppressed event should reset once and be suppressed.
handle_suppressed_watchdog_window
first_rc=$?
[ "$first_rc" -eq 0 ] || {
    echo "expected suppression on first event"
    exit 1
}
[ "$reset_calls" -eq 1 ] || {
    echo "expected one reset on first suppression"
    exit 1
}

# Second suppressed event should still suppress but not reset again (no thrash).
handle_suppressed_watchdog_window
second_rc=$?
[ "$second_rc" -eq 0 ] || {
    echo "expected suppression on second event"
    exit 1
}
[ "$reset_calls" -eq 1 ] || {
    echo "expected no additional reset during sustained suppression"
    exit 1
}

# Third event exits suppression; handler should allow normal processing.
set +e
handle_suppressed_watchdog_window
third_rc=$?
set -e
[ "$third_rc" -eq 1 ] || {
    echo "expected suppression handler to release after rearm boundary"
    exit 1
}

# Re-enter suppression after release should perform one fresh reset.
suspended_sequence="1"
handle_suppressed_watchdog_window
reenter_rc=$?
[ "$reenter_rc" -eq 0 ] || {
    echo "expected suppression on re-entry"
    exit 1
}
[ "$reset_calls" -eq 2 ] || {
    echo "expected exactly one additional reset when suppression re-enters"
    exit 1
}

echo "test_power_button_watchdog_v2_suppression: PASS"
