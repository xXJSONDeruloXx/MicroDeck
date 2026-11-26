"""Reflashing keeps the data partition: write a marker to /home, power off, overwrite the boot and root partitions with the
image again (everything before the data partition, as a flash does, including the partition table), boot, and check that
firstboot reused the partition and the marker survived.

  tools/vm.sh test reflash
"""
import os
import subprocess
import sys
import time

from session import ROOT, VM

DISK = os.path.join(ROOT, "out", "qemu", "disk.img")
BASE = os.path.join(ROOT, "out", "qemu", "disk.base.img")
FLASHED = (16 + 256 + 3072) * 1024 * 1024  # U-Boot area, boot partition, root: what an image write covers


def vm_script(*args):
    return subprocess.run(["bash", "tools/vm.sh", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def main():
    vm = VM()
    vm.wait_up(timeout=900)
    rc, out = vm.sh("findmnt -no SOURCE /home && echo keep-me-across-flashes > /home/marker && sync")
    assert rc == 0 and "/dev/vda3" in out, out
    print("ok   data partition has a marker")
    vm.sh("(sleep 1; poweroff -f) >/dev/null 2>&1 &", timeout=20)
    time.sleep(15)
    vm_script("stop")
    with open(BASE, "rb") as src, open(DISK, "r+b") as dst:
        remaining = FLASHED
        while remaining:
            chunk = src.read(min(8 * 1024 * 1024, remaining))
            dst.write(chunk)
            remaining -= len(chunk)
    print("ok   boot and root partitions rewritten from the image (data partition untouched)")
    print(vm_script("start"))
    vm.wait_up(timeout=900)
    rc, out = vm.sh("findmnt -no SOURCE /home; cat /home/marker; journalctl -u firstboot --no-pager | grep -E 'reusing|created' | cut -c1-100")
    ok = rc == 0 and "keep-me-across-flashes" in out and "reusing" in out
    print("%s data partition reused: %s" % ("ok  " if ok else "FAIL", out.replace("\n", " | ")))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
