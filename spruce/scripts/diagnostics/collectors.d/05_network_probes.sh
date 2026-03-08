#!/bin/sh
RUN_DIR="$1"
OUT="$RUN_DIR/raw/05_network_probes"
mkdir -p "$OUT"

if [ "${DIAG_ENABLE_NET_TESTS:-0}" != "1" ]; then
  echo "network_probes=disabled" > "$OUT/status.log"
  exit 0
fi

run_probe() {
  target="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 ping -c 2 "$target" > "$OUT/ping_${target}.log" 2>&1 || true
  else
    ping -c 2 "$target" > "$OUT/ping_${target}.log" 2>&1 || true
  fi
}

run_probe 8.8.8.8
run_probe 1.1.1.1
for ns in $(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null); do
  run_probe "$ns"
done
