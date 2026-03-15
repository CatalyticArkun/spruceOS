#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPTS_GLOB="$ROOT/spruce/scripts/*.sh"
RUNTIME="$ROOT/spruce/scripts/runtime.sh"

scan_literal_clearers() {
    marker="$1"
    pattern="rm[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*.*${marker}"

    if command -v rg >/dev/null 2>&1; then
        rg -n -e "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    else
        echo "warning: rg unavailable; using grep fallback for temp marker clearer scan" >&2
        grep -nE "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    fi
}

assert_allowed_literal_clearers() {
    marker="$1"
    expected="$2"

    clearers="$(scan_literal_clearers "$marker")"

    [ "$clearers" = "$expected" ] || {
        echo "expected literal clearers for $marker to be: $expected; found: ${clearers:-<none>}"
        exit 1
    }
}

assert_runtime_startup_cleanup_contains() {
    marker="$1"

    if command -v rg >/dev/null 2>&1; then
        rg -n '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | rg -q "$marker"
    else
        grep -E '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | grep -q "$marker"
    fi
}

assert_runtime_startup_cleanup_not_contains() {
    marker="$1"

    if command -v rg >/dev/null 2>&1; then
        ! rg -n '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | rg -q "$marker"
    else
        ! grep -E '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | grep -q "$marker"
    fi
}

# Narrow, explicit allowed clearers for lifecycle-relevant temp markers.
assert_allowed_literal_clearers '/tmp/power_watchdog_suspended' 'power_button_watchdog_v2.sh
sleep_helper.sh'
assert_allowed_literal_clearers '/tmp/power_pressed_flag' 'sleep_helper.sh'
assert_allowed_literal_clearers '/tmp/powerbtn' 'power_button_watchdog_v2.sh
sleep_helper.sh'
assert_allowed_literal_clearers '/tmp/powerbtn_cancelled' 'power_button_watchdog_v2.sh
sleep_helper.sh'
assert_allowed_literal_clearers '/tmp/cmd_to_run.sh' 'homebutton_watchdog.sh
principal.sh
runtimeHelper.sh'
assert_allowed_literal_clearers '/tmp/power_shutdown_requested' ''

# Runtime startup cleanup is intentionally broad for mixed-version stale recovery.
for startup_marker in \
    '/tmp/power_watchdog_suspended' \
    '/tmp/power_pressed_flag' \
    '/tmp/powerbtn' \
    '/tmp/powerbtn_cancelled' \
    '/tmp/power_shutdown_requested' \
    '/tmp/shutdown_in_progress.lockdir'
do
    assert_runtime_startup_cleanup_contains "$startup_marker" || {
        echo "expected runtime startup stale cleanup to include $startup_marker"
        exit 1
    }
done

assert_runtime_startup_cleanup_not_contains '/tmp/cmd_to_run.sh' || {
    echo 'did not expect runtime startup stale cleanup list to include /tmp/cmd_to_run.sh'
    exit 1
}

echo "test_temp_marker_clearer_contract: PASS"
