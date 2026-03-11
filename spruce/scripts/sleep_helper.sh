#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SLEEP_INVOCATION_SOURCE="${1:-unknown_source}"
sleep_shutdown_requested=0

shutdown_pending_now() {
    if command -v power_mode_is_shutdown_pending >/dev/null 2>&1; then
        power_mode_is_shutdown_pending
        return $?
    fi

    command -v power_trace_shutdown_pending >/dev/null 2>&1 && power_trace_shutdown_pending
}

if shutdown_pending_now; then
    log_message "sleep_helper.sh: suppressing sleep invocation because shutdown is pending (source=${SLEEP_INVOCATION_SOURCE})"
    power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "OFF" "RUNNING" "sleep_invocation_suppressed_shutdown_pending" "sleep_helper.sh:entry" "sleep suppressed while shutdown pending source=${SLEEP_INVOCATION_SOURCE}" "" "normal" "" "" "" ""
    exit 0
fi

if [ -e /tmp/sleep_helper_started ]; then
    existing_pid=$(cat /tmp/sleep_helper_started 2>/dev/null)
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        log_message "Sleep helper already active (pid=${existing_pid}), skipping duplicate invocation (source=${SLEEP_INVOCATION_SOURCE})." -v
        exit 0
    fi
    log_message "Sleep helper found stale /tmp/sleep_helper_started (pid=${existing_pid:-unknown}); clearing and continuing."
    rm -f /tmp/sleep_helper_started
fi

current_app="$(get_current_app)"
log_activity_event "$current_app" "STOP"

log_message "Sleep helper starting up (source=${SLEEP_INVOCATION_SOURCE})..."
rm -f /tmp/power_pressed_flag

echo "$$" > /tmp/sleep_helper_started

if command -v power_mode_claim_sleep_owner >/dev/null 2>&1; then
    if ! power_mode_claim_sleep_owner "sleep_helper"; then
        log_message "sleep_helper.sh: failed to claim sleep owner because shutdown is pending (source=${SLEEP_INVOCATION_SOURCE})"
        exit 0
    fi
fi

if [ "$(device_uses_pseudo_sleep)" = "true" ]; then
    # Transitional marker only: canonical sleep ownership is in power_mode; this remains for legacy observers.
    touch /tmp/power_watchdog_suspended
fi
START_TIME=$(date +%s)
getevent $EVENT_PATH_POWER | while read -r line; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    # Ignore events for the first 2 seconds of script starting
    # as sometimes the power button can trigger a couple times immediately
    if [ "$ELAPSED" -lt 2 ]; then
        continue
    fi
    case "$line" in
        *"key $B_POWER 1"*) 
            touch /tmp/power_pressed_flag
        ;;
    esac
done &
GET_EVENT_PID=$!


power_button_pressed() {
    if [ -e /tmp/power_pressed_flag ]; then
        rm -f /tmp/power_pressed_flag
        return 0
    else
        return 1
    fi
}

cleanup_sleep_helper() {
    log_message "sleep_helper.sh: cleanup (pid=$$, getevent_pid=${GET_EVENT_PID:-none})" -v
    kill "$GET_EVENT_PID" 2>/dev/null
    rm -f "$POWER_BUTTON_PIPE" /tmp/power_watchdog_suspended /tmp/sleep_helper_started /tmp/power_pressed_flag
}

# Clean up on exit
trap cleanup_sleep_helper EXIT

get_shutdown_timer() {
    local LID_TIMER
    LID_TIMER="$(get_config_value '.menuOptions."Battery Settings".shutdownFromSleep.selected' "15m")"
    local IDLE_TIMEOUT=0

    case "$LID_TIMER" in
        "Off")  IDLE_TIMEOUT=31536000 ;; # 1 year
        "5s")   IDLE_TIMEOUT=5 ;;
        "30s")  IDLE_TIMEOUT=30 ;;
        "1m")   IDLE_TIMEOUT=60 ;;
        "2m")   IDLE_TIMEOUT=120 ;;
        "5m")   IDLE_TIMEOUT=300 ;;
        "15m")  IDLE_TIMEOUT=900 ;;
        "30m")  IDLE_TIMEOUT=1800 ;;
        "60m")  IDLE_TIMEOUT=3600 ;;
        "2h")   IDLE_TIMEOUT=7200 ;;
        "3h")   IDLE_TIMEOUT=10800 ;;
        "4h")   IDLE_TIMEOUT=14400 ;;
    esac

    echo "$IDLE_TIMEOUT"
}


