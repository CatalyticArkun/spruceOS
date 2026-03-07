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

power_trace_boot_reconcile_pending
power_trace_emit "BOOT_BEGIN" "AUTO" "BOOTING" "BOOTING" "runtime_start" "runtime.sh:startup" "runtime startup sequence entered" "" "" "" "$(flag_check save_active && echo true || echo false)" "" ""

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

# Check for first_boot flags and run Unpacker accordingly
if flag_check "first_boot_${PLATFORM}"; then
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent &
    log_message "Unpacker started silently in background due to first_boot flag"
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
else
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

launch_startup_watchdogs

# run automation-first diagnostics in background only when explicitly enabled
if flag_check "RUN_STARTTIME_DIAGNOSTICS"; then
    /mnt/SDCARD/spruce/scripts/diagnostics/runner.sh >/dev/null 2>&1 &
    log_message "Start-time diagnostics enabled (RUN_STARTTIME_DIAGNOSTICS)."
else
    log_message "Start-time diagnostics disabled (RUN_STARTTIME_DIAGNOSTICS not set)."
fi

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

power_trace_emit "BOOT_COMPLETE" "AUTO" "RUNNING" "RUNNING" "runtime_ready" "runtime.sh:startup" "startup tasks complete; entering principal loop" "" "" "" "" "" ""

# start main loop
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
