#!/bin/sh

# mnt "/mnt/SDCARD/spruce/scripts/whte_rbt.obj"
# >access security
# access: PERMISSION DENIED.
# >access security grid
# access: PERMISSION DENIED.
# >access main security grid
# access: PERMISSION DENIED.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

[ "$LED_PATH" != "not applicable" ] && echo mmc0 > "$LED_PATH"/trigger

export HOME="/mnt/SDCARD"

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"

run_sd_card_fix_if_triggered    # do this before anything else
set_performance
device_init
set_volume_to_config &
# Check if WiFi is enabled and bring up network services if so
enable_or_disable_wifi_per_system_json &

# Flag cleanup
flag_remove "log_verbose" &
flag_remove "low_battery" &
flag_remove "in_menu" &

unstage_archives_wanted
check_and_handle_firmware_app &
check_and_hide_update_app &

startup_unpack_artifacts_clean() {
    if flag_check "pre_menu_unpacking" || flag_check "pre_cmd_unpacking" || flag_check "themes_unpacking"; then
        return 1
    fi

    for check_dir in \
        "/mnt/SDCARD/spruce/archives/preMenu" \
        "/mnt/SDCARD/spruce/archives/preCmd" \
        "/mnt/SDCARD/Themes" \
        "/mnt/SDCARD/RetroArch/.retroarch/assets"
    do
        [ -d "$check_dir" ] || continue
        if find "$check_dir" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1 | grep -q .; then
            return 1
        fi
    done

    return 0
}

# Check for first_boot lifecycle flags and run recovery flow when required
FIRST_BOOT_FLAG="first_boot_${PLATFORM}"
FIRST_BOOT_IN_PROGRESS_FLAG="first_boot_${PLATFORM}_in_progress"
FIRST_BOOT_COMPLETE_FLAG="first_boot_${PLATFORM}_complete"
FIRST_BOOT_VERIFIED_FLAG="first_boot_${PLATFORM}_complete_verified"

run_firstboot_recovery=false

if flag_check "$FIRST_BOOT_COMPLETE_FLAG" && ! flag_check "$FIRST_BOOT_VERIFIED_FLAG"; then
    if startup_unpack_artifacts_clean; then
        log_message "Firstboot complete marker verified"
        flag_add "$FIRST_BOOT_VERIFIED_FLAG"
    else
        log_message "Firstboot verification failed; forcing recovery"
        flag_remove "$FIRST_BOOT_COMPLETE_FLAG"
        flag_remove "$FIRST_BOOT_VERIFIED_FLAG"
        flag_add "$FIRST_BOOT_IN_PROGRESS_FLAG"
        run_firstboot_recovery=true
    fi
fi

if flag_check "$FIRST_BOOT_IN_PROGRESS_FLAG" && ! flag_check "$FIRST_BOOT_COMPLETE_FLAG"; then
    log_message "Firstboot recovery detected after interrupted startup"
    run_firstboot_recovery=true
fi

if flag_check "$FIRST_BOOT_FLAG"; then
    run_firstboot_recovery=true
fi

if [ "$run_firstboot_recovery" = "true" ]; then
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent &
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
else
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

launch_startup_watchdogs

# check whether to auto-resume into a game
if flag_check "save_active"; then
    auto_resume_game
else
    log_message "Auto Resume skipped (no save_active flag)"
fi

/mnt/SDCARD/spruce/scripts/autoIconRefresh.sh &
developer_mode_task &
update_checker &
# update_notification

# Initialize CPU settings
set_smart

# Set up the boot_to action prior to getting into the principal loop
set_up_boot_action

flag_remove "save_active"

# start main loop
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
