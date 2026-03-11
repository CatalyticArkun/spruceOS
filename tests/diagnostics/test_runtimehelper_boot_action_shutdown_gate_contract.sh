#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/runtimeHelper.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for runtimeHelper boot-action gate scan"
        grep -nE "$pattern" "$TARGET" || true
    fi
}

fn_refs="$(scan 'set_up_boot_action\s*\(\)')"
[ -n "$fn_refs" ] || {
    echo "expected set_up_boot_action function"
    exit 1
}

shared_gate_refs="$(scan 'shutdown_pending_now')"
[ -n "$shared_gate_refs" ] || {
    echo "expected boot action setup to delegate to shared shutdown_pending_now helper"
    exit 1
}

skip_refs="$(scan 'skipping boot-action dispatch')"
[ -n "$skip_refs" ] || {
    echo "expected explicit skip log for shutdown-pending boot-action suppression"
    exit 1
}

echo "test_runtimehelper_boot_action_shutdown_gate_contract: PASS"
