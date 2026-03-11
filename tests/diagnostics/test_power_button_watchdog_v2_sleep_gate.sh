#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" "$FAKE_SD_ROOT/sleep_helper.sh" /tmp/powerbtn /tmp/powerbtn_cancelled' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
power_trace_emit() { :; }
vibrate() { :; }
invoke_save_poweroff_singleflight() { :; }
sleep_requests_allowed_now() { power_mode_may_accept_sleep_requests; }
STUB

cat > "$FAKE_SD_ROOT/sleep_helper.sh" <<STUB
#!/bin/sh
echo called >> "$TMP/sleep_helper_called"
STUB
chmod +x "$FAKE_SD_ROOT/sleep_helper.sh"

POWER_BUTTON_WATCHDOG_TEST_MODE=1
# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

power_hold_pid=""

# phase 1: canonical gate denies short-press sleep dispatch
power_mode_may_accept_sleep_requests() { return 1; }
touch /tmp/powerbtn
power_key_up
[ ! -f "$TMP/sleep_helper_called" ] || {
    echo "did not expect sleep_helper dispatch when canonical gate denies"
    exit 1
}

# phase 2: canonical gate allows short-press sleep dispatch
power_mode_may_accept_sleep_requests() { return 0; }
touch /tmp/powerbtn
power_key_up
[ -f "$TMP/sleep_helper_called" ] || {
    echo "expected sleep_helper dispatch when canonical gate allows"
    exit 1
}

echo "test_power_button_watchdog_v2_sleep_gate: PASS"
