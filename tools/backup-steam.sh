#!/bin/bash
# Backs up the device's Steam install (client, Proton/FEX, runtimes, games, prefixes, login) to
# cache/steam-backup.tar, so a reflash does not mean downloading it all again. The tar is written on the
# device and pulled over adb: streaming it over SSH (Wi-Fi) or an adb shell pipe (not binary-safe) is slow
# or corrupts it. It holds the Steam login, so it stays in cache/ (gitignored).
#   tools/backup-steam.sh                  back up
#   STEAM_SEED=cache/steam-backup.tar tools/build-image.sh      seed an image with it
#   tools/restore-steam.sh                 put it back on a running device
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
s=$(adb devices | awk '$2 == "device" && $1 !~ /tls/ {print $1}' | while read -r d; do adb -s "$d" shell cat /etc/hostname | tr -d '\r' | grep -qE '^(microdeck-|rg40xx$)' && echo "$d" && break; done)
[ -n "$s" ] || { echo "device not on adb"; exit 1; }
cat > out/mk-backup.sh <<'EOS'
cd /home/steam
rm -f /var/tmp/steam-backup.tar /var/tmp/steam-backup.tar.part
# exit status 1 only means a file changed while it was read (Steam is running)
nice -n 10 tar --numeric-owner -cf /var/tmp/steam-backup.tar.part \
  --exclude=.local/share/Steam/logs --exclude=.local/share/Steam/steamapps/shadercache \
  --exclude=.local/share/Steam/steamapps/downloading --exclude=.local/share/Steam/steamapps/temp \
  --exclude=.local/share/Steam/package/dl --exclude=.local/share/Steam/dumps --exclude='*.zip.*' \
  .local/share/Steam .steam
[ $? -le 1 ] && mv /var/tmp/steam-backup.tar.part /var/tmp/steam-backup.tar
tar -tf /var/tmp/steam-backup.tar > /dev/null && echo ok
EOS
adb -s "$s" push out/mk-backup.sh /var/tmp/mk-backup.sh > /dev/null
adb -s "$s" shell 'sh /var/tmp/mk-backup.sh' | grep -q ok || { echo "tar failed"; exit 1; }
adb -s "$s" pull /var/tmp/steam-backup.tar cache/steam-backup.tar
adb -s "$s" shell 'rm -f /var/tmp/steam-backup.tar'
ls -la cache/steam-backup.tar
