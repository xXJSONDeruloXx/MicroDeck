#!/bin/bash
# Tests sxx-focus (rootfs/src/sxx-focus.c) against a real X server: a window with no _NET_WM_PID (like an SDL 1.2 game), started under a
# process that looks like `reaper SteamLaunch AppId=123`, must be recognised as app 123, published as focusable, and brought to the front
# when Steam's base layer asks for it. Needs: gcc, libx11-dev, libxres-dev, xvfb, openbox, x11-utils, x11-apps (xmessage), xdotool.
#   tests/focus/run.sh          (CI installs the packages; locally: tests/focus/docker.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "FAIL $*"; exit 1; }
gcc -O2 -Wall -o /tmp/sxx-focus rootfs/src/sxx-focus.c -lX11 -lXRes
Xvfb :99 -screen 0 640x480x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99
openbox >/dev/null 2>&1 &
sleep 2
mkdir -p /tmp/fake && cp "$(command -v bash)" /tmp/fake/reaper
# the game: a child of "reaper ... SteamLaunch AppId=123", its window carries no _NET_WM_PID
/tmp/fake/reaper -c 'xmessage -name Game123 -geometry 200x100+0+0 "game" & wait' SteamLaunch AppId=123 >/dev/null 2>&1 &
sleep 3
# a second window of no app, mapped later (the "Steam" window stand-in)
xmessage -name Other -geometry 200x100+300+0 "other" >/dev/null 2>&1 &
sleep 2
/tmp/sxx-focus >/tmp/focus.log 2>&1 &
sleep 2
xprop -root GAMESCOPE_FOCUSABLE_APPS | grep -q 123 || { cat /tmp/focus.log; fail "app 123 is not listed as focusable"; }
echo "ok   the PID-less window was recognised as app 123 through XRes"
# Steam asks for app 123 on top
xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c -set GAMESCOPECTRL_BASELAYER_APPID 123
sleep 2
active=$(xprop -root _NET_ACTIVE_WINDOW | grep -o '0x[0-9a-f]*')
game=$(xwininfo -root -tree | grep Game123 | grep -o '0x[0-9a-f]*' | head -1)
[ -n "$game" ] || fail "the game window does not exist"
[ "$(printf '%d' "$active")" = "$(printf '%d' "$game")" ] || fail "active window $active is not the game's $game"
echo "ok   the game window was activated"
echo "focus daemon test passed"
