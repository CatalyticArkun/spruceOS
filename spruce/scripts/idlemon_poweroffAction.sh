#!/bin/sh

# This script is a wrapper to take action on an idle event sourced from:
# ./idlemon -p MainUI -t 30 -c 5 -s "/mnt/SDCARD/spruce/scripts/idlemon_poweroffAction.sh" -i

[ -z "$1" ] && exit 1

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
process_name=$1

# Handle different process names....
case "$process_name" in

    MainUI|ra32.*|ra64.*|retroarch*|drastic*|PPSSPP*)
        invoke_save_poweroff_singleflight "idlemon_poweroffAction:${process_name}"
        ;;
    *)
        exit 1
        ;;
esac
