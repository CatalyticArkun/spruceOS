#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"


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

(
    RUN_ID="$RUN_ID" "$SCRIPT_DIR/runner.sh" >/dev/null 2>&1 || true
) &

exit 0
