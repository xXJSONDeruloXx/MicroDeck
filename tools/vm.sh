#!/bin/bash
# The QEMU virtual device: our real initramfs and image on a generic arm64 kernel, for work that needs no hardware (boot, services,
# firstboot, the updater and its rollback, overlay changes). Built for agents: every command is one short call.
#
#   tools/vm.sh setup <image.img.xz>   once: build the kernel (cached) and make a bootable disk with your SSH key in it
#   tools/vm.sh start                  boot in the background; returns when SSH answers (about 2 minutes)
#   tools/vm.sh stop | reset           power off | restore the disk to the state prepare made (before inject)
#   tools/vm.sh sh 'cmd'               run a command as root in the VM (the same tools/dev.sh the device uses, DEV_TARGET=vm)
#   tools/vm.sh inject                 write overlay/ into the stopped VM's disk (to test boot-time changes without an image)
#   tools/vm.sh push                   apply overlay/ to the running VM (tools/push-live.sh)
#   tools/vm.sh shot [out.png]         screenshot of the VM display through the QEMU monitor
#   tools/vm.sh log [n]                last n lines of the serial console
#   tools/vm.sh test [updater|reflash|boot]   integration tests from a fresh disk: updater install/rollback/recovery.txt (default),
#                                      reflash keeping the data partition, boot smoke
#   tools/vm.sh status
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
Q=out/qemu
export DEV_TARGET=vm DEV_HOST=127.0.0.1 DEV_PORT=2222
KEY=secrets/id_ed25519

running() { [ -f $Q/vm.pid ] && tasklist //FI "PID eq $(cat $Q/vm.pid)" 2>/dev/null | grep -q "$(cat $Q/vm.pid)" || kill -0 "$(cat $Q/vm.pid 2>/dev/null)" 2>/dev/null; }
ssh_ok() { tools/dev.sh sh true >/dev/null 2>&1; }

monitor() {  # one command to the QEMU monitor over TCP
  python - "$1" <<'PY'
import socket, sys, time
s = socket.create_connection(("127.0.0.1", 5556), timeout=5)
time.sleep(0.3); s.recv(65536)
s.sendall((sys.argv[1] + "\r\n").encode()); time.sleep(1.0)
s.settimeout(1)
try: print(s.recv(65536).decode(errors="replace").strip())
except OSError: pass
PY
}

case "${1:-status}" in
  setup)
    img=${2:?usage: tools/vm.sh setup <steamos-rg40xx.img.xz>}
    [ -f $Q/Image ] || bash tools/qemu/build-kernel.sh
    bash tools/qemu/prepare.sh "$img" ;;
  start)
    running && { echo "already running"; exit 0; }
    : > $Q/serial.log
    (bash tools/qemu/run.sh > $Q/qemu.out 2>&1 & echo $! > $Q/vm.pid)
    echo "booting (serial log: $Q/serial.log)"
    for i in $(seq 1 120); do ssh_ok && { echo "ssh up after ~$((i * 5)) s"; exit 0; }; sleep 5; done
    echo "ssh did not answer; see $Q/serial.log"; exit 1 ;;
  stop)
    running && kill "$(cat $Q/vm.pid)" 2>/dev/null; sleep 1; rm -f $Q/vm.pid; echo stopped ;;
  reset)
    running && { echo "stop it first"; exit 1; }
    cp $Q/disk.base.img $Q/disk.img && echo "disk restored" ;;
  sh) tools/dev.sh sh "$2" ;;
  inject) running && { echo "stop it first"; exit 1; }; bash tools/qemu/inject.sh ;;
  push) bash tools/push-live.sh ;;
  shot)
    out=${2:-out/vm-shot.ppm}
    monitor "screendump $out" >/dev/null; echo "$out" ;;
  log) tail -n "${2:-60}" $Q/serial.log | tr -d '\r' ;;
  test)
    # tools/vm.sh test [updater|reflash]: both run from a fresh disk with the current overlay and initramfs injected
    running && bash "$0" stop
    bash "$0" reset && bash "$0" inject && bash "$0" start || exit 1
    case "${2:-updater}" in
      updater) python tests/qemu/update_flow.py ;;
      reflash) python tests/qemu/reflash_reuse.py ;;
      boot)    python tests/qemu/boot_smoke.py ;;
      *) echo "tests: updater | reflash | boot"; exit 2 ;;
    esac ;;
  status)
    if running; then echo "vm: running (pid $(cat $Q/vm.pid))"; ssh_ok && echo "ssh: ok" || echo "ssh: not yet"; else echo "vm: stopped"; fi ;;
  *) sed -n 2,16p "$0"; exit 2 ;;
esac
