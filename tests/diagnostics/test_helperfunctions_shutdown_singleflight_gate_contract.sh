#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/helperFunctions.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for helperFunctions shutdown-gate scan"
        grep -nE "$pattern" "$TARGET" || true
    fi
}

fn_refs="$(scan 'invoke_save_poweroff_singleflight[[:space:]]*\(\)')"
[ -n "$fn_refs" ] || {
    echo "expected invoke_save_poweroff_singleflight function"
    exit 1
}

invoke_body="$(awk '
    /invoke_save_poweroff_singleflight\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^}/ { exit }
' "$TARGET")"

printf '%s\n' "$invoke_body" | grep -q 'shutdown_pending_now' || {
    echo "expected singleflight helper to delegate to shared shutdown_pending_now gate"
    exit 1
}

if printf '%s\n' "$invoke_body" | grep -q 'power_mode_is_shutdown_pending\|power_trace_shutdown_pending'; then
    echo "did not expect inline shutdown predicate checks inside invoke_save_poweroff_singleflight"
    exit 1
fi

singleflight_refs="$(scan 'shutdown_in_progress|shutdown_singleflight_begin')"
[ -n "$singleflight_refs" ] || {
    echo "expected singleflight helper to retain lockdir race protections"
    exit 1
}

shutdown_pending_body="$(awk '
    /shutdown_pending_now\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^}/ { exit }
' "$TARGET")"

printf '%s\n' "$shutdown_pending_body" | grep -q 'power_mode_is_shutdown_pending' || {
    echo "expected shutdown_pending_now to check canonical power_mode predicate"
    exit 1
}
printf '%s\n' "$shutdown_pending_body" | grep -q 'power_trace_shutdown_pending' || {
    echo "expected shutdown_pending_now to retain legacy power_trace fallback"
    exit 1
}

mode_line=$(printf '%s\n' "$shutdown_pending_body" | grep -n 'power_mode_is_shutdown_pending' | head -n1 | cut -d: -f1)
trace_line=$(printf '%s\n' "$shutdown_pending_body" | grep -n 'power_trace_shutdown_pending' | head -n1 | cut -d: -f1)
[ -n "$mode_line" ] && [ -n "$trace_line" ] && [ "$mode_line" -lt "$trace_line" ] || {
    echo "expected shutdown_pending_now to prefer canonical power_mode check before legacy fallback"
    exit 1
}

sleep_gate_body="$(awk '
    /sleep_requests_allowed_now\(\)/ { in_fn=1 }
    in_fn { print }
    in_fn && /^}/ { exit }
' "$TARGET")"

printf '%s\n' "$sleep_gate_body" | grep -q 'power_mode_may_accept_sleep_requests' || {
    echo "expected sleep_requests_allowed_now to check canonical sleep gate predicate"
    exit 1
}
printf '%s\n' "$sleep_gate_body" | grep -q 'shutdown_pending_now' || {
    echo "expected sleep_requests_allowed_now to fallback via shutdown_pending_now"
    exit 1
}

echo "test_helperfunctions_shutdown_singleflight_gate_contract: PASS"
