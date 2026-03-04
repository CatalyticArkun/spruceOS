#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/04_network_state"
mkdir -p "$OUT"

ifconfig -a > "$OUT/ifconfig.log" 2>/dev/null || true
ip addr > "$OUT/ip_addr.log" 2>/dev/null || true
route -n > "$OUT/route.log" 2>/dev/null || true
ip route > "$OUT/ip_route.log" 2>/dev/null || true
cat /etc/resolv.conf > "$OUT/resolv.conf.log" 2>/dev/null || true
