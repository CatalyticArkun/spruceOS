#!/bin/sh

##### IMPORTS AND CONSTANTS ###################

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
BG_TREE="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SAVE_IMG="/mnt/SDCARD/spruce/imgs/save.png"

EMU_PROCESSES="ra32.a30 ra32.mini ra64.universal retroarch \
drastic drastic32 drastic64 pico8_dyn pico8_64 \
flycast flycast-stock yabasanshiro yabasanshiro.trimui \
mupen64plus PPSSPPSDL PPSSPPSDL_TrimUI PPSSPPSDL_$PLATFORM"

STAGE_2_SD_PATH=/mnt/SDCARD/spruce/scripts/save_poweroff_stage2.sh
STAGE_2_TMP_PATH=/tmp/save_poweroff_stage2.sh

if [ "$1" = "--reboot" ]; then
    s2_arg="--reboot";
else
    s2_arg=""
fi

shutdown_guard_claimed="false"
if [ "${SHUTDOWN_GUARD_OWNED:-0}" = "1" ]; then
    shutdown_guard_claimed="true"
elif shutdown_singleflight_begin "save_poweroff.sh:entry"; then
    shutdown_guard_claimed="true"
else
    log_message "save_poweroff.sh: shutdown already in progress. Ignoring duplicate call before startup sequence."
    system_emit "power" "RUNNING" "OFF" "save_poweroff.sh:singleflight_guard" "duplicate save_poweroff invocation ignored by shutdown guard"
    exit 0
fi

shutdown_handoff_started="false"
power_shutdown_begin_emitted="false"
power_shutdown_handoff_emitted="false"

release_singleflight_if_prehandoff_exit() {
    reason="${1:-unknown}"

    if [ "$shutdown_guard_claimed" = "true" ] && [ "$shutdown_handoff_started" != "true" ]; then
        shutdown_singleflight_clear
        log_message "save_poweroff.sh: released shutdown singleflight guard before irreversible handoff (reason=${reason})"
        system_emit "power" "RUNNING" "RUNNING" "save_poweroff.sh:singleflight_release" "singleflight guard released before irreversible handoff reason=${reason}"
    fi
}

power_trace_emit_shutdown_begin_once() {
    [ "$power_shutdown_begin_emitted" = "true" ] && return 0

    if shutdown_pending_now; then
        system_emit "power" "SHUTDOWN_PENDING" "OFF" "save_poweroff.sh:startup" "shutdown already pending before save_poweroff entry"
    else
        system_emit "power" "RUNNING" "OFF" "save_poweroff.sh:startup" "shutdown path requested"
    fi

    power_shutdown_begin_emitted="true"
}

power_trace_emit_shutdown_handoff_once() {
    trigger="$1"
    source_ref="$2"
    notes="$3"

    [ "$power_shutdown_handoff_emitted" = "true" ] && return 0

    system_emit "power" "SHUTDOWN_PENDING" "OFF" "$source_ref" "${notes} trigger=${trigger}"
    power_shutdown_handoff_emitted="true"
}

if [ "$s2_arg" = "--reboot" ]; then
    system_emit "power" "RUNNING" "BOOTING" "save_poweroff.sh:startup" "reboot path requested"
else
    power_trace_emit_shutdown_begin_once
fi

if command -v power_mode_mark_shutdown_pending >/dev/null 2>&1; then
    power_mode_mark_shutdown_pending "save_poweroff"
fi

touch /tmp/power_shutdown_requested
log_message "save_poweroff.sh: marked /tmp/power_shutdown_requested at shutdown entry"

shutdown_had_emu=false

##### FUNCTION DEFINITIONS ####################

