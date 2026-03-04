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

mkdir -p "$RUN_DIR" "$RUN_DIR/state" "$RUN_DIR/raw" "$RUN_DIR/curated" "$RUN_DIR/results" "$RUN_DIR/bundles"

atomic_write "$STATE_FILE" \
"run_id=$RUN_ID" \
"boot_id=$RUN_BOOT_ID" \
"phase_target=$PHASE" \
"updated_at=$(timestamp_utc)"

step_done() { [ -f "$RUN_DIR/state/$1.done" ]; }
mark_step_done() { : > "$RUN_DIR/state/$1.done.tmp"; mv "$RUN_DIR/state/$1.done.tmp" "$RUN_DIR/state/$1.done"; }

capture_identity() {
    out="$RUN_DIR/summary/identity.txt"
    mkdir -p "$RUN_DIR/summary"
    {
        echo "timestamp=$(timestamp_utc)"
        echo "device_hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
        echo "kernel=$(uname -r 2>/dev/null || echo unknown)"
        echo "platform=${PLATFORM:-unknown}"
        echo "bundle_version=$(get_bundle_version)"
        if [ -f /etc/version ]; then
            echo "fw_version=$(tr -d '[:space:]' </etc/version)"
        fi
    } > "$out"
}

capture_logs() {
    dmesg > "$RUN_DIR/raw/dmesg.full" 2>/dev/null || true
    tail -n 1200 "$RUN_DIR/raw/dmesg.full" > "$RUN_DIR/raw/dmesg.tail" 2>/dev/null || true
    if [ -f "$LOG_ROOT/spruce.log" ]; then
        tail -n 800 "$LOG_ROOT/spruce.log" > "$RUN_DIR/raw/spruce.tail.log"
    fi
    if [ -f /var/log/messages ]; then
        tail -n 800 /var/log/messages > "$RUN_DIR/raw/messages.tail.log"
    fi
}

run_curation() {
    "$SCRIPT_DIR/curate_logs.sh" "$RUN_DIR"
}

run_checks() {
    "$SCRIPT_DIR/run_checks.sh" "$RUN_DIR"
}

run_mustard_checks() {
    "$SCRIPT_DIR/run_mustard_checks.sh" "$RUN_DIR"
}

collect_mustard_compat() {
    "$SCRIPT_DIR/collect_mustard_compat.sh" "$RUN_DIR" "$PHASE"
}

run_verifiers() {
    "$SCRIPT_DIR/run_verifiers.sh" "$RUN_DIR"
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
    mkdir -p "$RUN_DIR/summary"
    {
        echo "# Recommendations are hints only; no flags are auto-enabled."
        if cat "$RUN_DIR/results/check_results.txt" "$RUN_DIR/results/mustard_check_results.txt" 2>/dev/null | grep -Eq 'verdict=(WARN|FAIL)'; then
            echo "ENABLE_DIAG_PHASE_B.lock"
            echo "RUN_TEST_V-01.lock"
            echo "RUN_TEST_V-02.lock"
        fi
    } > "$out"
}

write_telemetry() {
    "$SCRIPT_DIR/write_telemetry.sh" "$RUN_DIR" "$PHASE" "$RUN_ID" "$RUN_BOOT_ID"
}

bundle_outputs() {
    (cd "$RUN_DIR" && tar -czf "$RUN_DIR/bundles/upload_bundle.tgz" .)
    (cd "$RUN_DIR" && tar -czf "$RUN_DIR/bundles/telemetry_bundle.tgz" summary/telemetry_event.json results/check_results.txt curated/signature_counts.txt 2>/dev/null || true)

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
run_step "02_capture_logs" capture_logs
run_step "03_mustard_compat" collect_mustard_compat
run_step "04_curation" run_curation
run_step "05_checks" run_checks
run_step "06_mustard_checks" run_mustard_checks
run_step "07_verifiers" run_verifiers

if [ "$PHASE" = "B" ]; then
    run_step "08_phase_b" phase_b_exports
fi

run_step "09_recommend" write_recommendations
run_step "10_telemetry" write_telemetry
run_step "11_bundle" bundle_outputs

atomic_write "$STATE_FILE" \
"run_id=$RUN_ID" \
"boot_id=$RUN_BOOT_ID" \
"phase_completed=$PHASE" \
"finished_at=$(timestamp_utc)"
