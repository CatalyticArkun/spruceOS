#!/bin/sh
# SpruceOS device check: free space on SD
line=$(df -Pk /mnt/SDCARD 2>/dev/null | awk 'NR==2' || true)
if [ -z "$line" ]; then
  echo "RESULT id=S-02 verdict=INFO severity=P3 confidence=low evidence=sd_df_unavailable"
  exit 0
fi

avail_kb=$(echo "$line" | awk '{print $4}')
if [ -z "$avail_kb" ]; then
  echo "RESULT id=S-02 verdict=INFO severity=P3 confidence=low evidence=sd_avail_parse_failed"
  exit 0
fi

if [ "$avail_kb" -lt 65536 ]; then
  echo "RESULT id=S-02 verdict=FAIL severity=P1 confidence=high evidence=sd_free_lt_64mb"
elif [ "$avail_kb" -lt 262144 ]; then
  echo "RESULT id=S-02 verdict=WARN severity=P2 confidence=high evidence=sd_free_lt_256mb"
else
  echo "RESULT id=S-02 verdict=PASS severity=P4 confidence=high evidence=sd_free_ok"
fi