blink_led_if_applicable() {
    [ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger
}

kill_current_process() {
    pid="$(pgrep -f '/tmp/cmd_to_run.sh' | head -n1)"
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
}

unmount_all() {
    sync
    log_message "save_poweroff.sh: Scanning for SD card related mounts..."
    MOUNTS=$(awk '
        {
            target = $5
            split($0, parts, " - ")
            device = parts[2]
            sub(/^[^ ]+ /, "", device)
            sub(/ .*/, "", device)

            # Match by block device, mount point under SD, source file on SD,
            # or overlay options referencing SD paths
            if (device == "'"$SD_DEV"'" ||
                target ~ "^'"$SD_MOUNTPOINT"'(/|$)" ||
                device ~ "^'"$SD_MOUNTPOINT"'/" ||
                device ~ "^/mnt/SDCARD/" ||
                ($0 ~ "/mnt/SDCARD" && device == "overlay")) {
                print target
            }
        }
    ' /proc/self/mountinfo)

    # Unmount deepest paths first, but skip the main SD mount (stage2 handles that)
    echo "$MOUNTS" | sort -r | while read -r TARGET; do
        [ -z "$TARGET" ] && continue
        if [ "$TARGET" != "$SD_MOUNTPOINT" ]; then
            log_message "save_poweroff.sh: Attempting to unmount $TARGET"
            umount "$TARGET" 2>/dev/null || umount -l "$TARGET" 2>/dev/null || \
                log_message "save_poweroff.sh: Failed to unmount $TARGET"
        fi
    done
}

attempt_to_close_emu_gracefully() {
    if pgrep -f "PPSSPPSDL" >/dev/null; then
        close_gracefully_ppsspp
    elif pgrep -f "drastic32" >/dev/null; then
        close_gracefully_drastic_steward
    else
        close_gracefully_all_emus
    fi
}

close_gracefully_ppsspp() {
    {
        # send autosave hot key
        echo 1 314 1 # SELECT down
        echo 1 311 1 # R1 down
        echo 1 311 0 # R1 up
        echo 1 314 0 # SELECT up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP || \
    log_message "Warning: sendevent failed during PPSSPP autosave"
    sleep 1
    killall -q -15 PPSSPPSDL_TrimUI 2>/dev/null
    killall -q -15 PPSSPPSDL_$PLATFORM 2>/dev/null
}

close_gracefully_drastic_steward() {
    {
        echo $B_L3 1    # Fn1 press
        echo $B_L3 0    # Fn1 release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        echo 0 0 0      # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_DRASTIC || \
    log_message "Warning: sendevent failed during DraStic-Steward autosave"
    sleep 1
    killall -q -15 drastic32 2>/dev/null
}

close_gracefully_all_emus() {
    for process in $EMU_PROCESSES; do
        killall -q -15 "$process" 2>/dev/null
    done
}

wait_for_graceful_emu_exit() {
    MAX_LOOPS=200   # ~10 seconds at 0.05s
    COUNT=0
    while :; do
        for process in $EMU_PROCESSES; do
            if killall -q -0 "$process" 2>/dev/null; then
                sleep 0.05
                COUNT=$((COUNT + 1))
                [ "$COUNT" -ge "$MAX_LOOPS" ] && break 2
                continue 2
            fi
        done
        break
    done
}

any_emu_is_running() {
    for process in $EMU_PROCESSES; do
        if killall -q -0 "$process" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

dismiss_active_emu_menu_state() {
    command -v send_menu_button_to_retroarch >/dev/null 2>&1 || return 0

    if pgrep -f "ra32.miyoo|retroarch|PPSSPPSDL" >/dev/null 2>&1; then
        log_message "save_poweroff.sh: attempting to dismiss in-game menu before emulator shutdown"
        send_menu_button_to_retroarch
        sleep 0.1
    fi
}

close_forcefully_all_emus() {
    for process in $EMU_PROCESSES; do
        killall -q -0 "$process" 2>/dev/null && killall -q -9 "$process" 2>/dev/null
    done
}

close_non_emu_cmd_to_run() {
    [ -f /tmp/cmd_to_run.sh ] || return 1
    if cat /tmp/cmd_to_run.sh | grep -q -v -e '/mnt/SDCARD/Emu' -e '/media/sdcard0/Emu' -e '/mnt/SDCARD/Emus'; then
        kill_current_process
        # remove lastgame flag to prevent loading any App after next boot
        rm "${FLAGS_DIR}/lastgame.lock"
    fi
}

stop_problematic_scripts() {
    # kill principal and runtime first so no new app / MainUI will be loaded anymore
    killall -q -15 runtime.sh
    killall -q -15 principal.sh

    # Ensure PyUI message writer can run
    killall -q -9 MainUI
    sleep 0.5

    # kill lid watchdog so that closing the lid doesn't interrupt the save/shutdown procedure
    pgrep -f "lid_watchdog_v2.sh" | xargs -r kill

    # kill enforceSmartCPU first so no CPU setting is changed during shutdown
    killall -q -15 enforceSmartCPU.sh

    # explicitly kill other watchdogs, etc. that might be keeping the SD card from unmounting.
    killall -q -9 homebutton_watchdog.sh
    killall -q -9 buttons_watchdog.sh
    killall -q -9 idlemon_mm.sh
    killall -q -9 low_power_warning.sh
    killall -q -9 autoIconRefresh.sh
    killall -q -9 inotifywait
    killall -q -9 inotifywatch
    killall -q -9 getevent
    killall -q -9 sendevent
}

display_appropriate_icon_and_message() {
    if flag_check "forced_shutdown"; then
        start_pyui_message_writer
        display_image_and_text "$SAVE_IMG" 33 10 "Battery level is below 1%. Shutting down to prevent progress loss." 60 50
        flag_remove "forced_shutdown"
    elif ! flag_check "in_menu"; then
        start_pyui_message_writer
        display_image_and_text "$SAVE_IMG" 33 10 "Saving and shutting down... Please wait a moment." 60 50
    fi
    sleep 1.5 # Let user read any messages
}

dim_screen_and_do_syncthing_check() {
    syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"
    if [ "$syncthing_enabled" = "True" ] && flag_check "emulator_launched"; then
        log_message "Syncthing is enabled, WiFi connection needed"

        if check_and_connect_wifi; then
            start_syncthing_process
            # Dimming screen before syncthing sync check
            dim_screen &
            DIM_SCREEN_PID=$!
            /mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh --shutdown
        fi

        flag_remove "syncthing_startup_synced"
    else
        dim_screen &
        DIM_SCREEN_PID=$!
    fi
}

kill_remaining_background_processes() {
    # Stop the PyUI message writer — it has file handles open on the SD card
    stop_pyui_message_writer

    # Kill dim_screen if it's still running (writes to sysfs, but inherits SD fds)
    if [ -n "$DIM_SCREEN_PID" ]; then
        kill "$DIM_SCREEN_PID" 2>/dev/null
        wait "$DIM_SCREEN_PID" 2>/dev/null
    fi

    # Kill syncthing if still alive — it actively writes to SD card
    killall -q -9 syncthing 2>/dev/null
    killall -q -9 wpa_supplicant 2>/dev/null

    # Brief pause for file descriptor cleanup
    sleep 0.2
}

clean_up_flags() {
    # Preserve autoresume only when shutdown came from an active game context
    # and we still have a command to resume.
    if flag_check "in_menu"; then
        # Menu-origin shutdown should not seed autoresume into a stale/ambiguous target,
        # while game-origin shutdown may preserve resume state when context is valid.
        flag_remove "save_active"
        rm -f "${FLAGS_DIR}/lastgame.lock"
        log_message "save_poweroff.sh: clean_up_flags -> in_menu=true, save_active cleared, lastgame.lock cleared"
    elif [ "$shutdown_had_emu" = "true" ] && [ -f "${FLAGS_DIR}/lastgame.lock" ]; then
        flag_add "save_active"
        log_message "save_poweroff.sh: clean_up_flags -> shutdown_had_emu=true and lastgame.lock present, save_active set"
    else
        flag_remove "save_active"
        log_message "save_poweroff.sh: clean_up_flags -> not preserving autoresume (shutdown_had_emu=${shutdown_had_emu}, lastgame_lock=$([ -f "${FLAGS_DIR}/lastgame.lock" ] && echo present || echo missing))"
    fi
    flag_remove "sleep.powerdown"
    flag_remove "emulator_launched"
    flag_remove "setting_cpu" # in case one of the set_cpu_mode() functions got interrupted

    if flag_check "in_menu"; then
        in_menu_state="true"
    else
        in_menu_state="false"
    fi
    log_message "save_poweroff.sh: autoresume decision summary save_active=$([ -f "${FLAGS_DIR}/save_active.lock" ] && echo true || echo false) lastgame_lock=$([ -f "${FLAGS_DIR}/lastgame.lock" ] && echo present || echo missing) shutdown_had_emu=${shutdown_had_emu} in_menu=${in_menu_state}"
}

exec_shutdown_stage_2() {
    log_message "Running stage 2 of save_poweroff from /tmp."
    sync
    if [ -e "$STAGE_2_SD_PATH" ]; then
        if [ "$s2_arg" != "--reboot" ]; then
            power_trace_emit_shutdown_handoff_once "stage2_exec_path" "save_poweroff.sh:exec_shutdown_stage_2" "copied stage2 shutdown script to tmp and handing off to final shutdown path"
        fi
        shutdown_handoff_started="true"
        cp $STAGE_2_SD_PATH $STAGE_2_TMP_PATH
        chmod +x $STAGE_2_TMP_PATH
        # Reset environment BEFORE exec so the new shell interpreter
        # doesn't load shared libraries from the SD card
        export PATH=/usr/bin:/usr/sbin:/bin:/sbin
        unset LD_LIBRARY_PATH
        exec "$STAGE_2_TMP_PATH" "$s2_arg"
    else
        log_message "ERROR: Stage 2 script missing! Executing run_poweroff_cmd() instead."
        system_emit "power" "RUNNING" "OFF" "save_poweroff.sh:exec_shutdown_stage_2" "stage2 shutdown script missing error=stage2_script_missing"
        if [ "$s2_arg" != "--reboot" ]; then
            power_trace_emit_shutdown_handoff_once "stage2_missing_fallback" "save_poweroff.sh:exec_shutdown_stage_2" "stage2 missing; handing off directly to platform poweroff command"
        fi
        shutdown_handoff_started="true"
        run_poweroff_cmd
    fi
}

cleanup_shutdown_attempt() {
    release_singleflight_if_prehandoff_exit "script_exit"
}

# Re-entry is canonicalized by shutdown_singleflight_* in helperFunctions.sh.
# Keep shutdown ownership in one place to avoid parallel PID-file contracts.
trap cleanup_shutdown_attempt EXIT INT TERM



                  ########
################### MAIN ######################
                  ########

blink_led_if_applicable
device_prepare_for_poweroff
log_activity_event "$(get_current_app)" "STOP"
# Sample emulator context before watchdog/process teardown so gameplay-origin
# shutdowns are not misclassified if emulators exit during shutdown sequencing.
if any_emu_is_running; then
    shutdown_had_emu=true
    log_message "save_poweroff.sh: preflight detected active emulator context"
fi
stop_problematic_scripts

if any_emu_is_running; then
    shutdown_had_emu=true
    dismiss_active_emu_menu_state
    attempt_to_close_emu_gracefully
    wait_for_graceful_emu_exit
    sync
    close_forcefully_all_emus
fi

if ! flag_check "in_menu"; then
    close_non_emu_cmd_to_run
fi

display_appropriate_icon_and_message
dim_screen_and_do_syncthing_check
clean_up_flags
alsactl store 2>/dev/null
kill_remaining_background_processes

# Systemd handles graceful shutdown on the pixel2
if device_system_handles_sdcard_unmount; then

    if [ "$s2_arg" = "--reboot" ]; then
        shutdown_handoff_started="true"
        device_run_reboot_cmd
    else
        power_trace_emit_shutdown_handoff_once "systemd_path" "save_poweroff.sh:systemd" "platform manages shutdown sequence directly"
        shutdown_handoff_started="true"
        run_poweroff_cmd
    fi

    exit 0
fi

unmount_all
sleep 0.1
unmount_all

exec_shutdown_stage_2
