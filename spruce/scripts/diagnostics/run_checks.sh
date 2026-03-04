#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
OUT_DIR="$RUN_DIR/results/checks"
SUMMARY="$RUN_DIR/results/check_results.txt"
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

for check in "$SCRIPT_DIR/checks.d"/*.sh; do
    [ -f "$check" ] || continue
    run_one "$check"
done

if flag_exists "ENABLE_RETIRED_CHECKS"; then
    for check in "$SCRIPT_DIR/retired_checks.d"/*.sh; do
        [ -f "$check" ] || continue
        run_one "$check"
    done
else
    echo "RESULT id=RETIRED verdict=INFO severity=P4 confidence=high evidence=retired_checks_disabled" >> "$SUMMARY"
fi
