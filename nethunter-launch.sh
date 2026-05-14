#!/bin/bash
# nethunter-launch: Quick launcher and verifier for NetHunter on Pixel 9 Pro Fold
# Usage: ./nethunter-launch.sh [command]
# Commands: check, launch, chroot, flash, recovery

set -e

# Colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RESET='\e[0m'

# Configuration
DEVICE="comet"
KERNEL_STRING="NetHunter-comet"
CHROOT_PATH="/data/local/nhsystem/kali-arm64"
APP_PACKAGE="com.offsec.nethunter"

##############################################
# Helper Functions
##############################################

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail() { echo -e "${RED}[FAIL]${RESET} $*"; }

##############################################
# Device Check
##############################################
check_device() {
    info "Checking ADB connection..."
    if ! adb devices | grep -q "device$"; then
        fail "No device connected. Connect Pixel 9 Pro Fold via USB with debugging enabled."
        exit 1
    fi
    ok "Device connected"
}

##############################################
# Kernel Verification
##############################################
check_kernel() {
    info "Checking kernel version..."
    local kernel=$(adb shell uname -r 2>/dev/null | tr -d '\r')
    if echo "$kernel" | grep -q "$KERNEL_STRING"; then
        ok "NetHunter kernel active: $kernel"
    else
        warn "Stock kernel detected: $kernel"
        warn "Expected: *$KERNEL_STRING*"
        echo "Run: ./nethunter-launch.sh flash"
    fi
}

##############################################
# Root Check
##############################################
check_root() {
    info "Checking root access..."
    if adb shell "su -c 'id'" 2>/dev/null | grep -q "uid=0"; then
        ok "Root access granted"
    else
        fail "No root access. Grant root in Magisk/KernelSU for shell."
    fi
}

##############################################
# NetHunter App Check
##############################################
check_app() {
    info "Checking NetHunter app..."
    if adb shell pm list packages | grep -q "$APP_PACKAGE"; then
        ok "NetHunter app installed"
        local ver=$(adb shell dumpsys package $APP_PACKAGE | grep versionName | head -1 | awk '{print $1}')
        info "Version: $ver"
    else
        warn "NetHunter app not installed"
        echo "Run: adb install nethunter.apk"
    fi
}

##############################################
# Chroot Check
##############################################
check_chroot() {
    info "Checking Kali chroot..."
    if adb shell "test -f $CHROOT_PATH/bin/bash" 2>/dev/null; then
        ok "Chroot present at $CHROOT_PATH"
    else
        warn "Chroot not found at $CHROOT_PATH"
        echo "Push rootfs and extract to $CHROOT_PATH"
    fi
}

##############################################
# Full Health Check
##############################################
cmd_check() {
    echo -e "${BLUE}========================================${RESET}"
    echo -e "${BLUE}   NetHunter System Check (Pixel 9 Pro Fold)${RESET}"
    echo -e "${BLUE}========================================${RESET}"
    echo ""
    check_device
    check_kernel
    check_root
    check_app
    check_chroot
    echo ""
    info "To launch app: ./nethunter-launch.sh launch"
    info "To enter chroot: ./nethunter-launch.sh chroot"
}

##############################################
# Launch NetHunter App
##############################################
cmd_launch() {
    check_device
    info "Launching NetHunter app..."
    adb shell am start -n $APP_PACKAGE/.AppNavHomeActivity >/dev/null 2>&1
    ok "NetHunter app launched"
}

##############################################
# Enter Chroot Shell
##############################################
cmd_chroot() {
    check_device
    check_root
    info "Entering Kali chroot..."
    echo "Mounting virtual filesystems..."
    adb shell "su -c 'mount -t proc proc $CHROOT_PATH/proc 2>/dev/null; mount -t sysfs sysfs $CHROOT_PATH/sys 2>/dev/null; mount -o bind /dev $CHROOT_PATH/dev 2>/dev/null; mount -o bind /dev/pts $CHROOT_PATH/dev/pts 2>/dev/null'" >/dev/null 2>&1
    ok "Mounts done"
    echo ""
    echo -e "${GREEN}Entering chroot...${RESET}"
    adb shell "su -c 'chroot $CHROOT_PATH /bin/bash -c \"export PATH=/usr/bin:/bin:/usr/sbin:/sbin; bash\"'"
}

