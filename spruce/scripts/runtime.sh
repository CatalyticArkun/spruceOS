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

if command -v power_trace_shutdown_pending >/dev/null 2>&1; then
    if power_trace_shutdown_pending; then
        log_message "runtime.sh: startup detected power_trace shutdown pending marker before boot reconcile"
    fi
fi

if command -v power_trace_boot_reconcile_pending >/dev/null 2>&1; then
    power_trace_boot_reconcile_pending || true
fi
if command -v power_trace_emit >/dev/null 2>&1; then
    power_trace_emit "BOOT_BEGIN" "AUTO" "BOOTING" "BOOTING" "runtime_start" "runtime.sh:startup" "runtime startup sequence entered" "" "" "" "$(flag_check save_active && echo true || echo false)" "" "" || true
fi

boot_complete_emitted=0
emit_boot_complete_once() {
    [ "$boot_complete_emitted" = "1" ] && return 0

    if command -v power_trace_emit >/dev/null 2>&1; then
        power_trace_emit "BOOT_COMPLETE" "AUTO" "RUNNING" "RUNNING" "$1" "runtime.sh:startup" "$2" "" "" "" "" "" "" || true
    fi

    boot_complete_emitted=1
    log_message "runtime.sh: BOOT_COMPLETE emitted (trigger=$1)"
}

if flag_check "save_active"; then
    save_active_state="true"
else
    save_active_state="false"
fi
if [ -f "$FLAGS_DIR/lastgame.lock" ]; then
    lastgame_state="present"
else
    lastgame_state="missing"
fi
if [ -f "$FLAGS_DIR/lastgame.lock" ]; then
    lastgame_preview="$(head -n 1 "$FLAGS_DIR/lastgame.lock" 2>/dev/null)"
else
    lastgame_preview=""
fi
log_message "runtime.sh: startup state snapshot save_active=${save_active_state} lastgame_lock=${lastgame_state} cmd_to_run=$([ -f /tmp/cmd_to_run.sh ] && echo present || echo missing)"
log_message "runtime.sh: startup lastgame.lock preview=${lastgame_preview}"

log_message "runtime.sh: milestone run_sd_card_fix_if_triggered (begin)"
run_sd_card_fix_if_triggered    # do this before anything else
log_message "runtime.sh: milestone run_sd_card_fix_if_triggered (end)"
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

# Recover from stale pseudo-sleep ownership markers left by unclean shutdown/reboot.
for stale_file in /tmp/power_mode.state /tmp/power_watchdog_suspended /tmp/power_watchdog_rearm_after /tmp/sleep_helper_started /tmp/power_pressed_flag /tmp/powerbtn /tmp/powerbtn_cancelled /tmp/power_shutdown_requested /tmp/shutdown_in_progress.lockdir; do
    if [ -e "$stale_file" ]; then
        log_message "runtime.sh: clearing stale power state marker ${stale_file}"
        if [ -d "$stale_file" ]; then
            rm -rf "$stale_file"
        else
            rm -f "$stale_file"
        fi
    fi
done

if command -v power_mode_boot_reset_running >/dev/null 2>&1; then
    power_mode_boot_reset_running "watchdog"
    log_message "runtime.sh: boot reset power mode contract to running/watchdog"
elif command -v power_mode_set_running >/dev/null 2>&1; then
    power_mode_set_running "watchdog"
    log_message "runtime.sh: initialized power mode contract to running/watchdog"
fi

# Check for first_boot flags and run Unpacker accordingly
FIRSTBOOT_FLAG="first_boot_${PLATFORM}"
FIRSTBOOT_IN_PROGRESS_FLAG="first_boot_${PLATFORM}_in_progress"
FIRSTBOOT_COMPLETE_FLAG="first_boot_${PLATFORM}_complete"
FIRSTBOOT_COMPLETE_VERIFIED_FLAG="first_boot_${PLATFORM}_complete_verified"

