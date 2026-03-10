#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)

cleanup() {
    kill "${PRINCIPAL_PID:-}" 2>/dev/null || true
    wait "${PRINCIPAL_PID:-}" 2>/dev/null || true
    if [ -n "${ORIG_SDCARD_DIR:-}" ] && [ -d "${ORIG_SDCARD_DIR:-}" ]; then
        rm -rf /mnt/SDCARD
        mv "$ORIG_SDCARD_DIR" /mnt/SDCARD
    else
        rm -rf /mnt/SDCARD
    fi
    rm -f /tmp/cmd_to_run.sh /tmp/pre_cmd_unpacking.lock /tmp/fbdisplay_exit
    rm -rf /tmp/miyoo_inputd
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

if [ -e /mnt/SDCARD ]; then
    ORIG_SDCARD_DIR="$TMP/original_sdcard"
    mv /mnt/SDCARD "$ORIG_SDCARD_DIR"
fi

mkdir -p /mnt/SDCARD/spruce/scripts /mnt/SDCARD/spruce/archives/preCmd /mnt/SDCARD/spruce/flags /tmp/miyoo_inputd "$TMP/bin"
cp "$ROOT/spruce/scripts/principal.sh" /mnt/SDCARD/spruce/scripts/principal.sh
chmod +x /mnt/SDCARD/spruce/scripts/principal.sh

cat > /mnt/SDCARD/spruce/scripts/helperFunctions.sh <<'HF'
#!/bin/sh
FLAGS_DIR="/mnt/SDCARD/spruce/flags"
SYSTEM_JSON="/tmp/system.json"
flag_add() { [ "$2" = "--tmp" ] 2>/dev/null && touch "/tmp/$1.lock" || touch "$FLAGS_DIR/$1.lock"; }
flag_remove() { rm -f "$FLAGS_DIR/$1.lock" "/tmp/$1.lock"; }
flag_check() { [ -f "$FLAGS_DIR/$1.lock" ] || [ -f "/tmp/$1.lock" ]; }
set_smart() { :; }
stop_pyui_message_writer() { :; }
enable_or_disable_rgb() { :; }
set_rgb_in_menu() { :; }
set_network_proxy() { :; }
display_kill() { :; }
low_battery_check() { :; }
finish_unpacking() { :; }
prepare_for_pyui_launch() { :; }
post_pyui_exit() { :; }
log_activity_event() { printf 'activity:%s:%s\n' "$1" "$2" >> "${TEST_LOG_FILE:?}"; }
set_performance() { :; }
log_message() { printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"; }
HF
chmod +x /mnt/SDCARD/spruce/scripts/helperFunctions.sh

echo '{"wifi":0}' > /tmp/system.json

cat > "$TMP/bin/udpbcast" <<'U'
#!/bin/sh
exit 0
U
chmod +x "$TMP/bin/udpbcast"

cat > "$TMP/bin/jq" <<'JQ'
#!/bin/sh
echo 0
JQ
chmod +x "$TMP/bin/jq"

# A) pre_cmd-dependent launch (standard_launch.sh signal) must wait until pre_cmd lane is drained.
LOG_A="$TMP/gate_a.log"
export TEST_LOG_FILE="$LOG_A"
export PATH="$TMP/bin:$PATH"

cat > /tmp/cmd_to_run.sh <<CMD
#!/bin/sh
# "/mnt/SDCARD/spruce/scripts/emu/standard_launch.sh" "/mnt/SDCARD/Roms/GBA/test.gba"
exit 0
CMD
chmod +x /tmp/cmd_to_run.sh

# pending pre_cmd work exists before loop starts
: > /mnt/SDCARD/spruce/archives/preCmd/pending.7z
(
    sleep 0.20
    : > /tmp/pre_cmd_unpacking.lock
    sleep 0.40
    rm -f /tmp/pre_cmd_unpacking.lock /mnt/SDCARD/spruce/archives/preCmd/pending.7z
) &

/mnt/SDCARD/spruce/scripts/principal.sh >/dev/null 2>&1 &
PRINCIPAL_PID=$!

sleep 0.15
if grep -q 'activity:.*:START' "$LOG_A" 2>/dev/null; then
    echo "pre_cmd launch executed before pre_cmd lane drained"
    exit 1
fi

for _ in $(seq 1 100); do
    grep -q 'activity:.*:START' "$LOG_A" 2>/dev/null && break
    sleep 0.05
done
if ! grep -q 'principal.sh: pre_cmd dispatch gate engaged' "$LOG_A" 2>/dev/null; then
    echo "pre_cmd gate did not engage for standard_launch signal"
    exit 1
fi
if ! grep -q 'principal.sh: pre_cmd dispatch gate released' "$LOG_A" 2>/dev/null; then
    echo "pre_cmd gate did not release after lane drained"
    exit 1
fi
if ! grep -q 'activity:.*:START' "$LOG_A" 2>/dev/null; then
    echo "pre_cmd launch did not execute after pre_cmd lane drained"
    exit 1
fi

kill "$PRINCIPAL_PID" 2>/dev/null || true
wait "$PRINCIPAL_PID" 2>/dev/null || true
PRINCIPAL_PID=""

# B) non-pre_cmd launch under Emu path (without standard_launch.sh signal)
# must not be blocked by pre_cmd lane state.
LOG_B="$TMP/gate_b.log"
export TEST_LOG_FILE="$LOG_B"

cat > /tmp/cmd_to_run.sh <<CMD
#!/bin/sh
# "/mnt/SDCARD/Emu/PORTS/custom_launcher.sh" "/mnt/SDCARD/Roms/PORTS/game.sh"
exit 0
CMD
chmod +x /tmp/cmd_to_run.sh
: > /mnt/SDCARD/spruce/archives/preCmd/still_pending.7z
: > /tmp/pre_cmd_unpacking.lock

/mnt/SDCARD/spruce/scripts/principal.sh >/dev/null 2>&1 &
PRINCIPAL_PID=$!

for _ in $(seq 1 30); do
    grep -q 'activity:.*:START' "$LOG_B" 2>/dev/null && break
    sleep 0.05
done
if [ -n "$(grep 'principal.sh: pre_cmd dispatch gate engaged' "$LOG_B" 2>/dev/null || true)" ]; then
    echo "non-pre_cmd launch incorrectly matched pre_cmd classification predicate"
    exit 1
fi
if ! grep -q 'activity:.*:START' "$LOG_B" 2>/dev/null; then
    echo "non-pre_cmd launch was incorrectly blocked by pre_cmd gate"
    exit 1
fi

kill "$PRINCIPAL_PID" 2>/dev/null || true
wait "$PRINCIPAL_PID" 2>/dev/null || true
PRINCIPAL_PID=""

rm -f /tmp/pre_cmd_unpacking.lock /mnt/SDCARD/spruce/archives/preCmd/still_pending.7z

echo "pre_cmd dispatch gate test: PASS"
