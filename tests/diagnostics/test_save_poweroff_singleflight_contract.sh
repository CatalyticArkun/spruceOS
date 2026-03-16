#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/spruce/scripts/save_poweroff.sh"

scan_for_pidfile_contract() {
    if command -v rg >/dev/null 2>&1; then
        rg -n '/tmp/save_poweroff\.pid|PIDFILE=' "$TARGET" || true
        return
    fi

    echo "warning: rg unavailable; using grep fallback for save_poweroff contract scan" >&2
    grep -nE '/tmp/save_poweroff\.pid|PIDFILE=' "$TARGET" || true
}

matches="$(scan_for_pidfile_contract)"
if [ -n "$matches" ]; then
    echo "unexpected legacy PIDFILE contract still present in save_poweroff.sh"
    echo "$matches"
    exit 1
fi

if command -v rg >/dev/null 2>&1; then
    guard_refs="$(rg -n 'shutdown_singleflight_begin|shutdown_singleflight_clear|SHUTDOWN_GUARD_OWNED' "$TARGET" || true)"
else
    guard_refs="$(grep -nE 'shutdown_singleflight_begin|shutdown_singleflight_clear|SHUTDOWN_GUARD_OWNED' "$TARGET" || true)"
fi

[ -n "$guard_refs" ] || {
    echo "expected save_poweroff.sh to rely on shutdown singleflight guard contract"
    exit 1
}

echo "test_save_poweroff_singleflight_contract: PASS"
