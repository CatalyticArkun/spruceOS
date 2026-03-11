#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "power_button_watchdog_v2.sh: Started up."


reset_power_button_state() {
    rm -f /tmp/powerbtn /tmp/powerbtn_cancelled

    if [ -n "$power_hold_pid" ]; then
        kill "$power_hold_pid" 2>/dev/null
        wait "$power_hold_pid" 2>/dev/null
        power_hold_pid=""
    fi
}

suppression_reset_done=0

handle_suppressed_watchdog_window() {
    if watchdog_suspended_or_not_rearmed; then
        if [ "$suppression_reset_done" -ne 1 ]; then
            log_message "power_button_watchdog_v2.sh: Sleep ownership active or rearm pending; resetting state while keeping stream alive."
            reset_power_button_state
            suppression_reset_done=1
        fi

        return 0
    fi

    suppression_reset_done=0
    return 1
}

watchdog_suspended_or_not_rearmed() {
    if command -v power_mode_watchdog_may_handle_input >/dev/null 2>&1; then
        # Reconcile rearm completion explicitly before asking the pure predicate.
        if command -v power_mode_watchdog_reconcile_after_rearm >/dev/null 2>&1; then
            power_mode_watchdog_reconcile_after_rearm >/dev/null 2>&1 || true
        fi

        if power_mode_watchdog_may_handle_input; then
            return 1
        fi

        if shutdown_pending_now; then
            log_message "power_button_watchdog_v2.sh: Suppressing input handling because shutdown is pending."
            return 0
        fi

        log_message "power_button_watchdog_v2.sh: Suppressing power event stream while sleep/rearm ownership is active."
        return 0
    fi

    # Legacy marker fallback only when power_mode helpers are unavailable
    # (partial-upgrade or helper-load failure paths).
    if [ -e /tmp/power_watchdog_suspended ]; then
        marker_pid="$(cat /tmp/power_watchdog_suspended 2>/dev/null)"
        case "$marker_pid" in
            ''|*[!0-9]*)
                log_message "power_button_watchdog_v2.sh: Clearing malformed legacy suspended marker."
                rm -f /tmp/power_watchdog_suspended
                return 1
                ;;
        esac

        if kill -0 "$marker_pid" 2>/dev/null; then
            return 0
        fi

        log_message "power_button_watchdog_v2.sh: Clearing stale legacy suspended marker pid=${marker_pid}."
        rm -f /tmp/power_watchdog_suspended
        return 1
    fi

    return 1
}

power_key_up () {
    log_message "Power button released at $(date +%s)"  
    if [ -e /tmp/powerbtn ]; then
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
                log_message "power_button_watchdog_v2.sh: suppressing short-press sleep because lifecycle gate denied request"
                power_trace_emit "REQUEST_SUPPRESSED" "AUTO" "OFF" "RUNNING" "short_press_ignored_lifecycle_gate" "power_button_watchdog_v2.sh:power_key_up" "sleep suppressed by lifecycle gate" "" "normal" "" "" "" ""
            else
                log_message "power_button_watchdog_v2.sh: invoking sleep_helper.sh after uncancelled short press"
                /mnt/SDCARD/spruce/scripts/sleep_helper.sh watchdog_short_press
            fi
        fi
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
                log_message "power_button_watchdog_v2.sh: Powering off due to power button hold."
                power_trace_emit "SHUTDOWN_BEGIN" "AUTO" "OFF" "RUNNING" "power_button_hold" "power_button_watchdog_v2.sh:power_key_down" "long press requested poweroff" "" "forced" "autosave_expected" "" "" ""
                # Canonical shutdown ownership belongs to save_poweroff singleflight;
                # do not pre-mark pending before handoff.
                vibrate &
                rm -f /tmp/powerbtn
                rm -f /tmp/powerbtn_cancelled
                killall getevent 2>/dev/null
                sleep 0.1
                invoke_save_poweroff_singleflight "power_button_watchdog_v2:power_button_hold"
            fi
        ) &
        power_hold_pid=$!
    fi
}


run_watchdog_loop() {
    while true; do
        LAST_POWER_DOWN=0
        log_message "power_button_watchdog_v2.sh: Monitoring power button events on $EVENT_PATH_POWER"
        getevent -exclusive -pid $$ $EVENT_PATH_POWER | while read line; do
            if handle_suppressed_watchdog_window; then
                # Keep consuming the stream so we do not create a restart/listener gap.
                continue
            fi

            now=$(date +%s)
            case $line in
                # Power key down
                *"key $B_POWER 1"*)
                    if [ $((now - LAST_POWER_DOWN)) -ge 1 ]; then
                        log_message "power_button_watchdog_v2.sh: power_key_down"
                        power_key_down
                        LAST_POWER_DOWN=$now
                    fi
                    ;;

                # Power key up
                *"key $B_POWER 0"*)
                        log_message "power_button_watchdog_v2.sh: power_key_up"
                        power_key_up
                    ;;
                esac
        done
        log_message "power_button_watchdog_v2.sh: getevent pipe exited, restarting..."
        sleep 1
    done
}

if [ "${POWER_BUTTON_WATCHDOG_TEST_MODE:-0}" != "1" ]; then
    run_watchdog_loop
fi
