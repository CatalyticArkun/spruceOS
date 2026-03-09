#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_BOOT_ID="$(boot_id)"
RUN_ID="${RUN_ID:-${RUN_BOOT_ID}}"
RUN_DIR="$RUNS_DIR/$RUN_ID"
STATE_FILE="$STATE_DIR/current_run.state"
LOCK_DIR="$STATE_DIR/runner.lock"
PHASE="A"

if flag_exists "ENABLE_DIAG_PHASE_B"; then
    PHASE="B"
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT INT TERM

mkdir -p "$RUN_DIR" "$RUN_DIR/state" "$RUN_DIR/raw" "$RUN_DIR/curated" "$RUN_DIR/results" "$RUN_DIR/bundles" "$RUN_DIR/summary"

atomic_write "$STATE_FILE" \
"run_id=$RUN_ID" \
"boot_id=$RUN_BOOT_ID" \
"phase_target=$PHASE" \
"updated_at=$(timestamp_utc)"

step_done() { [ -f "$RUN_DIR/state/$1.done" ]; }
mark_step_done() { : > "$RUN_DIR/state/$1.done.tmp"; mv "$RUN_DIR/state/$1.done.tmp" "$RUN_DIR/state/$1.done"; }

capture_identity() {
    out="$RUN_DIR/summary/identity.txt"
    fw="unknown"
    [ -f /etc/version ] && fw=$(tr -d '[:space:]' </etc/version)
    {
        echo "timestamp=$(timestamp_utc)"
        echo "device_hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
        echo "kernel=$(uname -r 2>/dev/null || echo unknown)"
        echo "platform=${PLATFORM:-unknown}"
        echo "bundle_version=$(get_bundle_version)"
        echo "boot_id=$RUN_BOOT_ID"
        echo "fw_build=$fw"
        echo "uptime_seconds=$(uptime_seconds)"
        echo "clock_sane=$(clock_sane)"
    } > "$out"
}

run_collectors() {
    "$SCRIPT_DIR/run_collectors.sh" "$RUN_DIR" "$PHASE"
}

run_curation() {
    "$SCRIPT_DIR/curate_logs.sh" "$RUN_DIR"
}

run_checks() {
    "$SCRIPT_DIR/run_checks.sh" "$RUN_DIR"
}

run_baseline_checks() {
    "$SCRIPT_DIR/run_baseline_checks.sh" "$RUN_DIR"
}

run_verifiers() {
    "$SCRIPT_DIR/run_verifiers.sh" "$RUN_DIR"
}

capture_power_traces() {
    mkdir -p "$RUN_DIR/raw" "$RUN_DIR/summary"
    if [ -f "$LOG_ROOT/power/events.jsonl" ]; then
        tail -n 400 "$LOG_ROOT/power/events.jsonl" > "$RUN_DIR/raw/power_trace.events.jsonl"
    fi
    if [ -f "$LOG_ROOT/power/summary.txt" ]; then
        tail -n 200 "$LOG_ROOT/power/summary.txt" > "$RUN_DIR/summary/power_trace.summary.txt"
    fi
    if [ -f "$LOG_ROOT/power/state.env" ]; then
        cp "$LOG_ROOT/power/state.env" "$RUN_DIR/summary/power_trace.state.env"
    fi
}

phase_b_exports() {
    dest="$RUN_DIR/phase_b"
    mkdir -p "$dest"
    marker="$RUN_DIR/state/phase_b_copy_index"
    idx="0"
    [ -f "$marker" ] && idx="$(cat "$marker")"

    i=0
    for f in "$LOG_ROOT"/*.log "$LOG_ROOT"/*.json; do
        [ -f "$f" ] || continue
        i=$((i + 1))
        [ "$i" -le "$idx" ] && continue
        cp "$f" "$dest/" 2>/dev/null || true
        atomic_write "$marker" "$i"
    done
}

write_recommendations() {
    out="$RUN_DIR/summary/recommended_flags.txt"
    {
        echo "# Recommendations are hints only; no flags are auto-enabled."
        if cat "$RUN_DIR/results/check_results.txt" "$RUN_DIR/results/baseline_check_results.txt" "$RUN_DIR/results/verifier_results.txt" 2>/dev/null | grep -Eq 'verdict=(WARN|FAIL)'; then
            echo "ENABLE_DIAG_PHASE_B.lock"
            echo "RUN_TEST_V-01.lock"
            echo "RUN_TEST_V-02.lock"
        fi
    } > "$out"
}

write_telemetry() {
    "$SCRIPT_DIR/write_telemetry.sh" "$RUN_DIR" "$PHASE" "$RUN_ID" "$RUN_BOOT_ID"
}

summarize_outputs() {
    "$SCRIPT_DIR/summarize_run.sh" "$RUN_DIR" "$RUN_ID" "$RUN_BOOT_ID" "$(timestamp_utc)"
}

bundle_outputs() {
    (cd "$RUN_DIR" && tar -czf "$RUN_DIR/bundles/upload_bundle.tgz" --exclude=./bundles --exclude=./bundles/* .)
    (cd "$RUN_DIR" && tar -czf "$RUN_DIR/bundles/telemetry_bundle.tgz" \
      summary/run_manifest.json \
      summary/findings.jsonl \
      summary/report.txt \
      summary/telemetry_event.json \
      results/check_results.txt \
      results/verifier_results.txt \
      results/baseline_check_results.txt \
      curated/signature_counts.txt \
      raw/power_trace.events.jsonl \
      summary/power_trace.summary.txt \
      summary/power_trace.state.env 2>/dev/null || true)

    cp "$RUN_DIR/bundles/upload_bundle.tgz" "$LATEST_DIR/bundle_latest.tgz"
    cp "$RUN_DIR/bundles/telemetry_bundle.tgz" "$LATEST_DIR/telemetry_latest.tgz"
}

run_step() {
    step="$1"
    shift
    if ! step_done "$step"; then
        "$@"
        mark_step_done "$step"
    fi
}

run_step "01_identity" capture_identity
run_step "02_collectors" run_collectors
run_step "03_curation" run_curation
run_step "04_checks" run_checks
run_step "05_baseline_checks" run_baseline_checks
run_step "06_verifiers" run_verifiers
run_step "07_power_trace" capture_power_traces

if [ "$PHASE" = "B" ]; then
    run_step "08_phase_b" phase_b_exports
fi

run_step "09_recommend" write_recommendations
run_step "10_telemetry" write_telemetry
run_step "11_summary" summarize_outputs
run_step "12_bundle" bundle_outputs

atomic_write "$STATE_FILE" \
"run_id=$RUN_ID" \
"boot_id=$RUN_BOOT_ID" \
"phase_completed=$PHASE" \
"finished_at=$(timestamp_utc)"
