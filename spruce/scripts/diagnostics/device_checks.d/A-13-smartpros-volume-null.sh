#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/platform/device_functions/SmartProS.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=A-13 verdict=INFO severity=P3 confidence=low evidence=smartpros_device_file_missing"
    exit 0
fi

if grep -Eq "current_volume=.*jq -r '\\.vol'" "$TARGET" &&
    grep -Fq 'if [ "$current_volume" -ne "$new_vol" ]; then' "$TARGET"; then
    echo "RESULT id=A-13 verdict=FAIL severity=P2 confidence=high evidence=smartpros_volume_null_not_guarded"
else
    echo "RESULT id=A-13 verdict=PASS severity=P4 confidence=high evidence=smartpros_volume_null_guard_present"
fi
