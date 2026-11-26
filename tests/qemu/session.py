"""Drive the QEMU virtual device (tools/vm.sh): commands over SSH, reboots detected by the kernel's boot id, the serial log for diagnosis."""
import os
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERIAL_LOG = os.path.join(ROOT, "out", "qemu", "serial.log")


class VM:
    def __init__(self):
        self.env = dict(os.environ, DEV_TARGET="vm", DEV_HOST="127.0.0.1", DEV_PORT="2222", MSYS_NO_PATHCONV="1")

    def sh(self, command, timeout=300):
        """Run a command as root in the VM; returns (exit status, output). Status 255 means ssh could not connect."""
        try:
            p = subprocess.run(["bash", "tools/dev.sh", "sh", command], cwd=ROOT, env=self.env, capture_output=True, text=True,
                               timeout=timeout)
        except subprocess.TimeoutExpired:
            return 124, "timed out"
        return p.returncode, (p.stdout + p.stderr).replace("\r", "").strip()

    def boot_id(self):
        rc, out = self.sh("cat /proc/sys/kernel/random/boot_id", timeout=20)
        return out if rc == 0 and len(out) == 36 else None

    def wait_up(self, timeout=900, not_boot_id=None):
        """Wait until ssh answers, and (when given) from a boot other than not_boot_id."""
        end = time.time() + timeout
        while time.time() < end:
            current = self.boot_id()
            if current and current != not_boot_id:
                return current
            time.sleep(5)
        raise TimeoutError("the VM did not come up; serial log tail:\n" + self.serial_tail())

    def reboot(self, timeout=1800):
        """Reboot and wait for the new boot. Failing boots in between (a release that does not start) are waited through."""
        old = self.boot_id()
        self.sh("sync; (sleep 1; reboot -f) >/dev/null 2>&1 &", timeout=20)
        return self.wait_up(timeout, not_boot_id=old)

    @staticmethod
    def serial_tail(n=30):
        try:
            with open(SERIAL_LOG, errors="replace") as f:
                return "".join(f.readlines()[-n:])
        except OSError:
            return "(no serial log)"
