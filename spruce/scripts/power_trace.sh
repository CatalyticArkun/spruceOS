#!/bin/sh

POWER_TRACE_DIR="${POWER_TRACE_DIR:-/mnt/SDCARD/Saves/spruce/power}"
POWER_TRACE_EVENTS_FILE="$POWER_TRACE_DIR/events.jsonl"
POWER_TRACE_SUMMARY_FILE="$POWER_TRACE_DIR/summary.txt"
POWER_TRACE_STATE_FILE="$POWER_TRACE_DIR/state.env"
POWER_TRACE_PENDING_FILE="$POWER_TRACE_DIR/pending.env"
POWER_TRACE_MAX_EVENTS="${POWER_TRACE_MAX_EVENTS:-400}"
POWER_TRACE_MAX_SUMMARY_LINES="${POWER_TRACE_MAX_SUMMARY_LINES:-120}"

power_trace_supported_event() {
    case "$1" in
        BOOT_BEGIN|BOOT_COMPLETE|SHUTDOWN_BEGIN|SHUTDOWN_COMPLETE|REBOOT_BEGIN|SLEEP_PREPARE_BEGIN|SLEEP_PREPARE_COMPLETE|SLEEP_REQUESTED|SLEEP_ENTER_BEGIN|SLEEP_ENTER_COMPLETE|WAKE_DETECTED|WAKE_RESUME_BEGIN|WAKE_RESUME_COMPLETE|TRANSITION_ABORTED|TRANSITION_TIMEOUT|INVALID_TRANSITION|POWER_ERROR|UNKNOWN_TRANSITION)
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

power_trace_state_defaults() {
    [ -n "${pt_boot_session_id:-}" ] || pt_boot_session_id="$(power_trace_boot_id)"
    [ -n "${pt_last_state:-}" ] || pt_last_state="UNKNOWN"
    [ -n "${pt_intended_state:-}" ] || pt_intended_state="UNKNOWN"
    [ -n "${pt_requested_state:-}" ] || pt_requested_state="UNKNOWN"
    [ -n "${pt_observed_state:-}" ] || pt_observed_state="UNKNOWN"
    [ -n "${pt_completed_state:-}" ] || pt_completed_state="UNKNOWN"
    [ -n "${pt_active_transition_id:-}" ] || pt_active_transition_id=""
    [ -n "${pt_event_seq:-}" ] || pt_event_seq="0"
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
pt_boot_session_id="$pt_boot_session_id"
pt_last_state="$pt_last_state"
pt_intended_state="$pt_intended_state"
pt_requested_state="$pt_requested_state"
pt_observed_state="$pt_observed_state"
pt_completed_state="$pt_completed_state"
pt_active_transition_id="$pt_active_transition_id"
pt_event_seq="$pt_event_seq"
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
        echo "${pt_active_transition_id:-}"
        return
    fi
    echo "pt-$(date +%s)-$$-${pt_event_seq:-0}"
}

power_trace_validate_transition() {
    event="$1"
    prev="$2"

    case "$event" in
        BOOT_BEGIN)
            return 0
            ;;
        BOOT_COMPLETE)
            [ "$prev" = "BOOTING" ] && return 0
            ;;
        SHUTDOWN_BEGIN)
            [ "$prev" = "RUNNING" ] || [ "$prev" = "WAKING" ] || [ "$prev" = "UNKNOWN" ] && return 0
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
        TRANSITION_ABORTED|TRANSITION_TIMEOUT|POWER_ERROR|UNKNOWN_TRANSITION|INVALID_TRANSITION)
            return 0
            ;;
    esac

    return 1
}

