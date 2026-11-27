#!/bin/bash
# Assembles out/microdeck-<device>.img from U-Boot + kernel + DTB and our rootfs; the root filesystem is the same for every device.
#   DEVICE=rg40xx|rg28xx tools/build-image.sh     (default rg40xx; runs itself inside an amd64 Debian container)
# Layout: MBR (disk id 53544d52), U-Boot at 8 KiB, p1 FAT32 "MICRODECK" 256 MiB at 16 MiB,
#         p2 ext4 "microdeck-root" sized to its contents (grown to the card on first boot).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f /.dockerenv ]; then
  exec env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -e STEAM_SEED -e UBOOT -e DTB -e DEVICE -e MDECK_VERSION -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w \
    debian:trixie bash -c 'export DEBIAN_FRONTEND=noninteractive; dpkg --add-architecture arm64; apt-get update -qq >/dev/null;
      apt-get install -y -qq e2fsprogs dosfstools mtools fdisk cpio >/dev/null 2>&1; tools/build-image.sh'
fi

DEVICE=${DEVICE:-rg40xx}
case $DEVICE in
  rg40xx) DTB=${DTB:-sun50i-h700-anbernic-rg40xx-h.dtb}; UBOOT=${UBOOT:-out/uboot/card.bin} ;;
  rg28xx) DTB=${DTB:-sun50i-h700-anbernic-rg28xx.dtb}; UBOOT=${UBOOT:-out/uboot/card-rg28xx.bin} ;;
  *) echo "unknown DEVICE $DEVICE"; exit 1 ;;
esac
work=/tmp/img
rm -rf $work && mkdir -p $work/root $work/boot/extlinux $work/boot/dtbs
echo "== unpacking rootfs"
tar -C $work/root -xpf out/rootfs.tar --numeric-owner
rm -f $work/root/.dockerenv
# the release tag when CI builds one (mdeck-update compares against it); "dev" is never offered an update
echo "${MDECK_VERSION:-dev}" > $work/root/etc/mdeck-release
echo "$DEVICE" > $work/root/etc/mdeck-device   # which release asset mdeck-update downloads
# docker export leaves the container-managed files empty
cp overlay/etc/hostname overlay/etc/hosts $work/root/etc/
# one name per handheld, so two on the same network (or the same PC) can be told apart: microdeck-rg40xx, microdeck-rg28xx
echo "microdeck-$DEVICE" > $work/root/etc/hostname
sed -i "s/^127.0.1.1 .*/127.0.1.1 microdeck-$DEVICE/" $work/root/etc/hosts
rm -f $work/root/etc/resolv.conf && ln -s ../run/NetworkManager/resolv.conf $work/root/etc/resolv.conf
# STEAM_SEED: a clean client from tools/fetch-steam.sh for release images; cache/steam-home.tar (a dev
# install, with its login) is the default for the dev card.
seed=${STEAM_SEED:-cache/steam-home.tar}
if [ -f "$seed" ]; then
  echo "== seeding the Steam install from $seed"
  tar -C $work/root/home/steam -xpf "$seed" --numeric-owner
  chown -R 1000:1000 $work/root/home/steam
fi

echo "== boot partition"
# Our kernel (kernel/build.sh, 7.2.0-mdeck: HIDRAW, UHID, USB/IP) when cache/kernel has it, else ROCKNIX's stock 7.2.0.
if [ -f cache/kernel/KERNEL ]; then
  cp cache/kernel/KERNEL $work/boot/KERNEL
else
  cp cache/boot/KERNEL $work/boot/KERNEL
fi
# the device's own tree: from our kernel build when it has one, else ROCKNIX's (same sources and patches)
for d in cache/kernel/dtbs cache/boot/device_trees; do
  [ -f "$d/$DTB" ] && { cp "$d/$DTB" $work/boot/dtbs/; break; }
