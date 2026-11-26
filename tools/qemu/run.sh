#!/bin/bash
# Boots out/qemu/disk.img in QEMU (virt machine, 4 cores, 2 GB) in the foreground. Use tools/vm.sh instead; this is what it runs.
#   serial console   tcp:127.0.0.1:5555 (tests/qemu/session.py), also logged to out/qemu/serial.log
#   monitor          tcp:127.0.0.1:5556 (screendump, sendkey)
#   ssh              127.0.0.1:2222 (root, key from tools/vm.sh prepare)
#   display          virtio-gpu, shown in a window with VM_DISPLAY=1, headless otherwise (screenshots via the monitor)
set -euo pipefail
cd "$(dirname "$0")/../.."
QEMU=${QEMU:-"/c/Program Files/qemu/qemu-system-aarch64.exe"}
[ -x "$QEMU" ] || QEMU=qemu-system-aarch64
accel=(-cpu cortex-a72)
[ -w /dev/kvm ] && accel=(-accel kvm -cpu host)   # on an arm64 host with KVM
display=(-display none)
[ "${VM_DISPLAY:-0}" = 1 ] && display=(-display sdl)
exec "$QEMU" -M virt "${accel[@]}" -smp 4 -m "${VM_MEM:-2048}" \
  -kernel out/qemu/Image -initrd out/qemu/initrd.cpio.gz \
  -append "root=PARTUUID=53544d52-02 rootwait rw init=/lib/systemd/systemd console=ttyAMA0 panic=-1 loglevel=4 ${VM_CMDLINE:-}" \
  -drive file=out/qemu/disk.img,if=none,format=raw,id=d0 -device virtio-blk-pci,drive=d0 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -device virtio-gpu-pci -device usb-ehci -device usb-kbd -device usb-tablet "${display[@]}" \
  -chardev socket,id=ser,host=127.0.0.1,port=5555,server=on,wait=off,logfile=out/qemu/serial.log -serial chardev:ser \
  -monitor tcp:127.0.0.1:5556,server=on,wait=off
