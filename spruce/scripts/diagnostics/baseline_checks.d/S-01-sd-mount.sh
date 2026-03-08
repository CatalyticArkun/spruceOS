#!/bin/sh
# SpruceOS baseline check: SD mount presence + read/write mode
MNT_LINE=$(grep ' /mnt/SDCARD ' /proc/mounts 2>/dev/null | head -n 1 || true)
if [ -z "$MNT_LINE" ]; then
  echo "RESULT id=S-01 verdict=FAIL severity=P1 confidence=high evidence=sd_mount_missing"
  exit 0
fi

MNT_OPTS=$(echo "$MNT_LINE" | awk '{print $4}')
if echo "$MNT_OPTS" | grep -Eq '(^|,)ro(,|$)'; then
  echo "RESULT id=S-01 verdict=WARN severity=P1 confidence=high evidence=sd_mount_read_only"
else
  echo "RESULT id=S-01 verdict=PASS severity=P4 confidence=high evidence=sd_mount_rw"
fi
