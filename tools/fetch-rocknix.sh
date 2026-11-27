#!/bin/bash
# Downloads the ROCKNIX H700 image and extracts what this project reuses into cache/:
#   uboot.bin (raw, written at 8 KiB), boot/KERNEL, boot/device_trees/*.dtb,
#   overlay/usr/lib/kernel-overlays/base (kernel 7.2.0 modules + firmware), joypad hwdb.
set -euo pipefail
cd "$(dirname "$0")/.."
REL=${ROCKNIX_RELEASE:-20261101}
RAM=${ROCKNIX_RAM:-DDR4}
name=ROCKNIX-H700.aarch64-$REL-$RAM.img.gz
url=https://github.com/ROCKNIX/distribution/releases/download/$REL/$name
mkdir -p cache
if [ ! -f cache/rocknix.img ]; then
  curl -fL -o cache/$name "$url"
  want=$(curl -fsSL "$url.sha256" | cut -d' ' -f1)
  echo "$want  cache/$name" | sha256sum -c -
  gzip -dc cache/$name > cache/rocknix.img
fi
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd)/cache:/w" -w /w debian:trixie bash -c '
  set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null
  apt-get install -y -qq mtools squashfs-tools >/dev/null 2>&1
  dd if=rocknix.img of=uboot.bin bs=1K skip=8 count=16376 status=none
  dd if=rocknix.img of=p1.img bs=1M skip=16 count=2048 status=none
  rm -rf boot overlay && mkdir boot && mcopy -s -i p1.img ::/* boot/ && rm p1.img
  unsquashfs -q -d overlay boot/SYSTEM usr/lib/kernel-overlays/base usr/lib/udev/hwdb.d/20-joypad.hwdb >/dev/null
  ls boot/device_trees | grep rg40xx'
