#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/App/PyUI/main-ui/devices/device_common.py"

if command -v rg >/dev/null 2>&1; then
    line="$(rg -n 'Controller\.last_input\(\) == ControllerInput\.X and self\.reboot_cmd\(\) is not None' "$TARGET" || true)"
else
    line="$(grep -nE 'Controller\.last_input\(\) == ControllerInput\.X and self\.reboot_cmd\(\) is not None' "$TARGET" || true)"
fi

[ -n "$line" ] || {
    echo "expected prompt_power_down to gate X/reboot path on reboot_cmd() capability"
    exit 1
}

echo "test_pyui_power_prompt_reboot_guard_contract: PASS"
