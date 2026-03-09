#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

RUN_DIR="$1"
PHASE="${2:-A}"
OUT="$RUN_DIR/raw/device_snapshot"
mkdir -p "$OUT/basic" "$OUT/cpumem" "$OUT/network" "$OUT/filesystem" "$OUT/process"

hostname >"$OUT/basic/hostname.log" 2>/dev/null || true
uname -a >"$OUT/basic/uname.log" 2>/dev/null || true
uptime >"$OUT/basic/uptime.log" 2>/dev/null || true
printenv >"$OUT/basic/env.log" 2>/dev/null || true
lsmod >"$OUT/basic/lsmod.log" 2>/dev/null || true

cat /proc/cpuinfo >"$OUT/cpumem/cpuinfo.log" 2>/dev/null || true
cat /proc/meminfo >"$OUT/cpumem/meminfo.log" 2>/dev/null || true
cat /sys/class/thermal/thermal_zone0/temp >"$OUT/cpumem/temp.log" 2>/dev/null || true

ifconfig -a >"$OUT/network/ifconfig.log" 2>/dev/null || true
netstat -tuln >"$OUT/network/netstat.log" 2>/dev/null || true
route -n >"$OUT/network/route.log" 2>/dev/null || true
cat /etc/resolv.conf >"$OUT/network/resolv.log" 2>/dev/null || true

cat /proc/mounts >"$OUT/filesystem/mounts.log" 2>/dev/null || true
df -h >"$OUT/filesystem/disk_usage.log" 2>/dev/null || true
lsblk -a >"$OUT/filesystem/lsblk.log" 2>/dev/null || true
blkid >"$OUT/filesystem/blkid.log" 2>/dev/null || true
fdisk -l >"$OUT/filesystem/fdisk.log" 2>/dev/null || true

ps -ef >"$OUT/process/ps.log" 2>/dev/null || true

BATTERY_OUT="$OUT/basic/battery.log"
: > "$BATTERY_OUT"
for b in /sys/class/power_supply/*; do
    [ -d "$b" ] || continue
    name=$(basename "$b")
    cap=$(cat "$b/capacity" 2>/dev/null || echo unknown)
    health=$(cat "$b/health" 2>/dev/null || echo unknown)
    volt=$(cat "$b/voltage_now" 2>/dev/null || echo unknown)
    status=$(cat "$b/status" 2>/dev/null || echo unknown)
    {
        echo "[$name]"
        echo "capacity=$cap"
        echo "health=$health"
        echo "voltage_now=$volt"
        echo "status=$status"
    } >> "$BATTERY_OUT"
done

# More expensive process snapshot only in Phase B.
if [ "$PHASE" = "B" ]; then
    top -b -n 3 -d 1 >"$OUT/process/top.log" 2>/dev/null || true
fi
