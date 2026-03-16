#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/save_poweroff.sh"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        grep -nE "$pattern" "$TARGET" || true
    fi
}

helper_refs="$(scan 'power_trace_emit_shutdown_handoff_once')"
[ -n "$helper_refs" ] || {
    echo "expected save_poweroff.sh to centralize shutdown handoff emission"
    exit 1
}

stage2_refs="$(scan 'stage2_exec_path|stage2_missing_fallback')"
[ -n "$stage2_refs" ] || {
    echo "expected non-systemd stage-2 path to emit shutdown handoff"
    exit 1
}

systemd_refs="$(scan 'systemd_path')"
[ -n "$systemd_refs" ] || {
    echo "expected systemd shutdown path to emit shutdown handoff"
    exit 1
}

echo "test_save_poweroff_shutdown_handoff_contract: PASS"
