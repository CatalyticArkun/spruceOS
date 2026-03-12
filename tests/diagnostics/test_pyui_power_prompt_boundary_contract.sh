#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/App/PyUI/main-ui/devices/device_common.py"

scan() {
    pattern="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$TARGET" || true
    else
        grep -nE "$pattern" "$TARGET" || true
    fi
}

power_off_body="$(awk '
    /def power_off\(self\):/ { in_fn=1 }
    in_fn { print }
    in_fn && /^[[:space:]]*def / && $0 !~ /def power_off\(self\):/ { exit }
' "$TARGET")"

reboot_body="$(awk '
    /def reboot\(self\):/ { in_fn=1 }
    in_fn { print }
    in_fn && /^[[:space:]]*def / && $0 !~ /def reboot\(self\):/ { exit }
' "$TARGET")"

printf '%s\n' "$power_off_body" | grep -q 'POWER_REQUEST_SCRIPT' || {
    echo "expected power_off to route through POWER_REQUEST_SCRIPT backend request path"
    exit 1
}
printf '%s\n' "$reboot_body" | grep -q 'POWER_REQUEST_SCRIPT' || {
    echo "expected reboot to route through POWER_REQUEST_SCRIPT backend request path"
    exit 1
}

if printf '%s\n%s\n' "$power_off_body" "$reboot_body" | grep -q 'get_poweroff_cmd\|get_reboot_cmd'; then
    echo "did not expect prompt-flow power_off/reboot to directly consult poweroffCmd/rebootCmd"
    exit 1
fi

echo "test_pyui_power_prompt_boundary_contract: PASS"
