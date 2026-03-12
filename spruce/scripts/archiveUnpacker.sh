#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# Unpack service for staged .7z archives with absolute /mnt/SDCARD paths.
#
# Run modes:
#   all      - default startup behavior:
#              * unpack themes ($THEME_DIR)
#              * unpack pre-menu assets ($ARCHIVE_DIR/preMenu)
#              * unpack pre-command assets ($ARCHIVE_DIR/preCmd), backgrounded when no save is active
#   pre_menu - first-boot preparation mode used before firstboot.sh:
#              * unpack themes ($THEME_DIR)
#              * unpack pre-menu assets ($ARCHIVE_DIR/preMenu)
#              * does not unpack preCmd assets
#   pre_cmd  - unpack pre-command assets only ($ARCHIVE_DIR/preCmd)
#
# Use --silent to suppress UI output and coordinate with other unpacker instances.

#  If a silentUnpacker flag is present another script is running and we don't want to run this one.
if flag_check "silentUnpacker"; then
    log_message "Unpacker: Another silent unpacker is running, exiting" -v
    exit 0
fi

log_message "Unpacker: Script started"

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


# Function to display text if not in silent mode
display_if_not_silent() {
    flag_check "silentUnpacker" || start_pyui_message_writer
    flag_check "silentUnpacker" || display_image_and_text "$ICON" 35 25 "$archive_name archive detected. Unpacking.........." 75
}

# Function to unpack archives from a specified directory
unpack_archives() {
    local dir="$1"
    local flag_name="$2"

    [ -n "$flag_name" ] && flag_add "$flag_name" --tmp

    for archive in "$dir"/*.7z; do
        if [ -f "$archive" ]; then
            archive_name=$(basename "$archive" .7z)
            display_if_not_silent

            if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
                if 7zr x -aoa "$archive" -o/; then
                    rm -f "$archive"
                    log_message "Unpacker: Unpacked and removed: $archive_name.7z"
                else
                    log_message "Unpacker: Failed to unpack: $archive_name.7z"
                fi
            else
                log_message "Unpacker: Skipped unpacking: $archive_name.7z (incorrect folder structure)"
            fi
        fi
    done

    [ -n "$flag_name" ] && flag_remove "$flag_name"
}

# Quick check for .7z files in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preCmd" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preMenu" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$RA_THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ]; then
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

log_message "Unpacker: Starting theme and archive unpacking process"

# Process archives based on run mode
case "$RUN_MODE" in
"all")
    unpack_archives "$THEME_DIR"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking"
    if flag_check "save_active"; then
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    else
        flag_add "silentUnpacker" --tmp
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" &
    fi
    ;;
"pre_menu")
    unpack_archives "$THEME_DIR"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking"
    ;;
"pre_cmd")
    unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    ;;
*)
    log_message "Unpacker: Invalid run mode specified"
    exit 1
    ;;
esac

log_message "Unpacker: Finished running"
