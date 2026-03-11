#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPTS_GLOB="$ROOT/spruce/scripts/*.sh"
RUNTIME="$ROOT/spruce/scripts/runtime.sh"
RUNTIME_HELPER="$ROOT/spruce/scripts/runtimeHelper.sh"

scan_files_for_pattern() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n -e "$pattern" $SCRIPTS_GLOB | cut -d: -f1 | xargs -r -n1 basename | sort -u
    else
        echo "warning: rg unavailable; using grep fallback for autoresume contract scan" >&2
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

# lastgame.lock writer/producer ownership:
# - principal seeds it from cmd_to_run before launch dispatch.
lastgame_seed_writers="$(scan_files_for_pattern 'cp[[:space:]]+/tmp/cmd_to_run\.sh[[:space:]]+"?\$FLAGS_DIR/lastgame\.lock')"
assert_file_set_eq "lastgame seed writers" "$lastgame_seed_writers" 'principal.sh'

# lastgame.lock handoff population into cmd_to_run for autoresume is runtimeHelper-owned.
lastgame_to_cmd_handoff="$(scan_files_for_pattern '\$MOVE_OR_COPY[[:space:]]+"?/mnt/SDCARD/spruce/flags/lastgame\.lock"?[[:space:]]+/tmp/cmd_to_run\.sh')"
assert_file_set_eq "lastgame->cmd autoresume handoff owners" "$lastgame_to_cmd_handoff" 'runtimeHelper.sh'

# lastgame.lock removers are intentionally split: port-exit watcher and shutdown cleanup.
lastgame_removers="$(scan_files_for_pattern 'rm[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*[^\n]*lastgame\.lock')"
assert_file_set_eq "lastgame removers" "$lastgame_removers" 'homebutton_watchdog.sh
save_poweroff.sh'

# save_active mutators are bounded by shutdown decisions + runtime/autoresume cleanup paths.
save_active_adders="$(scan_files_for_pattern 'flag_add[[:space:]]+"save_active"')"
assert_file_set_eq "save_active adders" "$save_active_adders" 'save_poweroff.sh'

save_active_removers="$(scan_files_for_pattern 'flag_remove[[:space:]]+"save_active"')"
assert_file_set_eq "save_active removers" "$save_active_removers" 'runtime.sh
runtimeHelper.sh
save_poweroff.sh'

# save_active checks that drive autoresume/read-only behavior remain bounded.
save_active_checkers="$(scan_files_for_pattern 'flag_check[[:space:]]+"save_active"')"
assert_file_set_eq "save_active checkers" "$save_active_checkers" 'archiveUnpacker.sh
runtime.sh
runtimeHelper.sh'

# runtime is the only startup trigger site for autoresume.
autoresume_triggers="$(scan_files_for_pattern 'auto_resume_game')"
assert_file_set_eq "autoresume trigger sites" "$autoresume_triggers" 'runtime.sh
runtimeHelper.sh'

runtime_autoresume_call="$( (command -v rg >/dev/null 2>&1 && rg -n 'if flag_check "save_active"; then[[:space:]]*$' "$RUNTIME" && rg -n 'auto_resume_game' "$RUNTIME") || true )"
[ -n "$runtime_autoresume_call" ] || {
    echo 'expected runtime startup to gate auto_resume_game by flag_check "save_active"'
    exit 1
}

# NDS move-vs-copy decision must stay confined to runtimeHelper autoresume path.
ndsmove_files="$(scan_files_for_pattern 'Roms/NDS.*MOVE_OR_COPY=mv|MOVE_OR_COPY=mv.*Roms/NDS')"
assert_file_set_eq "NDS move-vs-copy decision owners" "$ndsmove_files" 'runtimeHelper.sh'

# Tight shutdown-pending suppression ordering inside auto_resume_game:
# gate check must occur before startupInitOnly launch, handoff copy/move, and cmd execution.
autoresume_body="$(awk '
    /auto_resume_game\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^set_up_boot_action\(\)/ { exit }
' "$RUNTIME_HELPER")"

[ -n "$autoresume_body" ] || {
    echo 'expected to extract auto_resume_game function body'
    exit 1
}

line_of() {
    pattern="$1"
    printf '%s\n' "$autoresume_body" | nl -ba | grep -E "$pattern" | head -n1 | awk '{print $1}'
}

shutdown_line="$(line_of 'shutdown_pending_now')"
startup_init_line="$(line_of 'startupInitOnly True')"
handoff_line="$(line_of '\$MOVE_OR_COPY .*lastgame\.lock.*cmd_to_run\.sh')"
exec_line="$(line_of 'nice -n -20 /tmp/cmd_to_run\.sh')"

[ -n "$shutdown_line" ] && [ -n "$startup_init_line" ] && [ -n "$handoff_line" ] && [ -n "$exec_line" ] || {
    echo 'expected auto_resume_game to contain shutdown gate, startup init, handoff copy/move, and cmd execution lines'
    exit 1
}

[ "$shutdown_line" -lt "$startup_init_line" ] || {
    echo 'expected shutdown gate check before startupInitOnly launch in auto_resume_game'
    exit 1
}

[ "$shutdown_line" -lt "$handoff_line" ] || {
    echo 'expected shutdown gate check before lastgame->cmd handoff in auto_resume_game'
    exit 1
}

[ "$shutdown_line" -lt "$exec_line" ] || {
    echo 'expected shutdown gate check before cmd execution in auto_resume_game'
    exit 1
}

echo "test_autoresume_lastgame_save_active_contract: PASS"
