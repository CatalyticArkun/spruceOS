#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh

start_pyui_message_writer

FIRSTBOOT_FLAG="first_boot_$PLATFORM"
FIRSTBOOT_IN_PROGRESS_FLAG="first_boot_${PLATFORM}_in_progress"
FIRSTBOOT_COMPLETE_FLAG="first_boot_${PLATFORM}_complete"
FIRSTBOOT_COMPLETE_VERIFIED_FLAG="first_boot_${PLATFORM}_complete_verified"

flag_remove "$FIRSTBOOT_COMPLETE_FLAG"
flag_remove "$FIRSTBOOT_COMPLETE_VERIFIED_FLAG"
flag_add "$FIRSTBOOT_IN_PROGRESS_FLAG"
log_message "firstboot.sh: entered (set in-progress)"

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

unpacking_wait_ui_shown="false"

wait_for_unpack_with_grace() {
    lock_name="$1"
    label="$2"
    grace_checks=15 # 1.5s max to catch slightly-late lock publication

    while [ "$grace_checks" -gt 0 ]; do
        if flag_check "$lock_name"; then
            if [ "$unpacking_wait_ui_shown" != "true" ]; then
                display_image_and_text "$UNPACKING_ICON" 35 25 "Finishing up unpacking themes and files.........." 75
                flag_remove "silentUnpacker"
                unpacking_wait_ui_shown="true"
            fi

            log_message "firstboot.sh: waiting for ${label} to complete"
            while flag_check "$lock_name"; do
                sleep 0.2
            done
            log_message "firstboot.sh: ${label} complete"
            return 0
        fi

        grace_checks=$((grace_checks - 1))
        sleep 0.1
    done

    return 1
}

wait_for_unpack_with_grace "pre_menu_unpacking" "pre_menu_unpacking"
wait_for_unpack_with_grace "pre_cmd_unpacking" "pre_cmd_unpacking"
wait_for_unpack_with_grace "themes_unpacking" "themes_unpacking"

startup_unpack_converged() {
    if flag_check "themes_unpacking"; then
        log_message "firstboot.sh: startup convergence failed (themes_unpacking still active)"
        return 1
    fi

    if flag_check "pre_menu_unpacking"; then
        log_message "firstboot.sh: startup convergence failed (pre_menu_unpacking still active)"
        return 1
    fi

    if flag_check "pre_cmd_unpacking"; then
        log_message "firstboot.sh: startup convergence failed (pre_cmd_unpacking still active)"
        return 1
    fi

    for startup_dir in /mnt/SDCARD/spruce/archives/preMenu /mnt/SDCARD/spruce/archives/preCmd /mnt/SDCARD/Themes /mnt/SDCARD/RetroArch/.retroarch/assets; do
        [ -d "$startup_dir" ] || continue

        leftover_archive="$(find "$startup_dir" -maxdepth 1 \( -name '*.7z' -o -name '*.7z.extracting' \) | head -n 1)"
        if [ -n "$leftover_archive" ]; then
            log_message "firstboot.sh: startup convergence failed (leftover startup archive: ${leftover_archive})"
            return 1
        fi
    done

    return 0
}

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
else
	log_message "firstboot.sh: $SPLORE_CART already found."
fi

"$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/

display_image_and_text "$HAPPY_ICON" 35 25 "Happy gaming.........." 75
sleep 5

log_message "firstboot.sh: required work complete; setting complete marker"
if ! startup_unpack_converged; then
    log_message "firstboot.sh: convergence check failed; leaving in-progress marker for recovery on next boot"
    exit 1
fi

flag_remove "$FIRSTBOOT_FLAG"
flag_remove "$FIRSTBOOT_IN_PROGRESS_FLAG"
flag_remove "$FIRSTBOOT_COMPLETE_VERIFIED_FLAG"
flag_add "$FIRSTBOOT_COMPLETE_FLAG"
log_message "Finished firstboot script"
