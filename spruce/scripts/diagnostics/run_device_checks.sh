#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

RUN_DIR="$1"
OUT_DIR="$RUN_DIR/results/device_checks"
SUMMARY="$RUN_DIR/results/device_check_results.txt"
mkdir -p "$OUT_DIR"
: > "$SUMMARY"

run_one() {
    check="$1"
    id=$(basename "$check" .sh)
    out="$OUT_DIR/$id.out"
    sh "$check" "$RUN_DIR" > "$out" 2>&1 || true
    result=$(grep -E '^RESULT ' "$out" | tail -n 1 || true)
    if [ -z "$result" ]; then
        result="RESULT id=$id verdict=WARN severity=P2 confidence=low evidence=missing_RESULT_line"
    fi
    echo "$result" >> "$SUMMARY"
}

for check in "$SCRIPT_DIR/device_checks.d"/*.sh; do
    [ -f "$check" ] || continue
    run_one "$check"
done
