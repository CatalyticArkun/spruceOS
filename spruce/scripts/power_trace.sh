#!/bin/sh

POWER_TRACE_DIR="${POWER_TRACE_DIR:-/mnt/SDCARD/Saves/spruce/power}"
POWER_TRACE_EVENTS_FILE="$POWER_TRACE_DIR/events.jsonl"
POWER_TRACE_SUMMARY_FILE="$POWER_TRACE_DIR/summary.txt"
POWER_TRACE_STATE_FILE="$POWER_TRACE_DIR/state.env"
POWER_TRACE_PENDING_FILE="$POWER_TRACE_DIR/pending.env"
POWER_TRACE_MAX_EVENTS="${POWER_TRACE_MAX_EVENTS:-400}"
POWER_TRACE_MAX_SUMMARY_LINES="${POWER_TRACE_MAX_SUMMARY_LINES:-120}"
TRACE_CORE_SCRIPT="/mnt/SDCARD/spruce/scripts/trace.sh"

if [ -f "$TRACE_CORE_SCRIPT" ]; then
    # shellcheck disable=SC1090
    . "$TRACE_CORE_SCRIPT"
fi

power_trace_gate_enabled() {
    if command -v trace_gate_enabled >/dev/null 2>&1; then
        trace_gate_enabled "power"
        return $?
    fi

    [ "${POWER_TRACE_ENABLED:-1}" = "0" ] && return 1
    return 0
}

power_trace_supported_event() {
    case "$1" in
        BOOT_BEGIN|BOOT_COMPLETE|SHUTDOWN_BEGIN|SHUTDOWN_HANDOFF|SHUTDOWN_COMPLETE|SHUTDOWN_RECOVERED|REBOOT_BEGIN|SLEEP_PREPARE_BEGIN|SLEEP_PREPARE_COMPLETE|SLEEP_REQUESTED|SLEEP_ENTER_BEGIN|SLEEP_ENTER_COMPLETE|WAKE_DETECTED|WAKE_RESUME_BEGIN|WAKE_RESUME_COMPLETE|TRANSITION_ABORTED|TRANSITION_TIMEOUT|REQUEST_SUPPRESSED|DIRTY_STARTUP|INVALID_TRANSITION|POWER_ERROR|UNKNOWN_TRANSITION)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

power_trace_monotonic_ts() {
    awk '{print $1}' /proc/uptime 2>/dev/null
}

power_trace_wall_ts() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

power_trace_boot_id() {
    if [ -r /proc/sys/kernel/random/boot_id ]; then
        cat /proc/sys/kernel/random/boot_id
    else
        echo "boot-$(date +%s)"
    fi
}

power_trace_build() {
    cat /etc/version 2>/dev/null || echo "unknown"
}

power_trace_escape_json() {
    if command -v trace_escape_json >/dev/null 2>&1; then
        trace_escape_json "$1"
    else
        printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
    fi
}

power_trace_state_defaults() {
    [ -n "${pt_last_state:-}" ] || pt_last_state="UNKNOWN"
    [ -n "${pt_intended_state:-}" ] || pt_intended_state="UNKNOWN"
    [ -n "${pt_requested_state:-}" ] || pt_requested_state="UNKNOWN"
    [ -n "${pt_observed_state:-}" ] || pt_observed_state="UNKNOWN"
    [ -n "${pt_completed_state:-}" ] || pt_completed_state="UNKNOWN"
    [ -n "${pt_active_transition_id:-}" ] || pt_active_transition_id=""
    [ -n "${pt_event_seq:-}" ] || pt_event_seq="0"
    [ -n "${pt_last_reconciled_pending_key:-}" ] || pt_last_reconciled_pending_key="${pt_last_reconciled_pending_id:-}"
}

