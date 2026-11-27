#!/bin/bash
# Finds the device in whatever state it is in and gets back a shell, without touching it:
#   1. our OS on adb or SSH            -> done
#   2. muOS on adb (slot 1)            -> done (tools/fel-boot.sh boots our OS again)
#   3. boot ROM in FEL                 -> load out/uboot/fel-reset.bin, which resets into muOS
#   4. nothing on USB                  -> wait; a hung OS is rebooted into muOS by the watchdog
# Exit 0 with the state on stdout; exit 1 only when a person is needed (hung with USB power).
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
FEL=/c/Users/kurt/sdflash/tools/sunxi-fel.exe
MUOS=${MUOS_SERIAL:-0c001080c69249221d2}
KEY=secrets/id_ed25519
SSHO=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

state() {
  for s in $(adb devices | awk '$2 == "device" && $1 !~ /tls/ {print $1}'); do
    h=$(adb -s "$s" shell cat /etc/hostname 2>/dev/null | tr -d '\r')
    [[ "$h" =~ ^(microdeck-|rg40xx$) ]] && { echo "os-adb $s"; return; }
    [ "$s" = "$MUOS" ] && { echo "muos $s"; return; }
  done
  ssh "${SSHO[@]}" root@microdeck-rg40xx.local true 2>/dev/null && { echo "os-ssh microdeck-rg40xx.local"; return; }
  "$FEL" ver 2>/dev/null | grep -q AWUSBFEX && { echo fel; return; }
  echo none
}

deadline=$((SECONDS + ${RESCUE_WAIT:-240}))
while :; do
  st=$(state)
  case $st in
    os-adb*|os-ssh*|muos*) echo "$st"; exit 0 ;;
    fel)
      echo "== in FEL; loading the reset U-Boot" >&2
      "$FEL" uboot out/uboot/fel-reset.bin >&2 || true
      sleep 20 ;;
    none)
      [ $SECONDS -ge $deadline ] && {
        echo "nothing on USB, SSH or FEL for ${RESCUE_WAIT:-240} s: the SoC is probably hung with USB power;" \
             "needs a person: unplug USB, hold power 15 s, plug in, hold power 3 s" >&2
        exit 1; }
      sleep 5 ;;
  esac
done
