#!/bin/bash
# Proves that installing only the used chunks (mdeck-used-chunks) gives a correct root: take the root partition of an image, write just
# its used chunks onto a target full of random bytes (the worst case for stale data), then require a clean e2fsck and an identical
# file tree (`diff -r` of both mounted read-only).
#   tools/qemu/verify-chunks.sh <microdeck-rg40xx.img.xz>
set -euo pipefail
cd "$(dirname "$0")/../.."
img=${1:?usage: tools/qemu/verify-chunks.sh image.img.xz}
mkdir -p out/qemu
env MSYS_NO_PATHCONV=1 docker run --rm --privileged --platform linux/amd64 -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
  set -euo pipefail
  apt-get update -qq >/dev/null && apt-get install -y -qq e2fsprogs xz-utils python3 util-linux diffutils >/dev/null 2>&1
  W=/tmp/verify; mkdir -p $W /mnt/a /mnt/b
  echo "== extracting the root partition"
  xz -dc "'"$img"'" | { dd of=/dev/null bs=1M count=272 iflag=fullblock status=none; dd of=$W/root.img bs=1M count=3072 iflag=fullblock status=none; }
  echo "== used chunks"
  python3 overlay/usr/local/sbin/mdeck-used-chunks $W/root.img > $W/chunks
  awk "{s += \$2} END {print s \" of 3072 MiB are written\"}" $W/chunks
  echo "== target full of random bytes"
  head -c 3221225472 /dev/urandom > $W/target.img
  while read -r start count; do
    dd if=$W/root.img of=$W/target.img bs=1M skip=$start seek=$start count=$count conv=notrunc status=none
  done < $W/chunks
  sync
  echo "== e2fsck of the target"
  e2fsck -fn $W/target.img
  echo "== compare file trees"
  mount -o loop,ro,noload $W/root.img /mnt/a
  mount -o loop,ro,noload $W/target.img /mnt/b
  diff -r --no-dereference /mnt/a /mnt/b && echo "TREES IDENTICAL"
  umount /mnt/a /mnt/b
  echo "chunk install verified"'
