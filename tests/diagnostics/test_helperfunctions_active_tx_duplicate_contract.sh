#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/helperFunctions.sh"

invoke_body="$(awk '
    /invoke_save_poweroff_singleflight\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^}/ { exit }
' "$TARGET")"

printf '%s\n' "$invoke_body" | grep -q 'power_trace_tx_is_active_kind' || {
    echo "expected active tx kind suppression check in invoke_save_poweroff_singleflight"
    exit 1
}

printf '%s\n' "$invoke_body" | grep -q 'active_tx_same_kind' || {
    echo "expected active_tx_same_kind suppression reason"
    exit 1
}

echo "test_helperfunctions_active_tx_duplicate_contract: PASS"
