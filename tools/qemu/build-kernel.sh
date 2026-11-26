#!/bin/bash
# A generic arm64 kernel for the QEMU virtual device (tools/qemu/run.sh): kernel.org 7.2 defconfig with virtio disk, ext4 and
# FAT built in, so our own initramfs (which has no modules) can mount the image. Cross-compiled in an amd64 container.
#   tools/qemu/build-kernel.sh        -> out/qemu/Image
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/qemu cache/qemu
exec env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential gcc-aarch64-linux-gnu bc bison flex libssl-dev libelf-dev xz-utils curl cpio kmod >/dev/null
KVER=7.2
if [ ! -d /tmp/linux ]; then
  [ -f cache/qemu/linux.tar.xz ] || curl -fL -o cache/qemu/linux.tar.xz https://www.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz
  mkdir /tmp/linux && tar -xf cache/qemu/linux.tar.xz -C /tmp/linux --strip-components=1
fi
cd /tmp/linux
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make defconfig >/dev/null
for o in VIRTIO VIRTIO_PCI VIRTIO_MMIO VIRTIO_BLK VIRTIO_NET VIRTIO_CONSOLE HW_RANDOM_VIRTIO SCSI_VIRTIO BLK_DEV_LOOP \
         EXT4_FS VFAT_FS FAT_FS MSDOS_FS NLS_CODEPAGE_437 NLS_ISO8859_1 NLS_UTF8 DEVTMPFS DEVTMPFS_MOUNT TMPFS CGROUPS \
         SERIAL_AMBA_PL011 SERIAL_AMBA_PL011_CONSOLE PCI_HOST_GENERIC FB_SIMPLE DRM_VIRTIO_GPU VT FRAMEBUFFER_CONSOLE; do
  scripts/config -e CONFIG_$o
done
scripts/config --set-str CONFIG_DEFAULT_HOSTNAME qemu
make olddefconfig </dev/null >/dev/null
make -j"$(nproc)" Image >/dev/null
cp arch/arm64/boot/Image /w/out/qemu/Image
ls -la /w/out/qemu/Image
'
