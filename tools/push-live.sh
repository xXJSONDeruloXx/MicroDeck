#!/bin/bash
# Applies the repository to the running device without reflashing or rebuilding, so installed games and the
# Steam login survive: overlay files (only those that differ), the C helpers (compiled on the device), the
# packages named in rootfs/Dockerfile that the device lacks, then reloads systemd.
#   tools/push-live.sh [-r] [package ...]
# -r restarts steam-session when a file the session reads changed (it ends a running game).
# Not covered, so these still need a rebuild: the kernel, U-Boot and the lse_emu.so preload.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
restart=0; [ "${1:-}" = -r ] && { restart=1; shift; }
KEY=secrets/id_ed25519
HOST=${DEV_HOST:-microdeck-rg40xx.local}
SSH=(ssh -p "${DEV_PORT:-22}" -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
dev() { "${SSH[@]}" "root@$HOST" "$@"; }

# Packages the image installs, read from the Dockerfile's apt-get lines (backports pin and flags dropped).
pkgs=$(python - <<'PY'
import re
s = open("rootfs/Dockerfile", newline="").read().replace(chr(92) + chr(10), " ")
out = []
for m in re.finditer(r"apt-get install([^&\n]*)", s):
    t = m.group(1).split()
    skip = False
    for w in t:
        if skip: skip = False; continue
        if w == "-t": skip = True; continue
        if w.startswith("-") or w in ("locales",): continue
        out.append(w)
print(" ".join(dict.fromkeys(out)))
PY
)
pkgs="$pkgs $*"

# Overlay files whose content differs from the device's.
local_sums=$(cd overlay && find . -type f ! -name .keep -print0 | sort -z | xargs -0 sha256sum | sed -E 's| \*?\./| /|')
remote_sums=$(echo "$local_sums" | awk '{print $2}' | dev 'xargs sha256sum 2>/dev/null' || true)
changed=$(join -v1 -1 2 -2 2 <(echo "$local_sums" | sort -k2) <(echo "$remote_sums" | sort -k2) | awk '{print $1}'; \
          join -1 2 -2 2 <(echo "$local_sums" | sort -k2) <(echo "$remote_sums" | sort -k2) | awk '$2 != $3 {print $1}')
# /etc/steam-session.conf holds per-device switches (STEAMOS, NESTED_GAMESCOPE ...) that get edited on the device;
# a push would reset them. FORCE_CONF=1 overwrites it.
if [ "${FORCE_CONF:-0}" != 1 ] && echo "$changed" | grep -qx /etc/steam-session.conf; then
  echo "push-live: keeping the device's /etc/steam-session.conf (FORCE_CONF=1 to overwrite)"
  changed=$(echo "$changed" | grep -vx /etc/steam-session.conf || true)
fi
if [ -n "$changed" ]; then
  echo "push-live: $(echo "$changed" | wc -l) overlay file(s) changed"; echo "$changed" | sed 's/^/  /'
  echo "$changed" | sed 's|^/||' | tar -C overlay -cf - -T - | dev 'tar -xf - -C / --no-same-owner --no-overwrite-dir'
else
  echo "push-live: overlay already current"
fi
tar -C rootfs/src -cf - --exclude=lse_emu.c . | dev 'mkdir -p /usr/local/src && tar -xf - -C /usr/local/src --no-same-owner --no-overwrite-dir'
dev "set -e
  missing=\$(for p in $pkgs; do dpkg -s \$p >/dev/null 2>&1 || echo \$p; done)
  [ -z \"\$missing\" ] || { echo \"push-live: installing \$missing\"; apt-get update -qq && apt-get install -y -qq --no-install-recommends -o Dpkg::Options::=--force-confold \$missing; }
  gcc -O2 -Wall -o /usr/local/bin/padmap /usr/local/src/padmap.c
  gcc -O2 -Wall -o /usr/local/bin/memload /usr/local/src/memload.c
  mkdir -p /usr/local/lib/mdeck && gcc -O2 -Wall -shared -fPIC -o /usr/local/lib/mdeck/vk-fake-drm.so /usr/local/src/vk-fake-drm.c -ldl
  gcc -O2 -Wall -o /usr/local/bin/mdeck-focus /usr/local/src/mdeck-focus.c -lX11 -lXRes
  gcc -O2 -Wall -o /usr/local/sbin/reach-guard.new /usr/local/src/reach-guard.c && mv -f /usr/local/sbin/reach-guard.new /usr/local/sbin/reach-guard
  chmod +x /usr/local/bin/* /usr/local/sbin/*
  chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true
  systemctl daemon-reload
  systemd-tmpfiles --create /etc/tmpfiles.d/*.conf
  systemctl enable --now earlyoom.service >/dev/null 2>&1
  systemctl enable mdeck-wifi-import.service >/dev/null 2>&1
  systemctl restart reach-guard.service earlyoom.service
  if [ -e /swapfile ]; then swapoff /swapfile 2>/dev/null || true; rm -f /swapfile; fi"
# The session reads these at start; a running Steam keeps the old copies until it restarts.
if echo "$changed" | grep -qE '/(run-steam\.sh|steam-session[^/]*|mdeck-[^/]*|steam-defaults\.js|patch-webhelper\.py|openbox[^ ]*)$|/etc/steam-session\.conf$|/etc/xdg/openbox/'; then
  if [ "$restart" = 1 ]; then dev 'systemctl restart steam-session'; echo "push-live: steam-session restarted"
  else echo "push-live: session files changed; run 'systemctl restart steam-session' on the device (or push-live -r)"; fi
fi
echo "push-live: ok"
