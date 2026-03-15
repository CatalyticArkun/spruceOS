#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" "$FAKE_SD_ROOT/sleep_helper.sh"' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/sleep_helper.sh" <<STUB
#!/bin/sh
echo called >> "$TMP/sleep_helper_called"
STUB
chmod +x "$FAKE_SD_ROOT/sleep_helper.sh"

# phase 1: canonical power_mode gate denies sleep dispatch
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
device_lid_sensor_ready() { return 0; }
power_mode_may_accept_sleep_requests() { return 1; }
sleep_requests_allowed_now() { power_mode_may_accept_sleep_requests; }
device_lid_open() { echo 0; }
get_config_value() { echo "True"; }
device_get_charging_status() { echo "Discharging"; }
STUB

set +e
timeout 2 /bin/sh "$ROOT/spruce/scripts/lid_watchdog_v2.sh" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 124 ] || [ "$rc" -eq 0 ] || {
    echo "unexpected lid watchdog exit code (phase1): $rc"
    exit 1
}

[ ! -f "$TMP/sleep_helper_called" ] || {
    echo "sleep_helper should not be called when canonical gate denies sleep"
    exit 1
}

# phase 2: canonical power_mode gate allows sleep dispatch
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
device_lid_sensor_ready() { return 0; }
power_mode_may_accept_sleep_requests() { return 0; }
sleep_requests_allowed_now() { power_mode_may_accept_sleep_requests; }
device_lid_open() { echo 0; }
get_config_value() { echo "True"; }
device_get_charging_status() { echo "Discharging"; }
STUB

set +e
timeout 2 /bin/sh "$ROOT/spruce/scripts/lid_watchdog_v2.sh" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 124 ] || [ "$rc" -eq 0 ] || {
    echo "unexpected lid watchdog exit code (phase2): $rc"
    exit 1
}

[ -f "$TMP/sleep_helper_called" ] || {
    echo "expected sleep_helper call when canonical gate allows sleep"
    exit 1
}

echo "test_lid_watchdog_power_mode_sleep_gate: PASS"
