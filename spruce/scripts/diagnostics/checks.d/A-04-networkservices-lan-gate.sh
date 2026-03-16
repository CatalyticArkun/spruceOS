#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/common.sh"

TARGET="$SPRUCE_SCRIPTS_DIR/networkservices.sh"

if [ ! -f "$TARGET" ]; then
    echo "RESULT id=A-04 verdict=INFO severity=P3 confidence=low evidence=networkservices_missing"
    exit 0
fi

if grep -Eq 'ping[[:space:]]+-c[[:space:]]+1[[:space:]]+-W[[:space:]]+3[[:space:]]+1\.1\.1\.1' "$TARGET"; then
    echo "RESULT id=A-04 verdict=FAIL severity=P2 confidence=high evidence=networkservices_requires_public_ping"
else
    echo "RESULT id=A-04 verdict=PASS severity=P4 confidence=high evidence=networkservices_not_gated_on_public_ping"
fi
