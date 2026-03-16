#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/platform/device_functions/Pixel2.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=P-08 verdict=INFO severity=P3 confidence=low evidence=pixel2_device_file_missing"
    exit 0
fi

if grep -Fq 'if (( $new_bl >= 0 )) && (( $new_bl <= 10 )); then' "$TARGET"; then
    echo "RESULT id=P-08 verdict=FAIL severity=P3 confidence=high evidence=pixel2_backlight_uses_bash_arithmetic"
else
    echo "RESULT id=P-08 verdict=PASS severity=P4 confidence=high evidence=pixel2_backlight_uses_posix_guard"
fi
