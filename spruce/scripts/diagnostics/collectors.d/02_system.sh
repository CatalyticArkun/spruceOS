#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/02_system"
mkdir -p "$OUT"

uptime > "$OUT/uptime.log" 2>/dev/null || true
( printenv 2>/dev/null | grep -Eiv 'PASS|TOKEN|SECRET|KEY|COOKIE' ) > "$OUT/env_sanitized.log" || true
lsmod > "$OUT/lsmod.log" 2>/dev/null || true
cat /proc/mounts > "$OUT/mounts.log" 2>/dev/null || true
