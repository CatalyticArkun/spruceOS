#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

scan_file() {
    file="$1"
    pattern="$2"
    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$file" || true
    else
        grep -nE "$pattern" "$file" || true
    fi
}

assert_has() {
    file="$1"
    pattern="$2"
    msg="$3"
    out="$(scan_file "$file" "$pattern")"
    [ -n "$out" ] || {
        echo "$msg"
        exit 1
    }
}

# 1) Launch defaults watchdog ownership on.
assert_has "$ROOT/App/PyUI/launch.sh" 'SPRUCE_WATCHDOG_OWNS_POWER_BUTTON' \
    "expected launch.sh to export SPRUCE_WATCHDOG_OWNS_POWER_BUTTON default"

# 2) PyUI config exposes phase-1 ownership gates.
assert_has "$ROOT/App/PyUI/main-ui/utils/py_ui_config.py" 'def enable_power_button_watcher' \
    "expected PyUiConfig.enable_power_button_watcher gate"
assert_has "$ROOT/App/PyUI/main-ui/utils/py_ui_config.py" 'def enable_raw_power_button_semantics' \
    "expected PyUiConfig.enable_raw_power_button_semantics gate"

# 3) Controller raw power semantics are suppressible.
assert_has "$ROOT/App/PyUI/main-ui/controller/controller.py" 'enable_raw_power_button_semantics' \
    "expected controller non_sdl_input_event to consult raw power semantics gate"

# 4) Same-node/high-risk targets gate power watcher startup.
for f in \
    "$ROOT/App/PyUI/main-ui/devices/trimui/trim_ui_smart_pro.py" \
    "$ROOT/App/PyUI/main-ui/devices/trimui/trim_ui_brick.py" \
    "$ROOT/App/PyUI/main-ui/devices/gkd/gkd_pixel2.py" \
    "$ROOT/App/PyUI/main-ui/devices/miyoo/a30/miyoo_a30.py" \
    "$ROOT/App/PyUI/main-ui/devices/trimui/trim_ui_smart_pro_s.py"
do
    assert_has "$f" 'enable_power_button_watcher' "expected power watcher gate in $f"
done

# 5) MiyooMini shared event0 watcher filters to volume keycodes only (prevents power leakage).
assert_has "$ROOT/App/PyUI/main-ui/devices/miyoo/mini/miyoo_mini_common.py" 'allowed_keycodes=\{114, 115\}' \
    "expected miyoo_mini_common volume watcher to filter non-volume keycodes"

echo "test_pyui_power_ownership_phase1_contract: PASS"
