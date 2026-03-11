#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

export POWER_MODE_STATE_FILE="$TMP/power_mode.state"
export POWER_MODE_LOCK_DIR="$TMP/power_mode.lockdir"
export POWER_MODE_LOCK_RETRIES=200
export POWER_MODE_LOCK_SLEEP_SEC=0.005

# shellcheck disable=SC1091
. "$ROOT/spruce/scripts/power_mode.sh"

assert_true() {
    "$@" || {
        echo "expected success: $*"
        exit 1
    }
}

assert_false() {
    if "$@"; then
        echo "expected failure: $*"
        exit 1
    fi
}

# stale lock recovery behavior
mkdir -p "$POWER_MODE_LOCK_DIR"
printf '999999\n' > "$POWER_MODE_LOCK_DIR/pid"
assert_true power_mode_set_running watchdog

# generation increments on every successful transition
base_gen="$(power_mode_generation_get)"
assert_true power_mode_set_running watchdog
next_gen="$(power_mode_generation_get)"
[ "$next_gen" -eq $((base_gen + 1)) ] || {
    echo "expected generation increment after successful transition"
    exit 1
}

# owner validation permits safe chars and rejects unsafe ones
assert_true power_mode_set_running owner-1.abc_DEF
assert_false power_mode_set_running "bad owner"
assert_false power_mode_set_running 'bad"owner'

# write path must restore caller umask
original_umask="$(umask)"
umask 022
assert_true power_mode_set_running watchdog
[ "$(umask)" = "0022" ] || {
    echo "expected umask to be restored after power_mode write"
    exit 1
}
umask "$original_umask"

# invalid owner in persisted state fails closed
cat > "$POWER_MODE_STATE_FILE" <<STATE
power_mode="running"
power_owner="bad owner"
power_shutdown_pending="0"
power_rearm_until="0"
power_generation="1"
STATE
[ "$(power_mode_get)" = "shutdown_pending" ] || {
    echo "expected invalid persisted owner to fail closed"
    exit 1
}

# recover after fail-safe parse fence
assert_true power_mode_boot_reset_running watchdog

# invalid transition rejection: running -> waking is not allowed directly
assert_false power_mode_enter_rearm sleep_helper 1

# valid transition chain into shutdown pending
assert_true power_mode_claim_sleep_owner sleep_helper
assert_true power_mode_mark_shutdown_pending save_poweroff
assert_true power_mode_is_shutdown_pending

# shutdown_pending is monotonic for runtime callers
assert_false power_mode_set_running watchdog
assert_true power_mode_is_shutdown_pending

# boot-time reset is the only clear path
assert_true power_mode_boot_reset_running watchdog
assert_false power_mode_is_shutdown_pending

# serialized writes under concurrency keep state parseable and generation accurate
start_gen="$(power_mode_generation_get)"
i=1
while [ "$i" -le 20 ]; do
    power_mode_set_running "worker_$i" &
    i=$((i + 1))
done
wait

end_gen="$(power_mode_generation_get)"
[ "$end_gen" -eq $((start_gen + 20)) ] || {
    echo "expected generation to increase by 20 under concurrent writes (got $start_gen -> $end_gen)"
    exit 1
}

# file remains canonical key-value shell state
grep -q '^power_mode="' "$POWER_MODE_STATE_FILE"
grep -q '^power_generation="' "$POWER_MODE_STATE_FILE"

echo "test_power_mode_hardening: PASS"
