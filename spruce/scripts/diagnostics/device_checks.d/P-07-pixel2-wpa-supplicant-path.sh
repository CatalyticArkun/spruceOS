#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/platform/Pixel2.cfg"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=P-07 verdict=INFO severity=P3 confidence=low evidence=pixel2_cfg_missing"
    exit 0
fi

if grep -Fq 'export WPA_SUPPLICANT_FILE=""' "$TARGET"; then
    echo "RESULT id=P-07 verdict=FAIL severity=P2 confidence=high evidence=pixel2_wpa_supplicant_path_empty"
else
    echo "RESULT id=P-07 verdict=PASS severity=P4 confidence=high evidence=pixel2_wpa_supplicant_path_present"
fi
