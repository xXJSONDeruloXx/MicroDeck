#!/bin/bash
# Runs as the steam user with DISPLAY set. Settings come from /etc/steam-session.conf.
# patch-webhelper.py (a child process) reads it
. /etc/steam-session.conf
export WEBHELPER_EXTRA_ARGS
root=$HOME/.local/share/Steam
log=$HOME/steam-run.log
. /usr/local/share/mdeck/setup-ui.sh
if [ ! -x "$root/steamrtarm64/steam" ] || [ ! -f "$root/compatibilitytools.d/$(. /usr/local/share/mdeck/proton-armv8.conf; echo "$PROTON_NAME")/proton" ]; then
  setup_ui_start "Setting up MicroDeck"
  if [ ! -x "$root/steamrtarm64/steam" ]; then
    setup_ui 0 "Waiting for the internet connection..."
    waited=0
    until curl -fsI --max-time 10 https://client-update.steamstatic.com/ -o /dev/null || [ $? = 22 ]; do
      waited=$((waited + 5))
      if [ -e /sys/class/net/wlan0 ]; then
        [ "$waited" -lt 30 ] || setup_ui 0 "No internet yet. On a PC, copy wifi.txt.example to wifi.txt on the card's MICRODECK partition, fill in ssid= and psk=, and restart."
      else
        [ "$waited" -lt 30 ] || setup_ui 0 "No internet yet. This handheld has no Wi-Fi: plug it into a PC with the USB cable and share the PC's connection with it (README, Install)."
      fi
      sleep 5
    done
    setup_ui_run /usr/local/bin/steam-install.sh || { setup_ui_end; exit 1; }
  fi
  setup_ui_run /usr/local/bin/mdeck-install-proton || echo "== proton-armv8 install failed" >>"$log"
  setup_ui 100 "Starting Steam..."
  setup_ui_end
fi
# Linux x86 games run through a Steam compatibility tool that calls mdeck-fex (Valve's FEX with Steam's x86 runtime)
if [ -d "$root/compatibilitytools.d" ]; then
  rm -rf "$root/compatibilitytools.d/mdeck-fex" "$root/compatibilitytools.d/sx""x-fex"   # the second is the tool's name before the rename
  cp -r /usr/local/share/mdeck/compat/mdeck-fex "$root/compatibilitytools.d/" && chmod +x "$root/compatibilitytools.d/mdeck-fex/mdeck-fex-tool"
fi
export STEAM_RUNTIME=1 STEAM_STEAMRT_RECURSION_GUARD=1
export LD_LIBRARY_PATH=$root/steamrtarm64:$root/steamrtarm64/panorama
# LSE-Emu (ARMv8.0 has no LSE atomics; the client, its overlay, Proton and FEX are built with them):
# - liblse_emu_sys.so is in /etc/ld.so.preload. It loads after any LD_PRELOAD library and so initialises
#   first, before Steam's LSE-built overlay, which Steam adds to LD_PRELOAD for game launches.
# - liblse_emu.so here in LD_PRELOAD is what pressure-vessel carries into the game container, where the
#   host's ld.so.preload does not apply. The overlay is kept out of the container so nothing LSE-built
#   runs there before the handler exists.
export LD_PRELOAD=/usr/local/lib/lse/liblse_emu.so
export LSE_EMU=1 LSE_EMU_PATCH=1
export PRESSURE_VESSEL_REMOVE_GAME_OVERLAY=1
# Proton's xalia (gamepad helper for Win32 dialogs) costs ~14 % CPU and RAM in every game here.
export PROTON_USE_XALIA=0
# Direct3D through Wine's own renderer on the Mali (Panfrost GL 3.1) instead of DXVK on llvmpipe: Geometry
# Wars 8.6 FPS vs 1.4-6. Proton appends d3d9=n after any WINEDLLOVERRIDES, so only this switch works.
# D3D10/11 games need DXVK (WineD3D cannot do them on GL 3.1): set PROTON_USE_WINED3D=0 in their launch options.
export PROTON_USE_WINED3D=${PROTON_USE_WINED3D:-1}
export SDL_VIDEO_X11_DGAMOUSE=0
export XDG_RUNTIME_DIR=/run/user/$(id -u)
[ -d "$XDG_RUNTIME_DIR" ] || XDG_RUNTIME_DIR=/tmp/xdg-$(id -u)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/bus" ]; then export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
  else eval "$(dbus-launch --sh-syntax)"; fi
