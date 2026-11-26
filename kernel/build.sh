#!/bin/bash
# Rebuilds ROCKNIX's H700 kernel (kernel.org 7.2 + ROCKNIX's patches and config) with the HID options a Steam
# handheld needs: HIDRAW (Steam's hidapi drivers), UHID (virtual controllers), HID_STEAM, USB/IP virtual host.
# The stock kernel has none of them, and HID is built in, so they cannot be added as modules.
#
#   kernel/build.sh                 builds into out/kernel/ (Image, modules, dtbs)
# Needs Linux with: gcc (or aarch64-linux-gnu-gcc and CROSS_COMPILE), make, bc, bison, flex, libssl-dev, libelf-dev,
# rsync, xz-utils, python3, git, cpio, kmod, patch. tools/fetch-rocknix.sh must have filled cache/ first: the
# shipped kernel supplies the built-in initramfs and the extracted firmware supplies the built-in firmware.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

KVER=7.2
KSHA256=f9fef3d14c0df53819026f4be74459835c2a0b0dcbf5b5bbd9ea19f0829402b3
KURL=https://www.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz
ROCKNIX_COMMIT=cefc14339a4ae18c02bb69888f27835e50664b60
JOYPAD_REPO=https://github.com/hackbar/rocknix-joypad
JOYPAD_COMMIT=005033d1ddd8746c771f2c81f1174f2d892541c9
JOYPAD_SHA256=7a9a90d9d25d48384771bf8fe7cfb53bba708b64aa4e56d44e71205a8bcc699a
FW=$ROOT/cache/overlay/usr/lib/kernel-overlays/base/lib/firmware
JOBS=${JOBS:-$(nproc)}
WORK=${KERNEL_WORK:-$ROOT/out/kernel-work}
OUT=$ROOT/out/kernel
MAKE_ARGS=(ARCH=arm64)
[ -z "${CROSS_COMPILE:-}" ] || MAKE_ARGS+=(CROSS_COMPILE="$CROSS_COMPILE")
step() { echo "== $(date +%H:%M:%S) $*"; }

[ -f "$ROOT/cache/boot/KERNEL" ] && [ -d "$FW" ] || { echo "run tools/fetch-rocknix.sh first"; exit 1; }
mkdir -p "$WORK" "$OUT"

step "kernel source $KVER"
[ -f "$WORK/linux-$KVER.tar.xz" ] || curl -fL -o "$WORK/linux-$KVER.tar.xz" "$KURL"
echo "$KSHA256  $WORK/linux-$KVER.tar.xz" | sha256sum -c -
rm -rf "$WORK/linux"
mkdir "$WORK/linux" && tar -xf "$WORK/linux-$KVER.tar.xz" -C "$WORK/linux" --strip-components=1

step "ROCKNIX patches at $ROCKNIX_COMMIT"
if [ ! -d "$WORK/rocknix/.git" ]; then
  git clone -q --filter=blob:none --no-checkout https://github.com/ROCKNIX/distribution "$WORK/rocknix"
fi
git -C "$WORK/rocknix" sparse-checkout set --no-cone \
  /projects/ROCKNIX/packages/linux/patches /projects/ROCKNIX/devices/H700/patches/linux \
  /projects/ROCKNIX/devices/H700/linux