trigger_sleep() {
    power_trace_emit "SLEEP_PREPARE_BEGIN" "AUTO" "SLEEPING" "RUNNING" "power_button" "sleep_helper.sh:trigger_sleep" "sleep helper invoked source=${SLEEP_INVOCATION_SOURCE}" "" "" "autosave_possible" "" "" ""
    log_message "Entering sleep"
    lid_ever_closed=false
    sleep_exited=false
    # Get the lid powerdown timeout
    local IDLE_TIMEOUT
    IDLE_TIMEOUT=$(get_shutdown_timer)
    start_ts=$(date +%s)
    set_volume 0 false # Mute on sleep so when we wake to shutdown it's silent
    pause_emulators
    sleep 0.5
    # Kill exclusive getevent to prevent buffered wake button events
    # from causing a re-sleep loop. The power watchdog's outer loop
    # will restart getevent fresh after sleep_helper exits.
    power_trace_emit "SLEEP_PREPARE_COMPLETE" "AUTO" "SLEEPING" "RUNNING" "pre_sleep_ready" "sleep_helper.sh:trigger_sleep" "pre-sleep preparation done" "" "" "autosave_possible" "" "" ""
    power_trace_emit "SLEEP_REQUESTED" "AUTO" "SLEEPING" "RUNNING" "sleep_request" "sleep_helper.sh:trigger_sleep" "calling device_enter_sleep" "" "" "" "" "" ""
    power_trace_emit "SLEEP_ENTER_BEGIN" "AUTO" "SLEEPING" "RUNNING" "sleep_entry" "sleep_helper.sh:trigger_sleep" "about to enter device sleep" "" "" "" "" "" ""
    if [ "$(device_uses_pseudo_sleep)" != "true" ]; then
        kill $(pgrep -f "getevent.*-exclusive") 2>/dev/null
        sleep 0.3
    fi
    if ! device_enter_sleep "$IDLE_TIMEOUT"; then
        power_trace_emit "POWER_ERROR" "AUTO" "SLEEPING" "RUNNING" "device_enter_sleep" "sleep_helper.sh:trigger_sleep" "device_enter_sleep failed" "" "" "" "" "device_enter_sleep_returned_nonzero" ""
        power_trace_emit "TRANSITION_ABORTED" "AUTO" "SLEEPING" "RUNNING" "device_enter_sleep" "sleep_helper.sh:trigger_sleep" "sleep transition aborted during entry" "" "" "" "" "" ""
        return 1
    fi
    power_trace_emit "SLEEP_ENTER_COMPLETE" "AUTO" "SLEEPING" "SLEEPING" "sleep_entered" "sleep_helper.sh:trigger_sleep" "device sleep call returned" "" "" "" "" "" ""
    if [ "$(device_uses_pseudo_sleep)" = "true" ]; then
        log_message "Device uses pseudosleep -- starting idle loop"
        log_message "Starting idle timeout countdown: ${IDLE_TIMEOUT}s until poweroff if lid remains closed"
        local elapsed=0
        local current_lid_state

        while [ "$elapsed" -lt "$IDLE_TIMEOUT" ]; do
            if shutdown_pending_now; then
                log_message "sleep_helper.sh: shutdown pending while pseudo-sleep active, aborting resume path"
                return 0
            fi

            current_lid_state=$(device_lid_open)
                
            # Track if lid was ever closed
            if [ "$current_lid_state" = "0" ]; then
                log_message "Detected lid closed, will now wait for it to open"
                lid_ever_closed=true
            fi

            # If lid opened, restore screen and break
            if [ "$current_lid_state" = "1" ] && [ "$lid_ever_closed" = true ]; then
                log_message "Lid opened"
                sleep_exited=true 
                break
            elif power_button_pressed; then
                if [ "$current_lid_state" = "1" ]; then
                    log_message "Power button pressed, exiting pseudosleep"
                    sleep_exited=true 
                    break
                else
                    log_message "Power button pressed but lid is closed, continuing pseudosleep"
                fi
            fi

            sleep 1
            now_ts=$(date +%s)
            elapsed=$((now_ts - start_ts))
        done

        # Timeout reached without exitting sleep → poweroff
        if [ "$sleep_exited" = false ]; then
            power_trace_emit "TRANSITION_TIMEOUT" "AUTO" "RUNNING" "SLEEPING" "sleep_timeout" "sleep_helper.sh:trigger_sleep" "pseudo-sleep timeout hit; requesting poweroff" "" "idle_timeout" "" "" "" "$((IDLE_TIMEOUT * 1000))"
            log_message "Lid closed for ${IDLE_TIMEOUT}s, triggering poweroff"
            # Set clocks bad to full speed
            set_performance
            sleep 0.1
            sleep_shutdown_requested=1
            invoke_save_poweroff_singleflight "sleep_helper:lid_timeout"
            return 0
        fi
    else
        
        while [ "$(device_lid_open)" = "0" ]; do
            if shutdown_pending_now; then
                log_message "sleep_helper.sh: shutdown pending while waiting for lid open, aborting resume path"
                return 0
            fi
            if [ "$(device_woke_via_timer)" = "true" ]; then
                break
            fi

            log_message "Lid is closed, but not in sleep -- Retrigger sleep -- IDLE_TIMEOUT=$IDLE_TIMEOUT"
            device_continue_sleep
        done


        if [ "$(device_woke_via_timer)" = "true" ]; then
            power_trace_emit "TRANSITION_TIMEOUT" "AUTO" "RUNNING" "SLEEPING" "rtc_timeout" "sleep_helper.sh:trigger_sleep" "woke via timer and escalating to poweroff" "rtc" "idle_timeout" "" "" "" "$((IDLE_TIMEOUT * 1000))"
            log_message "Idle time exceeded, triggering poweroff -- IDLE_TIMEOUT=$IDLE_TIMEOUT"
            sleep 0.1
            sleep_shutdown_requested=1
            invoke_save_poweroff_singleflight "sleep_helper:rtc_timeout"
            return 0
        else
            power_trace_emit "WAKE_DETECTED" "AUTO" "RUNNING" "WAKING" "manual" "sleep_helper.sh:trigger_sleep" "manual wake detected" "power_button_or_lid" "" "" "" "" ""
            log_message "Woke from sleep manually"
        fi
    fi
}

