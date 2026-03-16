#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/runtimeHelper.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        echo "warning: rg unavailable; using grep fallback for runtimeHelper autoresume gate scan" >&2
        grep -nE "$pattern" "$TARGET" || true
    fi
}

fn_refs="$(scan 'auto_resume_game[[:space:]]*\(\)')"
[ -n "$fn_refs" ] || {
    echo "expected auto_resume_game function"
    exit 1
}

shared_gate_refs="$(scan 'shutdown_pending_now')"
[ -n "$shared_gate_refs" ] || {
    echo "expected autoresume path to delegate to shared shutdown_pending_now helper"
    exit 1
}

skip_refs="$(scan 'suppressing autoresume dispatch')"
[ -n "$skip_refs" ] || {
    echo "expected explicit log for shutdown-pending autoresume suppression"
    exit 1
}

echo "test_runtimehelper_autoresume_shutdown_gate_contract: PASS"
