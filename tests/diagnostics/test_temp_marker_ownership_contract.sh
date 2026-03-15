#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPTS_GLOB="$ROOT/spruce/scripts/*.sh"

scan_writers() {
    marker="$1"
    pattern="(touch[[:space:]]+${marker}|>[[:space:]]*${marker})"

    if command -v rg >/dev/null 2>&1; then
        rg -n -e "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    else
        echo "warning: rg unavailable; using grep fallback for temp marker ownership scan" >&2
        grep -nE "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    fi
}

assert_single_writer() {
    marker="$1"
    expected="$2"

    writers="$(scan_writers "$marker")"

    [ "$writers" = "$expected" ] || {
        echo "expected only $expected to write $marker; found: ${writers:-<none>}"
        exit 1
    }
}

assert_single_writer '/tmp/power_shutdown_requested' 'save_poweroff.sh'
assert_single_writer '/tmp/power_watchdog_suspended' 'sleep_helper.sh'
assert_single_writer '/tmp/power_pressed_flag' 'sleep_helper.sh'
assert_single_writer '/tmp/powerbtn' 'power_button_watchdog_v2.sh'

echo "test_temp_marker_ownership_contract: PASS"
