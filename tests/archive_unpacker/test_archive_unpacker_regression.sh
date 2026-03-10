#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
LOG_FILE="$TMP/unpacker.log"

cleanup() {
    if [ -n "${ORIG_SDCARD_DIR:-}" ] && [ -d "${ORIG_SDCARD_DIR:-}" ]; then
        rm -rf /mnt/SDCARD
        mv "$ORIG_SDCARD_DIR" /mnt/SDCARD
    else
        rm -rf /mnt/SDCARD
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

if [ -e /mnt/SDCARD ]; then
    ORIG_SDCARD_DIR="$TMP/original_sdcard"
    mv /mnt/SDCARD "$ORIG_SDCARD_DIR"
fi

mkdir -p /mnt/SDCARD/spruce/scripts/network /mnt/SDCARD/spruce/archives/staging /mnt/SDCARD/spruce/archives/preMenu /mnt/SDCARD/spruce/archives/preCmd /mnt/SDCARD/Themes /mnt/SDCARD/RetroArch/.retroarch/assets /mnt/SDCARD/spruce/flags
cp "$ROOT/spruce/scripts/archiveUnpacker.sh" /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
cp "$ROOT/spruce/scripts/runtimeHelper.sh" /mnt/SDCARD/spruce/scripts/runtimeHelper.sh
chmod +x /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

cat > /mnt/SDCARD/spruce/scripts/helperFunctions.sh <<'HF'
#!/bin/sh
FLAGS_DIR="/mnt/SDCARD/spruce/flags"
mkdir -p "$FLAGS_DIR"
flag_path() { echo "$FLAGS_DIR/$1"; }
flag_check() { [ -f "$(flag_path "$1")" ]; }
flag_add() { touch "$(flag_path "$1")"; }
flag_remove() { rm -f "$(flag_path "$1")"; }
log_message() { printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"; }
start_pyui_message_writer() { :; }
display_image_and_text() { :; }
HF
chmod +x /mnt/SDCARD/spruce/scripts/helperFunctions.sh

cat > /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh <<'EOF2'
#!/bin/sh
EOF2
cat > /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh <<'EOF3'
#!/bin/sh
EOF3

mkdir -p "$TMP/bin"
cat > "$TMP/bin/7zr" <<'Z7'
#!/bin/sh
cmd="$1"
shift
archive=""
for arg in "$@"; do
    case "$arg" in
        *.7z|*.7z.extracting) archive="$arg" ;;
    esac
done
case "$cmd" in
    l)
        if [ -n "$archive" ] && grep -q 'VALIDROOT' "$archive"; then
            echo "/mnt/SDCARD/ok"
        fi
        exit 0
        ;;
    x)
        if [ "${FORCE_FAIL:-0}" = "1" ]; then
            exit 9
        fi
        [ -n "$archive" ] || exit 3
        echo "x:$archive" >> "${EXTRACT_LOG:?}"
        exit 0
        ;;
    *)
        exit 2
        ;;
esac
Z7
chmod +x "$TMP/bin/7zr"

cat > "$TMP/bin/rm" <<'RM'
#!/bin/sh
for arg in "$@"; do
    if [ -n "${RM_FAIL_PATTERN:-}" ] && echo "$arg" | grep -q "$RM_FAIL_PATTERN"; then
        exit 1
    fi
done
exec /bin/rm "$@"
RM
chmod +x "$TMP/bin/rm"

export PATH="$TMP/bin:$PATH"
export TEST_LOG_FILE="$LOG_FILE"
export EXTRACT_LOG="$TMP/extract.log"

assert_file_exists() { [ -f "$1" ] || { echo "expected file: $1"; exit 1; }; }
assert_file_missing() { [ ! -f "$1" ] || { echo "unexpected file: $1"; exit 1; }; }
assert_log_has() { grep -q "$1" "$LOG_FILE" || { echo "expected log pattern: $1"; exit 1; }; }

# A) Lane integrity tests
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

: > "$LOG_FILE"
touch /mnt/SDCARD/spruce/archives/staging/direct_precmd.7z
unstage_archive "direct_precmd.7z" "preCmd"
assert_file_exists /mnt/SDCARD/spruce/archives/preCmd/direct_precmd.7z
assert_file_missing /mnt/SDCARD/spruce/archives/preMenu/direct_precmd.7z

touch /mnt/SDCARD/spruce/archives/staging/fallback_empty.7z
unstage_archive "fallback_empty.7z" ""
assert_file_exists /mnt/SDCARD/spruce/archives/preMenu/fallback_empty.7z

touch /mnt/SDCARD/spruce/archives/staging/fallback_other.7z
unstage_archive "fallback_other.7z" "other"
assert_file_exists /mnt/SDCARD/spruce/archives/preMenu/fallback_other.7z

DISPLAY_WIDTH="640"
DISPLAY_HEIGHT="480"
DEVICE_CAN_USE_EXTERNAL_CONTROLLER="true"
DEVICE_USES_64_BIT_RA="true"
for f in overlays_640x480.7z autoconfig.7z cores64.7z; do
    touch "/mnt/SDCARD/spruce/archives/staging/$f"
