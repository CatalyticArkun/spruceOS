#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# This is a service to unpack archives that a preformatted to land in the right place.
# Since some files need to be available before the menu is displayed, we need to unpack them before the menu is displayed so that's one mode.
# The other mode is to unpack archives needed before the command_to_run, this is used for the preCmd folder.

# This can be called with a "pre_cmd" argument to run a check and unpack over the preCmd folder only.
# Typically you'd use that for any unpacking process since we don't want extraction to happen in the background.
# It's rather resource heavy and we don't want leave it running in the background.

#  If a silentUnpacker flag is present another script is running and we don't want to run this one.
if flag_check "silentUnpacker"; then
    log_message "Unpacker: Another silent unpacker is running, exiting" -v
    exit 0
fi

log_message "Unpacker: Script started (mode arg: ${1:-all})"

cleanup() {
    flag_remove "silentUnpacker"
}

# Set trap for script exit
trap cleanup EXIT

# Process command line arguments
RUN_MODE="all"
if [ "$1" = "--silent" ]; then
    flag_add "silentUnpacker" --tmp
    [ -n "$2" ] && RUN_MODE="$2"
elif [ -n "$1" ]; then
    RUN_MODE="$1"
fi

if flag_check "silentUnpacker"; then
    unpacker_silent="true"
else
    unpacker_silent="false"
fi
log_message "Unpacker: invocation context mode=${RUN_MODE} silent=${unpacker_silent}"

# Function to display text if not in silent mode
display_if_not_silent() {
    flag_check "silentUnpacker" || start_pyui_message_writer
    flag_check "silentUnpacker" || display_image_and_text "$ICON" 35 25 "$archive_name archive detected. Unpacking.........." 75
}

# Function to unpack archives from a specified directory
unpack_archives() {
    local dir="$1"
    local flag_name="$2"
    local lane_name="$3"

    [ -n "$flag_name" ] && flag_add "$flag_name" --tmp
    [ -z "$lane_name" ] && lane_name="$(basename "$dir")"
    log_message "Unpacker: lane scan start lane=${lane_name} dir=${dir} flag=${flag_name:-none}"

    for archive in "$dir"/*.7z.extracting "$dir"/*.7z; do
        [ -f "$archive" ] || continue

        recovering="false"
        candidate_type="fresh"
        if echo "$archive" | grep -q '\.7z\.extracting$'; then
            archive_name=$(basename "$archive" .7z.extracting)
            recovering="true"
            candidate_type="recovery"
            log_message "Unpacker: recovery candidate detected lane=${lane_name} name=${archive_name}.7z.extracting"
        else
            archive_name=$(basename "$archive" .7z)
            extracting_archive="${archive}.extracting"
            log_message "Unpacker: fresh candidate detected lane=${lane_name} name=${archive_name}.7z"
            log_message "Unpacker: rename before extract lane=${lane_name} from=${archive_name}.7z to=${archive_name}.7z.extracting"
            if mv -f "$archive" "$extracting_archive"; then
                archive="$extracting_archive"
            else
                log_message "Unpacker: archive extraction prepare failed lane=${lane_name} name=${archive_name}.7z"
                continue
            fi
        fi

        log_message "Unpacker: eligible archive lane=${lane_name} type=${candidate_type} name=${archive_name}.7z"
        display_if_not_silent

        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            log_message "Unpacker: extraction start lane=${lane_name} type=${candidate_type} name=${archive_name}.7z"
            if 7zr x -aoa "$archive" -o/; then
                log_message "Unpacker: extraction success lane=${lane_name} name=${archive_name}.7z"
                if rm -f "$archive"; then
                    log_message "Unpacker: cleanup success lane=${lane_name} removed=${archive_name}.7z.extracting"
                else
                    log_message "Unpacker: cleanup failed lane=${lane_name} remove_target=${archive_name}.7z.extracting"
                fi
            else
                rc=$?
                log_message "Unpacker: extraction failed lane=${lane_name} name=${archive_name}.7z rc=${rc}"
            fi
        else
            log_message "Unpacker: archive skipped invalid-root lane=${lane_name} name=${archive_name}.7z"
            if [ "$recovering" = "false" ]; then
                mv -f "$archive" "$dir/${archive_name}.7z"
            fi
        fi
    done

    [ -n "$flag_name" ] && flag_remove "$flag_name"
    log_message "Unpacker: lane scan complete lane=${lane_name} dir=${dir} flag=${flag_name:-none}"
}

# Quick check for .7z files in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preCmd" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preMenu" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)" ] &&
    [ -z "$(find "$THEME_DIR" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)" ] &&
    [ -z "$(find "$RA_THEME_DIR" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)" ]; then
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

if flag_check "save_active"; then
    unpacker_save_active="true"
else
    unpacker_save_active="false"
fi
if [ -f "$FLAGS_DIR/lastgame.lock" ]; then
    unpacker_lastgame="present"
else
    unpacker_lastgame="missing"
fi
log_message "Unpacker: startup context run_mode=${RUN_MODE} save_active=${unpacker_save_active} lastgame_lock=${unpacker_lastgame}"
log_message "Unpacker: Starting theme and archive unpacking process"

# Process archives based on run mode
case "$RUN_MODE" in
"all")
    unpack_archives "$THEME_DIR" "" "themes"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking" "preMenu"
    if flag_check "save_active"; then
        log_message "Unpacker: preCmd unpack running in foreground because save_active=true (autoresume-sensitive boot)"
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" "preCmd"
    else
        log_message "Unpacker: preCmd unpack running in background via dedicated silent pre_cmd worker because save_active=false"
        /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent pre_cmd &
    fi
    ;;
"pre_cmd")
    unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" "preCmd"
    ;;
*)
    log_message "Unpacker: Invalid run mode specified"
    exit 1
    ;;
esac

log_message "Unpacker: Finished running"