if ! trigger_sleep; then
    power_trace_emit "TRANSITION_ABORTED" "AUTO" "RUNNING" "RUNNING" "trigger_sleep_failed" "sleep_helper.sh:main" "trigger_sleep returned failure" "" "" "" "" "" ""
    kill "$GET_EVENT_PID" 2>/dev/null
    rm -f /tmp/sleep_helper_started
    exit 1
fi

if [ "$sleep_shutdown_requested" = "1" ] || shutdown_pending_now; then
    log_message "sleep_helper.sh: shutdown pending/requested after sleep trigger; skipping resume actions"
    exit 0
fi

power_trace_emit "WAKE_RESUME_BEGIN" "AUTO" "RUNNING" "WAKING" "resume_start" "sleep_helper.sh:main" "beginning post-wake restore" "" "" "" "" "" ""
if ! device_exit_sleep; then
    power_trace_emit "POWER_ERROR" "AUTO" "RUNNING" "WAKING" "device_exit_sleep" "sleep_helper.sh:main" "device_exit_sleep failed" "" "" "" "" "device_exit_sleep_returned_nonzero" ""
fi

log_activity_event "$current_app" "START"

# Restore volume before unpausing so audio is ready
VOLUME_LV=$(jq -r '.vol' "$SYSTEM_JSON")
set_volume "$VOLUME_LV"

unpause_emulators
power_trace_emit "WAKE_RESUME_COMPLETE" "AUTO" "RUNNING" "RUNNING" "resume_complete" "sleep_helper.sh:main" "post-wake restore complete" "" "" "" "" "" ""

if [ "$(device_uses_pseudo_sleep)" = "true" ]; then
    if command -v power_mode_enter_rearm >/dev/null 2>&1; then
        power_mode_enter_rearm "sleep_helper" 3
    fi

    # Canonical rearm boundary is owned by power_mode.
else
    if command -v power_mode_set_running >/dev/null 2>&1; then
        power_mode_set_running "watchdog"
    fi
fi

kill "$GET_EVENT_PID" 2>/dev/null

# Clear pending power-button watchdog state before allowing new sleep requests.
# This prevents wake-related/stale power transitions from immediately retriggering sleep.
rm -f /tmp/powerbtn /tmp/powerbtn_cancelled /tmp/power_pressed_flag

# Remove transitional marker after canonical ownership handoff completes.
rm -f /tmp/power_watchdog_suspended

sleep 2 #don't allow resleeping for a few seconds
if command -v power_mode_set_running >/dev/null 2>&1; then
    power_mode_set_running "watchdog"
fi
rm -f /tmp/sleep_helper_started
