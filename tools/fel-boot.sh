#!/bin/bash
# Boots the OS on the slot-2 card without touching the device:
#   muOS (slot 1, adb) -> reboot(RESTART2, "efex") -> FEL -> sunxi-fel loads out/uboot/fel-boot.bin
#   -> U-Boot boots extlinux from mmc 2 (or exposes the slot-2 card over USB if that fails).
# A reset of the device returns to muOS, since the boot ROM still boots slot 1.
#   tools/fel-boot.sh [u-boot.bin]
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
UBOOT=${1:-out/uboot/fel-boot.bin}
FEL=/c/Users/kurt/sdflash/tools/sunxi-fel.exe
MUOS=${MUOS_SERIAL:-0c001080c69249221d2}
step() { echo "== $(date +%H:%M:%S) $*"; }

if ! "$FEL" ver 2>/dev/null | grep -q AWUSBFEX; then
  step "waiting for muOS on adb"
  until adb -s "$MUOS" get-state 2>/dev/null | grep -q device; do sleep 3; done
  step "rebooting muOS into FEL"
  # the RG40XX-H's muOS has no python of its own (a Debian chroot image supplies it); the RG28XX's muOS has
  adb -s "$MUOS" shell '[ -f /mnt/mmc/steamrg.img ] && { mountpoint -q /opt/steamrg || mount -o loop,noatime /mnt/mmc/steamrg.img /opt/steamrg; PY="chroot /opt/steamrg/root python3"; } || PY=python3; sync;
    $PY -c "import ctypes,os; os.sync(); ctypes.CDLL(None).syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, b\"efex\")"' >/dev/null 2>&1
  for i in $(seq 1 40); do "$FEL" ver 2>/dev/null | grep -q AWUSBFEX && break; sleep 2; done
fi
"$FEL" ver | grep AWUSBFEX || { step "FEL did not appear"; exit 1; }
step "loading $UBOOT over FEL"
"$FEL" -p uboot "$UBOOT" || { step "sunxi-fel failed"; exit 1; }
step "U-Boot started; waiting for the OS (adb hostname rg40xx) or the slot-2 card over USB"
for i in $(seq 1 90); do
  for s in $(adb devices | awk '$2=="device" && !/tls/ {print $1}'); do
    [ "$(adb -s "$s" shell cat /etc/hostname 2>/dev/null | tr -d '\r')" = rg40xx ] && { step "OS up on adb $s"; exit 0; }
  done
  powershell -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object InstanceId -like 'USB\VID_1F3A&PID_1010*'" 2>/dev/null | grep -q 1010 && { step "U-Boot is exposing the slot-2 card over USB (boot failed)"; exit 2; }
  sleep 4
done
step "nothing came up within 6 minutes"
exit 3
