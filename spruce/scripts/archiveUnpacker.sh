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

own_lock() {
    local lock_name="$1"
    local lock_opt="$2"

    flag_add "$lock_name" "$lock_opt"

    case " $LOCKS_OWNED " in
        *" $lock_name "*) ;;
        *)
            if [ -n "$LOCKS_OWNED" ]; then
                LOCKS_OWNED="$LOCKS_OWNED $lock_name"
            else
                LOCKS_OWNED="$lock_name"
            fi
            ;;
    esac
}

release_lock() {
    local lock_name="$1"
    local new_locks=""
    local owned_lock

    flag_remove "$lock_name"

    for owned_lock in $LOCKS_OWNED; do
        [ "$owned_lock" = "$lock_name" ] && continue
        if [ -n "$new_locks" ]; then
            new_locks="$new_locks $owned_lock"
        else
            new_locks="$owned_lock"
        fi
    done

    LOCKS_OWNED="$new_locks"
}

cleanup() {
    local lock_name
    local owned_locks_snapshot="$LOCKS_OWNED"

    for lock_name in $owned_locks_snapshot; do
        release_lock "$lock_name"
    done
}

# Set trap for script exit
trap cleanup EXIT

# Process command line arguments
RUN_MODE="all"
if [ "$1" = "--silent" ]; then
    own_lock "silentUnpacker" "--tmp"
    [ -n "$2" ] && RUN_MODE="$2"
elif [ -n "$1" ]; then
    RUN_MODE="$1"
fi

# Function to display text if not in silent mode
display_if_not_silent() {
    flag_check "silentUnpacker" || start_pyui_message_writer
    flag_check "silentUnpacker" || display_image_and_text "$ICON" 35 25 "$archive_name archive detected. Unpacking.........." 75
}

extract_archive() {
    local archive_path="$1"
    local archive_name_local

    archive_name_local=$(basename "$archive_path")

    if 7zr l "$archive_path" | grep -q "/mnt/SDCARD/"; then
        if 7zr x -aoa "$archive_path" -o/; then
            rm -f "$archive_path"
            log_message "Unpacker: Unpacked and removed: $archive_name_local"
            return 0
        fi

        log_message "Unpacker: Failed to unpack: $archive_name_local"
        return 1
    fi

    log_message "Unpacker: Invalid root for $archive_name_local, restoring archive"
    mv -f "$archive_path" "${archive_path%.extracting}" 2>/dev/null
    return 1
}

# Function to unpack archives from a specified directory
unpack_archives() {
    local dir="$1"
    local flag_name="$2"

    [ -n "$flag_name" ] && own_lock "$flag_name"

    for archive in "$dir"/*.7z.extracting "$dir"/*.7z; do
        [ -f "$archive" ] || continue

        case "$archive" in
            *.7z)
                extracting_archive="${archive}.extracting"
                if mv -f "$archive" "$extracting_archive"; then
                    archive="$extracting_archive"
                else
                    log_message "Unpacker: Could not stage archive for extraction: $archive"
                    continue
                fi
                ;;
        esac

        archive_name=$(basename "$archive" .7z.extracting)
        display_if_not_silent
        extract_archive "$archive"
    done

    [ -n "$flag_name" ] && release_lock "$flag_name"
}

has_pending_archives() {
    local dir="$1"

    [ -d "$dir" ] || return 1

    if find "$dir" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1 | grep -q .; then
        return 0
    fi

    return 1
}

# Quick check for startup archives in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    ! has_pending_archives "$ARCHIVE_DIR/preCmd" &&
    ! has_pending_archives "$ARCHIVE_DIR/preMenu" &&
    ! has_pending_archives "$THEME_DIR" &&
    ! has_pending_archives "$RA_THEME_DIR"; then
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

log_message "Unpacker: Starting theme and archive unpacking process"

# Process archives based on run mode
case "$RUN_MODE" in
"all")
    own_lock "themes_unpacking"
    unpack_archives "$THEME_DIR"
    unpack_archives "$RA_THEME_DIR"
    release_lock "themes_unpacking"

    own_lock "pre_menu_unpacking"
    unpack_archives "$ARCHIVE_DIR/preMenu"
    release_lock "pre_menu_unpacking"

    if flag_check "save_active"; then
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    else
        case " $LOCKS_OWNED " in
            *" silentUnpacker "*) /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh pre_cmd & ;;
            *) /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent pre_cmd & ;;
        esac
    fi
    ;;
"pre_menu")
    own_lock "themes_unpacking"
    unpack_archives "$THEME_DIR"
    unpack_archives "$RA_THEME_DIR"
    release_lock "themes_unpacking"

    own_lock "pre_menu_unpacking"
    unpack_archives "$ARCHIVE_DIR/preMenu"
    release_lock "pre_menu_unpacking"
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