power_trace_load_state() {
    mkdir -p "$POWER_TRACE_DIR"
    if [ -f "$POWER_TRACE_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$POWER_TRACE_STATE_FILE"
    fi
    power_trace_state_defaults
}

power_trace_save_state() {
    umask 077
    cat > "$POWER_TRACE_STATE_FILE.tmp.$$" <<EOF_STATE
pt_last_state="$pt_last_state"
pt_intended_state="$pt_intended_state"
pt_requested_state="$pt_requested_state"
pt_observed_state="$pt_observed_state"
pt_completed_state="$pt_completed_state"
pt_active_transition_id="$pt_active_transition_id"
pt_event_seq="$pt_event_seq"
pt_last_reconciled_pending_key="$pt_last_reconciled_pending_key"
EOF_STATE
    mv "$POWER_TRACE_STATE_FILE.tmp.$$" "$POWER_TRACE_STATE_FILE"
}

power_trace_trim_file() {
    file="$1"
    max_lines="$2"
    [ -f "$file" ] || return 0
    count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if [ "$count" -gt "$max_lines" ]; then
        tail -n "$max_lines" "$file" > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
    fi
}

power_trace_new_correlation_id() {
    if [ -n "${pt_active_transition_id:-}" ]; then
        echo "$pt_active_transition_id"
        return
    fi
    echo "pt-$(date +%s)-$$-${pt_event_seq:-0}"
}

power_trace_validate_transition() {
    event="$1"
    prev="$2"

    case "$event" in
        BOOT_BEGIN)
            # Always allowed: runtime startup and recovered reboot paths both emit BOOT_BEGIN.
            return 0
            ;;
        BOOT_COMPLETE)
            [ "$prev" = "BOOTING" ] && return 0
            ;;
        SHUTDOWN_BEGIN)
            [ "$prev" = "RUNNING" ] || [ "$prev" = "WAKING" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        SHUTDOWN_HANDOFF)
            [ "$prev" = "SHUTDOWN_PENDING" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        SHUTDOWN_COMPLETE|SHUTDOWN_RECOVERED)
            [ "$prev" = "SHUTDOWN_PENDING" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        REBOOT_BEGIN)
            [ "$prev" = "RUNNING" ] || [ "$prev" = "WAKING" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        SLEEP_PREPARE_BEGIN|SLEEP_PREPARE_COMPLETE|SLEEP_REQUESTED|SLEEP_ENTER_BEGIN)
            [ "$prev" = "RUNNING" ] || [ "$prev" = "SLEEP_PREP" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        SLEEP_ENTER_COMPLETE)
            [ "$prev" = "SLEEPING" ] || [ "$prev" = "SLEEP_PREP" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        WAKE_DETECTED|WAKE_RESUME_BEGIN|WAKE_RESUME_COMPLETE)
            [ "$prev" = "SLEEPING" ] || [ "$prev" = "WAKING" ] || [ "$prev" = "UNKNOWN" ] && return 0
            ;;
        DIRTY_STARTUP)
            [ "$prev" = "UNKNOWN" ] || [ "$prev" = "RUNNING" ] && return 0
            ;;
        TRANSITION_ABORTED|TRANSITION_TIMEOUT|REQUEST_SUPPRESSED|POWER_ERROR|UNKNOWN_TRANSITION|INVALID_TRANSITION)
            return 0
            ;;
    esac

    return 1
}

power_trace_set_snapshot() {
    pt_last_state="$1"
    pt_requested_state="$2"
    pt_intended_state="$3"
    pt_observed_state="$4"
    pt_completed_state="$5"
    pt_active_transition_id="$6"
}

