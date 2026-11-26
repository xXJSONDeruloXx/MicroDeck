#!/bin/bash
# Copies overlay/ (and the initramfs, if you rebuilt it) into the VM disk while it is stopped, so first-boot and boot-time changes can
# be tested without building an image: the overlay lands in the root partition as it would in the real image.
#   tools/qemu/inject.sh [disk.img]      default out/qemu/disk.img; run tools/vm.sh reset first for a fresh first boot
set -euo pipefail
cd "$(dirname "$0")/../.."
disk=${1:-out/qemu/disk.img}
env MSYS_NO_PATHCONV=1 docker run --rm --privileged --platform linux/amd64 -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
  set -euo pipefail
  apt-get update -qq >/dev/null && apt-get install -y -qq e2fsprogs rsync mtools util-linux >/dev/null 2>&1
  mkdir -p /mnt/root
  # root partition: 16 MiB + 256 MiB in, 3 GiB long (tools/build-image.sh)
  mount -o loop,offset=$((272*1024*1024)),sizelimit=$((3072*1024*1024)) "'"$disk"'" /mnt/root
  rsync -rlptD --no-owner --no-group --chmod=D755 overlay/ /mnt/root/
  chown -R root:root /mnt/root/usr/local /mnt/root/etc/systemd /mnt/root/etc/sysctl.d 2>/dev/null || true
  chmod +x /mnt/root/usr/local/bin/* /mnt/root/usr/local/sbin/* 2>/dev/null || true
  umount /mnt/root
  # the initramfs from debug/initramfs/init, built the way tools/build-image.sh does (the VM boots it from out/qemu, not from p1)
  dpkg --add-architecture arm64 && apt-get update -qq >/dev/null && apt-get install -y -qq cpio gzip >/dev/null 2>&1
  (cd /tmp && apt-get download -qq busybox-static:arm64 && dpkg-deb -x busybox-static_*.deb bb)
  ir=/tmp/ir && rm -rf $ir && mkdir -p $ir/bin $ir/dev $ir/proc $ir/sys $ir/mnt
  cp /tmp/bb/usr/bin/busybox $ir/bin/busybox
  sed "s/$//" debug/initramfs/init > $ir/init && chmod 755 $ir/init $ir/bin/busybox
  (cd $ir && find . | cpio -o -H newc --quiet | gzip -9) > out/qemu/initrd.cpio.gz
  echo "overlay injected into '"$disk"'"'
