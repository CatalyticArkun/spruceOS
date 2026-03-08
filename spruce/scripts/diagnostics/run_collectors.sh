#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

RUN_DIR="$1"
PHASE="${2:-A}"

for collector in "$SCRIPT_DIR/collectors.d"/*.sh; do
    [ -f "$collector" ] || continue
    sh "$collector" "$RUN_DIR" "$PHASE" >/dev/null 2>&1 || true
done
