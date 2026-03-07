#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export SD_ROOT="$TMP/sd"
mkdir -p "$SD_ROOT/spruce/scripts/diagnostics" "$SD_ROOT/spruce/flags" "$SD_ROOT/Saves/spruce/power" "$SD_ROOT/Saves/spruce"
cp -a "$ROOT/spruce/scripts/diagnostics/." "$SD_ROOT/spruce/scripts/diagnostics/"
cp "$ROOT/tests/diagnostics/simulated_logs/dmesg.sample" "$SD_ROOT/Saves/spruce/spruce.log"
printf '{"event":"BOOT_BEGIN"}\n{"event":"BOOT_COMPLETE"}\n' > "$SD_ROOT/Saves/spruce/power/events.jsonl"
printf '2026-01-01T00:00:00Z | BOOT_BEGIN | prev=UNKNOWN intended=BOOTING observed=BOOTING trigger=test notes=fixture\n' > "$SD_ROOT/Saves/spruce/power/summary.txt"

RUN_DIR="$SD_ROOT/Saves/spruce/diag/runs/test-run"
mkdir -p "$RUN_DIR/raw"
cp "$ROOT/tests/diagnostics/simulated_logs/dmesg.sample" "$RUN_DIR/raw/dmesg.tail"
mkdir -p "$RUN_DIR/summary"
cp "$SD_ROOT/Saves/spruce/power/events.jsonl" "$RUN_DIR/raw/power_trace.events.jsonl"
cp "$SD_ROOT/Saves/spruce/power/summary.txt" "$RUN_DIR/summary/power_trace.summary.txt"

"$SD_ROOT/spruce/scripts/diagnostics/collect_mustard_compat.sh" "$RUN_DIR" "A"
"$SD_ROOT/spruce/scripts/diagnostics/curate_logs.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_checks.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_mustard_checks.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/write_telemetry.sh" "$RUN_DIR" "A" "test-run" "boot-1"

grep -q 'SIG_KERNEL_OOPS' "$RUN_DIR/curated/signature_counts.txt"
grep -q '^RESULT id=M-08' "$RUN_DIR/results/check_results.txt"
grep -q '^RESULT id=S-01' "$RUN_DIR/results/mustard_check_results.txt"
test -f "$RUN_DIR/raw/mustard_compat/basic/hostname.log"
jq -e '.run_id == "test-run" and (.detector_results | length) >= 1 and .power_trace_event_count == "2"' "$RUN_DIR/summary/telemetry_event.json" >/dev/null

echo "diagnostics test_runner: PASS"