power_trace_apply_snapshot() {
    event="$1"
    corr="$2"
    source_ref="$3"
    observed_state="$4"

    normalized_observed="${observed_state:-UNKNOWN}"
    [ "$normalized_observed" = "AUTO" ] && normalized_observed="UNKNOWN"

    case "$event" in
        BOOT_BEGIN)
            power_trace_set_snapshot "BOOTING" "BOOTING" "BOOTING" "BOOTING" "UNKNOWN" "$corr"
            ;;
        BOOT_COMPLETE)
            power_trace_set_snapshot "RUNNING" "RUNNING" "RUNNING" "RUNNING" "RUNNING" ""
            ;;
        SHUTDOWN_BEGIN)
            power_trace_set_snapshot "SHUTDOWN_PENDING" "SHUTDOWN" "OFF" "RUNNING" "$pt_completed_state" "$corr"
            power_trace_mark_pending "SHUTDOWN" "$corr" "$source_ref"
            ;;
        SHUTDOWN_HANDOFF)
            active="${pt_active_transition_id:-$corr}"
            power_trace_set_snapshot "SHUTDOWN_PENDING" "SHUTDOWN" "OFF" "OFF" "$pt_completed_state" "$active"
            ;;
        SHUTDOWN_COMPLETE|SHUTDOWN_RECOVERED)
            power_trace_set_snapshot "OFF" "SHUTDOWN" "OFF" "OFF" "OFF" ""
            power_trace_clear_pending
            ;;
        REBOOT_BEGIN)
            power_trace_set_snapshot "REBOOT_PENDING" "REBOOT" "BOOTING" "RUNNING" "$pt_completed_state" "$corr"
            power_trace_mark_pending "REBOOT" "$corr" "$source_ref"
            ;;
        SLEEP_PREPARE_BEGIN|SLEEP_PREPARE_COMPLETE|SLEEP_REQUESTED|SLEEP_ENTER_BEGIN)
            power_trace_set_snapshot "SLEEP_PREP" "SLEEP" "SLEEPING" "RUNNING" "$pt_completed_state" "$corr"
            power_trace_mark_pending "SLEEP" "$corr" "$source_ref"
            ;;
        SLEEP_ENTER_COMPLETE)
            power_trace_set_snapshot "SLEEPING" "SLEEP" "SLEEPING" "SLEEPING" "$pt_completed_state" "$corr"
            ;;
        WAKE_DETECTED|WAKE_RESUME_BEGIN)
            power_trace_set_snapshot "WAKING" "WAKE" "RUNNING" "WAKING" "$pt_completed_state" "$corr"
            ;;
        WAKE_RESUME_COMPLETE)
            power_trace_set_snapshot "RUNNING" "WAKE" "RUNNING" "RUNNING" "RUNNING" ""
            power_trace_clear_pending
            ;;
        DIRTY_STARTUP)
            power_trace_set_snapshot "RUNNING" "RUNNING" "RUNNING" "RUNNING" "RUNNING" ""
            ;;
        TRANSITION_ABORTED|TRANSITION_TIMEOUT|REQUEST_SUPPRESSED|POWER_ERROR|UNKNOWN_TRANSITION|INVALID_TRANSITION)
            # Diagnostic/meta events should not advance canonical milestones.
            power_trace_set_snapshot "$pt_last_state" "$pt_requested_state" "$pt_intended_state" "$pt_observed_state" "$pt_completed_state" "$pt_active_transition_id"
            ;;
    esac
}

