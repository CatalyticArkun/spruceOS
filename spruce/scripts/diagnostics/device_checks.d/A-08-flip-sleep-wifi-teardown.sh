#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/platform/device_functions/Flip.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=A-08 verdict=INFO severity=P3 confidence=low evidence=flip_device_file_missing"
    exit 0
fi

if awk '/^device_enter_sleep\(\)[[:space:]]*\{/,/^}/ {print}' "$TARGET" | grep -Eq 'disable_wifi|networkservices\.sh[[:space:]]+off|enable_or_disable_wifi_per_system_json'; then
    echo "RESULT id=A-08 verdict=PASS severity=P4 confidence=high evidence=flip_sleep_has_wifi_teardown"
else
    echo "RESULT id=A-08 verdict=FAIL severity=P2 confidence=high evidence=flip_sleep_missing_wifi_teardown"
fi
