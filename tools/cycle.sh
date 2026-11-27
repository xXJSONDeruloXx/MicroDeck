#!/bin/bash
# Build, flash, restore and test in one command, no physical steps (muOS in slot 1 is the recovery).
#   tools/cycle.sh                      build flash test (restore is first-time only: the data partition survives a flash)
#   tools/cycle.sh flash restore test   only the named stages, in this order
#   APPID=8400 tools/cycle.sh test      the game mdeck-gametest launches (default 8400, Geometry Wars)
# build   rootfs + lean image (no Steam seed: the host disk is too small for the 11 GB tree)
# flash   writes slot 2 from muOS and FEL-boots it (tools/reflash-slot2.sh)
# restore streams cache/steam-backup.tar back: games, Proton, FEX and the login (tools/restore-steam.sh)
# test    tools/smoke.sh, then mdeck-gametest on the device
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
APPID=${APPID:-8400}
# restore is needed once per card: Steam lives on the data partition (/home), which a flash keeps.
stages=("$@"); [ ${#stages[@]} -gt 0 ] || stages=(build flash test)
step() { echo; echo "=== $(date +%H:%M:%S) $*"; }

wait_steam_ui() {
  for _ in $(seq 120); do
    tools/dev.sh sh "mdeck eval 'document.location.pathname'" 2>/dev/null | tr -d '\r' | grep -q '^/routes/' && return 0
    sleep 5
  done
  echo "Steam's UI did not come up within 10 minutes"; return 1
}

for stage in "${stages[@]}"; do
  case "$stage" in
    build)   step "build"; DEV_MODE=${DEV_MODE:-1} tools/build-rootfs.sh; STEAM_SEED=none tools/build-image.sh ;;
    flash)   step "flash"; tools/reflash-slot2.sh ;;
    restore) step "restore"; tools/restore-steam.sh; step "waiting for Steam"; wait_steam_ui ;;
    test)    step "smoke"; wait_steam_ui; tools/smoke.sh
             step "game test $APPID"; tools/dev.sh sh "mdeck-gametest $APPID" ;;
    *) echo "unknown stage '$stage' (build flash restore test)"; exit 2 ;;
  esac
done
step "done"
