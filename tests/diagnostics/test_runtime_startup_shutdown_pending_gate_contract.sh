#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/runtime.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for runtime startup-gate contract scan"
        grep -nE "$pattern" "$TARGET" || true
    fi
}

fn_refs="$(scan 'startup_shutdown_pending_now\s*\(\)')"
[ -z "$fn_refs" ] || {
    echo "did not expect redundant startup_shutdown_pending_now wrapper after shared helper extraction"
    exit 1
}

shared_refs="$(scan 'shutdown_pending_now')"
[ -n "$shared_refs" ] || {
    echo "expected runtime startup gate to delegate to shared shutdown_pending_now helper"
    exit 1
}

callsite_refs="$(scan 'if shutdown_pending_now; then')"
[ -n "$callsite_refs" ] || {
    echo "expected runtime startup path to call shared shutdown_pending_now directly"
    exit 1
}

echo "test_runtime_startup_shutdown_pending_gate_contract: PASS"