done
unstage_archives_wanted
for f in overlays_640x480.7z autoconfig.7z cores64.7z; do
    assert_file_exists "/mnt/SDCARD/spruce/archives/preCmd/$f"
    assert_file_missing "/mnt/SDCARD/spruce/archives/preMenu/$f"
done

# B) Boot orchestration static checks
rg -n '/mnt/SDCARD/spruce/scripts/archiveUnpacker\.sh$' "$ROOT/spruce/scripts/runtime.sh" >/dev/null
rg -n '/mnt/SDCARD/spruce/scripts/archiveUnpacker\.sh --silent &' "$ROOT/spruce/scripts/runtime.sh" >/dev/null
! rg -n '/mnt/SDCARD/spruce/scripts/archiveUnpacker\.sh pre_cmd' "$ROOT/spruce/scripts/runtime.sh" >/dev/null
rg -n '/mnt/SDCARD/spruce/scripts/archiveUnpacker\.sh$' "$ROOT/App/ThemeGarden/launch.sh" >/dev/null

# C) Unpacker mode-scope tests
: > "$LOG_FILE"
: > "$EXTRACT_LOG"
flag_add save_active
printf 'VALIDROOT\n' > /mnt/SDCARD/Themes/theme_lane.7z
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preMenu/menu_lane.7z
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preCmd/cmd_lane.7z
/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
assert_file_missing /mnt/SDCARD/Themes/theme_lane.7z.extracting
assert_file_missing /mnt/SDCARD/spruce/archives/preMenu/menu_lane.7z.extracting
assert_file_missing /mnt/SDCARD/spruce/archives/preCmd/cmd_lane.7z.extracting
assert_log_has 'lane scan start lane=themes'
assert_log_has 'lane scan start lane=preMenu'
assert_log_has 'lane scan start lane=preCmd'
flag_remove save_active

: > "$LOG_FILE"
printf 'VALIDROOT\n' > /mnt/SDCARD/Themes/theme_should_not_run.7z
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preCmd/only_cmd.7z
/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd
assert_file_exists /mnt/SDCARD/Themes/theme_should_not_run.7z
assert_file_missing /mnt/SDCARD/spruce/archives/preCmd/only_cmd.7z.extracting
assert_log_has 'invocation context mode=pre_cmd'
! grep -q 'lane=themes' "$LOG_FILE"

if /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh nonsense >/dev/null 2>&1; then
    echo "invalid mode should fail"
    exit 1
fi

# D) Recovery + convergence tests
: > "$LOG_FILE"
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preCmd/fail_then_retry.7z
FORCE_FAIL=1 /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd
assert_file_exists /mnt/SDCARD/spruce/archives/preCmd/fail_then_retry.7z.extracting
assert_log_has 'extraction failed lane=preCmd name=fail_then_retry.7z rc=9'

FORCE_FAIL=0 /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd
assert_file_missing /mnt/SDCARD/spruce/archives/preCmd/fail_then_retry.7z.extracting
assert_log_has 'recovery candidate detected lane=preCmd name=fail_then_retry.7z.extracting'
assert_log_has 'cleanup success lane=preCmd removed=fail_then_retry.7z.extracting'

: > "$LOG_FILE"
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preCmd/recovery_only.7z.extracting
/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd
assert_file_missing /mnt/SDCARD/spruce/archives/preCmd/recovery_only.7z.extracting
assert_log_has 'recovery candidate detected lane=preCmd name=recovery_only.7z.extracting'

# E) Logging verification including cleanup failure
: > "$LOG_FILE"
printf 'VALIDROOT\n' > /mnt/SDCARD/spruce/archives/preCmd/cleanup_fail.7z
RM_FAIL_PATTERN='cleanup_fail\.7z\.extracting' /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd || true
assert_file_exists /mnt/SDCARD/spruce/archives/preCmd/cleanup_fail.7z.extracting
assert_log_has 'fresh candidate detected lane=preCmd name=cleanup_fail.7z'
assert_log_has 'rename before extract lane=preCmd from=cleanup_fail.7z to=cleanup_fail.7z.extracting'
assert_log_has 'extraction start lane=preCmd type=fresh name=cleanup_fail.7z'
assert_log_has 'extraction success lane=preCmd name=cleanup_fail.7z'
assert_log_has 'cleanup failed lane=preCmd remove_target=cleanup_fail.7z.extracting'

RM_FAIL_PATTERN='' /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd
assert_file_missing /mnt/SDCARD/spruce/archives/preCmd/cleanup_fail.7z.extracting
assert_log_has 'recovery candidate detected lane=preCmd name=cleanup_fail.7z.extracting'

assert_log_has 'invocation context mode=pre_cmd'
assert_log_has 'lane scan start lane=preCmd'
assert_log_has 'lane scan complete lane=preCmd'

echo "archive unpacker regression tests: PASS"
