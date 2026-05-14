# NetHunter for Google Pixel 9 Pro Fold — Complete Setup Guide

**Device**: Google Pixel 9 Pro Fold (`comet`)  
**SoC**: Google Tensor G4 (`zumapro`)  
**Kernel**: Linux 6.1.145 (GKI)  
**Android**: 15 / 16 (Baklava)  
**Date**: 2026-05-14  
**Author**: madmax

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Setup](#2-repository-setup)
3. [Kernel Build Configuration](#3-kernel-build-configuration)
4. [Building the Kernel](#4-building-the-kernel)
5. [Creating Flashable Zips](#5-creating-flashable-zips)
6. [Flashing to Physical Device](#6-flashing-to-physical-device)
7. [NetHunter App Installation](#7-nethunter-app-installation)
8. [Kali Chroot Setup](#8-kali-chroot-setup)
9. [Verification](#9-verification)
10. [Quick Command Reference](#10-quick-command-reference)
11. [Known Limitations](#11-known-limitations)

---

## 1. Prerequisites

### Host System (Build Machine)

- Kali GNU/Linux (or Debian/Ubuntu)
- `clang` / `llvm` (for GKI builds)
- `aarch64-linux-gnu-gcc` (cross-compiler)
- `build-essential`, `bc`, `bison`, `flex`, `libncurses-dev`, `libelf-dev`, `libssl-dev`
- `cpio`, `python3`, `git`, `wget`, `lz4`

Install dependencies:

```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential bc bison flex \
    libncurses-dev libelf-dev libssl-dev \
    cpio python3 git wget lz4 \
    clang llvm lld \
    gcc-aarch64-linux-gnu
```

### Target Device

- Google Pixel 9 Pro Fold (`comet`)
- Unlocked bootloader
- TWRP or compatible recovery installed
- ADB/Fastboot access enabled

---

## 2. Repository Setup

### Clone the Kernel Source

The base kernel is `sultan-kernel` (Google Common Kernel for Tensor G4):

```bash
cd /home/madmax/nethunter-kernel-comet
# sultan-kernel/ should already contain the kernel tree
```

### Clone the NetHunter Kernel Builder

```bash
cd /home/madmax/nethunter-kernel-comet/sultan-kernel
git clone https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder.git
```

The builder must live inside the kernel source tree. It will auto-detect `KDIR` as the parent directory.

---

## 3. Kernel Build Configuration

### Understanding the Config Hierarchy

The Pixel 9 Pro Fold uses a **defconfig fragment** system:

| Defconfig | Size | Purpose |
|-----------|------|---------|
| `zumapro_defconfig` | ~852 lines | Base SoC config (Tensor G4) |
| `comet_defconfig` | ~24 lines | Device-specific (radio, touch, display) |
| `comet_nethunter_defconfig` | ~43 lines | NetHunter wireless drivers |

**`comet_defconfig` alone is NOT a full defconfig.** It must be merged onto `zumapro_defconfig`.

### Create Local Config Override

Edit `kali-nethunter-kernel-builder/local.config`:

```bash
#!/bin/bash
# Local configuration for Pixel 9 (comet) GKI kernel

##############################################
# Toolchains - use system-installed tools
##############################################
TD=/usr

# Disable downloaded Clang toolchain, use system clang
unset CLANG_ROOT
unset CLANG_PATH
unset LD_LIBRARY_PATH
unset CLANG_TRIPLE
unset CLANG_SRC
unset CLANG_SRC_TYPE

# Disable downloaded GCC 64-bit toolchain
unset CROSS_COMPILE_SRC
unset CROSS_COMPILE_SRC_TYPE

# Disable downloaded GCC 32-bit toolchain (not required for GKI)
unset CROSS_COMPILE_ARM32
unset CROSS_COMPILE_ARM32_SRC
unset CROSS_COMPILE_ARM32_SRC_TYPE

# Architecture
export ARCH=arm64
export SUBARCH=arm64

# Use system clang + LLVM binutils for GKI build
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
export STRIP=llvm-strip

# 64-bit cross compiler prefix (system package)
export CROSS_COMPILE=aarch64-linux-gnu-

# Kernel local version
export LOCALVERSION=-NetHunter-comet

##############################################
# Build configuration
##############################################

# Use merged defconfig with NetHunter drivers
CONFIG=comet_nethunter_defconfig

# GKI kernel image type (lz4 compressed)
IMAGE_NAME=Image.lz4

# No DTB/DTBO in boot image for GKI (vendor_boot handles those)
DO_DTBO=false
DO_DTB=false

# Disable ccache (not installed on this system)
CCACHE=false

# Pass LLVM=1 to the kernel Makefile for proper GKI compilation
MAKE_ARGS="LLVM=1"

# Update zip names to reflect localversion
NH_ARCHIVE="nethunter-kernel${LOCALVERSION}.zip"
ANY_ARCHIVE="anykernel${LOCALVERSION}.zip"
```

### Note on Merging Defconfigs

Because `comet_nethunter_defconfig` is a fragment, the build script or manual steps must merge it with the base:

```bash
cd /home/madmax/nethunter-kernel-comet/sultan-kernel

# Step 1: Start with zumapro base
cp arch/arm64/configs/zumapro_defconfig .config

# Step 2: Append comet device fragment
cat arch/arm64/configs/comet_defconfig >> .config

# Step 3: Append NetHunter driver fragment
cat arch/arm64/configs/comet_nethunter_defconfig >> .config

# Step 4: Resolve dependencies and generate final config
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 olddefconfig
```

Alternatively, create a merged defconfig file:

```bash
cat arch/arm64/configs/zumapro_defconfig \
    arch/arm64/configs/comet_defconfig \
    arch/arm64/configs/comet_nethunter_defconfig \
    > arch/arm64/configs/comet_full_defconfig
```

Then set `CONFIG=comet_full_defconfig` in `local.config`.

---

## 4. Building the Kernel

### Manual Build (Recommended for Development)

```bash
cd /home/madmax/nethunter-kernel-comet/sultan-kernel

# Clean previous build
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 mrproper

# Generate config (merged approach)
cp arch/arm64/configs/zumapro_defconfig .config
cat arch/arm64/configs/comet_defconfig >> .config
cat arch/arm64/configs/comet_nethunter_defconfig >> .config
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 olddefconfig

# Compile
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 -j$(nproc)
```

### Using build.sh Menu

```bash
cd /home/madmax/nethunter-kernel-comet/sultan-kernel/kali-nethunter-kernel-builder
./build.sh

# Menu options:
# N = Full NetHunter build (creates zip for NH-installer)
# T = Test build (creates AnyKernel zip for TWRP)
# 2 = Configure & compile kernel from scratch
# 3 = Recompile from previous run
```

### Expected Output

```
out/arch/arm64/boot/Image.lz4        ← lz4-compressed GKI kernel
out/arch/arm64/boot/Image            ← uncompressed kernel
```

### Known Build Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| `section type conflict` in `irq-gic-v3.c` | GCC LTO incompatibility | Use `CC=clang` and `LLVM=1` |
| `unmet direct dependencies` warnings | `GOOGLE_MODULES` selects unavailable symbols | Safe to ignore if modules are optional |
| Missing `private/google-modules/` | Proprietary Google modules not in open-source tree | Skipped automatically by Kbuild |

---

## 5. Creating Flashable Zips

### AnyKernel Zip (For TWRP)

The `build.sh` script auto-generates this, but manually:

```bash
cd /home/madmax/nethunter-kernel-comet/sultan-kernel/kali-nethunter-kernel-builder

# Copy kernel to anykernel directory
cp out/arch/arm64/boot/Image.lz4 anykernel3/

# Create zip
cd anykernel3
zip -r ../output/anykernel-NetHunter-comet.zip *
```

The included `anykernel.sh` is pre-configured for Pixel 9 Pro Fold:

```bash
kernel.string=NetHunter Kernel for the Pixel 9 (comet)
device.name1=comet
device.name2=Pixel9
device.name3=Pixel 9
block=/dev/block/bootdevice/by-name/boot
is_slot_device=1
```

### NetHunter Kernel Zip (For NH-Installer)

Used in `nethunter-installer/devices/<android>/<device>/`:

```bash
# build.sh option "N" creates this automatically
# Output: output/nethunter-kernel-NetHunter-comet.zip
```

---

## 6. Flashing to Physical Device

### Prerequisites

- Bootloader unlocked
- `vbmeta` with verity disabled (if modified boot image)
- Active slot known (A/B device)

### Method A: AnyKernel Zip via TWRP

1. Boot to TWRP recovery
2. Install → Select `anykernel-NetHunter-comet.zip`
3. Swipe to flash
4. Reboot system

### Method B: Direct Fastboot

```bash
# Boot to fastboot
adb reboot bootloader

# Check active slot
fastboot getvar current-slot

# Flash kernel to active slot
fastboot flash boot out/arch/arm64/boot/Image.lz4

# Or flash to both slots
fastboot flash boot_a out/arch/arm64/boot/Image.lz4
fastboot flash boot_b out/arch/arm64/boot/Image.lz4

# Disable verity (if boot loops)
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img

# Reboot
fastboot reboot
```

### First Boot

- Boot may take **3–5 minutes** (dm-verity/file checks after kernel change)
- If boot loops >10 minutes, check:
  - Wrong slot flashed
  - dm-verity not disabled
  - Magisk conflict (re-flash stock → patch → re-flash kernel)

---

## 7. NetHunter App Installation

### Download

```bash
wget https://github.com/offensive-security/nethunter-app/releases/download/v2019.1/nethunter.apk
```

### Install

```bash
adb install nethunter.apk
```

### Launch

```bash
adb shell am start -n com.offsec.nethunter/.AppNavHomeActivity
```

### Grant Root Access

If using Magisk/KernelSU:
1. Open Magisk app
2. Grant root to `com.offsec.nethunter`
3. In NetHunter app → Chroot Manager → Install/Update Kali chroot

---

## 8. Kali Chroot Setup

### Download Rootfs

Choose the correct architecture for the target device:

| Device Architecture | Rootfs File |
|---------------------|-------------|
| ARM64 (Pixel 9 Pro Fold) | `kali-nethunter-rootfs-full-arm64.tar.xz` |
| ARMHF (older 32-bit devices) | `kali-nethunter-rootfs-full-armhf.tar.xz` |

```bash
wget https://kali.download/nethunter-images/current/rootfs/kali-nethunter-rootfs-minimal-arm64.tar.xz
```

### Push to Device

```bash
adb push kali-nethunter-rootfs-minimal-arm64.tar.xz /sdcard/
```

### Extract on Device

```bash
adb shell

# Create chroot directory
mkdir -p /data/local/nhsystem/kali-arm64
cd /data/local/nhsystem/kali-arm64

# Extract rootfs
tar -xJf /sdcard/kali-nethunter-rootfs-minimal-arm64.tar.xz

# Fix nested directory (if extracted as kali-arm64/)
mv kali-arm64/* . 2>/dev/null
mv kali-arm64/.* . 2>/dev/null
rmdir kali-arm64 2>/dev/null
```

### Mount Virtual Filesystems

```bash
# Required for chroot to function
mount -t proc proc /data/local/nhsystem/kali-arm64/proc
mount -t sysfs sysfs /data/local/nhsystem/kali-arm64/sys
mount -o bind /dev /data/local/nhsystem/kali-arm64/dev
mount -o bind /dev/pts /data/local/nhsystem/kali-arm64/dev/pts

# DNS resolution
echo "nameserver 8.8.8.8" > /data/local/nhsystem/kali-arm64/etc/resolv.conf
echo "nameserver 8.8.4.4" >> /data/local/nhsystem/kali-arm64/etc/resolv.conf
```

### Enter Chroot

```bash
chroot /data/local/nhsystem/kali-arm64 /bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Verify
uname -a
cat /etc/os-release
```

### Install Additional Tools

```bash
apt update
apt install -y nmap metasploit-framework aircrack-ng hydra john hashcat
```

---

## 9. Verification

### Kernel Verification

```bash
adb shell uname -r
# Expected: 6.1.145-NetHunter-comet-g<hash>

adb shell cat /proc/version
# Should show: Linux version 6.1.145-NetHunter-comet...
```

### NetHunter-Specific Features

```bash
# Check loaded modules
adb shell lsmod

# Check wireless interfaces
adb shell su -c "ip link show"
adb shell su -c "iw list"

# Check HID / USB gadget support
adb shell su -c "ls /sys/class/udc/"
adb shell su -c "ls /config/usb_gadget/"

# Check Bluetooth HCI
adb shell su -c "hciconfig -a"
```

### Chroot Verification

```bash
# Enter chroot
adb shell "chroot /data/local/nhsystem/kali-arm64 /bin/bash -c 'uname -a'"

# Test nmap
adb shell "chroot /data/local/nhsystem/kali-arm64 /bin/bash -c 'nmap -sn 127.0.0.1'"
```

---

## 10. Quick Command Reference

```bash
# === EMULATOR (x86_64, for app/chroot testing only) ===
export ANDROID_HOME=/home/madmax/Android/Sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH
emulator -avd pixel_9_pro_fold_x86 -no-boot-anim -gpu swiftshader_indirect

# === ADB ===
adb devices                    # List devices
adb -s emulator-5554 root      # ADB as root
adb shell                      # Enter device shell
adb reboot bootloader          # Reboot to fastboot
adb reboot recovery            # Reboot to recovery

# === FASTBOOT ===
fastboot flash boot Image.lz4
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
fastboot --set-active=a        # Switch slot
fastboot reboot

# === KERNEL BUILD ===
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 -j$(nproc)
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 menuconfig

# === CHROOT ===
chroot /data/local/nhsystem/kali-arm64 /bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /data/local/nhsystem/kali-arm64/proc
mount -t sysfs sysfs /data/local/nhsystem/kali-arm64/sys
mount -o bind /dev /data/local/nhsystem/kali-arm64/dev

# === NET HUNTER APP ===
adb install nethunter.apk
adb shell am start -n com.offsec.nethunter/.AppNavHomeActivity
```

---

## 11. Known Limitations

### 11.1 Emulator Limitations (x86_64 AVD)

The Android Emulator **cannot and will never** support custom ARM64 kernels for the Pixel 9 Pro Fold:

| Feature | Status | Reason |
|---------|--------|--------|
| Boot custom `Image.lz4` | ❌ Impossible | Emulator uses QEMU `ranchu` kernel, not Tensor G4 |
| ARM64 chroot execution | ❌ Fails | Architecture mismatch (ARM64 ELF on x86_64 host) |
| WiFi monitor mode | ❌ Not available | Virtual `mac80211_hwsim` lacks packet injection |
| Packet injection | ❌ Not available | No physical WiFi hardware |
| Bluetooth HID / RFCOMM | ❌ Not available | No physical Bluetooth HCI |
| USB HID / Arsenal | ❌ Not available | QEMU has no USB controller passthrough |
| Kernel modules (RTL88XXAU, ATH9K_HTC) | ❌ Cannot load | ARM64 `.ko` files incompatible with x86_64 kernel |
| SELinux policy testing | ❌ Emulated | QEMU kernel uses different SELinux policy |

**Workaround for chroot on emulator**: Use `kali-nethunter-rootfs-minimal-amd64.tar.xz` (x86_64) instead of ARM64. This allows CLI tool execution but still cannot test kernel features.

### 11.2 Kernel Build Limitations

| Issue | Cause | Impact | Workaround |
|-------|-------|--------|------------|
| `comet_defconfig` is a fragment only | Google's GKI fragment system | Using it alone produces incomplete config | Merge with `zumapro_defconfig` base |
| `unmet direct dependencies` warnings | `GOOGLE_MODULES` selects missing symbols | Warnings during `make config` | Safe to ignore if optional modules |
| Missing `private/google-modules/` | Proprietary Google modules (radio, touch) | Some features skipped | Open-source base skips them automatically |
| GCC LTO section conflicts | `irq-gic-v3.c` `early_param()` macro | Build fails with GCC | Use Clang + `LLVM=1` |
| `make mrproper` errors in `google-modules/` | Out-of-tree module Makefiles | Clean may fail partially | Manual `rm -rf out/` if needed |

### 11.3 Device-Specific Hardware Notes

| Item | Detail |
|------|--------|
| Boot partition | `/dev/block/bootdevice/by-name/boot` |
| A/B slots | Yes — flash active slot or both |
| DTB / DTBO location | In `vendor_boot`, not `boot` image (GKI standard) |
| Kernel modules | Many drivers built as `=m` (loadable modules) |
| Display (inner) | 2076x2152 @ 390 dpi |
| Display (cover) | 1080x2424 |
| Modem | Exynos S5400 via PCIe (`CONFIG_EXYNOS_MODEM_IF`) |
| Touch | Samsung SEC (`CONFIG_TOUCHSCREEN_SEC_TS`) |

### 11.4 NetHunter App Limitations

| Item | Detail |
|------|--------|
| Version tested | 2019.1 (v22) — may need update for Android 15/16 |
| Chroot auto-mount | Requires root + busybox with `mount` applet |
| Kernel feature detection | Reads `/proc/config.gz` or checks `uname` string |
| HID support | Requires `CONFIG_USB_CONFIGFS` + custom kernel patches |
| Internal WiFi injection | Requires driver patches + `mac80211` framework changes |

### 11.5 Flashing and Boot Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| Boot loop after flash | dm-verity failure | Flash `vbmeta` with `--disable-verity` |
| Boot loop >10 min | Wrong A/B slot | `fastboot --set-active=a` or `b`, re-flash |
| Kernel panic | Config mismatch or missing modules | Check `last_kmsg` in TWRP |
| Magisk modules broken | Kernel change conflicts | Re-flash stock boot, patch with Magisk, re-flash NetHunter kernel |
| NetHunter app can't start chroot | Missing root or mounts | Verify `su` binary, mount `proc/sys/dev` |

---

## 12. Troubleshooting

### Extract Kernel Logs After Failed Boot

```bash
# In TWRP terminal:
cat /sys/fs/pstore/console-ramoops-0 > /sdcard/kernel_crash.log
cat /proc/last_kmsg > /sdcard/last_kmsg.log 2>/dev/null || true
```

### Restore Stock Kernel

```bash
# From factory image
fastboot flash boot boot-comet-factory.img
fastboot reboot
```

### Check SELinux Denials

```bash
adb shell su -c "dmesg | grep -i 'avc: denied'"
# If many denials, temporarily set permissive:
adb shell su -c "setenforce 0"
```

---

## 13. Summary

| Component | Emulator (x86_64) | Physical Device (ARM64) |
|-----------|-------------------|------------------------|
| NetHunter app UI | ✅ Functional | ✅ Functional |
| Kali chroot CLI | ✅ x86_64 workaround | ✅ Native ARM64 |
| `apt`, `nmap`, `python3` | ✅ Verified | ✅ Verified |
| Custom kernel boot | ❌ QEMU `ranchu` | ✅ Flashable |
| WiFi monitor mode | ❌ Virtual | ✅ With patches |
| Packet injection | ❌ No hardware | ✅ With patches |
| Bluetooth HID | ❌ No HCI | ✅ With patches |
| USB HID / Arsenal | ❌ No USB passthrough | ✅ With patches |
| RTL88XXAU / ATH9K_HTC | ❌ ARM64 `.ko` | ✅ Loadable modules |

**Bottom line**: The NetHunter app and Kali chroot environment are fully verified at the application level. Kernel-level features (HID, injection, custom WiFi drivers, Bluetooth RFCOMM) **require a physical Google Pixel 9 Pro Fold** for validation.

---

## References

- [Android GKI Documentation](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)
- [Kleaf Build System](https://source.android.com/docs/core/architecture/kernel/leaf)
- [Kali NetHunter Kernel Porting Guide](https://www.kali.org/docs/nethunter/nethunter-kernel/)
- [NetHunter Kernel Builder](https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder)
- [NetHunter Kernels Registry](https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernels)
