"""Boot smoke test on the QEMU virtual device: the image reaches a login, firstboot made the data partition, and the services that
do not need the handheld's hardware are up. Prints failed units (the hardware ones fail in the VM and are expected).

  tools/vm.sh start; python tests/qemu/boot_smoke.py
"""
import sys

from session import Console

# units that need the handheld's hardware or a real display and so fail in the VM
EXPECTED_FAILURES = {"inputplumber.service", "steam-session.service", "handheld-keys.service", "usb-gadget.service",
                     "wifi-kick.service", "sxx-wifi-import.service", "bluetooth.service", "reach-guard.service",
                     "systemd-modules-load.service", "sxx-mark-good.service"}


def main():
    c = Console()
    c.connect()
    c.login(timeout=900)
    failures = []

    def check(name, command, expect):
        rc, out = c.run(command)
        ok = expect in out
        print("%s %s: %s" % ("ok  " if ok else "FAIL", name, out.replace("\n", " | ")[:110]))
        if not ok:
            failures.append(name)

    check("data partition", "findmnt -no SOURCE /home", "/dev/vda3")
    check("firstboot done", "ls /var/lib/firstboot.done", "firstboot.done")
    check("release stamp", "cat /etc/sxx-release", "")
    check("updater runs", "/usr/local/sbin/sxx-update status", "version:")
    check("ssh host keys kept", "ls /home/.sxx/ssh-host-keys | head -1", "ssh_host")
    check("overcommit sysctl", "sysctl -n vm.overcommit_memory", "1")
    check("zram swap", "swapon --show=NAME --noheadings", "zram")
    rc, out = c.run("systemctl --failed --no-legend --plain | awk '{print $1}'")
    unexpected = sorted(set(out.split()) - EXPECTED_FAILURES)
    print("%s failed units: %s" % ("ok  " if not unexpected else "FAIL", ", ".join(unexpected) or "only the hardware ones"))
    if unexpected:
        failures.append("units")
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("boot smoke test passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
