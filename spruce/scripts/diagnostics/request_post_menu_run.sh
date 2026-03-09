#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


if ! flag_exists "RUN_STARTTIME_DIAGNOSTICS"; then
    exit 0
fi

# Trigger exactly once per boot after PyUI first reaches interactive main-menu control.
BOOT_ID="$(boot_id)"
MARKER="$STATE_DIR/post_menu_boot_${BOOT_ID}.done"

if [ -f "$MARKER" ]; then
    exit 0
fi

RUN_ID="${BOOT_ID}-postmenu"
TMP_MARKER="${MARKER}.tmp.$$"
: > "$TMP_MARKER"
mv "$TMP_MARKER" "$MARKER"

if [ ! -f /tmp/run_starttime_diagnostics_boot_init ]; then
    log_message "power_trace: diagnostics started mid-runtime — marking DIRTY_STARTUP session"
    if command -v power_trace_emit >/dev/null 2>&1; then
        power_trace_emit "DIRTY_STARTUP" "UNKNOWN" "RUNNING" "RUNNING" "runtime_diagnostics_started_mid_session" "diagnostics/request_post_menu_run.sh" "diagnostics enabled without clean boot boundary" "" "" "" "" "" "" || true
    fi
fi

(
    RUN_ID="$RUN_ID" "$SCRIPT_DIR/runner.sh" >/dev/null 2>&1 || true
) &

exit 0
