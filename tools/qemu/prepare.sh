#!/bin/bash
# Makes a bootable copy of a release image for the QEMU virtual device: a larger raw disk plus our initramfs taken out of its boot
# partition (the generic kernel from build-kernel.sh replaces the H700 kernel; everything after it is the real image).
#   tools/qemu/prepare.sh <steamos-rg40xx.img.xz>  -> out/qemu/disk.img, out/qemu/initrd.cpio.gz
set -euo pipefail
cd "$(dirname "$0")/../.."
src=${1:?usage: tools/qemu/prepare.sh steamos-rg40xx.img.xz}
mkdir -p out/qemu
echo "== unpacking $src"
xz -dc "$src" > out/qemu/disk.img
truncate -s 8G out/qemu/disk.img
echo "== reading the boot partition"
env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
  apt-get update -qq && apt-get install -y -qq mtools >/dev/null
  mcopy -n -i out/qemu/disk.img@@16M ::initrd.cpio.gz out/qemu/initrd.cpio.gz
  mcopy -n -i out/qemu/disk.img@@16M ::extlinux/extlinux.conf out/qemu/extlinux.conf
  mcopy -o -i out/qemu/disk.img@@16M /w/secrets/id_ed25519.pub ::authorized_keys
  ls -la out/qemu/initrd.cpio.gz'
cp out/qemu/disk.img out/qemu/disk.base.img 2>/dev/null || true
echo "== ready: tools/qemu/run.sh"
