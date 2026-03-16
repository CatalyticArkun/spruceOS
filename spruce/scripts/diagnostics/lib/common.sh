#!/bin/sh

SD_ROOT="${SD_ROOT:-/mnt/SDCARD}"
SPRUCE_ROOT="$SD_ROOT/spruce"
SPRUCE_SCRIPTS_DIR="$SPRUCE_ROOT/scripts"
FLAGS_DIR="$SPRUCE_ROOT/flags"
LOG_ROOT="$SD_ROOT/Saves/spruce"
POWER_LOG_ROOT="$LOG_ROOT/power"
DIAG_ROOT="$LOG_ROOT/diag"
RUNS_DIR="$DIAG_ROOT/runs"
LATEST_DIR="$DIAG_ROOT/latest"
STATE_DIR="$DIAG_ROOT/state"
TELEMETRY_LOG="$DIAG_ROOT/telemetry.jsonl"
BUNDLE_VERSION_FILE="$SPRUCE_ROOT/scripts/diagnostics/bundle_version.txt"

mkdir -p "$FLAGS_DIR" "$LOG_ROOT" "$DIAG_ROOT" "$RUNS_DIR" "$LATEST_DIR" "$STATE_DIR"

get_bundle_version() {
    if [ -f "$BUNDLE_VERSION_FILE" ]; then
        tr -d '[:space:]' < "$BUNDLE_VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

atomic_write() {
    target="$1"
    shift
    tmp="${target}.tmp.$$"
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$*" > "$tmp"
    mv "$tmp" "$target"
}

flag_exists() {
    [ -f "$FLAGS_DIR/$1" ] || [ -f "$FLAGS_DIR/$1.lock" ]
}

boot_id() {
    if [ -r /proc/sys/kernel/random/boot_id ]; then
        cat /proc/sys/kernel/random/boot_id
    else
        date +%s
    fi
}

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

json_escape() {
    printf '%s' "$1" | awk 'BEGIN{RS=""; ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); gsub(/\n/,"\\n"); print}'
}

uptime_seconds() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0
}

clock_sane() {
    y=$(date -u +%Y 2>/dev/null || echo 1970)
    [ "$y" -ge 2020 ] && echo 1 || echo 0
}
