#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

RUN_DIR="$1"
OUT="$RUN_DIR/raw/10_runtime_state"
mkdir -p "$OUT"

{
    echo "timestamp=$(timestamp_utc)"
    for marker in \
        /tmp/cmd_to_run.sh \
        /tmp/power_mode.state \
        /tmp/power_shutdown_requested \
        /tmp/shutdown_in_progress.lockdir \
        /tmp/sleep_timer_info \
        /tmp/wifi_on \
        /tmp/bluetooth_ready; do
        if [ -e "$marker" ]; then
            echo "present $marker"
        else
            echo "missing $marker"
        fi
    done
} > "$OUT/markers.txt"

find "$FLAGS_DIR" -maxdepth 1 -type f 2>/dev/null | sed "s|$FLAGS_DIR/||" | sort > "$OUT/flags.txt" || true

if [ -f /tmp/cmd_to_run.sh ]; then
    sed 's/[[:space:]]*$//' /tmp/cmd_to_run.sh > "$OUT/cmd_to_run.sh"
fi

if [ -f /tmp/power_mode.state ]; then
    cp /tmp/power_mode.state "$OUT/power_mode.state"
fi

if [ -n "${SYSTEM_JSON:-}" ] && [ -f "$SYSTEM_JSON" ] && command -v jq >/dev/null 2>&1; then
    jq '{
        wifi,
        bluetooth,
        vol,
        backlight,
        bootTo: .menuOptions."System Settings".bootTo.selected,
        disableWifiInGame: .menuOptions."Battery Settings".disableWifiInGame.selected,
        enableSyncthing: .menuOptions."Network Settings".enableSyncthing.selected
    }' "$SYSTEM_JSON" > "$OUT/system_json_focus.json" 2>/dev/null || true
fi
