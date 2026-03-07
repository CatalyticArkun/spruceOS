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
UPTIME_SECONDS=$(uptime_seconds)
CLOCK_SANE=$(clock_sane)

SIG_JSON=$(awk -F'|' 'BEGIN{printf "["} {if (NR>1) printf ","; printf "{\"key\":\"%s\",\"tier\":\"%s\",\"category\":\"%s\",\"count\":%s}",$1,$2,$3,$4} END{printf "]"}' "$RUN_DIR/curated/signature_counts.txt" 2>/dev/null || echo "[]")

RES_JSON='['
sep=''
for file in "$RUN_DIR/results/check_results.txt" "$RUN_DIR/results/baseline_check_results.txt" "$RUN_DIR/results/verifier_results.txt"; do
  [ -f "$file" ] || continue
  while IFS= read -r line; do
    case "$line" in
      RESULT\ *)
        id=""; verdict=""; severity=""; confidence=""; evidence=""
        for tok in $line; do
          case "$tok" in
            id=*) id=${tok#id=} ;;
            verdict=*) verdict=${tok#verdict=} ;;
            severity=*) severity=${tok#severity=} ;;
            confidence=*) confidence=${tok#confidence=} ;;
            evidence=*) evidence=${line#* evidence=} ; break ;;
          esac
        done
        RES_JSON="${RES_JSON}${sep}{\"id\":\"$(json_escape "$id")\",\"verdict\":\"$(json_escape "$verdict")\",\"severity\":\"$(json_escape "$severity")\",\"confidence\":\"$(json_escape "$confidence")\",\"evidence\":\"$(json_escape "$evidence")\"}"
        sep=','
        ;;
    esac
  done < "$file"
done
RES_JSON="${RES_JSON}]"

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
  "uptime_seconds": $UPTIME_SECONDS,
  "clock_sane": $CLOCK_SANE,
  "signatures": $SIG_JSON,
  "detector_results": $RES_JSON
}
JSON

printf '%s\n' "$(tr -d '\n' < "$OUT")" >> "$TELEMETRY_LOG"
