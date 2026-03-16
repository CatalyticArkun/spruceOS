#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export SD_ROOT="$TMP/sd"
mkdir -p "$SD_ROOT/spruce/scripts/diagnostics" "$SD_ROOT/spruce/scripts/platform/device_functions" "$SD_ROOT/spruce/scripts/platform" "$SD_ROOT/spruce/flags" "$SD_ROOT/Saves/spruce/power" "$SD_ROOT/Saves/spruce"
cp -a "$ROOT/spruce/scripts/diagnostics/." "$SD_ROOT/spruce/scripts/diagnostics/"
cp "$ROOT/spruce/scripts/bluetooth_watchdog.sh" "$SD_ROOT/spruce/scripts/bluetooth_watchdog.sh"
cp "$ROOT/spruce/scripts/networkservices.sh" "$SD_ROOT/spruce/scripts/networkservices.sh"
cp "$ROOT/spruce/scripts/save_poweroff_stage2.sh" "$SD_ROOT/spruce/scripts/save_poweroff_stage2.sh"
cp "$ROOT/spruce/scripts/platform/device_functions/Flip.sh" "$SD_ROOT/spruce/scripts/platform/device_functions/Flip.sh"
cp "$ROOT/spruce/scripts/platform/device_functions/SmartProS.sh" "$SD_ROOT/spruce/scripts/platform/device_functions/SmartProS.sh"
cp "$ROOT/spruce/scripts/platform/device_functions/trimui_a133p.sh" "$SD_ROOT/spruce/scripts/platform/device_functions/trimui_a133p.sh"
cp "$ROOT/spruce/scripts/platform/device_functions/Pixel2.sh" "$SD_ROOT/spruce/scripts/platform/device_functions/Pixel2.sh"
cp "$ROOT/spruce/scripts/platform/Pixel2.cfg" "$SD_ROOT/spruce/scripts/platform/Pixel2.cfg"
cp "$ROOT/tests/diagnostics/simulated_logs/dmesg.sample" "$SD_ROOT/Saves/spruce/spruce.log"
printf '{"event":"BOOT_BEGIN"}\n{"event":"BOOT_COMPLETE"}\n' > "$SD_ROOT/Saves/spruce/power/events.jsonl"
printf '2026-01-01T00:00:00Z | BOOT_BEGIN | prev=UNKNOWN intended=BOOTING observed=BOOTING trigger=test notes=fixture\n' > "$SD_ROOT/Saves/spruce/power/summary.txt"

RUN_DIR="$SD_ROOT/Saves/spruce/diag/runs/test-run"
mkdir -p "$RUN_DIR/raw/08_kernel"
cp "$ROOT/tests/diagnostics/simulated_logs/dmesg.sample" "$RUN_DIR/raw/08_kernel/dmesg.tail"

"$SD_ROOT/spruce/scripts/diagnostics/run_collectors.sh" "$RUN_DIR" "A"
"$SD_ROOT/spruce/scripts/diagnostics/curate_logs.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_checks.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_device_checks.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_baseline_checks.sh" "$RUN_DIR"
"$SD_ROOT/spruce/scripts/diagnostics/run_verifiers.sh" "$RUN_DIR"
mkdir -p "$RUN_DIR/summary"
cat > "$RUN_DIR/summary/identity.txt" <<IDENT
device_hostname=testbox
kernel=testkernel
platform=testplatform
fw_build=testfw
IDENT
"$SD_ROOT/spruce/scripts/diagnostics/write_telemetry.sh" "$RUN_DIR" "A" "test-run" "boot-1"
"$SD_ROOT/spruce/scripts/diagnostics/summarize_run.sh" "$RUN_DIR" "test-run" "boot-1" "2026-01-01T00:00:00Z"

grep -q 'SIG_KERNEL_OOPS' "$RUN_DIR/curated/signature_counts.txt"
grep -q '^RESULT id=GEN-01' "$RUN_DIR/results/check_results.txt"
grep -q '^RESULT id=GEN-04' "$RUN_DIR/results/check_results.txt"
grep -q '^RESULT id=A-03' "$RUN_DIR/results/check_results.txt"
grep -q '^RESULT id=P-07' "$RUN_DIR/results/device_check_results.txt"
grep -q '^RESULT id=S-01' "$RUN_DIR/results/baseline_check_results.txt"
test -f "$RUN_DIR/raw/01_identity/identity.txt"
test -f "$RUN_DIR/raw/10_runtime_state/markers.txt"
test -f "$RUN_DIR/summary/report.txt"
test -f "$RUN_DIR/summary/findings.jsonl"
test -f "$RUN_DIR/summary/run_manifest.json"
jq -e '.run_id == "test-run" and (.detector_results | length) >= 1 and (.uptime_seconds >= 0) and (.power_trace_event_count | tonumber) >= 0' "$RUN_DIR/summary/telemetry_event.json" >/dev/null
jq -e '.counts.device_check >= 1' "$RUN_DIR/summary/run_manifest.json" >/dev/null

echo "diagnostics test_runner: PASS"
