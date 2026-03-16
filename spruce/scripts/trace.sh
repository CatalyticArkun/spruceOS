#!/bin/sh

TRACE_ROOT="${TRACE_ROOT:-/mnt/SDCARD/Saves/spruce}"
TRACE_DIR="${TRACE_DIR:-$TRACE_ROOT/trace}"
TRACE_EVENTS_FILE="${TRACE_EVENTS_FILE:-$TRACE_DIR/events.jsonl}"
TRACE_SUMMARY_FILE="${TRACE_SUMMARY_FILE:-$TRACE_DIR/summary.txt}"
TRACE_STATE_FILE="${TRACE_STATE_FILE:-$TRACE_DIR/state.env}"
TRACE_MAX_EVENTS="${TRACE_MAX_EVENTS:-400}"
TRACE_MAX_SUMMARY_LINES="${TRACE_MAX_SUMMARY_LINES:-120}"
POWER_TRACE_DIR="${POWER_TRACE_DIR:-$TRACE_ROOT/power}"
POWER_TRACE_EVENTS_FILE="${POWER_TRACE_EVENTS_FILE:-$POWER_TRACE_DIR/events.jsonl}"
POWER_TRACE_SUMMARY_FILE="${POWER_TRACE_SUMMARY_FILE:-$POWER_TRACE_DIR/summary.txt}"
TRACE_ENABLED="${TRACE_ENABLED:-1}"
POWER_TRACE_ENABLED="${POWER_TRACE_ENABLED:-1}"
AUDIO_TRACE_ENABLED="${AUDIO_TRACE_ENABLED:-1}"
NETWORK_TRACE_ENABLED="${NETWORK_TRACE_ENABLED:-${WIFI_TRACE_ENABLED:-1}}"
BRIGHTNESS_TRACE_ENABLED="${BRIGHTNESS_TRACE_ENABLED:-1}"
TRACE_GATE_DIR="${TRACE_GATE_DIR:-/tmp/spruce_trace_gates}"
TRACE_STATE_FLUSH_INTERVAL="${TRACE_STATE_FLUSH_INTERVAL:-20}"
TRACE_TRIM_INTERVAL="${TRACE_TRIM_INTERVAL:-20}"

trace_state_loaded=0
trace_dirs_ready=0
trace_trim_counter=0
trace_unknown_domain_warned=""
trace_cached_boot_id=""
trace_cached_build_id=""

trace_normalize_subsystem() {
    case "$1" in
        wifi|network|networking)
            printf '%s\n' "networking"
            ;;
        power|audio|brightness)
            printf '%s\n' "$1"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

trace_gate_enabled() {
    subsystem="$(trace_normalize_subsystem "$1")"

    [ "$TRACE_ENABLED" = "0" ] && return 1
    [ -f "$TRACE_GATE_DIR/trace.off" ] && return 1

    case "$subsystem" in
        power)
            [ "$POWER_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/power.off" ] && return 1
            ;;
        audio)
            [ "$AUDIO_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/audio.off" ] && return 1
            ;;
        networking)
            [ "$NETWORK_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/networking.off" ] && return 1
            [ -f "$TRACE_GATE_DIR/wifi.off" ] && return 1
            ;;
        brightness)
            [ "$BRIGHTNESS_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/brightness.off" ] && return 1
            ;;
        *)
            case " $trace_unknown_domain_warned " in
                *" $subsystem "*)
                    ;;
                *)
                    trace_unknown_domain_warned="$trace_unknown_domain_warned $subsystem"
                    printf '%s\n' "trace_gate_enabled: unknown subsystem '$subsystem'" >&2
                    ;;
            esac
            return 1
            ;;
    esac

    return 0
}

trace_monotonic_ts() {
    awk '{print $1}' /proc/uptime 2>/dev/null
}

trace_wall_ts() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

trace_boot_id() {
    if [ -z "$trace_cached_boot_id" ]; then
        if [ -r /proc/sys/kernel/random/boot_id ]; then
            trace_cached_boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
        fi
        [ -n "$trace_cached_boot_id" ] || trace_cached_boot_id="boot-unknown"
    fi
    printf '%s\n' "$trace_cached_boot_id"
}

trace_build() {
    if [ -z "$trace_cached_build_id" ]; then
        trace_cached_build_id="$(cat /etc/version 2>/dev/null)"
        [ -n "$trace_cached_build_id" ] || trace_cached_build_id="unknown"
    fi
    printf '%s\n' "$trace_cached_build_id"
}

