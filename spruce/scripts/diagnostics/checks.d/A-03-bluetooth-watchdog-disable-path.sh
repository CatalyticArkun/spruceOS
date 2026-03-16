#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/bluetooth_watchdog.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=A-03 verdict=INFO severity=P3 confidence=low evidence=bluetooth_watchdog_missing"
    exit 0
fi

if grep -Eq 'hciconfig[[:space:]]+hci0[[:space:]]+up' "$TARGET" &&
    ! grep -Eq 'hciconfig[[:space:]]+hci0[[:space:]]+down|killall[[:space:]].*bluealsa|pkill[[:space:]].*bluealsa|else|BLUETOOTH.*-eq[[:space:]]*0' "$TARGET" &&
    ! grep -Fq 'rm -f /tmp/bluetooth_ready' "$TARGET"; then
    echo "RESULT id=A-03 verdict=FAIL severity=P2 confidence=high evidence=bluetooth_watchdog_missing_disable_path"
else
    echo "RESULT id=A-03 verdict=PASS severity=P4 confidence=high evidence=bluetooth_watchdog_has_disable_or_guard_path"
fi
