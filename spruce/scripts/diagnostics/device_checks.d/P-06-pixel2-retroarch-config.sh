#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/platform/device_functions/Pixel2.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=P-06 verdict=INFO severity=P3 confidence=low evidence=pixel2_device_file_missing"
    exit 0
fi

if grep -Fq 'retroarch-Flip.cfg' "$TARGET"; then
    echo "RESULT id=P-06 verdict=FAIL severity=P2 confidence=high evidence=pixel2_hotkeys_target_flip_config"
else
    echo "RESULT id=P-06 verdict=PASS severity=P4 confidence=high evidence=pixel2_hotkeys_target_pixel2_config"
fi