trace_escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

trace_trim_file() {
    file="$1"
    max_lines="$2"
    [ -f "$file" ] || return 0
    count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if [ "$count" -gt "$max_lines" ]; then
        tail -n "$max_lines" "$file" > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
    fi
}

trace_load_state() {
    [ "$trace_state_loaded" = "1" ] && return 0
    trace_ensure_dirs
    if [ -f "$TRACE_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$TRACE_STATE_FILE"
    fi
    [ -n "${trace_seq:-}" ] || trace_seq=0
    trace_state_loaded=1
}

trace_save_state() {
    trace_ensure_dirs
    umask 077
    cat > "$TRACE_STATE_FILE.tmp.$$" <<EOF_STATE
trace_seq="$trace_seq"
EOF_STATE
    mv "$TRACE_STATE_FILE.tmp.$$" "$TRACE_STATE_FILE"
}

trace_ensure_dirs() {
    [ "$trace_dirs_ready" = "1" ] && return 0
    mkdir -p "$TRACE_DIR"
    mkdir -p "$(dirname "$TRACE_EVENTS_FILE")"
    mkdir -p "$(dirname "$TRACE_SUMMARY_FILE")"
    trace_dirs_ready=1
}

trace_next_seq() {
    trace_load_state
    trace_seq=$(( ${trace_seq:-0} + 1 ))
    printf '%s\n' "$trace_seq"

    flush_interval="$TRACE_STATE_FLUSH_INTERVAL"
    case "$flush_interval" in
        ''|*[!0-9]*) flush_interval=20 ;;
    esac
    if [ ! -f "$TRACE_STATE_FILE" ] || [ "$flush_interval" -le 1 ] || [ $((trace_seq % flush_interval)) -eq 0 ]; then
        trace_save_state
    fi
}

trace_emit_core() {
    events_file="$1"
    summary_file="$2"
    max_events="$3"
    max_summary="$4"
    json_line="$5"
    summary_line="$6"

    trace_ensure_dirs
    mkdir -p "$(dirname "$events_file")"
    mkdir -p "$(dirname "$summary_file")"
    printf '%s\n' "$json_line" >> "$events_file"
    printf '%s\n' "$summary_line" >> "$summary_file"

    trace_trim_counter=$((trace_trim_counter + 1))
    trim_interval="$TRACE_TRIM_INTERVAL"
    case "$trim_interval" in
        ''|*[!0-9]*) trim_interval=20 ;;
    esac
    if [ "$trim_interval" -le 1 ] || [ $((trace_trim_counter % trim_interval)) -eq 0 ]; then
        trace_trim_file "$events_file" "$max_events"
        trace_trim_file "$summary_file" "$max_summary"
    fi
}

trace_subsystem_dir() {
    subsystem="$(trace_normalize_subsystem "$1")"
    printf '%s/%s\n' "$TRACE_ROOT" "$subsystem"
}

trace_subsystem_events_file() {
    printf '%s/events.jsonl\n' "$(trace_subsystem_dir "$1")"
}

trace_subsystem_summary_file() {
    printf '%s/summary.txt\n' "$(trace_subsystem_dir "$1")"
}

trace_build_json_line() {
    seq="$1"
    subsystem="$2"
    current_state="$3"
    requested_state="$4"
    source_ref="$5"
    context="$6"
    ts_mono="$7"
    ts_wall="$8"
    boot_session_id="$9"
    platform_id="${10}"
    build_id="${11}"

    printf '{"seq":%s,"subsystem":"%s","current_state":"%s","requested_state":"%s","source":"%s","context":"%s","ts_monotonic":"%s","ts_wall":"%s","boot_session_id":"%s","platform":"%s","build":"%s"}' \
        "$seq" \
        "$(trace_escape_json "$subsystem")" \
        "$(trace_escape_json "$current_state")" \
        "$(trace_escape_json "$requested_state")" \
        "$(trace_escape_json "$source_ref")" \
        "$(trace_escape_json "$context")" \
        "$ts_mono" \
        "$ts_wall" \
        "$boot_session_id" \
        "$platform_id" \
        "$build_id"
}

