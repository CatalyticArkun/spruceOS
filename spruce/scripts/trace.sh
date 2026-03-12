#!/bin/sh

TRACE_DIR="${TRACE_DIR:-/mnt/SDCARD/Saves/spruce/trace}"
TRACE_EVENTS_FILE="${TRACE_EVENTS_FILE:-$TRACE_DIR/events.jsonl}"
TRACE_SUMMARY_FILE="${TRACE_SUMMARY_FILE:-$TRACE_DIR/summary.txt}"
TRACE_STATE_FILE="${TRACE_STATE_FILE:-$TRACE_DIR/state.env}"
TRACE_MAX_EVENTS="${TRACE_MAX_EVENTS:-400}"
TRACE_MAX_SUMMARY_LINES="${TRACE_MAX_SUMMARY_LINES:-120}"
TRACE_ENABLED="${TRACE_ENABLED:-1}"
POWER_TRACE_ENABLED="${POWER_TRACE_ENABLED:-1}"
AUDIO_TRACE_ENABLED="${AUDIO_TRACE_ENABLED:-1}"
WIFI_TRACE_ENABLED="${WIFI_TRACE_ENABLED:-1}"
TRACE_GATE_DIR="${TRACE_GATE_DIR:-/tmp/spruce_trace_gates}"

trace_gate_enabled() {
    domain="$1"

    [ "$TRACE_ENABLED" = "0" ] && return 1
    [ -f "$TRACE_GATE_DIR/trace.off" ] && return 1

    case "$domain" in
        power)
            [ "$POWER_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/power.off" ] && return 1
            ;;
        audio)
            [ "$AUDIO_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/audio.off" ] && return 1
            ;;
        wifi)
            [ "$WIFI_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/wifi.off" ] && return 1
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
    if [ -r /proc/sys/kernel/random/boot_id ]; then
        cat /proc/sys/kernel/random/boot_id
    else
        echo "boot-$(date +%s)"
    fi
}

trace_build() {
    cat /etc/version 2>/dev/null || echo "unknown"
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
    mkdir -p "$TRACE_DIR"
    if [ -f "$TRACE_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$TRACE_STATE_FILE"
    fi
    [ -n "${trace_seq:-}" ] || trace_seq=0
}

trace_save_state() {
    umask 077
    cat > "$TRACE_STATE_FILE.tmp.$$" <<EOF_STATE
trace_seq="$trace_seq"
EOF_STATE
    mv "$TRACE_STATE_FILE.tmp.$$" "$TRACE_STATE_FILE"
}

trace_next_seq() {
    trace_load_state
    trace_seq=$(( ${trace_seq:-0} + 1 ))
    trace_save_state
    echo "$trace_seq"
}

trace_emit_core() {
    events_file="$1"
    summary_file="$2"
    max_events="$3"
    max_summary="$4"
    json_line="$5"
    summary_line="$6"

    mkdir -p "$(dirname "$events_file")"
    mkdir -p "$(dirname "$summary_file")"
    printf '%s\n' "$json_line" >> "$events_file"
    printf '%s\n' "$summary_line" >> "$summary_file"
    trace_trim_file "$events_file" "$max_events"
    trace_trim_file "$summary_file" "$max_summary"
}

trace_emit() {
    domain="$1"
    event="$2"
    shift 2

    trace_gate_enabled "$domain" || return 0

    seq="$(trace_next_seq)"
    ts_mono="$(trace_monotonic_ts)"
    ts_wall="$(trace_wall_ts)"
    boot_session_id="$(trace_boot_id)"
    platform_id="${PLATFORM:-unknown}"
    build_id="$(trace_build)"

    extras_json=""
    summary_extra=""
    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        [ -n "$key" ] || continue
        if [ "$key" = "$val" ]; then
            val=""
        fi
        json_key="$(trace_escape_json "$key")"
        json_val="$(trace_escape_json "$val")"
        extras_json="$extras_json,\"$json_key\":\"$json_val\""
        summary_extra="$summary_extra $key=$val"
    done

    json_line=$(printf '{"seq":%s,"domain":"%s","event":"%s","ts_monotonic":"%s","ts_wall":"%s","boot_session_id":"%s","platform":"%s","build":"%s"%s}' \
        "$seq" "$(trace_escape_json "$domain")" "$(trace_escape_json "$event")" "$ts_mono" "$ts_wall" "$boot_session_id" "$platform_id" "$build_id" "$extras_json")
    summary_line=$(printf '%s | %s/%s%s' "$ts_wall" "$domain" "$event" "$summary_extra")

    trace_emit_core "$TRACE_EVENTS_FILE" "$TRACE_SUMMARY_FILE" "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"
}

audio_trace_emit() {
    event="$1"
    shift
    trace_emit "audio" "$event" "$@"
}

wifi_trace_emit() {
    event="$1"
    shift
    trace_emit "wifi" "$event" "$@"
}