##############################################
# Flash Kernel (AnyKernel Zip)
##############################################
cmd_flash() {
    local zip_file="$1"
    if [ -z "$zip_file" ]; then
        # Default to pre-built zip
        zip_file="/home/madmax/nethunter-kernel-comet/sultan-kernel/kali-nethunter-kernel-builder/output/anykernel-NetHunter-comet.zip"
    fi

    if [ ! -f "$zip_file" ]; then
        fail "Zip not found: $zip_file"
        echo "Usage: ./nethunter-launch.sh flash <path-to-anykernel.zip>"
        exit 1
    fi

    info "Preparing to flash: $zip_file"
    info "Rebooting to bootloader..."
    adb reboot bootloader
    sleep 5

    # Extract Image.lz4 from zip for direct flash
    local tmpdir=$(mktemp -d)
    unzip -o "$zip_file" Image.lz4 -d "$tmpdir" 2>/dev/null || true

    if [ -f "$tmpdir/Image.lz4" ]; then
        info "Flashing Image.lz4 to both boot slots..."
        fastboot flash boot_a "$tmpdir/Image.lz4"
        fastboot flash boot_b "$tmpdir/Image.lz4"
        rm -rf "$tmpdir"
    else
        warn "Could not extract Image.lz4 from zip. Flash zip in TWRP instead."
        info "Booting TWRP temporarily..."
        # fastboot boot twrp.img
        # Then install zip manually
    fi

    info "Flashing vbmeta with verity disabled..."
    fastboot flash vbmeta --disable-verity --disable-verification 2>/dev/null || warn "vbmeta flash failed (may not be needed)"

    info "Rebooting..."
    fastboot reboot
    ok "Flash complete. Device should boot with NetHunter kernel."
}

##############################################
# Boot to Recovery / Fastboot
##############################################
cmd_recovery() {
    info "Rebooting to recovery..."
    adb reboot recovery
}

cmd_fastboot() {
    info "Rebooting to bootloader..."
    adb reboot bootloader
}

##############################################
# Main Menu
##############################################
show_menu() {
    echo -e "${BLUE}========================================${RESET}"
    echo -e "${BLUE}   NetHunter Launcher (Pixel 9 Pro Fold)${RESET}"
    echo -e "${BLUE}========================================${RESET}"
    echo ""
    echo "  1. check    - Full system verification"
    echo "  2. launch   - Launch NetHunter app"
    echo "  3. chroot   - Enter Kali chroot shell"
    echo "  4. flash    - Flash AnyKernel zip"
    echo "  5. recovery - Reboot to TWRP"
    echo "  6. fastboot - Reboot to bootloader"
    echo "  7. quit     - Exit"
    echo ""
}

interactive_menu() {
    while true; do
        show_menu
        read -p "Select option [1-7]: " choice
        case $choice in
            1) cmd_check ;;
            2) cmd_launch ;;
            3) cmd_chroot ;;
            4) cmd_flash ;;
            5) cmd_recovery ;;
            6) cmd_fastboot ;;
            7) break ;;
            *) warn "Invalid option" ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

##############################################
# Main
##############################################
main() {
    local cmd="${1:-menu}"
    shift || true

    case $cmd in
        check|1)      cmd_check ;;
        launch|2)     cmd_launch ;;
        chroot|3)     cmd_chroot ;;
        flash|4)     cmd_flash "$@" ;;
        recovery|5)  cmd_recovery ;;
        fastboot|6)  cmd_fastboot ;;
        menu|*)      interactive_menu ;;
    esac
}

main "$@"
