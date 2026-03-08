#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
RAW="$RUN_DIR/raw/08_kernel/dmesg.tail"
[ -f "$RAW" ] || RAW="$RUN_DIR/raw/dmesg.tail"
CURATED_DIR="$RUN_DIR/curated"
mkdir -p "$CURATED_DIR"
COUNTS="$CURATED_DIR/signature_counts.txt"
CTX="$CURATED_DIR/tier1_context.txt"
: > "$COUNTS"
: > "$CTX"

[ -f "$RAW" ] || : > "$RAW"
HAS_GREP_P=0
command -v grep >/dev/null 2>&1 && printf 'test\n' | grep -P 'test' >/dev/null 2>&1 && HAS_GREP_P=1

grep_count() {
    regex="$1"
    if [ "$HAS_GREP_P" -eq 1 ] && echo "$regex" | grep -q '\\s'; then
        grep -Pic "$regex" "$RAW" 2>/dev/null || true
    else
        grep -Eic "$regex" "$RAW" 2>/dev/null || true
    fi
}

grep_lines() {
    regex="$1"
    if [ "$HAS_GREP_P" -eq 1 ] && echo "$regex" | grep -q '\\s'; then
        grep -Pin "$regex" "$RAW" 2>/dev/null || true
    else
        grep -Ein "$regex" "$RAW" 2>/dev/null || true
    fi
}

while IFS='|' read -r sig tier category regex; do
    [ -z "$sig" ] && continue
    case "$sig" in \#*) continue ;; esac
    count=$(grep_count "$regex")
    echo "$sig|$tier|$category|$count" >> "$COUNTS"

    if [ "$tier" = "T1" ] && [ "$count" -gt 0 ]; then
        echo "### $sig ($category)" >> "$CTX"
        grep_lines "$regex" | head -n 5 | while IFS=: read -r ln _; do
            start=$((ln - 2)); [ "$start" -lt 1 ] && start=1
            end=$((ln + 2))
            sed -n "${start},${end}p" "$RAW" >> "$CTX"
            echo "---" >> "$CTX"
        done
    fi
done < "$SCRIPT_DIR/patterns.conf"
