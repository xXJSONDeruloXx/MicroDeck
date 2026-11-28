#!/bin/bash
# Tests mdeck-focus (rootfs/src/mdeck-focus.c) against a real X server: a window with no _NET_WM_PID (like an SDL 1.2 game), started under a
# process that looks like `reaper SteamLaunch AppId=123`, must be recognised as app 123, published as focusable, and brought to the front
# when Steam's base layer asks for it. Needs: gcc, libx11-dev, libxres-dev, xvfb, openbox, x11-utils, x11-apps (xmessage), xdotool.
#   tests/focus/run.sh          (CI installs the packages; locally: tests/focus/docker.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "FAIL $*"; exit 1; }
gcc -O2 -Wall -o /tmp/mdeck-focus rootfs/src/mdeck-focus.c -lX11 -lXRes
gcc -O2 -Wall -o /tmp/mdeck-scale rootfs/src/mdeck-scale.c -lX11 -lXcomposite -lXdamage -lXfixes -lGL
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
# stands in for mdeck-fit: records what the daemon asks for
cat > /tmp/fake-fit <<'EOF'
#!/bin/sh
echo "$@" >> /tmp/fit.calls
EOF
chmod +x /tmp/fake-fit; rm -f /tmp/fit.calls
MDECK_FIT=/tmp/fake-fit /tmp/mdeck-focus >/tmp/focus.log 2>&1 &
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
# a game window bigger than the 640x480 screen: the screen is fitted to it; when it shrinks back, the fit is undone
xdotool windowsize "$game" 800 600
sleep 3
grep -q "^800 600$" /tmp/fit.calls || { cat /tmp/fit.calls /tmp/focus.log; fail "no fit to 800x600 for a window bigger than the screen"; }
echo "ok   a window bigger than the screen was fitted (mdeck-fit 800 600)"
xdotool windowsize "$game" 200 100
sleep 3
tail -1 /tmp/fit.calls | grep -q "^reset$" || { cat /tmp/fit.calls /tmp/focus.log; fail "the fit was not undone when the window shrank"; }
echo "ok   the fit was undone"
# with mdeck-scale installed the screen is never resized: the daemon names the window in MDECK_SCALE_WINDOW and starts the scaler
# (a stand-in here, Xvfb has no texture-from-pixmap), also for a window smaller than the screen, and takes the name away again
pkill -x mdeck-focus || true
sleep 1
cat > /tmp/fake-scaler <<'EOF2'
#!/bin/sh
echo started >> /tmp/scaler.calls
sleep 30
EOF2
chmod +x /tmp/fake-scaler; rm -f /tmp/scaler.calls /tmp/fit.calls
MDECK_SCALE_CMD=/tmp/fake-scaler /tmp/mdeck-focus >/tmp/focus2.log 2>&1 &
sleep 2
xdotool windowsize "$game" 424 240
sleep 3
xprop -root MDECK_SCALE_WINDOW | grep -q "$(printf '%d' "$game")" || { cat /tmp/focus2.log; xprop -root MDECK_SCALE_WINDOW; fail "the scaler window was not named for a 424x240 window"; }
[ "$(cat /tmp/scaler.calls 2>/dev/null | wc -l)" = 1 ] || fail "the scaler was not started exactly once"
[ ! -s /tmp/fit.calls ] || fail "the screen was resized although the scaler is in use"
echo "ok   a window smaller than the screen is named for the scaler (no screen change)"
xdotool windowsize "$game" 640 480
sleep 3
xprop -root MDECK_SCALE_WINDOW | grep -q "not found" || fail "the scaler window was not cleared for a window the size of the screen"
echo "ok   the scaler window is cleared for a window the size of the screen"
echo "focus daemon test passed"
