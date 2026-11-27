#!/bin/bash
# Assembles out/steamos-rg40xx.img from ROCKNIX's U-Boot + kernel + DTBs and our rootfs.
#   tools/build-image.sh             (runs itself inside an amd64 Debian container)
# Layout: MBR (disk id 53544d52), U-Boot at 8 KiB, p1 FAT32 "STEAMBOOT" 256 MiB at 16 MiB,
#         p2 ext4 "steamroot" sized to its contents (grown to the card on first boot).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f /.dockerenv ]; then
  exec env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -e STEAM_SEED -e UBOOT -e DTB -e SXX_VERSION -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w \
    debian:trixie bash -c 'export DEBIAN_FRONTEND=noninteractive; dpkg --add-architecture arm64; apt-get update -qq >/dev/null;
      apt-get install -y -qq e2fsprogs dosfstools mtools fdisk cpio >/dev/null 2>&1; tools/build-image.sh'
fi

DTB=${DTB:-sun50i-h700-anbernic-rg40xx-h.dtb}
work=/tmp/img
rm -rf $work && mkdir -p $work/root $work/boot/extlinux $work/boot/dtbs
echo "== unpacking rootfs"
tar -C $work/root -xpf out/rootfs.tar --numeric-owner
rm -f $work/root/.dockerenv
# the release tag when CI builds one (sxx-update compares against it); "dev" is never offered an update
echo "${SXX_VERSION:-dev}" > $work/root/etc/sxx-release
# docker export leaves the container-managed files empty
cp overlay/etc/hostname overlay/etc/hosts $work/root/etc/
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
# Our kernel (kernel/build.sh, 7.2.0-sxx: HIDRAW, UHID, USB/IP) when cache/kernel has it, else ROCKNIX's stock 7.2.0.
if [ -f cache/kernel/KERNEL ]; then
  cp cache/kernel/KERNEL $work/boot/KERNEL
  cp cache/kernel/dtbs/sun50i-h700-anbernic-rg40xx-*.dtb $work/boot/dtbs/
else
  cp cache/boot/KERNEL $work/boot/KERNEL
  cp cache/boot/device_trees/sun50i-h700-anbernic-rg40xx-*.dtb $work/boot/dtbs/
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
mkfs.vfat -F 32 -n STEAMBOOT -i 53544d52 $work/boot.img >/dev/null
mcopy -s -i $work/boot.img $work/boot/* ::/

echo "== root partition"
used_mb=$(du -sm $work/root | cut -f1)
# Fixed size: the data partition (/home, created on first boot) starts right after the root at the same offset in every
# image, which is what lets a reflash find the previous one.
root_mb=3072
[ "$used_mb" -lt 2600 ] || { echo "root is ${used_mb} MB, too big for the fixed ${root_mb} MB root"; exit 1; }
mke2fs -q -t ext4 -L steamroot -m 1 -E root_owner=0:0 -d $work/root $work/root.img ${root_mb}M

echo "== disk image"
out=out/steamos-rg40xx.img
# The image must end exactly where the root ends: flashing it must not touch the data partition that follows.
total_mb=$(( 16 + boot_mb + root_mb ))
rm -f $out && truncate -s ${total_mb}M $out
UBOOT=${UBOOT:-out/uboot/card.bin}
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
