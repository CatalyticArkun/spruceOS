#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
RUN_ID="$2"
BOOT_ID="$3"
TS="$4"

SUMMARY_DIR="$RUN_DIR/summary"
mkdir -p "$SUMMARY_DIR"
REPORT="$SUMMARY_DIR/report.txt"
FINDINGS="$SUMMARY_DIR/findings.jsonl"
MANIFEST="$SUMMARY_DIR/run_manifest.json"

ID_FILE="$SUMMARY_DIR/identity.txt"
uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
year=$(date -u +%Y 2>/dev/null || echo 1970)
clock_sane=0
[ "$year" -ge 2020 ] && clock_sane=1

json_result_lines() {
  kind="$1"
  file="$2"
  artifact_ptr="$3"
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      RESULT\ *)
        id=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i ~ /^id=/){sub(/^id=/,"",$i);print $i;break}}}')
        verdict=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i ~ /^verdict=/){sub(/^verdict=/,"",$i);print $i;break}}}')
        severity=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i ~ /^severity=/){sub(/^severity=/,"",$i);print $i;break}}}')
        confidence=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i ~ /^confidence=/){sub(/^confidence=/,"",$i);print $i;break}}}')
        evidence=$(echo "$line" | sed -n 's/.* evidence=//p' | cut -c1-300)
        printf '{"type":"%s","run_id":"%s","boot_id":"%s","timestamp_utc":"%s","uptime_seconds":%s,"clock_sane":%s,"id":"%s","verdict":"%s","severity":"%s","confidence":"%s","evidence":"%s","artifact":"%s"}\n' \
          "$kind" "$(json_escape "$RUN_ID")" "$(json_escape "$BOOT_ID")" "$(json_escape "$TS")" "$uptime_seconds" "$clock_sane" \
          "$(json_escape "$id")" "$(json_escape "$verdict")" "$(json_escape "$severity")" "$(json_escape "$confidence")" "$(json_escape "$evidence")" "$(json_escape "$artifact_ptr")"
        ;;
    esac
  done < "$file"
}

: > "$FINDINGS"
json_result_lines "check" "$RUN_DIR/results/check_results.txt" "results/check_results.txt" >> "$FINDINGS"
json_result_lines "baseline_check" "$RUN_DIR/results/baseline_check_results.txt" "results/baseline_check_results.txt" >> "$FINDINGS"
json_result_lines "verifier" "$RUN_DIR/results/verifier_results.txt" "results/verifier_results.txt" >> "$FINDINGS"

counts=$(awk '
BEGIN{fail=0; warn=0; info=0; ok=0}
/^RESULT / {
  for(i=1;i<=NF;i++){
    if($i=="verdict=FAIL") fail++;
    else if($i=="verdict=WARN") warn++;
    else if($i=="verdict=INFO") info++;
    else if($i=="verdict=PASS" || $i=="verdict=OK") ok++;
  }
}
END{printf "%d %d %d %d", fail,warn,info,ok}
' "$RUN_DIR/results"/*_results.txt 2>/dev/null || echo "0 0 0 0")

fail_count=$(echo "$counts" | awk '{print $1}')
warn_count=$(echo "$counts" | awk '{print $2}')
info_count=$(echo "$counts" | awk '{print $3}')
ok_count=$(echo "$counts" | awk '{print $4}')

device_hostname=""
kernel=""
platform=""
fw_build=""
if [ -f "$ID_FILE" ]; then
  device_hostname=$(sed -n "s/^device_hostname=//p" "$ID_FILE" | head -n1)
  kernel=$(sed -n "s/^kernel=//p" "$ID_FILE" | head -n1)
  platform=$(sed -n "s/^platform=//p" "$ID_FILE" | head -n1)
  fw_build=$(sed -n "s/^fw_build=//p" "$ID_FILE" | head -n1)
fi

if [ "$fail_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
  rec_verifiers="RUN_TEST_V-01.lock RUN_TEST_V-02.lock"
else
  rec_verifiers="none"
fi

{
  echo "SpruceOS Diagnostics Report"
  echo "run_id=$RUN_ID"
  echo "boot_id=$BOOT_ID"
  echo "timestamp_utc=$TS"
  [ -f "$ID_FILE" ] && cat "$ID_FILE"
  echo "uptime_seconds=$uptime_seconds"
  echo "clock_sane=$clock_sane"
  echo
  echo "Severity summary"
  echo "FAIL=$fail_count"
  echo "WARN=$warn_count"
  echo "INFO=$info_count"
  echo "OK=$ok_count"
  echo
  echo "Top findings"
  grep -h '^RESULT ' "$RUN_DIR/results"/*_results.txt 2>/dev/null | head -n 20 || true
  echo
  echo "Recommended verifiers"
  if [ "$rec_verifiers" = "none" ]; then
    echo "none"
  else
    echo "RUN_TEST_V-01.lock"
    echo "RUN_TEST_V-02.lock"
  fi
  echo
  echo "Appendix: artifacts"
  find "$RUN_DIR" -type f | sed "s|$RUN_DIR/||" | while read -r rel; do
    size=$(wc -c < "$RUN_DIR/$rel" 2>/dev/null || echo 0)
    echo "$size $rel"
  done | sort -nr
} > "$REPORT"

ARTIFACTS_JSON=$(find "$RUN_DIR" -type f | sed "s|$RUN_DIR/||" | while read -r rel; do
  size=$(wc -c < "$RUN_DIR/$rel" 2>/dev/null || echo 0)
  printf '{"path":"%s","bytes":%s}\n' "$(json_escape "$rel")" "$size"
done | awk 'BEGIN{printf "["} {if (NR>1) printf ","; printf "%s",$0} END{printf "]"}')

cat > "$MANIFEST" <<JSON
{
  "schema_version": "1",
  "run_id": "$(json_escape "$RUN_ID")",
  "boot_id": "$(json_escape "$BOOT_ID")",
  "timestamp_utc": "$(json_escape "$TS")",
  "identity": {
    "device_hostname": "$(json_escape "$device_hostname")",
    "kernel": "$(json_escape "$kernel")",
    "platform": "$(json_escape "$platform")",
    "fw_build": "$(json_escape "$fw_build")"
  },
  "collection": {
    "uptime_seconds": $uptime_seconds,
    "clock_sane": $clock_sane
  },
  "uptime_seconds": $uptime_seconds,
  "clock_sane": $clock_sane,
  "counts": {
    "fail": $fail_count,
    "warn": $warn_count,
    "info": $info_count,
    "ok": $ok_count,
    "check": $(grep -c '"type":"check"' "$FINDINGS" 2>/dev/null || echo 0),
    "verifier": $(grep -c '"type":"verifier"' "$FINDINGS" 2>/dev/null || echo 0)
  },
  "artifacts": $ARTIFACTS_JSON
}
JSON
