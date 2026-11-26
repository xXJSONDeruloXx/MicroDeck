"""Boot smoke test on the QEMU virtual device: the image boots, firstboot made the data partition, and the services that do not need
the handheld's hardware are up. Units that need the handheld's hardware fail in the VM and are expected to.

  tools/vm.sh start; python tests/qemu/boot_smoke.py
"""
import sys

from session import VM

EXPECTED_FAILURES = {"inputplumber.service", "steam-session.service", "handheld-keys.service", "usb-gadget.service",
                     "wifi-kick.service", "sxx-wifi-import.service", "bluetooth.service", "reach-guard.service",
                     "systemd-modules-load.service", "sxx-mark-good.service", "sxx-zram-recompress.service",
                     "systemd-zram-setup@zram0.service", "earlyoom.service"}


def main():
    vm = VM()
    vm.wait_up(timeout=900)
    failures = []

    def check(name, command, expect):
        rc, out = vm.sh(command)
        ok = rc == 0 and expect in out
        print("%s %s: %s" % ("ok  " if ok else "FAIL", name, out.replace("\n", " | ")[:110]))
        if not ok:
            failures.append(name)

    check("data partition", "findmnt -no SOURCE /home", "/dev/vda3")
    check("firstboot done", "ls /var/lib/firstboot.done", "firstboot.done")
    check("release stamp", "cat /etc/sxx-release", "")
    check("updater runs", "/usr/local/sbin/sxx-update status", "version:")
    check("ssh host keys kept", "ls /home/.sxx/ssh-host-keys | head -1", "ssh_host")
    check("overcommit sysctl", "sysctl -n vm.overcommit_memory", "1")
    rc, out = vm.sh("systemctl --failed --no-legend --plain | awk '{print $1}'")
    unexpected = sorted(set(out.split()) - EXPECTED_FAILURES)
    print("%s failed units: %s" % ("ok  " if not unexpected else "FAIL", ", ".join(unexpected) or "only the hardware ones"))
    if unexpected:
        failures.append("units")
    if failures:
        print("FAILED:", ", ".join(failures))
        print(vm.serial_tail())
        return 1
    print("boot smoke test passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
