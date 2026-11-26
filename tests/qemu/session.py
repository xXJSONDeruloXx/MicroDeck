"""Drive the QEMU virtual device (tools/qemu/run.sh) over its serial console socket."""
import random
import re
import socket
import time


class Console:
    def __init__(self, host="127.0.0.1", port=5555):
        self.addr = (host, port)
        self.sock = None
        self.buf = ""
        self.log = []
        self.before = ""

    def connect(self, timeout=60):
        end = time.time() + timeout
        while time.time() < end:
            try:
                self.sock = socket.create_connection(self.addr, timeout=2)
                self.sock.settimeout(1)
                return
            except OSError:
                time.sleep(1)
        raise TimeoutError("no serial socket on %s:%d" % self.addr)

    def _read(self):
        try:
            data = self.sock.recv(65536)
        except socket.timeout:
            return False
        except OSError:
            return None
        if not data:
            return None
        text = data.decode("utf-8", "replace")
        self.log.append(text)
        self.buf += text
        return True

    def expect(self, pattern, timeout=300):
        """Wait for a regex in the console output; returns the match and drops everything up to it."""
        end = time.time() + timeout
        rx = re.compile(pattern)
        while time.time() < end:
            m = rx.search(self.buf)
            if m:
                self.before = self.buf[:m.start()]
                self.buf = self.buf[m.end():]
                return m
            r = self._read()
            if r is None:
                time.sleep(0.5)
                self.reconnect()
        raise TimeoutError("timed out waiting for %r; last output: %r" % (pattern, self.buf[-400:]))

    def reconnect(self):
        try:
            self.sock.close()
        except OSError:
            pass
        self.connect(timeout=30)

    def send(self, text):
        self.sock.sendall(text.encode())

    def login(self, timeout=600):
        self.expect(r"login: ", timeout)
        self.send("root\n")
        self.expect(r"[#$] ", 60)

    def run(self, command, timeout=300):
        """Run a shell command; returns (exit status, output)."""
        tag = "__END%d__" % random.randrange(10 ** 9)
        self.buf = ""
        self.send("%s; echo %s$?%s\n" % (command, tag, tag))
        m = self.expect(re.escape(tag) + r"(\d+)" + re.escape(tag), timeout)
        return int(m.group(1)), self.before.split("\n", 1)[-1].strip()
