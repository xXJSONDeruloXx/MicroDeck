"""A card from before the rename (data partition labelled sxxdata, state in /home/.sxx) keeps working on the current image:

  1. the installed initramfs finds the old-labelled partition and moves /home/.sxx to /home/.mdeck;
  2. after a reflash (the image rewrites the partition table, so only firstboot can bring the partition back) firstboot accepts
     the old label, reuses the data and moves the state directory.

  tools/vm.sh test legacy
"""
import os
import subprocess
import sys
import time

from session import ROOT, VM

DISK = os.path.join(ROOT, "out", "qemu", "disk.img")
BASE = os.path.join(ROOT, "out", "qemu", "disk.base.img")
FLASHED = (16 + 256 + 3072) * 1024 * 1024


def vm_script(*args):
    return subprocess.run(["bash", "tools/vm.sh", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def check(ok, what, detail=""):
    print("%s %s%s" % ("ok  " if ok else "FAIL", what, (": " + detail.replace("\n", " | ")[-200:]) if detail else ""))
    if not ok:
        print(VM.serial_tail(30))
        sys.exit(1)


def make_legacy(vm):
    """What an installation from before the rename looks like: old label, old state directory, a marker in /home."""
    rc, out = vm.sh("set -e; tune2fs -L sxxdata /dev/vda3 >/dev/null; [ -d /home/.sxx ] || mv /home/.mdeck /home/.sxx; "
                    "echo legacy-card > /home/marker; cat /home/.sxx/ssh-host-keys/ssh_host_ed25519_key.pub; sync")
    check(rc == 0 and "ssh-ed25519" in out, "the card is made to look like one from before the rename", out)
    return out.split()[1]


def main():
    vm = VM()
    vm.wait_up(timeout=900)
    key = make_legacy(vm)

    vm.reboot(timeout=900)
    rc, out = vm.sh("blkid -s LABEL -o value /dev/vda3; ls -d /home/.sxx /home/.mdeck 2>&1; cat /home/marker; "
                    "cat /home/.mdeck/ssh-host-keys/ssh_host_ed25519_key.pub")
    check("/home/.mdeck" in out and "No such file" in out and key in out, "initramfs moved /home/.sxx to /home/.mdeck, keys intact", out)

    # reflash: write the image over the boot and root partitions again with the data partition in the old shape
    make_legacy(vm)
    vm.sh("(sleep 1; poweroff -f) >/dev/null 2>&1 &", timeout=20)
    time.sleep(15)
    vm_script("stop")
    with open(BASE, "rb") as src, open(DISK, "r+b") as dst:
        remaining = FLASHED
        while remaining:
            chunk = src.read(min(8 * 1024 * 1024, remaining))
            dst.write(chunk)
            remaining -= len(chunk)
    vm_script("inject")
    print(vm_script("start"))
    vm.wait_up(timeout=900)
    rc, out = vm.sh("findmnt -no SOURCE /home; blkid -s LABEL -o value /dev/vda3; ls -d /home/.sxx /home/.mdeck 2>&1; cat /home/marker; "
                    "cat /home/.mdeck/ssh-host-keys/ssh_host_ed25519_key.pub; "
                    "journalctl -u firstboot --no-pager | grep -E 'reusing|created' | cut -c1-100")
    check(rc == 0 and "/dev/vda3" in out and "legacy-card" in out and "reusing" in out and key in out and "No such file" in out,
          "reflash over an old card: data reused, state moved to .mdeck, keys intact", out)
    print("legacy data checks passed")


if __name__ == "__main__":
    main()
