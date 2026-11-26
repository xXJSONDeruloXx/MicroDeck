"""Integration test on the QEMU virtual device: staged update install, automatic rollback of a release that does not boot, and the
recovery.txt trigger, all through the real initramfs (debug/initramfs/init) and the real image.

  tools/qemu/build-kernel.sh && tools/qemu/prepare.sh <image.img.xz> && tools/qemu/run.sh &   (or run.sh in another terminal)
  python tests/qemu/update_flow.py

Each reboot runs the whole boot again under emulation, so the run takes a while.
"""
import sys

from session import Console

STAGE = r"""
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


def check(c, command, expect, what):
    rc, out = c.run(command)
    ok = expect in out
    print("%s %s: %s" % ("ok  " if ok else "FAIL", what, out.replace("\n", " | ")[:120]))
    if not ok:
        raise SystemExit(1)


def stage(c, tag, mutation=""):
    rc, out = c.run(STAGE.format(tag=tag, mutation=mutation), timeout=900)
    if rc != 0:
        print("staging %s failed: %s" % (tag, out))
        raise SystemExit(1)


def reboot_and_wait(c, wait=1800):
    c.send("sync; reboot -f\n")
    c.login(timeout=wait)


def main():
    c = Console()
    c.connect()
    print("== waiting for the first boot (data partition)")
    c.login(timeout=900)
    check(c, "findmnt -no SOURCE /home; ls /var/lib/firstboot.done", "/dev/vda3", "firstboot made the data partition")

    print("== 1. a staged update installs, and is on trial until marked good")
    stage(c, "vA", "")
    reboot_and_wait(c)
    check(c, "cat /etc/qemu-marker /etc/sxx-release", "vA", "root replaced by vA")
    check(c, "cat /home/.sxx/update/installed/tag; ls /home/.sxx/update", "trial", "vA is on trial")
    c.run("/usr/local/sbin/sxx-update good")
    check(c, "ls /home/.sxx/update", "installed", "vA kept for rollback")
    rc, out = c.run("test -e /home/.sxx/update/trial && echo still-on-trial || echo trial-cleared")
    assert "trial-cleared" in out, out

    print("== 2. a release that does not boot rolls back after three tries")
    stage(c, "vB", BREAK)
    reboot_and_wait(c)
    check(c, "cat /etc/qemu-marker; cat /home/.sxx/update/bad; cat /home/.sxx/update/installed/tag", "vA", "back on vA")
    check(c, "cat /home/.sxx/update/bad", "vB", "vB recorded as bad")
    c.run("/usr/local/sbin/sxx-update good")

    print("== 3. recovery.txt asks for the previous release")
    stage(c, "vC", "")
    reboot_and_wait(c)
    c.run("/usr/local/sbin/sxx-update good")
    check(c, "cat /etc/qemu-marker", "vC", "on vC")
    c.run("echo sxx=previous > /boot/firmware/recovery.txt; sync")
    reboot_and_wait(c)
    check(c, "cat /etc/qemu-marker; ls /boot/firmware", "vA", "recovery.txt took it back to vA")
    check(c, "ls /boot/firmware", "recovery.txt.used", "recovery.txt was consumed")
    print("all update-flow checks passed")


if __name__ == "__main__":
    sys.exit(main())