git -C "$WORK/rocknix" checkout -q "$ROCKNIX_COMMIT"
RK=$WORK/rocknix/projects/ROCKNIX
# Same order as ROCKNIX's scripts/unpack for H700: the package's patch directories (mainline, default, then the
# kernel version's), then the device's. @TARGET_CPU@ and @DEVICE@ are substituted as there.
for dir in "$RK/packages/linux/patches/mainline" "$RK/packages/linux/patches/default" \
           "$RK/packages/linux/patches/$KVER" "$RK/devices/H700/patches/linux"; do
  [ -d "$dir" ] || continue
  for p in $(ls "$dir"/*.patch 2>/dev/null | sort); do
    echo "patch $(basename "$p")"
    if grep -qE '^GIT binary patch$|^rename from|^rename to' "$p"; then
      sed -e 's#@TARGET_CPU@#cortex-a53#g' -e 's#@DEVICE@#H700#g' "$p" | git -C "$WORK/linux" apply -p1
    else
      sed -e 's#@TARGET_CPU@#cortex-a53#g' -e 's#@DEVICE@#H700#g' "$p" | patch -d "$WORK/linux" -p1 --no-backup-if-mismatch -s
    fi
  done
done
rsync -a "$RK/devices/H700/linux/dts/" "$WORK/linux/arch/arm64/boot/dts/"

step "built-in initramfs from the shipped kernel"
python3 "$ROOT/kernel/extract-initramfs.py" "$ROOT/cache/boot/KERNEL" "$WORK/initramfs.cpio.gz"

step "firmware to embed"
FWDIR=$WORK/linux/external-firmware
rm -rf "$FWDIR" && mkdir -p "$FWDIR/rtl_bt" "$FWDIR/rtw88" "$FWDIR/panels"
cp -L "$FW"/rtl_bt/rtl8821cs_config.bin "$FW"/rtl_bt/rtl8821cs_fw.bin "$FWDIR/rtl_bt/"
cp -L "$FW"/rtw88/rtw8821c_fw.bin "$FWDIR/rtw88/"
cp -L "$FW"/panels/*.panel "$FWDIR/panels/"
cp -L "$FW"/regulatory.db "$FW"/regulatory.db.p7s "$FWDIR/"
FW_LIST=$(cd "$FWDIR" && find . -type f | sed 's|^\./||' | sort | xargs)

step "configuration"
cd "$WORK/linux"
cp "$RK/devices/H700/linux/linux.aarch64.conf" .config
scripts/config --set-str CONFIG_INITRAMFS_SOURCE "$WORK/initramfs.cpio.gz"
scripts/config --set-str CONFIG_EXTRA_FIRMWARE "$FW_LIST"
scripts/config --set-str CONFIG_EXTRA_FIRMWARE_DIR external-firmware
scripts/config --set-str CONFIG_DEFAULT_HOSTNAME rg40xx
# A release name of its own (7.2.0-sxx) keeps this kernel's modules next to the stock 7.2.0 ones, so either can boot.
scripts/config --set-str CONFIG_LOCALVERSION "-sxx"
# the additions this directory exists for
scripts/config -e CONFIG_HIDRAW -m CONFIG_UHID -m CONFIG_HID_STEAM -m CONFIG_USBIP_CORE -m CONFIG_USBIP_VHCI_HCD
# memory experiments: DAMON-driven reclaim, and access-time tracking for zram's idle recompression and writeback
scripts/config -e CONFIG_ZRAM_TRACK_ENTRY_ACTIME -e CONFIG_DAMON -e CONFIG_DAMON_VADDR -e CONFIG_DAMON_PADDR -e CONFIG_DAMON_SYSFS -e CONFIG_DAMON_RECLAIM -e CONFIG_DAMON_LRU_SORT
make "${MAKE_ARGS[@]}" olddefconfig </dev/null >/dev/null
for opt in HIDRAW UHID HID_STEAM USBIP_CORE USBIP_VHCI_HCD ZRAM_TRACK_ENTRY_ACTIME DAMON DAMON_RECLAIM; do grep -E "^CONFIG_$opt=" .config || { echo "CONFIG_$opt did not stick"; exit 1; }; done
cp .config "$OUT/config"

step "build (-j$JOBS)"
dtbs=$(cd arch/arm64/boot/dts/allwinner && ls sun50i-h700-anbernic-rg40xx*.dts | sed 's/\.dts$/.dtb/; s|^|allwinner/|' | xargs)
DTC_FLAGS=-@ make "${MAKE_ARGS[@]}" -j"$JOBS" Image $dtbs modules

step "install"
rm -rf "$OUT/modules" "$OUT/dtbs" && mkdir -p "$OUT/modules" "$OUT/dtbs"
cp arch/arm64/boot/Image "$OUT/KERNEL"
for d in $dtbs; do cp "arch/arm64/boot/dts/$d" "$OUT/dtbs/"; done
make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$OUT/modules" modules_install >/dev/null
KREL=$(cat include/config/kernel.release)

step "rocknix-joypad (out of tree)"
# ROCKNIX fetches this commit as an archive (it is not on a branch a clone would get) and pins the hash.
curl -fL -o "$WORK/joypad.tar.gz" "$JOYPAD_REPO/archive/$JOYPAD_COMMIT.tar.gz"
echo "$JOYPAD_SHA256  $WORK/joypad.tar.gz" | sha256sum -c -
rm -rf "$WORK/joypad" && mkdir "$WORK/joypad" && tar -xzf "$WORK/joypad.tar.gz" -C "$WORK/joypad" --strip-components=1
# rumble: ff-memless calls the play callback from a timer, so it must not take the mutex the PWM work item holds (found by
# the Handtop project on the RG35XX-H, same driver); kernel/patches/joypad-rumble-no-mutex.patch
patch -d "$WORK/joypad" -p1 < "$ROOT/kernel/patches/joypad-rumble-no-mutex.patch"
# its Makefile picks the driver by DEVICE: H700 is the single-ADC one this handheld uses
make "${MAKE_ARGS[@]}" -C "$WORK/linux" M="$WORK/joypad" DEVICE=H700 modules >/dev/null
mkdir -p "$OUT/modules/lib/modules/$KREL/rocknix-joypad"
find "$WORK/joypad" -name '*.ko' -exec cp {} "$OUT/modules/lib/modules/$KREL/rocknix-joypad/" \;
depmod -b "$OUT/modules" "$KREL" 2>/dev/null || true
rm -f "$OUT/modules/lib/modules/$KREL/build" "$OUT/modules/lib/modules/$KREL/source"
echo "$KREL" > "$OUT/release"
ls -la "$OUT/KERNEL"
step "done: kernel $KREL in $OUT"
