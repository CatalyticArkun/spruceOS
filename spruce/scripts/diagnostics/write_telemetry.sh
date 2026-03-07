#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
PHASE="$2"
RUN_ID="$3"
BOOT_ID="$4"
OUT="$RUN_DIR/summary/telemetry_event.json"
mkdir -p "$RUN_DIR/summary"

DEVICE_HOST=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)
KERNEL=$(uname -r 2>/dev/null || echo unknown)
BUILD=$(cat /etc/version 2>/dev/null || echo unknown)
BUNDLE_VERSION=$(get_bundle_version)
TS=$(timestamp_utc)
POWER_SUMMARY_FILE="$RUN_DIR/summary/power_trace.summary.txt"
POWER_EVENTS_FILE="$RUN_DIR/raw/power_trace.events.jsonl"
POWER_SUMMARY=$(tail -n 20 "$POWER_SUMMARY_FILE" 2>/dev/null | sed 's/"/\\"/g' | awk 'BEGIN{printf ""} {if (NR>1) printf "\n"; printf "%s", $0}')
if [ -f "$POWER_EVENTS_FILE" ]; then
    POWER_EVENT_COUNT=$(wc -l < "$POWER_EVENTS_FILE")
else
    POWER_EVENT_COUNT=0
fi

SIG_JSON=$(awk -F'|' 'BEGIN{printf "["} {if (NR>1) printf ","; printf "{\"key\":\"%s\",\"tier\":\"%s\",\"category\":\"%s\",\"count\":%s}",$1,$2,$3,$4} END{printf "]"}' "$RUN_DIR/curated/signature_counts.txt" 2>/dev/null || echo "[]")
RES_JSON=$(cat "$RUN_DIR/results/check_results.txt" "$RUN_DIR/results/mustard_check_results.txt" 2>/dev/null | awk 'BEGIN{printf "["} /^RESULT / {if (n++) printf ","; id="";v="";s="";c="";e=""; for(i=1;i<=NF;i++){split($i,a,"="); if(a[1]=="id")id=a[2]; else if(a[1]=="verdict")v=a[2]; else if(a[1]=="severity")s=a[2]; else if(a[1]=="confidence")c=a[2]; else if(a[1]=="evidence")e=a[2];} printf "{\"id\":\"%s\",\"verdict\":\"%s\",\"severity\":\"%s\",\"confidence\":\"%s\",\"evidence\":\"%s\"}",id,v,s,c,e} END{printf "]"}')

cat > "$OUT" <<JSON
{
  "device_identity": "$(json_escape "$DEVICE_HOST")",
  "kernel": "$(json_escape "$KERNEL")",
  "build": "$(json_escape "$BUILD")",
  "bundle_version": "$(json_escape "$BUNDLE_VERSION")",
  "run_id": "$(json_escape "$RUN_ID")",
  "boot_id": "$(json_escape "$BOOT_ID")",
  "timestamp": "$(json_escape "$TS")",
  "phase_completed": "$(json_escape "$PHASE")",
  "signatures": $SIG_JSON,
  "detector_results": $RES_JSON,
  "power_trace_event_count": "$(json_escape "$POWER_EVENT_COUNT")",
  "power_trace_recent_summary": "$(json_escape "$POWER_SUMMARY")"
}
JSON

printf '%s\n' "$(tr -d '\n' < "$OUT")" >> "$TELEMETRY_LOG"
