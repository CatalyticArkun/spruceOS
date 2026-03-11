#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export POWER_MODE_STATE_FILE="$TMP/power_mode.state"
export POWER_MODE_LOCK_DIR="$TMP/power_mode.lockdir"

# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_mode.sh"

assert_eq() {
    a="$1"
    b="$2"
    msg="$3"
    [ "$a" = "$b" ] || {
        echo "$msg: expected '$b' got '$a'"
        exit 1
    }
}

# malformed state should not be trusted and should fail-safe to defaults
cat > "$POWER_MODE_STATE_FILE" <<STATE
this_is_not_valid
power_mode="shutdown_pending"
STATE
assert_eq "$(power_mode_get)" "shutdown_pending" "malformed state should fail closed to shutdown_pending"

# missing/invalid keys should fail-safe to defaults
cat > "$POWER_MODE_STATE_FILE" <<STATE
power_mode="waking"
power_owner=""
power_shutdown_pending="7"
power_rearm_until="abc"
power_generation="xyz"
STATE
assert_eq "$(power_mode_get)" "shutdown_pending" "invalid key values should fail closed to shutdown_pending"

# unknown keys should also be treated as invalid input
cat > "$POWER_MODE_STATE_FILE" <<STATE
power_mode="running"
power_owner="watchdog"
power_shutdown_pending="0"
power_rearm_until="0"
power_generation="1"
power_surprise="oops"
STATE
assert_eq "$(power_mode_get)" "shutdown_pending" "unknown keys should fail closed to shutdown_pending"


power_mode_is_shutdown_pending || {
    echo "fail-safe parse path should set shutdown pending"
    exit 1
}

# recover canonical state from parse-fail fence before transition checks
power_mode_boot_reset_running watchdog
assert_eq "$(power_mode_get)" "running" "boot reset should recover from parse-fail fence"

# boot-reset remains only clear path

power_mode_claim_sleep_owner sleep_helper
power_mode_mark_shutdown_pending save_poweroff
power_mode_set_running watchdog && {
    echo "set_running should fail while shutdown is pending"
    exit 1
}
power_mode_boot_reset_running watchdog
assert_eq "$(power_mode_get)" "running" "boot reset should clear pending"

# guard against direct-write bypasses in migrated scripts
if rg -n '(^|[^A-Za-z0-9_])(>|>>|cat\s*>)\s*/tmp/power_mode\.state\b|(^|[^A-Za-z0-9_])(>|>>|cat\s*>)\s*\$\{?POWER_MODE_STATE_FILE\}?' spruce/scripts | grep -v 'spruce/scripts/power_mode.sh' >/dev/null; then
    echo "found direct-write bypass to power_mode state outside power_mode.sh"
    exit 1
fi

echo "test_power_mode_integrity: PASS"
