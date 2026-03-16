#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPTS_GLOB="$ROOT/spruce/scripts/*.sh"
RUNTIME="$ROOT/spruce/scripts/runtime.sh"

scan_files_for_pattern() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n -e "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    else
        echo "warning: rg unavailable; using grep fallback for cmd_to_run contract scan" >&2
        grep -nE "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    fi
}

assert_file_set_eq() {
    label="$1"
    actual="$2"
    expected="$3"
    [ "$actual" = "$expected" ] || {
        echo "expected $label file set to be: ${expected:-<none>}; found: ${actual:-<none>}"
        exit 1
    }
}

# Producers/populators: runtimeHelper owns all writes for boot-action and autoresume dispatch.
producers_redirect="$(scan_files_for_pattern '>[[:space:]]*/tmp/cmd_to_run\.sh')"
assert_file_set_eq "cmd_to_run redirect producers" "$producers_redirect" 'runtimeHelper.sh'

producers_copy_move="$(scan_files_for_pattern '\$MOVE_OR_COPY[[:space:]].*/tmp/cmd_to_run\.sh')"
assert_file_set_eq "cmd_to_run copy/move producers" "$producers_copy_move" 'runtimeHelper.sh'

# Consumers/dispatchers: principal launches UI-selected commands, runtimeHelper launches autoresume.
executors="$(scan_files_for_pattern '/tmp/cmd_to_run\.sh[[:space:]]*(&>[[:space:]]*/dev/null|>[[:space:]]*/dev/null[[:space:]]+2>&1)')"
assert_file_set_eq "cmd_to_run executors" "$executors" 'principal.sh
runtimeHelper.sh'

# Readers that inspect current handoff command (for switcher/validation/telemetry) are expected.
readers="$(scan_files_for_pattern 'cat[[:space:]]+/tmp/cmd_to_run\.sh|sed .* /tmp/cmd_to_run\.sh')"
assert_file_set_eq "cmd_to_run readers" "$readers" 'helperFunctions.sh
homebutton_watchdog.sh
principal.sh
save_poweroff.sh'

# Removers: principal and runtimeHelper clean up after dispatch; homebutton clears port relaunch handoff.
removers="$(scan_files_for_pattern '^[[:space:]]*rm[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*([^[:space:]#]+[[:space:]]+)*"?/tmp/cmd_to_run\.sh"?([[:space:];|&]|$)')"
assert_file_set_eq "cmd_to_run removers" "$removers" 'homebutton_watchdog.sh
principal.sh
runtimeHelper.sh'

# runtime startup stale cleanup must keep excluding cmd_to_run handoff artifact.
if command -v rg >/dev/null 2>&1; then
    ! rg -n '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | rg -q '/tmp/cmd_to_run\.sh'
else
    ! grep -E '/tmp/power_mode\.state.*/tmp/shutdown_in_progress\.lockdir' "$RUNTIME" | grep -q '/tmp/cmd_to_run\.sh'
fi

# No touch-based producer path should exist for cmd_to_run handoff payload.
touch_producers="$(scan_files_for_pattern 'touch[[:space:]]+/tmp/cmd_to_run\.sh')"
assert_file_set_eq "cmd_to_run touch producers" "$touch_producers" ''

echo "test_cmd_to_run_handoff_contract: PASS"
