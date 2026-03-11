#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/principal.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for principal launch-gate contract scan"
        grep -nE "$pattern" "$TARGET" || true
    fi
}

gate_fn_refs="$(scan 'launch_allowed_now\s*\(\)')"
[ -z "$gate_fn_refs" ] || {
    echo "did not expect redundant launch_allowed_now wrapper after shared helper extraction"
    exit 1
}

pending_refs="$(scan 'shutdown_pending_now')"
[ -n "$pending_refs" ] || {
    echo "expected principal launch gate to delegate to shared shutdown_pending_now helper"
    exit 1
}

callsite_refs="$(scan 'if shutdown_pending_now; then')"
[ -n "$callsite_refs" ] || {
    echo "expected principal command-dispatch path to call shared shutdown_pending_now directly"
    exit 1
}

echo "test_principal_shutdown_pending_launch_gate_contract: PASS"