fi
ui=()
[ "${STEAM_UI:-gamepadui}" = gamepadui ] && ui=(-gamepadui)
# STEAMOS=1: SteamOS client mode (system settings, power menu); needs the steamos-* helpers on PATH.
if [ "${STEAMOS:-0}" = 1 ]; then
  ui=(-gamepadui -steamos3 -steampal -steamdeck)
  export STEAMOS_STEAM_REBOOT_SENTINEL=/tmp/steamos-reboot-sentinel
  export STEAMOS_STEAM_SHUTDOWN_SENTINEL=/tmp/steamos-shutdown-sentinel
  export STEAM_ENABLE_VOLUME_HANDLER=1
  # Steam's UI turns on its gamescope behaviour (hide itself while a game window has focus, base-layer
  # app queue) only when this is set. mdeck-focus plays gamescope's side on Xorg; nothing listens here.
  [ "${GAMESCOPE_COMPAT:-1}" = 1 ] && export GAMESCOPE_WAYLAND_DISPLAY=gamescope-0
  rm -f "$STEAMOS_STEAM_REBOOT_SENTINEL" "$STEAMOS_STEAM_SHUTDOWN_SENTINEL"
fi
cef=(-cef-disable-gpu -cef-disable-gpu-compositing)
[ "${CEF_GPU:-0}" = 1 ] && cef=()
[ -n "${CDP_PORT:-}" ] && cef+=(-cef-enable-debugging -devtools-port "$CDP_PORT")
cd "$root"
while :; do
  # Steam re-extracts the whole client when its post-crash checksum pass finds the patched steamwebhelper.sh, so
  # start it stock and patch once the updater has finished verifying, before the client launches the web helper.
  /usr/local/bin/patch-webhelper.py --restore >>"$log" 2>&1
  /usr/local/bin/mdeck-compat-default --seed >>"$log" 2>&1
  bootstrap=$root/logs/bootstrap_log.txt
  offset=$(stat -c %s "$bootstrap" 2>/dev/null || echo 0)
  ( tail -c +$((offset + 1)) -F "$bootstrap" 2>/dev/null | grep -a --line-buffered -E 'Verification complete|Update complete, launching' |
      while read -r _; do /usr/local/bin/patch-webhelper.py >>"$log" 2>&1; done ) &
  patcher=$!
  echo "== $(date -u +%FT%TZ) starting steam ${ui[*]} ${cef[*]} ${STEAM_EXTRA_ARGS:-}" >>"$log"
  [ -n "${CDP_PORT:-}" ] && /usr/local/bin/mdeck-steam-defaults >>"$log" 2>&1 &
  "$root/steamrtarm64/steam" -clientbeta "$(cat "$root/package/beta")" "${ui[@]}" \
    -no-cef-sandbox -cef-ozone-platform=x11 "${cef[@]}" ${STEAM_EXTRA_ARGS:-} >>"$log" 2>&1
  rc=$?
  pkill -P "$patcher" 2>/dev/null; kill "$patcher" 2>/dev/null
  echo "== $(date -u +%FT%TZ) steam exited rc=$rc" >>"$log"
  [ "$rc" = 42 ] || break
done
# Steam's power menu leaves a sentinel and exits; in dev mode poweroff is linked to reboot.
if [ -e "${STEAMOS_STEAM_REBOOT_SENTINEL:-/nonexistent}" ]; then
  rm -f "$STEAMOS_STEAM_REBOOT_SENTINEL"; echo "== reboot requested by Steam" >>"$log"; systemctl reboot
elif [ -e "${STEAMOS_STEAM_SHUTDOWN_SENTINEL:-/nonexistent}" ]; then
  rm -f "$STEAMOS_STEAM_SHUTDOWN_SENTINEL"; echo "== shutdown requested by Steam" >>"$log"; systemctl poweroff
fi
exit $rc
