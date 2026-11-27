#!/bin/bash
# One-shot health check of the running device, no hands needed. Prints PASS/FAIL per area and saves a
# screenshot to out/smoke.png. Exit status is the number of failures.
#   tools/smoke.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() {  # check NAME COMMAND-ON-DEVICE [EXPECTED-REGEX]
  local name=$1 cmd=$2 want=${3:-.}
  local out; out=$(tools/dev.sh sh "$cmd" 2>&1 | tr -d '\r')
  if echo "$out" | grep -qE "$want"; then echo "PASS $name: $(echo "$out" | tail -1 | cut -c1-90)"
  else echo "FAIL $name: $(echo "$out" | tail -3 | tr '\n' ' ' | cut -c1-160)"; fails=$((fails + 1)); fi
}
Q_ROUTE='document.location.pathname'
Q_FOCUS='(()=>{const e=document.activeElement;return (e&&(e.innerText||e.getAttribute("aria-label")||"")||"").toString().slice(0,60).replace(/\n/g," ")})()'

check reachability   'echo up $(uptime -p)' 'up'
check services       'systemctl is-active usb-gadget ssh NetworkManager steam-session reach-guard earlyoom handheld-keys | sort | uniq -c' '^ *7 active$'
check failed-units   'systemctl --failed --no-legend | wc -l' '^0$'
check display        'cat /sys/class/drm/card1-DSI-1/status' 'connected'
check gpu            'runuser -u steam -- env DISPLAY=:0 XAUTHORITY=/home/steam/.Xauthority glxinfo -B | grep "OpenGL renderer"' 'Panfrost'
check network        'nmcli -t -f DEVICE,STATE dev | grep -E "^(wlan0|usb0):"' ':connected'
check audio-sink     'runuser -u steam -- env XDG_RUNTIME_DIR=/run/user/1000 wpctl status | grep -A3 Sinks: | grep -c Built-in' '^1$'
check battery        'upower -i /org/freedesktop/UPower/devices/battery_battery | grep percentage' '%'
check gamepad        'grep -c "H700 Gamepad" /proc/bus/input/devices' '[1-9]'
check pad-not-in-x   'udevadm info /dev/input/by-path/*joypad*event* 2>/dev/null | grep -c LIBINPUT_IGNORE_DEVICE=1 || udevadm info -q property -n $(grep -l "H700 Gamepad" /sys/class/input/event*/device/name | sed "s|/sys/class/input/||;s|/device/name||;s|^|/dev/input/|") | grep -c LIBINPUT_IGNORE_DEVICE=1' '^1$'
check steam-ui       "mdeck eval '$Q_ROUTE'" '^/routes/'
check gamescope-mode "mdeck eval 'String(!SteamUIStore.WindowStore.GamepadUIMainWindowInstance.BUseSeparateOverlayWindows())'" '^true$'
check focus-daemon   'pgrep -x mdeck-focus >/dev/null && runuser -u steam -- env DISPLAY=:0 XAUTHORITY=/home/steam/.Xauthority xprop -root GAMESCOPE_FOCUSABLE_APPS' '769'
check memory-guards  'systemctl is-active earlyoom reach-guard | sort -u; cat /sys/kernel/mm/lru_gen/min_ttl_ms' '^1000$'
tools/dev.sh sh 'systemctl start mdeck-vpad; sleep 2' >/dev/null 2>&1   # dev-mode only service; releases leave it off
before=$(tools/dev.sh sh "mdeck eval -t 'Steam Big Picture Mode' '$Q_FOCUS'" 2>&1)
tools/dev.sh sh 'mdeck pad down wait:600' >/dev/null 2>&1
after=$(tools/dev.sh sh "mdeck eval -t 'Steam Big Picture Mode' '$Q_FOCUS'" 2>&1)
tools/dev.sh sh 'mdeck pad up wait:300' >/dev/null 2>&1
if [ -n "$after" ] && [ "$before" != "$after" ]; then echo "PASS pad-navigation: focus moved"
else echo "FAIL pad-navigation: focus did not move ($before)"; fails=$((fails + 1)); fi
check memory         'free -m | awk "/Mem:/ {print \"available \" \$7 \" MB\"}"' 'available'
tools/dev.sh shot out/smoke.png >/dev/null 2>&1 && echo "screenshot: out/smoke.png"
echo "failures: $fails"
exit $fails
