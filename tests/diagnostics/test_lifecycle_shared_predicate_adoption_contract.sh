#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HELPERS="$ROOT/spruce/scripts/helperFunctions.sh"

scan_file() {
    file="$1"
    pattern="$2"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$file" || true
    else
        echo "warning: rg unavailable; using grep fallback for lifecycle shared predicate scan"
        grep -nE "$pattern" "$file" || true
    fi
}

# shared helper definitions exist
[ -n "$(scan_file "$HELPERS" 'shutdown_pending_now[[:space:]]*\(\)')" ] || {
    echo "expected helperFunctions.sh to define shutdown_pending_now"
    exit 1
}
[ -n "$(scan_file "$HELPERS" 'sleep_requests_allowed_now[[:space:]]*\(\)')" ] || {
    echo "expected helperFunctions.sh to define sleep_requests_allowed_now"
    exit 1
}

# representative adapters delegate to shared helpers
for f in \
    "$ROOT/spruce/scripts/sleep_helper.sh" \
    "$ROOT/spruce/scripts/lid_watchdog_v2.sh" \
    "$ROOT/spruce/scripts/power_button_watchdog_v2.sh" \
    "$ROOT/spruce/scripts/principal.sh" \
    "$ROOT/spruce/scripts/runtime.sh" \
    "$ROOT/spruce/scripts/runtimeHelper.sh"
do
    [ -n "$(scan_file "$f" 'shutdown_pending_now|sleep_requests_allowed_now')" ] || {
        echo "expected $f to use shared lifecycle predicates"
        exit 1
    }

    inline_refs="$(scan_file "$f" 'power_mode_is_shutdown_pending|power_trace_shutdown_pending|power_mode_may_accept_sleep_requests')"
    [ -z "$inline_refs" ] || {
        echo "did not expect inline lifecycle predicate checks in $f after shared helper extraction"
        echo "$inline_refs"
        exit 1
    }
done

# wrappers that were pure pass-through should stay removed
[ -z "$(scan_file "$ROOT/spruce/scripts/principal.sh" 'launch_allowed_now[[:space:]]*\(\)')" ] || {
    echo "expected principal.sh launch_allowed_now wrapper to remain removed"
    exit 1
}

[ -z "$(scan_file "$ROOT/spruce/scripts/runtime.sh" 'startup_shutdown_pending_now[[:space:]]*\(\)')" ] || {
    echo "expected runtime.sh startup_shutdown_pending_now wrapper to remain removed"
    exit 1
}

echo "test_lifecycle_shared_predicate_adoption_contract: PASS"
