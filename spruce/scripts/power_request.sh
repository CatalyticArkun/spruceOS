#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

action="${1:-shutdown}"
requester="${2:-ui}"

case "$action" in
    shutdown)
        invoke_save_poweroff_singleflight "pyui_request:${requester}:shutdown"
        ;;
    reboot)
        invoke_save_poweroff_singleflight "pyui_request:${requester}:reboot" --reboot
        ;;
    *)
        log_message "power_request.sh: unknown action=${action} requester=${requester}"
        exit 1
        ;;
esac