power_trace_emit() {
    power_trace_gate_enabled || return 0

    event="$1"
    prev_state="$2"
    intended_state="$3"
    observed_state="$4"
    trigger="$5"
    source_ref="$6"
    notes="$7"
    wake_source="$8"
    shutdown_reason="$9"
    autosave_context="${10}"
    autoresume_context="${11}"
    error_detail="${12}"
    timeout_ms="${13}"
    transition_origin="${14:-live}"

    mkdir -p "$POWER_TRACE_DIR"
    power_trace_load_state

    if ! power_trace_supported_event "$event"; then
        notes="unsupported_event=$event $notes"
        event="UNKNOWN_TRANSITION"
    fi

    if [ -z "$prev_state" ] || [ "$prev_state" = "AUTO" ]; then
        prev_state="${pt_last_state:-UNKNOWN}"
    fi

    if ! power_trace_validate_transition "$event" "$prev_state"; then
        invalid_note="event=${event} prev=${prev_state}"
        power_trace_emit "INVALID_TRANSITION" "$prev_state" "$intended_state" "$observed_state" "$trigger" "$source_ref" "$invalid_note" "$wake_source" "$shutdown_reason" "$autosave_context" "$autoresume_context" "$error_detail" "$timeout_ms" "$transition_origin"
        return 1
    fi

    if command -v trace_next_seq >/dev/null 2>&1; then
        pt_event_seq="$(trace_next_seq)"
    else
        pt_event_seq=$(( ${pt_event_seq:-0} + 1 ))
    fi
    corr="$(power_trace_new_correlation_id)"
    ts_mono="$(power_trace_monotonic_ts)"
    ts_wall="$(power_trace_wall_ts)"
    boot_session_id="$(power_trace_boot_id)"
    platform_id="${PLATFORM:-unknown}"
    build_id="$(power_trace_build)"

    target_caps=""
    target_notes=""
    if command -v device_power_trace_capabilities >/dev/null 2>&1; then
        target_caps="$(device_power_trace_capabilities 2>/dev/null)"
    fi
    if command -v device_power_trace_notes >/dev/null 2>&1; then
        target_notes="$(device_power_trace_notes 2>/dev/null)"
    fi

    if [ -n "$target_caps" ]; then
        notes="$notes capabilities:$target_caps"
    fi
    if [ -n "$target_notes" ]; then
        notes="$notes target_notes:$target_notes"
    fi

    json_notes="$(power_trace_escape_json "$notes")"
    json_trigger="$(power_trace_escape_json "$trigger")"
    json_src="$(power_trace_escape_json "$source_ref")"
    json_wake="$(power_trace_escape_json "$wake_source")"
    json_shutdown="$(power_trace_escape_json "$shutdown_reason")"
    json_auto_save="$(power_trace_escape_json "$autosave_context")"
    json_auto_resume="$(power_trace_escape_json "$autoresume_context")"
    json_error="$(power_trace_escape_json "$error_detail")"
    json_origin="$(power_trace_escape_json "$transition_origin")"

    json_line=$(printf '{"seq":%s,"domain":"power","event":"%s","ts_monotonic":"%s","ts_wall":"%s","boot_session_id":"%s","correlation_id":"%s","platform":"%s","build":"%s","prev_state":"%s","intended_state":"%s","observed_state":"%s","trigger":"%s","wake_source":"%s","shutdown_reason":"%s","autosave_context":"%s","autoresume_context":"%s","source":"%s","timeout_ms":"%s","error":"%s","transition_origin":"%s","notes":"%s"}' \
        "$pt_event_seq" "$event" "$ts_mono" "$ts_wall" "$boot_session_id" "$corr" "$platform_id" "$build_id" \
        "$prev_state" "$intended_state" "$observed_state" "$json_trigger" "$json_wake" "$json_shutdown" \
        "$json_auto_save" "$json_auto_resume" "$json_src" "$timeout_ms" "$json_error" "$json_origin" "$json_notes")

    summary_line=$(printf '%s | %s | origin=%s prev=%s intended=%s observed=%s trigger=%s notes=%s' \
        "$ts_wall" "$event" "$transition_origin" "$prev_state" "$intended_state" "$observed_state" "$trigger" "$notes")

    if command -v trace_emit_core >/dev/null 2>&1; then
        trace_emit_core "$POWER_TRACE_EVENTS_FILE" "$POWER_TRACE_SUMMARY_FILE" "$POWER_TRACE_MAX_EVENTS" "$POWER_TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"
    else
        printf '%s\n' "$json_line" >> "$POWER_TRACE_EVENTS_FILE"
        printf '%s\n' "$summary_line" >> "$POWER_TRACE_SUMMARY_FILE"
        power_trace_trim_file "$POWER_TRACE_EVENTS_FILE" "$POWER_TRACE_MAX_EVENTS"
        power_trace_trim_file "$POWER_TRACE_SUMMARY_FILE" "$POWER_TRACE_MAX_SUMMARY_LINES"
    fi

    power_trace_apply_snapshot "$event" "$corr" "$source_ref" "$observed_state"

    power_trace_save_state
}

