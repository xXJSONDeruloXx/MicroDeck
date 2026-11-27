#!/bin/bash
# Talks to the device: adb over USB when the gadget is up, otherwise SSH over Wi-Fi.
#   tools/dev.sh status          which channels work
#   tools/dev.sh sh 'cmd'        run a command (adb first, then ssh)
#   tools/dev.sh ssh [args]      interactive/raw ssh
#   tools/dev.sh shot [out.png]  screenshot of the panel (X root window)
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
KEY=secrets/id_ed25519
HOST=${DEV_HOST:-microdeck-rg40xx.local}
PORT=${DEV_PORT:-22}
SSH=(ssh -p "$PORT" -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

# Two handhelds can be online at once (both are named rg40xx): DEV_SERIAL=<adb serial> picks one by USB, DEV_VIA=ssh with DEV_HOST=<ip> the other over the network.
adb_serial() {
  [ "${DEV_TARGET:-}" = vm ] && return 0   # the QEMU virtual device (tools/vm.sh) is reached over SSH only
  [ "${DEV_VIA:-}" = ssh ] && return 0
  [ -n "${DEV_SERIAL:-}" ] && { echo "$DEV_SERIAL"; return; }
  adb devices | awk '$2 == "device" && $1 !~ /tls/ {print $1}' | while read -r s; do
    adb -s "$s" shell cat /etc/hostname 2>/dev/null | tr -d '\r' | grep -qE '^(microdeck-|rg40xx$)' && { echo "$s"; break; }
  done
}

run() {
  local s; s=$(adb_serial)
  if [ -n "$s" ]; then adb -s "$s" shell "$1"; return; fi
  "${SSH[@]}" "root@$HOST" "$1"
}

case "${1:-status}" in
  status)
    s=$(adb_serial); echo "adb: ${s:-not connected}"
    if "${SSH[@]}" "root@$HOST" true 2>/dev/null; then echo "ssh: root@$HOST ok"; else echo "ssh: root@$HOST unreachable"; fi ;;
  sh) run "$2" ;;
  ssh) shift; "${SSH[@]}" "root@$HOST" "$@" ;;
  shot)
    # What the panel scans out (KMS plane via ffmpeg kmsgrab); xwd of the X root misreads GL windows.
    out=${2:-out/shot.png}
    run 'ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card1 -f kmsgrab -i - -vf hwdownload,format=bgr0 -frames:v 1 /tmp/shot.png' >/dev/null 2>&1
    s=$(adb_serial)
    if [ -n "$s" ]; then adb -s "$s" pull /tmp/shot.png "$out" >/dev/null
    else scp -q -P "$PORT" -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$HOST:/tmp/shot.png" "$out"; fi
    echo "$out" ;;
  *) echo "usage: $0 status|sh CMD|ssh ARGS|shot [png]"; exit 2 ;;
esac
