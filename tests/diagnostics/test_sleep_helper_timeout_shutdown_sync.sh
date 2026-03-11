#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh"' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT" "$TMP/bin"

cat > "$TMP/bin/getevent" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$TMP/bin/getevent"

cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
TEST_TMP="/tmp/sleep_helper_timeout_test"
mkdir -p "$TEST_TMP"

log_message() { :; }
power_trace_emit() { :; }
log_activity_event() { :; }
get_current_app() { echo "test-app"; }
get_config_value() { echo "5s"; }
set_volume() { :; }
pause_emulators() { :; }
unpause_emulators() { echo unpause >> "$TEST_TMP/unpause_called"; }
set_performance() { :; }

EVENT_PATH_POWER="/dev/null"
B_POWER="116"
POWER_BUTTON_PIPE="/tmp/unused_pipe"
SYSTEM_JSON="/tmp/unused_system_json"

power_mode_claim_sleep_owner() { return 0; }
power_mode_set_running() { :; }
power_mode_enter_rearm() { :; }
power_mode_is_shutdown_pending() { [ -f "$TEST_TMP/shutdown_pending" ]; }

invoke_save_poweroff_singleflight() {
    echo "$1" > "$TEST_TMP/shutdown_invoked"
    touch "$TEST_TMP/shutdown_pending"
}

device_uses_pseudo_sleep() { echo "false"; }
device_enter_sleep() { return 0; }
device_lid_open() { echo "0"; }
device_woke_via_timer() { echo "true"; }
device_continue_sleep() { :; }
device_exit_sleep() { echo exit_sleep >> "$TEST_TMP/exit_sleep_called"; }
STUB

rm -rf /tmp/sleep_helper_timeout_test
PATH="$TMP/bin:$PATH" /bin/sh "$ROOT/spruce/scripts/sleep_helper.sh" timeout_test

[ -f /tmp/sleep_helper_timeout_test/shutdown_invoked ] || {
    echo "expected timeout shutdown invocation"
    exit 1
}

[ ! -f /tmp/sleep_helper_timeout_test/exit_sleep_called ] || {
    echo "did not expect resume device_exit_sleep after timeout shutdown"
    exit 1
}

[ ! -f /tmp/sleep_helper_timeout_test/unpause_called ] || {
    echo "did not expect unpause_emulators after timeout shutdown"
    exit 1
}

echo "test_sleep_helper_timeout_shutdown_sync: PASS"