power_trace_emit() {
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

    mkdir -p "$POWER_TRACE_DIR"
    power_trace_load_state

    if ! power_trace_supported_event "$event"; then
        notes="unsupported_event=$event ${notes}"
        event="UNKNOWN_TRANSITION"
    fi

    if [ -z "$prev_state" ] || [ "$prev_state" = "AUTO" ]; then
        prev_state="${pt_last_state:-UNKNOWN}"
    fi

    if ! power_trace_validate_transition "$event" "$prev_state"; then
        invalid_note="event=${event} prev=${prev_state}"
        power_trace_emit "INVALID_TRANSITION" "$prev_state" "$intended_state" "$observed_state" "$trigger" "$source_ref" "$invalid_note" "$wake_source" "$shutdown_reason" "$autosave_context" "$autoresume_context" "$error_detail" "$timeout_ms"
    fi

    pt_event_seq=$(( ${pt_event_seq:-0} + 1 ))
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
        notes="${notes} capabilities:${target_caps}"
    fi
    if [ -n "$target_notes" ]; then
        notes="${notes} target_notes:${target_notes}"
    fi

    json_notes=$(printf '%s' "$notes" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_trigger=$(printf '%s' "$trigger" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_src=$(printf '%s' "$source_ref" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_wake=$(printf '%s' "$wake_source" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_shutdown=$(printf '%s' "$shutdown_reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_auto_save=$(printf '%s' "$autosave_context" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_auto_resume=$(printf '%s' "$autoresume_context" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json_error=$(printf '%s' "$error_detail" | sed 's/\\/\\\\/g; s/"/\\"/g')

    printf '{"seq":%s,"event":"%s","ts_monotonic":"%s","ts_wall":"%s","boot_session_id":"%s","correlation_id":"%s","platform":"%s","build":"%s","prev_state":"%s","intended_state":"%s","observed_state":"%s","trigger":"%s","wake_source":"%s","shutdown_reason":"%s","autosave_context":"%s","autoresume_context":"%s","source":"%s","timeout_ms":"%s","error":"%s","notes":"%s"}\n' \
        "$pt_event_seq" "$event" "$ts_mono" "$ts_wall" "$boot_session_id" "$corr" "$platform_id" "$build_id" \
        "$prev_state" "$intended_state" "$observed_state" "$json_trigger" "$json_wake" "$json_shutdown" \
        "$json_auto_save" "$json_auto_resume" "$json_src" "$timeout_ms" "$json_error" "$json_notes" >> "$POWER_TRACE_EVENTS_FILE"

    printf '%s | %s | prev=%s intended=%s observed=%s trigger=%s notes=%s\n' \
        "$ts_wall" "$event" "$prev_state" "$intended_state" "$observed_state" "$trigger" "$notes" >> "$POWER_TRACE_SUMMARY_FILE"

    case "$event" in
        BOOT_BEGIN)
            pt_last_state="BOOTING"
            pt_requested_state="BOOTING"
            pt_intended_state="BOOTING"
            ;;
        BOOT_COMPLETE)
            pt_last_state="RUNNING"
            pt_completed_state="RUNNING"
            pt_active_transition_id=""
            ;;
        SHUTDOWN_BEGIN)
            pt_last_state="SHUTDOWN_PENDING"
            pt_requested_state="SHUTDOWN"
            pt_intended_state="OFF"
            pt_active_transition_id="$corr"
            power_trace_mark_pending "SHUTDOWN" "$corr" "$source_ref"
            ;;
        REBOOT_BEGIN)
            pt_last_state="REBOOT_PENDING"
            pt_requested_state="REBOOT"
            pt_intended_state="BOOTING"
            pt_active_transition_id="$corr"
            power_trace_mark_pending "REBOOT" "$corr" "$source_ref"
            ;;
        SLEEP_PREPARE_BEGIN|SLEEP_PREPARE_COMPLETE|SLEEP_REQUESTED|SLEEP_ENTER_BEGIN)
            pt_last_state="SLEEP_PREP"
            pt_requested_state="SLEEP"
            pt_intended_state="SLEEPING"
            pt_active_transition_id="$corr"
            power_trace_mark_pending "SLEEP" "$corr" "$source_ref"
            ;;
        SLEEP_ENTER_COMPLETE)
            pt_last_state="SLEEPING"
            pt_observed_state="SLEEPING"
            ;;
        WAKE_DETECTED|WAKE_RESUME_BEGIN)
            pt_last_state="WAKING"
            pt_requested_state="WAKE"
            pt_intended_state="RUNNING"
            pt_active_transition_id="$corr"
            ;;
        WAKE_RESUME_COMPLETE)
            pt_last_state="RUNNING"
            pt_completed_state="RUNNING"
            pt_active_transition_id=""
            power_trace_clear_pending
            ;;
        TRANSITION_ABORTED|TRANSITION_TIMEOUT|POWER_ERROR|UNKNOWN_TRANSITION|INVALID_TRANSITION)
            ;;
    esac

    power_trace_save_state
    power_trace_trim_file "$POWER_TRACE_EVENTS_FILE" "$POWER_TRACE_MAX_EVENTS"
    power_trace_trim_file "$POWER_TRACE_SUMMARY_FILE" "$POWER_TRACE_MAX_SUMMARY_LINES"
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
    # shellcheck disable=SC1090
    . "$POWER_TRACE_PENDING_FILE"

    case "$pending_kind" in
        SLEEP)
            power_trace_emit "WAKE_DETECTED" "UNKNOWN" "RUNNING" "RUNNING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Wake observed during new boot session without WAKE_RESUME_COMPLETE in prior session" "unknown" "" "" "" "" ""
            power_trace_emit "UNKNOWN_TRANSITION" "UNKNOWN" "RUNNING" "RUNNING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Pending sleep transition remained across reboot; possible crash/restart during sleep handling" "" "" "" "" "" ""
            ;;
        SHUTDOWN)
            power_trace_emit "SHUTDOWN_COMPLETE" "SHUTDOWN_PENDING" "OFF" "OFF" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Inferred completion from subsequent boot" "" "normal" "" "" "" ""
            ;;
        REBOOT)
            power_trace_emit "BOOT_BEGIN" "UNKNOWN" "BOOTING" "BOOTING" "boot_reconcile" "runtime.sh:power_trace_boot_reconcile_pending" "Reboot path inferred from pending reboot marker" "" "" "" "" "" ""
            ;;
    esac

    power_trace_clear_pending
}

power_trace_recent_json() {
    count="${1:-40}"
    if [ -f "$POWER_TRACE_EVENTS_FILE" ]; then
        tail -n "$count" "$POWER_TRACE_EVENTS_FILE"
    fi
}
