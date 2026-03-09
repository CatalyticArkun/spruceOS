#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/06_filesystem"
mkdir -p "$OUT"

df -h > "$OUT/df_h.log" 2>/dev/null || true
df -Pk > "$OUT/df_pk.log" 2>/dev/null || true
mount > "$OUT/mount.log" 2>/dev/null || true
lsblk -a > "$OUT/lsblk.log" 2>/dev/null || true
blkid > "$OUT/blkid.log" 2>/dev/null || true
fdisk -l > "$OUT/fdisk.log" 2>/dev/null || true
