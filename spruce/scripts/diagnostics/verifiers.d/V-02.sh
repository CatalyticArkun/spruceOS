#!/bin/sh
# Flag-gated network verifier aligned with SpruceOS device connectivity checks.
RUN_DIR="$1"
OUT_DIR="$RUN_DIR/results/verifiers"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/V-02-network.out"
: > "$OUT"

ok=0
fail=0

for host in 8.8.8.8 1.1.1.1; do
  if ping -c 2 -W 2 "$host" >"$OUT.$host" 2>&1; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
  cat "$OUT.$host" >> "$OUT"
  rm -f "$OUT.$host"
done

for ns in $(awk '/^nameserver/ { print $2 }' /etc/resolv.conf 2>/dev/null); do
  if ping -c 2 -W 2 "$ns" >"$OUT.ns" 2>&1; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
  cat "$OUT.ns" >> "$OUT"
  rm -f "$OUT.ns"
done

if [ "$ok" -gt 0 ] && [ "$fail" -eq 0 ]; then
  echo "RESULT id=V-02 verdict=PASS severity=P3 confidence=medium evidence=network_ping_all_ok"
elif [ "$ok" -gt 0 ] && [ "$fail" -gt 0 ]; then
  echo "RESULT id=V-02 verdict=WARN severity=P2 confidence=medium evidence=network_ping_partial_ok"
else
  echo "RESULT id=V-02 verdict=FAIL severity=P1 confidence=medium evidence=network_ping_all_failed"
fi
