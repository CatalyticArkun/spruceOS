#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
LOG_FILE="$TMP/save_poweroff.log"
TRACE_FILE="$TMP/power_trace.log"
BEGIN_COUNT_FILE="$TMP/begin_count"

cleanup() {
    rm -f "${TEST_GUARD_DIR:-/tmp/test_shutdown_singleflight.lockdir}/owner" 2>/dev/null || true
    rm -rf "${TEST_GUARD_DIR:-/tmp/test_shutdown_singleflight.lockdir}" 2>/dev/null || true
    rm -f /tmp/save_poweroff.pid /tmp/power_shutdown_requested 2>/dev/null || true
    if [ -n "${ORIG_SDCARD_DIR:-}" ] && [ -d "${ORIG_SDCARD_DIR:-}" ]; then
        rm -rf /mnt/SDCARD
        mv "$ORIG_SDCARD_DIR" /mnt/SDCARD
    else
        rm -rf /mnt/SDCARD
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

if [ -e /mnt/SDCARD ]; then
    ORIG_SDCARD_DIR="$TMP/original_sdcard"
    mv /mnt/SDCARD "$ORIG_SDCARD_DIR"
fi

mkdir -p /mnt/SDCARD/spruce/scripts/network /mnt/SDCARD/spruce/flags /mnt/SDCARD/spruce/imgs
cp "$ROOT/spruce/scripts/save_poweroff.sh" /mnt/SDCARD/spruce/scripts/save_poweroff.sh
chmod +x /mnt/SDCARD/spruce/scripts/save_poweroff.sh

cat > /mnt/SDCARD/spruce/scripts/helperFunctions.sh <<'HF'
#!/bin/sh
FLAGS_DIR="/mnt/SDCARD/spruce/flags"
SHUTDOWN_GUARD_DIR="${TEST_SHUTDOWN_GUARD_DIR:-/tmp/test_shutdown_singleflight.lockdir}"
POWER_OFF_SCRIPT="/mnt/SDCARD/spruce/scripts/save_poweroff.sh"
LED_PATH="not applicable"
PLATFORM="test"
SD_DEV="/dev/mmcblk0p1"
SD_MOUNTPOINT="/mnt/SDCARD"

shutdown_singleflight_begin() {
    if mkdir "$SHUTDOWN_GUARD_DIR" 2>/dev/null; then
        count=0
        [ -f "${TEST_BEGIN_COUNT_FILE:?}" ] && count=$(cat "$TEST_BEGIN_COUNT_FILE")
        count=$((count + 1))
        echo "$count" > "$TEST_BEGIN_COUNT_FILE"
        return 0
    fi
    return 1
}
shutdown_singleflight_clear() { rm -rf "$SHUTDOWN_GUARD_DIR"; }
shutdown_in_progress() { [ -d "$SHUTDOWN_GUARD_DIR" ]; }
power_trace_emit() { printf '%s\n' "$*" >> "${TEST_TRACE_FILE:?}"; }
log_message() { printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"; }
log_activity_event() { :; }
get_current_app() { echo MainUI; }
flag_check() { [ -f "$FLAGS_DIR/$1.lock" ] || [ -f "/tmp/$1.lock" ]; }
flag_add() { touch "$FLAGS_DIR/$1.lock"; }
flag_remove() { rm -f "$FLAGS_DIR/$1.lock" "/tmp/$1.lock"; }
device_prepare_for_poweroff() { :; }
stop_problematic_scripts() { :; }
any_emu_is_running() { return 1; }
dismiss_active_emu_menu_state() { :; }
attempt_to_close_emu_gracefully() { :; }
wait_for_graceful_emu_exit() { :; }
close_forcefully_all_emus() { :; }
close_non_emu_cmd_to_run() { :; }
display_appropriate_icon_and_message() { :; }
dim_screen_and_do_syncthing_check() { :; }
kill_remaining_background_processes() { :; }
device_system_handles_sdcard_unmount() { [ "${TEST_SYSTEMD_PATH:-0}" = "1" ]; }
device_run_reboot_cmd() { printf 'reboot\n' >> "${TEST_LOG_FILE:?}"; return 0; }
run_poweroff_cmd() { printf 'poweroff\n' >> "${TEST_LOG_FILE:?}"; return 0; }
HF
chmod +x /mnt/SDCARD/spruce/scripts/helperFunctions.sh

cat > /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh <<'NF'
#!/bin/sh
NF
chmod +x /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

assert_true() {
    "$@" || { echo "assertion failed: $*"; exit 1; }
}

# 1) Failed pre-handoff attempt releases singleflight guard.
: > "$LOG_FILE"
: > "$TRACE_FILE"
echo 0 > "$BEGIN_COUNT_FILE"
TEST_GUARD_DIR="/tmp/test_shutdown_singleflight.lockdir"
rm -rf "$TEST_GUARD_DIR"

sleep 30 &
oldpid=$!
echo "$oldpid" > /tmp/save_poweroff.pid
TEST_SHUTDOWN_GUARD_DIR="$TEST_GUARD_DIR" TEST_LOG_FILE="$LOG_FILE" TEST_TRACE_FILE="$TRACE_FILE" TEST_BEGIN_COUNT_FILE="$BEGIN_COUNT_FILE" /mnt/SDCARD/spruce/scripts/save_poweroff.sh >/dev/null 2>&1 || true
kill "$oldpid" 2>/dev/null || true
wait "$oldpid" 2>/dev/null || true

assert_true test ! -d "$TEST_GUARD_DIR"
assert_true grep -q 'released shutdown singleflight guard before irreversible handoff' "$LOG_FILE"
assert_true grep -q 'shutdown_prehandoff_exit' "$TRACE_FILE"

# 2) A second attempt in same session is allowed (guard can be reacquired).
sleep 30 &
oldpid=$!
echo "$oldpid" > /tmp/save_poweroff.pid
TEST_SHUTDOWN_GUARD_DIR="$TEST_GUARD_DIR" TEST_LOG_FILE="$LOG_FILE" TEST_TRACE_FILE="$TRACE_FILE" TEST_BEGIN_COUNT_FILE="$BEGIN_COUNT_FILE" /mnt/SDCARD/spruce/scripts/save_poweroff.sh >/dev/null 2>&1 || true
kill "$oldpid" 2>/dev/null || true
wait "$oldpid" 2>/dev/null || true

assert_true test "$(cat "$BEGIN_COUNT_FILE")" -eq 2
assert_true test ! -d "$TEST_GUARD_DIR"
assert_true test "$(grep -c 'shutdown_prehandoff_exit' "$TRACE_FILE")" -eq 2

# 3) Irreversible handoff keeps guard latched and duplicate protection active.
rm -f /tmp/save_poweroff.pid
: > "$LOG_FILE"
: > "$TRACE_FILE"
TEST_SHUTDOWN_GUARD_DIR="$TEST_GUARD_DIR" TEST_SYSTEMD_PATH=1 TEST_LOG_FILE="$LOG_FILE" TEST_TRACE_FILE="$TRACE_FILE" TEST_BEGIN_COUNT_FILE="$BEGIN_COUNT_FILE" /mnt/SDCARD/spruce/scripts/save_poweroff.sh >/dev/null 2>&1 || true
assert_true test -d "$TEST_GUARD_DIR"
begin_after_handoff="$(cat "$BEGIN_COUNT_FILE")"

TEST_SHUTDOWN_GUARD_DIR="$TEST_GUARD_DIR" TEST_SYSTEMD_PATH=1 TEST_LOG_FILE="$LOG_FILE" TEST_TRACE_FILE="$TRACE_FILE" TEST_BEGIN_COUNT_FILE="$BEGIN_COUNT_FILE" /mnt/SDCARD/spruce/scripts/save_poweroff.sh >/dev/null 2>&1 || true
assert_true grep -q 'shutdown already in progress' "$LOG_FILE"
assert_true test "$(cat "$BEGIN_COUNT_FILE")" -eq "$begin_after_handoff"
assert_true test "$(grep -c 'shutdown_prehandoff_exit' "$TRACE_FILE" 2>/dev/null || true)" -eq 0

echo "shutdown singleflight release test: PASS"
