#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/01_identity"
mkdir -p "$OUT"

boot_id_file="/proc/sys/kernel/random/boot_id"
boot_id="unknown"
[ -r "$boot_id_file" ] && boot_id=$(cat "$boot_id_file")
platform="${PLATFORM:-unknown}"
fw="unknown"
[ -f /etc/version ] && fw=$(tr -d '[:space:]' < /etc/version)

{
  echo "hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
  echo "kernel=$(uname -r 2>/dev/null || echo unknown)"
  echo "platform=$platform"
  echo "fw_build=$fw"
  echo "boot_id=$boot_id"
} > "$OUT/identity.txt"