done
[ -f "$work/boot/dtbs/$DTB" ] || { echo "no $DTB in cache/kernel/dtbs or cache/boot/device_trees"; exit 1; }
if [ "$DEVICE" = rg40xx ]; then   # the panel-revision variants stay selectable by editing extlinux.conf
  for d in cache/kernel/dtbs cache/boot/device_trees; do
    ls $d/sun50i-h700-anbernic-rg40xx-*.dtb >/dev/null 2>&1 && { cp $d/sun50i-h700-anbernic-rg40xx-*.dtb $work/boot/dtbs/; break; }
  done
fi
# Logging initramfs: writes bootlog-N.txt to this partition, then switches to the real root.
# (rdinit=/no-initramfs, which skips ROCKNIX's built-in initramfs, reset the board; this boots.)
(cd /tmp && apt-get download -qq busybox-static:arm64 >/dev/null 2>&1 && dpkg-deb -x busybox-static_*.deb bb)
ir=/tmp/ir && rm -rf $ir && mkdir -p $ir/bin $ir/dev $ir/proc $ir/sys $ir/mnt
cp /tmp/bb/usr/bin/busybox $ir/bin/busybox
sed 's/\r$//' debug/initramfs/init > $ir/init && chmod 755 $ir/init $ir/bin/busybox
(cd $ir && find . | cpio -o -H newc --quiet | gzip -9) > $work/boot/initrd.cpio.gz
cat > $work/boot/extlinux/extlinux.conf <<EOF
TIMEOUT 1
DEFAULT steamos
LABEL steamos
  LINUX /KERNEL
  INITRD /initrd.cpio.gz
  FDT /dtbs/$DTB
  APPEND root=PARTUUID=53544d52-02 rootwait rw init=/lib/systemd/systemd console=ttyS0,115200 console=tty0 panic=10 oops=panic softlockup_panic=1 loglevel=4 fsck.repair=yes
EOF
cat > $work/boot/wifi.txt.example <<EOF
# To join Wi-Fi on first start: copy this file to wifi.txt on this partition and fill it in.
# The first start downloads Steam (about 1 GB), so the handheld needs a connection.
ssid=YourNetworkName
psk=YourPassword
# Optional: band=a joins 5 GHz only (usually much faster than 2.4 GHz); band=bg joins 2.4 GHz only.
EOF
cat > $work/boot/authorized_keys.example <<EOF
# Optional: for SSH access, put your public key(s) here, one per line (ssh-ed25519 AAAA... you@host), and rename this
# file to authorized_keys. They are installed for root and steam at the next boot. adb over USB works without it.
EOF
boot_mb=256
truncate -s ${boot_mb}M $work/boot.img
mkfs.vfat -F 32 -n MICRODECK -i 53544d52 $work/boot.img >/dev/null
mcopy -s -i $work/boot.img $work/boot/* ::/

echo "== root partition"
used_mb=$(du -sm $work/root | cut -f1)
# Fixed size: the data partition (/home, created on first boot) starts right after the root at the same offset in every
# image, which is what lets a reflash find the previous one.
root_mb=3072
[ "$used_mb" -lt 2600 ] || { echo "root is ${used_mb} MB, too big for the fixed ${root_mb} MB root"; exit 1; }
mke2fs -q -t ext4 -L microdeck-root -m 1 -E root_owner=0:0 -d $work/root $work/root.img ${root_mb}M

echo "== disk image"
out=out/microdeck-$DEVICE.img
# The image must end exactly where the root ends: flashing it must not touch the data partition that follows.
total_mb=$(( 16 + boot_mb + root_mb ))
rm -f $out && truncate -s ${total_mb}M $out
[ -f "$UBOOT" ] || UBOOT=cache/uboot.bin
echo "== U-Boot: $UBOOT"
dd if="$UBOOT" of=$out bs=1K seek=8 conv=notrunc status=none
sfdisk -q $out <<EOF
label: dos
label-id: 0x53544d52
start=16MiB, size=${boot_mb}MiB, type=c, bootable
start=$(( 16 + boot_mb ))MiB, size=${root_mb}MiB, type=83
EOF
dd if=$work/boot.img of=$out bs=1M seek=16 conv=notrunc status=none
dd if=$work/root.img of=$out bs=1M seek=$(( 16 + boot_mb )) conv=notrunc status=none
sfdisk -l $out
ls -la $out
