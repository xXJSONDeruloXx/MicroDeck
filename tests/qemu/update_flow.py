"""Integration test on the QEMU virtual device: staged update install, automatic rollback of a release that does not boot, and the
recovery.txt trigger, all through the real initramfs (debug/initramfs/init) and the real image.

  tools/vm.sh test            (resets the disk, injects the current overlay and initramfs, boots, runs this)
  python tests/qemu/update_flow.py    against a VM that is already running

Each reboot runs the whole boot again under emulation, so the run takes a while.
"""
import sys

from session import VM

STAGE = r"""
set -e
sync   # a copy of a live filesystem must not catch files whose data is still in the page cache
U=/home/.sxx/update; rm -rf $U/root.img $U/boot $U/pending; mkdir -p $U/boot
dd if=/dev/vda2 of=$U/root.img bs=1M conv=sparse status=none
mkdir -p /mnt/r && mount -o loop $U/root.img /mnt/r
echo {tag} > /mnt/r/etc/sxx-release
echo {tag} > /mnt/r/etc/qemu-marker
{mutation}
umount /mnt/r
cp -a /boot/firmware/. $U/boot/ && rm -f $U/boot/bootlog-* $U/boot/wifi.txt $U/boot/authorized_keys $U/boot/recovery.txt*
echo {tag} > $U/pending; sync
"""
BREAK = "mv /mnt/r/lib/systemd/systemd /mnt/r/lib/systemd/systemd.x"


class Failed(Exception):
    pass


def check(vm, command, expect, what):
    rc, out = vm.sh(command)
    ok = rc == 0 and expect in out
    print("%s %s: %s" % ("ok  " if ok else "FAIL", what, out.replace("\n", " | ")[:120]))
    if not ok:
        raise Failed(what)


def stage(vm, tag, mutation=""):
    rc, out = vm.sh(STAGE.format(tag=tag, mutation=mutation), timeout=1200)
    if rc != 0:
        raise Failed("staging %s: %s" % (tag, out))


def install_release(vm, tag, mutation=""):
    stage(vm, tag, mutation)
    vm.reboot(timeout=2400)


def scenario_install(vm):
    print("== 1. a staged update installs, and is on trial until marked good")
    install_release(vm, "vA")
    check(vm, "cat /etc/qemu-marker /etc/sxx-release", "vA", "root replaced by vA")
    check(vm, "ls /home/.sxx/update", "trial", "vA is on trial")
    check(vm, "cat /home/.sxx/update/installed/tag", "vA", "vA recorded as installed")
    vm.sh("/usr/local/sbin/sxx-update good")
    check(vm, "test -e /home/.sxx/update/trial && echo still || echo cleared", "cleared", "trial cleared once marked good")


def scenario_rollback(vm):
    print("== 2. a release that does not boot rolls back after three tries")
    install_release(vm, "vB", BREAK)
    check(vm, "cat /etc/qemu-marker", "vA", "back on vA")
    check(vm, "cat /home/.sxx/update/bad", "vB", "vB recorded as bad")
    vm.sh("/usr/local/sbin/sxx-update good")


def scenario_recovery(vm):
    print("== 3. recovery.txt asks for the previous release")
    install_release(vm, "vC")
    vm.sh("/usr/local/sbin/sxx-update good")
    check(vm, "cat /etc/qemu-marker", "vC", "on vC")
    check(vm, "ls /home/.sxx/update/previous", "tag", "vA is kept as the previous release")
    vm.sh("echo sxx=previous > /boot/firmware/recovery.txt; sync")
    vm.reboot()
    check(vm, "cat /etc/qemu-marker", "vA", "recovery.txt took it back to vA")
    check(vm, "ls /boot/firmware", "recovery.txt.used", "recovery.txt was consumed")


def main():
    vm = VM()
    vm.wait_up(timeout=900)
    check(vm, "findmnt -no SOURCE /home", "/dev/vda3", "firstboot made the data partition")
    wanted = sys.argv[1:] or ["1", "2", "3"]
    if "1" in wanted:
        scenario_install(vm)
    elif wanted != ["1"]:
        install_release(vm, "vA")   # the later scenarios need vA installed (and so kept as the previous release)
        vm.sh("/usr/local/sbin/sxx-update good")
    if "2" in wanted:
        scenario_rollback(vm)
    if "3" in wanted:
        scenario_recovery(vm)
    print("all update-flow checks passed")


if __name__ == "__main__":
    try:
        main()
    except Failed as e:
        print("FAILED:", e)
        print(VM.serial_tail(40))
        sys.exit(1)