power_trace_mark_pending() {
    pending_kind="$1"
    correlation_id="$2"
    source_ref="$3"
    cat > "$POWER_TRACE_PENDING_FILE.tmp.$$" <<EOF_PENDING
pending_kind="$pending_kind"
pending_correlation_id="$correlation_id"
pending_source="$source_ref"
pending_wall_ts="$(power_trace_wall_ts)"
pending_boot_id="$(power_trace_boot_id)"
EOF_PENDING
    mv "$POWER_TRACE_PENDING_FILE.tmp.$$" "$POWER_TRACE_PENDING_FILE"
}

power_trace_clear_pending() {
    rm -f "$POWER_TRACE_PENDING_FILE"
}

power_trace_boot_reconcile_pending() {
    [ -f "$POWER_TRACE_PENDING_FILE" ] || return 0
    power_trace_load_state
    # shellcheck disable=SC1090
    . "$POWER_TRACE_PENDING_FILE"

    pending_key="${pending_kind:-UNKNOWN}:${pending_correlation_id:-none}"
    if [ "$pt_last_reconciled_pending_key" = "$pending_key" ]; then
        power_trace_clear_pending
        return 0
    fi

    emitted=0
    case "$pending_kind" in
        SLEEP)
            power_trace_emit "WAKE_DETECTED" "UNKNOWN" "RUNNING" "RUNNING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Wake observed during new boot session without WAKE_RESUME_COMPLETE in prior session" "unknown" "" "" "" "" "" "recovered" &&
            power_trace_emit "UNKNOWN_TRANSITION" "UNKNOWN" "RUNNING" "RUNNING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Pending sleep transition remained across reboot; possible crash/restart during sleep handling" "" "" "" "" "" "" "recovered" && emitted=1
            ;;
        SHUTDOWN)
            power_trace_emit "SHUTDOWN_RECOVERED" "SHUTDOWN_PENDING" "OFF" "OFF" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Recovered shutdown completion from pending marker after boot" "" "normal" "" "" "" "" "recovered" && emitted=1
            ;;
        REBOOT)
            power_trace_emit "BOOT_BEGIN" "UNKNOWN" "BOOTING" "BOOTING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Reboot path inferred from pending reboot marker; recovered path" "" "" "" "" "" "" "recovered" && emitted=1
            ;;
        *)
            power_trace_emit "UNKNOWN_TRANSITION" "UNKNOWN" "RUNNING" "RUNNING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Unknown pending marker during boot reconcile" "" "" "" "" "" "" "recovered" && emitted=1
            ;;
    esac

    if [ "$emitted" -eq 1 ]; then
        pt_last_reconciled_pending_key="$pending_key"
        power_trace_save_state
        power_trace_clear_pending
    fi
}

# Shared canonical predicate for callers that must suppress sleep or duplicate
# shutdown work once shutdown has already begun.
power_trace_shutdown_pending() {
    power_trace_load_state

    if [ "${pt_last_state:-}" = "SHUTDOWN_PENDING" ] ||
        { [ "${pt_requested_state:-}" = "SHUTDOWN" ] && [ "${pt_active_transition_id:-}" != "" ]; }; then
        return 0
    fi

    if [ -f "$POWER_TRACE_PENDING_FILE" ]; then
        # shellcheck disable=SC1090
        . "$POWER_TRACE_PENDING_FILE"
        [ "${pending_kind:-}" = "SHUTDOWN" ] && return 0
    fi

    return 1
}

power_trace_recent_json() {
    count="${1:-40}"
    if [ -f "$POWER_TRACE_EVENTS_FILE" ]; then
        tail -n "$count" "$POWER_TRACE_EVENTS_FILE"
    fi
}
