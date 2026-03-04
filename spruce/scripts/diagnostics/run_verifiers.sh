#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
OUT_DIR="$RUN_DIR/results/verifiers"
SUMMARY="$RUN_DIR/results/verifier_results.txt"
mkdir -p "$OUT_DIR"
: > "$SUMMARY"

for verifier in "$SCRIPT_DIR/verifiers.d"/*.sh; do
    [ -f "$verifier" ] || continue
    id=$(basename "$verifier" .sh)
    flag="RUN_TEST_${id}"
    if flag_exists "$flag"; then
        out="$OUT_DIR/$id.out"
        sh "$verifier" "$RUN_DIR" > "$out" 2>&1 || true
        result=$(grep -E '^RESULT ' "$out" | tail -n 1 || true)
        [ -n "$result" ] || result="RESULT id=$id verdict=WARN severity=P2 confidence=low evidence=missing_RESULT_line"
        echo "$result" >> "$SUMMARY"
    else
        echo "RESULT id=$id verdict=INFO severity=P4 confidence=high evidence=flag_${flag}_not_set" >> "$SUMMARY"
    fi
done
