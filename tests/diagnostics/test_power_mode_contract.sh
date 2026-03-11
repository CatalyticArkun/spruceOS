#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export POWER_MODE_STATE_FILE="$TMP/power_mode.state"

# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_mode.sh"

assert_true() {
    "$@" || {
        echo "expected success: $*"
        exit 1
    }
}

assert_false() {
    if "$@"; then
        echo "expected failure: $*"
        exit 1
    fi
}

# default contract behavior = running/watchdog
assert_true power_mode_watchdog_may_handle_input
assert_true power_mode_may_accept_sleep_requests

# sleep ownership handoff suppresses watchdog and sleep requests
assert_true power_mode_claim_sleep_owner sleep_helper
assert_false power_mode_watchdog_may_handle_input
assert_false power_mode_may_accept_sleep_requests

# wake/rearm transitions still suppress watchdog until explicit reconcile
assert_true power_mode_enter_rearm sleep_helper 1
assert_false power_mode_watchdog_may_handle_input
sleep 2
assert_false power_mode_watchdog_may_handle_input
[ "$(power_mode_get)" = "waking" ] || {
    echo "expected predicate to remain side-effect free in waking mode"
    exit 1
}
assert_true power_mode_watchdog_reconcile_after_rearm
assert_true power_mode_watchdog_may_handle_input
assert_true power_mode_may_accept_sleep_requests

# shutdown pending is a hard fence regardless of mode
assert_true power_mode_mark_shutdown_pending save_poweroff
assert_false power_mode_watchdog_may_handle_input
assert_false power_mode_may_accept_sleep_requests
assert_true power_mode_is_shutdown_pending

echo "test_power_mode_contract: PASS"
