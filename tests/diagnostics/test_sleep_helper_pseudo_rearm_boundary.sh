#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" /tmp/power_watchdog_suspended /tmp/sleep_helper_started /tmp/power_pressed_flag /tmp/powerbtn /tmp/powerbtn_cancelled' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT" "$TMP/bin"

cat > "$TMP/bin/getevent" <<'STUB'
#!/bin/sh
sleep 10
STUB
chmod +x "$TMP/bin/getevent"

cat > "$TMP/bin/jq" <<'STUB'
#!/bin/sh
echo 5
STUB
chmod +x "$TMP/bin/jq"

cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
TEST_TMP="/tmp/sleep_helper_pseudo_rearm_test"
mkdir -p "$TEST_TMP"

log_message() { :; }
system_emit() { :; }
log_activity_event() { :; }
get_current_app() { echo "test-app"; }
get_config_value() { echo "5s"; }
set_volume() { :; }
pause_emulators() { :; }
unpause_emulators() { :; }
set_performance() { :; }

EVENT_PATH_POWER="/dev/null"
B_POWER="116"
POWER_BUTTON_PIPE="/tmp/unused_pipe"
SYSTEM_JSON="/tmp/unused_system_json"

device_uses_pseudo_sleep() { echo "true"; }
device_enter_sleep() { return 0; }
device_exit_sleep() { :; }
invoke_save_poweroff_singleflight() { :; }

lid_reads_file="/tmp/sleep_helper_pseudo_rearm_test/lid_reads"
echo 0 > "$lid_reads_file"
device_lid_open() {
    reads="$(cat "$lid_reads_file")"
    reads=$((reads + 1))
    echo "$reads" > "$lid_reads_file"
    if [ "$reads" -eq 1 ]; then
        echo 0
    else
        echo 1
    fi
}

device_woke_via_timer() { echo "false"; }
device_continue_sleep() { :; }

power_mode_claim_sleep_owner() { return 0; }
power_mode_is_shutdown_pending() { return 1; }
power_mode_enter_rearm() { echo "$*" >> "$TEST_TMP/rearm_calls"; }
power_mode_set_running() { echo "$*" >> "$TEST_TMP/running_calls"; }
STUB

mkdir -p /tmp/sleep_helper_pseudo_rearm_test
PATH="$TMP/bin:$PATH" /bin/sh "$ROOT/spruce/scripts/sleep_helper.sh" pseudo_test

[ -f /tmp/sleep_helper_pseudo_rearm_test/rearm_calls ] || {
    echo "expected pseudo wake path to enter rearm"
    exit 1
}

[ ! -f /tmp/sleep_helper_pseudo_rearm_test/running_calls ] || {
    echo "did not expect pseudo wake path to clear rearm with set_running"
    exit 1
}

[ ! -e /tmp/power_watchdog_suspended ] || {
    echo "expected transitional watchdog marker to be cleaned on exit"
    exit 1
}

echo "test_sleep_helper_pseudo_rearm_boundary: PASS"
