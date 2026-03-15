#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "power_button_watchdog_v2.sh: Started up."




power_key_up () {
    if [ -e /tmp/powerbtn ]; then
        log_message "Power button released at $(date +%s)"  
        rm -f /tmp/powerbtn

        was_cancelled=false
        if [ -e /tmp/powerbtn_cancelled ]; then
            was_cancelled=true
            rm -f /tmp/powerbtn_cancelled
        fi

        # Kill background hold timer if still running
        if [ -n "$power_hold_pid" ]; then
            kill "$power_hold_pid" 2>/dev/null
            wait "$power_hold_pid" 2>/dev/null
            power_hold_pid=""
        fi

        if [ "$was_cancelled" = false ]; then
            if ! sleep_requests_allowed_now; then
                power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "SLEEPING" "RUNNING" "power_button_short_press" "power_button_watchdog_v2.sh:power_key_up" "sleep request suppressed; lifecycle gate closed" "" "normal" "" "" "" ""
                return
            fi
            power_trace_emit "SLEEP_REQUESTED" "AUTO" "SLEEPING" "RUNNING" "power_button_short_press" "power_button_watchdog_v2.sh:power_key_up" "short press requested sleep" "" "normal" "" "" "" ""
            /mnt/SDCARD/spruce/scripts/sleep_helper.sh
        else
            power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "SLEEPING" "RUNNING" "power_button_short_press" "power_button_watchdog_v2.sh:power_key_up" "sleep request cancelled by combo input" "" "normal" "" "" "" ""
        fi
    else
        log_message "Power button released during cooldown at $(date +%s)"  
    fi

}

power_key_down () {

    if [ ! -e /tmp/powerbtn ]; then
        power_btn_press_time=$(date +%s)
        log_message "Power button pressed at $power_btn_press_time" 
        touch /tmp/powerbtn

        # Launch background timer that waits required seconds, then triggers the action
        (
            power_hold_time=2
            sleep "$power_hold_time"
            # Check if the powerbtn file still exists (i.e. button still held) AND NOT cancelled (i.e. no other button pressed)
            if [ -e /tmp/powerbtn ] && [ ! -e /tmp/powerbtn_cancelled ]; then
                if power_trace_shutdown_pending; then
                    power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "OFF" "RUNNING" "power_button_hold" "power_button_watchdog_v2.sh:power_key_down" "long press duplicate_request while shutdown pending" "" "forced" "autosave_expected" "" "" ""
                    rm -f /tmp/powerbtn
                    return
                fi
                log_message "power_button_watchdog_v2.sh: Powering off due to power button hold."
                power_trace_emit "SHUTDOWN_BEGIN" "AUTO" "OFF" "RUNNING" "power_button_hold" "power_button_watchdog_v2.sh:power_key_down" "long press requested poweroff" "" "forced" "autosave_expected" "" "" ""
                vibrate &
                rm -f /tmp/powerbtn
                rm -f /tmp/powerbtn_cancelled
                killall getevent 2>/dev/null
                sleep 0.1
                "$POWER_OFF_SCRIPT"
            fi
        ) &
        power_hold_pid=$!
    else
        log_message "Power button pressed during cooldown at $power_btn_press_time"  
    fi
}

LAST_POWER_DOWN=0
PREV_WAS_POWER=0
while true; do
    log_message "power_button_watchdog_v2.sh: Monitoring power button events on $EVENT_PATH_POWER"
    getevent -exclusive -pid $$ $EVENT_PATH_POWER | while read line; do
        now=$(date +%s)
        # If last loop contained B_POWER, update LAST_POWER_DOWN now
        if [ "$PREV_WAS_POWER" -eq 1 ]; then
            LAST_POWER_DOWN=$now
            PREV_WAS_POWER=0
        fi
        case $line in
            # Power key down
            *"key $B_POWER 1"*)
                if [ $((now - LAST_POWER_DOWN)) -ge 1 ]; then
                    log_message "power_button_watchdog_v2.sh: power_key_down"
                    power_key_down
                    PREV_WAS_POWER=1
                else
                    power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "RUNNING" "RUNNING" "power_button_debounce" "power_button_watchdog_v2.sh:main" "duplicate_request suppressed by debounce" "" "normal" "" "" "" ""
                fi
                ;;

            # Power key up
            *"key $B_POWER 0"*)
                    log_message "power_button_watchdog_v2.sh: power_key_up"
                    power_key_up
                    PREV_WAS_POWER=1
                ;;
            esac
    done
}

if [ "${POWER_BUTTON_WATCHDOG_TEST_MODE:-0}" != "1" ]; then
    run_watchdog_loop
fi
