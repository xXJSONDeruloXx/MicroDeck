import os
import stat
import subprocess
import tempfile
import unittest

import helpers

SCRIPT = helpers.script("usr", "local", "bin", "steamos-session-select")


class SessionSelectTest(unittest.TestCase):
    """steamos-session-select records which session the next start runs and ends the current one (Steam, or the desktop)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = os.path.join(self.tmp.name, "home")
        self.bin = os.path.join(self.tmp.name, "bin")
        self.log = os.path.join(self.tmp.name, "calls")
        steam_dir = os.path.join(self.home, ".local", "share", "Steam", "steamrtarm64")
        os.makedirs(steam_dir)
        os.makedirs(self.bin)
        self.stub(os.path.join(steam_dir, "steam"), 'echo "steam $*" >> "$CALLS"')
        self.stub(os.path.join(self.bin, "logger"), "true")
        self.stub(os.path.join(self.bin, "pkill"), 'echo "pkill $*" >> "$CALLS"')

    def stub(self, path, body):
        with open(path, "w", newline="\n") as f:
            f.write("#!/bin/sh\n%s\n" % body)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def run_select(self, *args, desktop_running=False):
        self.stub(os.path.join(self.bin, "pgrep"), "exit %d" % (0 if desktop_running else 1))
        env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"], CALLS=self.log)
        subprocess.run(["bash", SCRIPT, *args], env=env, check=True)
        with open(os.path.join(self.home, ".config", "mdeck", "session")) as f:
            session = f.read().strip()
        calls = []
        if os.path.exists(self.log):
            with open(self.log) as f:
                calls = f.read().splitlines()
        return session, calls

    def test_desktop_and_plasma_choose_the_desktop_and_shut_steam_down(self):
        for name in ("desktop", "plasma"):
            session, calls = self.run_select(name)
            self.assertEqual(session, "desktop")
            self.assertEqual(calls[-1], "steam -shutdown")

    def test_gamescope_from_the_desktop_ends_the_desktop(self):
        session, calls = self.run_select("gamescope", desktop_running=True)
        self.assertEqual(session, "gaming")
        self.assertEqual(calls, ["pkill -x mdeck-desktop"])

    def test_no_argument_means_gaming(self):
        session, calls = self.run_select()
        self.assertEqual(session, "gaming")
        self.assertEqual(calls, ["steam -shutdown"])


if __name__ == "__main__":
    unittest.main()
