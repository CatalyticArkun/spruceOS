#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh

start_pyui_message_writer

log_message "Starting firstboot script on $PLATFORM"

FIRST_BOOT_FLAG="first_boot_${PLATFORM}"
FIRST_BOOT_IN_PROGRESS_FLAG="first_boot_${PLATFORM}_in_progress"
FIRST_BOOT_COMPLETE_FLAG="first_boot_${PLATFORM}_complete"
FIRST_BOOT_VERIFIED_FLAG="first_boot_${PLATFORM}_complete_verified"

flag_add "$FIRST_BOOT_IN_PROGRESS_FLAG"
flag_remove "$FIRST_BOOT_COMPLETE_FLAG"
flag_remove "$FIRST_BOOT_VERIFIED_FLAG"

WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
UNPACKING_ICON="/mnt/SDCARD/spruce/imgs/refreshing.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"


display_image_and_text "$SPRUCE_LOGO" 35 25 "Installing spruce $SPRUCE_VERSION" 75

sleep 5 # make sure installing spruce logo stays up longer; gives more time for XMB to unpack too

SSH_SERVICE_NAME=$(get_ssh_service_name)
if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
    log_message "Preparing SSH keys if necessary"
    dropbear_generate_keys &
fi

if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
    mkdir -p /mnt/SDCARD/Persistent/
    if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
        display_image_and_text "$SPRUCE_LOGO" 35 25 "Extracting PortMaster!" 75
        extract_7z_with_progress /mnt/SDCARD/App/PortMaster/portmaster.7z /mnt/SDCARD/Persistent/ /mnt/SDCARD/Saves/spruce/portmaster_extract.log
    else
        display_image_and_text "$SPRUCE_LOGO" 35 25 "PortMaster already exists, removing install archive" 75
    fi

    rm -f /mnt/SDCARD/App/PortMaster/portmaster.7z
fi

# Extract ScummVM standalone binaries (64-bit only)
if [ "$PLATFORM_ARCHITECTURE" != "armhf" ]; then
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    for SCUMMVM_7Z in "$SCUMMVM_DIR"/scummvm_*.7z; do
        [ -f "$SCUMMVM_7Z" ] || continue
        display_image_and_text "$SPRUCE_LOGO" 35 25 "Extracting ScummVM!" 75
        extract_7z_with_progress "$SCUMMVM_7Z" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log
        rm -f "$SCUMMVM_7Z"
    done
fi

display_image_and_text "$WIKI_ICON" 35 25 "Check out the spruce wiki on our GitHub page for tips and FAQs!" 75
sleep 5

perform_fw_check

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
else
	log_message "firstboot.sh: $SPLORE_CART already found."
fi

"$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/

display_image_and_text "$HAPPY_ICON" 35 25 "Happy gaming.........." 75
sleep 5

wait_for_startup_unpack_flags() {
    grace_seconds=90
    waited=0

    while [ "$waited" -lt "$grace_seconds" ]; do
        if ! flag_check "pre_menu_unpacking" && ! flag_check "pre_cmd_unpacking" && ! flag_check "themes_unpacking"; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 1
}

startup_unpack_converged() {
    if flag_check "pre_menu_unpacking" || flag_check "pre_cmd_unpacking" || flag_check "themes_unpacking"; then
        log_message "Firstboot convergence failed: unpack flags still present"
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
            log_message "Firstboot convergence failed: startup archives remain in $check_dir"
            return 1
        fi
    done

    return 0
}

display_image_and_text "$UNPACKING_ICON" 35 25 "Finishing up unpacking themes and files.........." 75

if ! wait_for_startup_unpack_flags || ! startup_unpack_converged; then
    log_message "Firstboot convergence did not complete successfully"
    exit 1
fi

flag_add "$FIRST_BOOT_COMPLETE_FLAG"
flag_add "$FIRST_BOOT_VERIFIED_FLAG"
flag_remove "$FIRST_BOOT_FLAG"
flag_remove "$FIRST_BOOT_IN_PROGRESS_FLAG"

log_message "Finished firstboot script"
