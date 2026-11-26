#!/bin/bash
# Boots out/qemu/disk.img in QEMU (virt machine, 4 cores, 2 GB). The serial console is a TCP socket on 127.0.0.1:5555 so tests
# can drive it (tests/qemu_session.py); with no argument it also stays in the foreground.
#   tools/qemu/run.sh            boot, serial on tcp:5555
#   tools/qemu/run.sh reset      restore the disk from the copy made by prepare.sh first
set -euo pipefail
cd "$(dirname "$0")/../.."
QEMU=${QEMU:-"/c/Program Files/qemu/qemu-system-aarch64.exe"}
[ -x "$QEMU" ] || QEMU=qemu-system-aarch64
[ "${1:-}" = reset ] && cp out/qemu/disk.base.img out/qemu/disk.img
exec "$QEMU" -M virt -cpu cortex-a72 -smp 4 -m 2048 -nographic \
  -kernel out/qemu/Image -initrd out/qemu/initrd.cpio.gz \
  -append "root=PARTUUID=53544d52-02 rootwait rw init=/lib/systemd/systemd console=ttyAMA0 panic=-1 loglevel=4 systemd.log_level=info" \
  -drive file=out/qemu/disk.img,if=none,format=raw,id=d0 -device virtio-blk-pci,drive=d0 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -serial tcp:127.0.0.1:5555,server,nowait -monitor none
