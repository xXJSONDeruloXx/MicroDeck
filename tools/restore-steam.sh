#!/bin/bash
# Replaces the device's Steam tree with cache/steam-backup.tar (the session is stopped meanwhile). After a
# reflash this is what restores games, Proton, FEX and the login; the host disk is too small to bake them
# into the image (STEAM_SEED= works where there is room).
# The tar travels as a raw TCP stream through `adb forward` and is unpacked on the fly: `adb push` of
# gigabytes makes the device's adbd balloon until the OOM killer ends the transfer, and SSH over Wi-Fi is slow.
#   tools/restore-steam.sh [tar]
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
TAR=${1:-cache/steam-backup.tar}
PORT=${RESTORE_PORT:-19001}
s=$(adb devices | awk '$2 == "device" && $1 !~ /tls/ {print $1}' | while read -r d; do adb -s "$d" shell cat /etc/hostname | tr -d '\r' | grep -qE '^(microdeck-|rg40xx$)' && echo "$d" && break; done)
[ -n "$s" ] || { echo "device not on adb"; exit 1; }
[ -f "$TAR" ] || { echo "no $TAR"; exit 1; }
cat > out/recv.py <<'EOS'
import socket, sys
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", int(sys.argv[1]))); srv.listen(1)
c, _ = srv.accept(); out = sys.stdout.buffer
while True:
    b = c.recv(1 << 20)
    if not b: break
    out.write(b)
out.flush()
EOS
adb -s "$s" push out/recv.py /var/tmp/recv.py > /dev/null
adb -s "$s" shell 'systemctl stop steam-session; rm -rf /home/steam/.local/share/Steam /home/steam/.steam; mkdir -p /home/steam/.local/share
  rm -f /var/tmp/restore.done; (python3 /var/tmp/recv.py '"$PORT"' | tar -C /home/steam --numeric-owner -xf - ; echo "$?" > /var/tmp/restore.done) > /var/tmp/restore.log 2>&1 &'
adb -s "$s" forward tcp:"$PORT" tcp:"$PORT" > /dev/null
sleep 3
python - "$TAR" "$PORT" <<'EOS'
import socket, sys, time
f = open(sys.argv[1], "rb"); c = socket.create_connection(("127.0.0.1", int(sys.argv[2])))
total = 0; t = time.time()
while True:
    b = f.read(1 << 20)
    if not b: break
    c.sendall(b); total += len(b)
    if total % (1 << 29) == 0: print(f"{total >> 20} MB, {total / (time.time() - t) / 1e6:.1f} MB/s", flush=True)
c.close()
EOS
until adb -s "$s" shell 'test -f /var/tmp/restore.done' 2>/dev/null; do sleep 3; done
rc=$(adb -s "$s" shell 'cat /var/tmp/restore.done' | tr -d '\r')
adb -s "$s" forward --remove tcp:"$PORT" > /dev/null
[ "$rc" = 0 ] || { echo "tar exited $rc"; adb -s "$s" shell 'cat /var/tmp/restore.log'; exit 1; }
adb -s "$s" shell 'chown -R steam:steam /home/steam/.local /home/steam/.steam; rm -f /var/tmp/recv.py /var/tmp/restore.done /var/tmp/steam-backup.tar; systemctl start steam-session; echo restored'
