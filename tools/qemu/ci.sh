#!/bin/bash
# Boots a built image in QEMU on a CI runner (ubuntu-24.04-arm) and runs the boot smoke test. Natively builds the generic kernel
# (cached by the workflow) so no cross compiler is needed.
#   tools/qemu/ci.sh out/microdeck-rg40xx.img.xz                       boot smoke test of that image
#   tools/qemu/ci.sh out/microdeck-rg40xx.img.xz <previous.img.xz>    boot the PREVIOUS release and update it in place to the first image
#                                                                   (the old release's own updater and initramfs do the install, as for a user)
set -euo pipefail
cd "$(dirname "$0")/../.."
img=${1:?usage: tools/qemu/ci.sh image.img.xz [previous-release.img.xz]}
base=${2:-$img}   # the disk the VM boots from
sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-arm mtools build-essential bc bison flex libssl-dev libelf-dev xz-utils curl cpio kmod python3 openssh-client >/dev/null
mkdir -p out/qemu cache/qemu
if [ ! -f cache/qemu/Image ]; then
  KVER=7.2
  curl -fL -o cache/qemu/linux.tar.xz "https://www.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz"
  mkdir -p /tmp/linux && tar -xf cache/qemu/linux.tar.xz -C /tmp/linux --strip-components=1
  (cd /tmp/linux && make ARCH=arm64 defconfig >/dev/null &&
    for o in VIRTIO VIRTIO_PCI VIRTIO_MMIO VIRTIO_BLK VIRTIO_NET VIRTIO_CONSOLE HW_RANDOM_VIRTIO SCSI_VIRTIO BLK_DEV_LOOP EXT4_FS \
             VFAT_FS FAT_FS MSDOS_FS NLS_CODEPAGE_437 NLS_ISO8859_1 NLS_UTF8 DEVTMPFS DEVTMPFS_MOUNT TMPFS CGROUPS SERIAL_AMBA_PL011 \
             SERIAL_AMBA_PL011_CONSOLE PCI_HOST_GENERIC DRM_VIRTIO_GPU VT FRAMEBUFFER_CONSOLE; do scripts/config -e CONFIG_$o; done &&
    make ARCH=arm64 olddefconfig </dev/null >/dev/null && make ARCH=arm64 -j"$(nproc)" Image >/dev/null)
  cp /tmp/linux/arch/arm64/boot/Image cache/qemu/Image
fi
cp cache/qemu/Image out/qemu/Image
xz -dc "$base" > out/qemu/disk.img
truncate -s 12G out/qemu/disk.img
mcopy -n -i out/qemu/disk.img@@16M ::initrd.cpio.gz out/qemu/initrd.cpio.gz
mkdir -p secrets
[ -f secrets/id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -f secrets/id_ed25519
mcopy -o -i out/qemu/disk.img@@16M secrets/id_ed25519.pub ::authorized_keys
cp out/qemu/disk.img out/qemu/disk.base.img
: > out/qemu/serial.log
bash tools/qemu/run.sh > out/qemu/qemu.out 2>&1 &
trap 'kill %1 2>/dev/null || true' EXIT
rc=0
if [ -n "${2:-}" ]; then
  python3 tests/qemu/update_download.py "$img" || rc=$?
else
  python3 tests/qemu/boot_smoke.py || rc=$?
  python3 tests/qemu/desktop_smoke.py || rc=$?
fi
echo "== last serial lines"; tail -n 40 out/qemu/serial.log | tr -d '\r'
exit $rc
