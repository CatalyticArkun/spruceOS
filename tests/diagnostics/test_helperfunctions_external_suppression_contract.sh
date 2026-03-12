#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/helperFunctions.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        grep -nE "$pattern" "$TARGET" || true
    fi
}

external_fn="$(scan 'external_transition_now[[:space:]]*\(\)')"
[ -n "$external_fn" ] || {
    echo "expected external_transition_now helper"
    exit 1
}

invoke_body="$(awk '
    /invoke_save_poweroff_singleflight\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^}/ { exit }
' "$TARGET")"

printf '%s\n' "$invoke_body" | grep -q 'external_transition_now' || {
    echo "expected invoke_save_poweroff_singleflight to suppress when external transition is active"
    exit 1
}

for reason in active_tx_same_kind external_transition_active shutdown_pending_duplicate singleflight_in_progress singleflight_race_lost; do
    printf '%s\n' "$invoke_body" | grep -q "$reason" || {
        echo "expected REQUEST_SUPPRESSED reason $reason in invoke_save_poweroff_singleflight"
        exit 1
    }
done

echo "test_helperfunctions_external_suppression_contract: PASS"
