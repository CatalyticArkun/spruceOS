#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/power_button_watchdog_v2.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for watchdog dispatch-site scan" >&2
        grep -nE "$pattern" "$TARGET" || true
    fi
}

count_matches() {
    pattern="$1"
    refs="$(scan "$pattern")"
    if [ -z "$refs" ]; then
        echo 0
    else
        printf '%s\n' "$refs" | wc -l | tr -d ' '
    fi
}

sleep_dispatch_count="$(count_matches '/mnt/SDCARD/spruce/scripts/sleep_helper\.sh watchdog_short_press')"
[ "$sleep_dispatch_count" -eq 1 ] || {
    echo "expected exactly one short-press sleep dispatch site; found $sleep_dispatch_count"
    exit 1
}

shutdown_handoff_count="$(count_matches 'invoke_save_poweroff_singleflight "power_button_watchdog_v2:power_button_hold"')"
[ "$shutdown_handoff_count" -eq 1 ] || {
    echo "expected exactly one long-press shutdown handoff site; found $shutdown_handoff_count"
    exit 1
}

# Guard against bypassing the canonical save_poweroff marker ownership.
shutdown_marker_write_count="$(count_matches 'touch[[:space:]]+/tmp/power_shutdown_requested|>[[:space:]]*/tmp/power_shutdown_requested')"
[ "$shutdown_marker_write_count" -eq 0 ] || {
    echo "did not expect direct /tmp/power_shutdown_requested writes in power_button_watchdog_v2.sh"
    exit 1
}

echo "test_power_button_watchdog_v2_dispatch_site_contract: PASS"
