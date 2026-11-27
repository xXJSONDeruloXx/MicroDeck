#!/bin/bash
# Rewrites the slot-2 card (the OS under test) from out/microdeck-rg40xx.img without touching the device:
# boots muOS (slot 1, recovery), copies the gzipped image over adb, writes it to /dev/mmcblk1, then
# FEL-boots the new system. The card's first boot grows the root partition. Games, Proton and the Steam
# login are not in a lean image: tools/restore-steam.sh puts cache/steam-backup.tar back afterwards.
#   tools/reflash-slot2.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
MUOS=${MUOS_SERIAL:-0c001080c69249221d2}
IMG=out/microdeck-rg40xx.img
step() { echo "== $(date +%H:%M:%S) $*"; }
[ -f "$IMG" ] || { echo "build the image first: tools/build-image.sh"; exit 1; }

if ! adb -s "$MUOS" get-state 2>/dev/null | grep -q device; then
  step "getting the device into muOS"
  tools/dev.sh sh 'systemctl reboot' >/dev/null 2>&1 || true
  until adb -s "$MUOS" get-state 2>/dev/null | grep -q device; do sleep 3; done
  sleep 15
fi
step "compressing the image"
[ "$IMG.gz" -nt "$IMG" ] || gzip -1 -c "$IMG" > "$IMG.gz"
size_mb=$(( $(stat -c %s "$IMG.gz") / 1048576 ))
free_mb=$(adb -s "$MUOS" shell 'df -m /mnt/mmc | tail -1' | tr -s ' ' | cut -d' ' -f4)
[ "${free_mb:-0}" -gt $((size_mb + 200)) ] || { echo "muOS storage has ${free_mb:-?} MB free, need $((size_mb + 200))"; exit 1; }
step "copying ${size_mb} MB to muOS"
adb -s "$MUOS" push "$IMG.gz" /mnt/mmc/steamos.img.gz
step "writing /dev/mmcblk1"
# muOS keeps slot 2 mounted: make it read-only first, or its writeback corrupts the new image
adb -s "$MUOS" shell 'mount -o remount,ro /mnt/sdcard 2>/dev/null; umount /mnt/sdcard 2>/dev/null; gunzip -c /mnt/mmc/steamos.img.gz | dd of=/dev/mmcblk1 bs=4M conv=fsync 2>&1 | tail -2; sync; rm -f /mnt/mmc/steamos.img.gz'
step "booting the new system through FEL"
tools/fel-boot.sh ${UBOOT:+"$UBOOT"}