firstboot_completion_artifacts_look_clean() {
    # Runtime-side one-time verification is convergence-based. It does not rely
    # on whether firstboot happened to observe unpack locks during grace windows.
    if flag_check "pre_menu_unpacking"; then
        log_message "runtime.sh: firstboot verification failed (pre_menu_unpacking still active)"
        return 1
    fi

    if flag_check "themes_unpacking"; then
        log_message "runtime.sh: firstboot verification failed (themes_unpacking still active)"
        return 1
    fi

    if flag_check "pre_cmd_unpacking"; then
        log_message "runtime.sh: firstboot verification failed (pre_cmd_unpacking still active)"
        return 1
    fi

    # Startup-owned archive locations must be empty once firstboot is complete.
    # preCmd is intentionally excluded because later boots may legitimately stage
    # pre_cmd work there.
    for startup_dir in /mnt/SDCARD/spruce/archives/preMenu /mnt/SDCARD/Themes /mnt/SDCARD/RetroArch/.retroarch/assets; do
        if [ ! -d "$startup_dir" ]; then
            log_message "runtime.sh: verification skipping missing startup archive directory ${startup_dir}"
            continue
        fi

        leftover_archive="$(find "$startup_dir" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)"
        if [ -n "$leftover_archive" ]; then
            log_message "runtime.sh: firstboot verification failed (leftover startup archive: ${leftover_archive})"
            return 1
        fi
    done

    return 0
}

log_message "runtime.sh: milestone archive_unpack_boot_gate (checking ${FIRSTBOOT_FLAG} / ${FIRSTBOOT_IN_PROGRESS_FLAG} / ${FIRSTBOOT_COMPLETE_FLAG})"

if flag_check "$FIRSTBOOT_COMPLETE_FLAG" && ! flag_check "$FIRSTBOOT_COMPLETE_VERIFIED_FLAG"; then
    log_message "runtime.sh: found firstboot complete marker; verifying startup artifacts"
    if firstboot_completion_artifacts_look_clean; then
        flag_add "$FIRSTBOOT_COMPLETE_VERIFIED_FLAG"
        log_message "runtime.sh: firstboot completion verified successfully"
    else
        log_message "runtime.sh: firstboot completion marker invalidated by leftover startup artifacts; re-entering recovery"
        flag_remove "$FIRSTBOOT_COMPLETE_FLAG"
        flag_remove "$FIRSTBOOT_COMPLETE_VERIFIED_FLAG"
        flag_add "$FIRSTBOOT_FLAG"
        flag_add "$FIRSTBOOT_IN_PROGRESS_FLAG"
    fi
fi

if flag_check "$FIRSTBOOT_FLAG" || (flag_check "$FIRSTBOOT_IN_PROGRESS_FLAG" && ! flag_check "$FIRSTBOOT_COMPLETE_FLAG"); then
    if flag_check "$FIRSTBOOT_IN_PROGRESS_FLAG" && ! flag_check "$FIRSTBOOT_FLAG"; then
        log_message "runtime.sh: detected interrupted firstboot recovery path"
        flag_add "$FIRSTBOOT_FLAG"
    fi

    log_message "runtime.sh: launching archiveUnpacker.sh --silent in background (first boot/recovery path)"
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent &
    log_message "Unpacker started silently in background due to first_boot/in-progress flag"
    log_message "runtime.sh: launching firstboot.sh (foreground)"
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
    log_message "runtime.sh: firstboot.sh completed"
else
    log_message "runtime.sh: launching archiveUnpacker.sh (default/all mode, foreground)"
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    log_message "runtime.sh: archiveUnpacker.sh default/all mode foreground run completed"
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

# Emit BOOT_COMPLETE before entering any active runtime lanes (watchdogs,
# power-button handling, and potential game autoresume) so shutdown/sleep
# transitions cannot evaluate against stale BOOTING state.
emit_boot_complete_once "runtime_services_start" "startup tasks complete; enabling runtime services"

log_message "runtime.sh: milestone launch_startup_watchdogs (begin)"
launch_startup_watchdogs
log_message "runtime.sh: milestone launch_startup_watchdogs (end)"

# run automation-first diagnostics in background only when explicitly enabled
if flag_check "RUN_STARTTIME_DIAGNOSTICS"; then
    touch /tmp/run_starttime_diagnostics_boot_init
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

# Safety net in case startup flow changes in future edits.
emit_boot_complete_once "runtime_ready" "startup tasks complete; entering principal loop"

# start main loop
log_message "runtime.sh: starting principal loop"
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
