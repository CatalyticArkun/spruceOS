#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FAKE_SD_ROOT="/mnt/SDCARD/spruce/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$FAKE_SD_ROOT/helperFunctions.sh" "$FAKE_SD_ROOT/sleep_helper.sh" /tmp/powerbtn /tmp/powerbtn_cancelled /tmp/power_event_state_save_calls /tmp/power_event_state_sleep_calls' EXIT INT TERM

mkdir -p "$FAKE_SD_ROOT"
cat > "$FAKE_SD_ROOT/helperFunctions.sh" <<'STUB'
log_message() { :; }
system_emit() { :; }
vibrate() { :; }
invoke_save_poweroff_singleflight() { echo "$1" >> /tmp/power_event_state_save_calls; }
sleep_requests_allowed_now() { return 0; }
STUB

cat > "$FAKE_SD_ROOT/sleep_helper.sh" <<'STUB'
#!/bin/sh
echo "$*" >> /tmp/power_event_state_sleep_calls
STUB
chmod +x "$FAKE_SD_ROOT/sleep_helper.sh"

POWER_BUTTON_WATCHDOG_TEST_MODE=1
# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

power_hold_pid=""
killall() { :; }
rm -f /tmp/power_event_state_save_calls /tmp/power_event_state_sleep_calls /tmp/powerbtn /tmp/powerbtn_cancelled

# Phase 1: cancelled short press must not dispatch sleep.
touch /tmp/powerbtn /tmp/powerbtn_cancelled
power_key_up
[ ! -e /tmp/powerbtn ] || { echo "expected powerbtn to be cleared on key up"; exit 1; }
[ ! -e /tmp/powerbtn_cancelled ] || { echo "expected powerbtn_cancelled to be cleared on key up"; exit 1; }
[ ! -e /tmp/power_event_state_sleep_calls ] || { echo "did not expect sleep dispatch for cancelled short press"; exit 1; }

# Phase 2: long press must handoff shutdown and exclude short-press sleep dispatch.
power_key_down
wait "$power_hold_pid"
[ -e /tmp/power_event_state_save_calls ] || { echo "expected long press to invoke shutdown handoff"; exit 1; }
[ "$(wc -l < /tmp/power_event_state_save_calls)" -eq 1 ] || { echo "expected one shutdown handoff call"; exit 1; }
[ ! -e /tmp/power_event_state_sleep_calls ] || { echo "did not expect sleep dispatch during long-press path"; exit 1; }
[ ! -e /tmp/powerbtn ] || { echo "expected long-press path to clear powerbtn"; exit 1; }
[ ! -e /tmp/powerbtn_cancelled ] || { echo "expected long-press path to clear powerbtn_cancelled"; exit 1; }
power_hold_pid=""

# Releasing after long-press completion should not emit a short-press action.
power_key_up
[ ! -e /tmp/power_event_state_sleep_calls ] || { echo "did not expect post-hold release to dispatch sleep"; exit 1; }

# Phase 3: normal short press must dispatch sleep exactly once and not handoff shutdown.
touch /tmp/powerbtn
power_key_up
[ -e /tmp/power_event_state_sleep_calls ] || { echo "expected sleep dispatch for uncancelled short press"; exit 1; }
[ "$(wc -l < /tmp/power_event_state_sleep_calls)" -eq 1 ] || { echo "expected exactly one short-press sleep dispatch"; exit 1; }
[ "$(wc -l < /tmp/power_event_state_save_calls)" -eq 1 ] || { echo "did not expect additional shutdown handoff during short press"; exit 1; }

# Phase 4: suppression-window reset should reset once per suppression entry.
reset_calls=0
suspended_sequence="1 1 0"

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
    rm -f /tmp/powerbtn /tmp/powerbtn_cancelled
    if [ -n "$power_hold_pid" ]; then
        kill "$power_hold_pid" 2>/dev/null || true
        wait "$power_hold_pid" 2>/dev/null || true
        power_hold_pid=""
    fi
}

touch /tmp/powerbtn /tmp/powerbtn_cancelled
sleep 30 &
power_hold_pid=$!

handle_suppressed_watchdog_window
[ "$reset_calls" -eq 1 ] || { echo "expected one reset on first suppression"; exit 1; }
[ ! -e /tmp/powerbtn ] || { echo "expected reset to clear powerbtn"; exit 1; }
[ ! -e /tmp/powerbtn_cancelled ] || { echo "expected reset to clear powerbtn_cancelled"; exit 1; }

handle_suppressed_watchdog_window
[ "$reset_calls" -eq 1 ] || { echo "expected no additional reset during sustained suppression"; exit 1; }

set +e
handle_suppressed_watchdog_window
third_rc=$?
set -e
[ "$third_rc" -eq 1 ] || { echo "expected suppression release on rearm boundary"; exit 1; }

suspended_sequence="1"
handle_suppressed_watchdog_window
[ "$reset_calls" -eq 2 ] || { echo "expected one new reset when suppression re-enters"; exit 1; }

echo "test_power_button_watchdog_v2_event_state_contract: PASS"
