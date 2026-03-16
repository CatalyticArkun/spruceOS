#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/save_poweroff_stage2.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=A-16 verdict=INFO severity=P3 confidence=low evidence=save_poweroff_stage2_missing"
    exit 0
fi

if grep -Fq '[ -d /customer/app ] && [ ! -e /customer/app/axp_test ]' "$TARGET" &&
    ! grep -Fq 'sun8i' "$TARGET"; then
    echo "RESULT id=A-16 verdict=FAIL severity=P2 confidence=high evidence=stage2_missing_sun8i_a30_guard"
else
    echo "RESULT id=A-16 verdict=PASS severity=P4 confidence=high evidence=stage2_has_a30_guard_or_no_ogmini_proxy"
fi
