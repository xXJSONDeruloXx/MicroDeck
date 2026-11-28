"""Desktop mode on the QEMU virtual device, on a virtual X server (Xvfb, installed for the test): the session script starts openbox and
the panel, Menu opens the openbox menu, the on-screen keyboard draws and answers its navigation words, and the pad daemon refuses to
run without the built-in pad. The VM has no GPU or pad, so this covers the session's own scripts and configs, not the hardware.

  tools/vm.sh start; python tests/qemu/desktop_smoke.py
"""
import sys

from session import VM

STEAM = 'su steam -c "DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/xdg-steam %s"'
failures = []


def main():
    vm = VM()
    vm.wait_up(timeout=900)

    def run(command, timeout=120):
        return vm.sh(command, timeout=timeout)

    def check(name, command, expect):
        rc, out = run(command)
        ok = rc == 0 and expect in out
        print("%s %s: %s" % ("ok  " if ok else "FAIL", name, out.replace("\n", " | ")[:120]))
        if not ok:
            failures.append(name)
        return out

    rc, out = run("export TMPDIR=/tmp; apt-get update -qq >/dev/null 2>&1; apt-get install -y --no-install-recommends xvfb >/dev/null 2>&1; which Xvfb xdotool",
                  timeout=600)
    if rc != 0 or "Xvfb" not in out:
        print("SKIP: could not install Xvfb in the VM (no network?): " + out[-100:])
        return 0
    run("mkdir -p /tmp/xdg-steam && chown steam:steam /tmp/xdg-steam && chmod 700 /tmp/xdg-steam; pkill Xvfb; sleep 1;"
        "su steam -c 'nohup Xvfb :1 -screen 0 640x480x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &'; sleep 3")
    run(STEAM % "nohup /usr/local/bin/mdeck-desktop >/tmp/desk.log 2>&1 &")
    run("sleep 8")
    check("desktop session processes", "ps -eo comm | grep -E '^(openbox|tint2)$' | sort | tr '\n' ' '", "openbox tint2")
    # the panel loads its launcher icons, which takes a while on the virtual device
    for _ in range(12):
        if "Geometry" in run(STEAM % "xdotool search --class tint2 getwindowgeometry %@")[1]:
            break
        run("sleep 3")
    check("panel is a window at the top", STEAM % "xdotool search --class tint2 getwindowgeometry %@", "Geometry: 640x26")
    check("pad daemon needs the built-in pad", "cat /tmp/desk.log", "no built-in pad")
    before = run(STEAM % "xdotool search --onlyvisible --name '' | wc -l")[1]
    run(STEAM % "xdotool mousemove 200 150 key Menu")
    run("sleep 2")
    after = run(STEAM % "xdotool search --onlyvisible --name '' | wc -l")[1]
    ok = before.isdigit() and after.isdigit() and int(after) > int(before)
    print("%s openbox menu opens on the Menu key: %s -> %s visible windows" % ("ok  " if ok else "FAIL", before, after))
    if not ok:
        failures.append("menu")
    run(STEAM % "xdotool key Escape")
    run("rm -f /tmp/oskin; mkfifo /tmp/oskin; chmod 666 /tmp/oskin; su steam -c \"DISPLAY=:1 nohup sh -c 'tail -f /tmp/oskin | /usr/local/bin/mdeck-osk > /tmp/osk.out 2>&1' >/dev/null 2>&1 &\"; sleep 2")
    check("on-screen keyboard is on screen", "ps -eo comm | grep -c '^mdeck-osk$'", "1")
    run("printf 'press\n' > /tmp/oskin; sleep 1")  # the highlighted key starts on the home row: 'a' is key code 30
    check("on-screen keyboard reports the pressed key", "cat /tmp/osk.out", "key 30")
    run("pkill Xvfb; pkill -f 'tail -f /tmp/oskin'")
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("desktop checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