trace_build_summary_line() {
    ts_wall="$1"
    subsystem="$2"
    current_state="$3"
    requested_state="$4"
    source_ref="$5"
    context="$6"

    printf '%s | %s current=%s requested=%s source=%s context=%s' \
        "$ts_wall" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

trace_write_system_emit() {
    subsystem="$(trace_normalize_subsystem "$1")"
    current_state="${2:-UNKNOWN}"
    requested_state="${3:-$current_state}"
    source_ref="${4:-unknown}"
    context="${5:-}"

    [ -n "$current_state" ] || current_state="UNKNOWN"
    [ -n "$requested_state" ] || requested_state="$current_state"
    [ -n "$source_ref" ] || source_ref="unknown"

    trace_gate_enabled "$subsystem" || return 0

    trace_next_seq >/dev/null
    seq="$trace_seq"
    ts_mono="$(trace_monotonic_ts)"
    ts_wall="$(trace_wall_ts)"
    boot_session_id="$(trace_boot_id)"
    platform_id="${PLATFORM:-unknown}"
    build_id="$(trace_build)"

    json_line="$(trace_build_json_line "$seq" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context" "$ts_mono" "$ts_wall" "$boot_session_id" "$platform_id" "$build_id")"
    summary_line="$(trace_build_summary_line "$ts_wall" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context")"

    trace_emit_core "$TRACE_EVENTS_FILE" "$TRACE_SUMMARY_FILE" "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"
    trace_emit_core "$(trace_subsystem_events_file "$subsystem")" "$(trace_subsystem_summary_file "$subsystem")" "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"
}

system_emit() {
    [ "$#" -ge 4 ] || return 1

    subsystem="$(trace_normalize_subsystem "$1")"
    current_state="${2:-UNKNOWN}"
    requested_state="${3:-$current_state}"
    source_ref="${4:-unknown}"
    shift 4
    context="$*"

    trace_write_system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

trace_compat_emit() {
    subsystem="$(trace_normalize_subsystem "$1")"
    event="$2"
    shift 2

    source_ref="${subsystem}:legacy"
    current_state="UNKNOWN"
    requested_state="UNKNOWN"
    context="$event"

    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        [ "$key" = "$val" ] && val=""

        case "$key" in
            source)
                [ -n "$val" ] && source_ref="$val"
                ;;
            current|current_state)
                [ -n "$val" ] && current_state="$val"
                ;;
            requested|requested_state|target)
                [ -n "$val" ] && requested_state="$val"
                ;;
        esac

        if [ -n "$val" ]; then
            context="$context ${key}=${val}"
        else
            context="$context ${key}"
        fi
    done

    system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

trace_emit() {
    subsystem="$1"
    event="$2"
    shift 2
    trace_compat_emit "$subsystem" "$event" "$@"
}

power_trace_emit() {
    if [ "$#" -eq 4 ]; then
        system_emit "power" "$1" "$2" "$3" "$4"
        return
    fi

    event="$1"
    prev_state="${2:-UNKNOWN}"
    intended_state="${3:-$prev_state}"
    observed_state="${4:-$prev_state}"
    source_ref="${6:-power_trace_emit}"
    shift 6 2>/dev/null || true

    case "$observed_state" in
        ''|AUTO) current_state="$prev_state" ;;
        *) current_state="$observed_state" ;;
    esac
    case "$current_state" in
        ''|AUTO) current_state="UNKNOWN" ;;
    esac
    case "$intended_state" in
        ''|AUTO) requested_state="$current_state" ;;
        *) requested_state="$intended_state" ;;
    esac

    context="$event"
    for extra in "$@"; do
        [ -n "$extra" ] || continue
        context="$context $extra"
    done

    system_emit "power" "$current_state" "$requested_state" "$source_ref" "$context"
}

power_trace_boot_reconcile_pending() {
    return 0
}

power_trace_shutdown_pending() {
    return 1
}

power_trace_recent_json() {
    count="${1:-40}"
    if [ -f "$POWER_TRACE_EVENTS_FILE" ]; then
        tail -n "$count" "$POWER_TRACE_EVENTS_FILE"
    fi
}

audio_trace_emit() {
    if [ "$#" -eq 4 ]; then
        system_emit "audio" "$1" "$2" "$3" "$4"
        return
    fi
    trace_compat_emit "audio" "$@"
}

network_trace_emit() {
    if [ "$#" -eq 4 ]; then
        system_emit "networking" "$1" "$2" "$3" "$4"
        return
    fi
    trace_compat_emit "networking" "$@"
}

wifi_trace_emit() {
    network_trace_emit "$@"
}

brightness_trace_emit() {
    if [ "$#" -eq 4 ]; then
        system_emit "brightness" "$1" "$2" "$3" "$4"
        return
    fi
    trace_compat_emit "brightness" "$@"
}
