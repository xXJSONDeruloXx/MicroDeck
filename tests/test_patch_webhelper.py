import os
import subprocess
import sys
import tempfile
import unittest

import helpers

SCRIPT = helpers.script("usr", "local", "bin", "patch-webhelper.py")
LEGACY = "sx" + "x"


class PatchWebhelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = self.tmp.name
        self.helper = os.path.join(self.home, "steamwebhelper.sh")
        self.stock_text = b'#!/bin/bash\n\nSCRIPTPATH="$(dirname -- "${BASH_SOURCE[0]}")"\ncd $SCRIPTPATH\ntaskset 0x7c ./steamwebhelper "$@"\n' + b"#" * 200 + b"\n"
        with open(self.helper, "wb") as f:
            f.write(self.stock_text)

    def run_script(self, *args):
        env = dict(os.environ, HOME=self.home)
        return subprocess.run([sys.executable, SCRIPT, *args, self.helper], env=env, capture_output=True, text=True)

    def read(self):
        with open(self.helper, "rb") as f:
            return f.read()

    def test_patch_keeps_the_size_and_restore_brings_the_original_back(self):
        self.run_script()
        patched = self.read()
        self.assertIn(b"--disable-hang-monitor", patched)
        self.assertEqual(len(patched), len(self.stock_text))
        self.run_script("--restore")
        self.assertEqual(self.read(), self.stock_text)

    def test_restore_finds_the_original_a_card_from_before_the_rename_saved(self):
        # an old install patched the wrapper and saved the original under the old state directory
        legacy_dir = os.path.join(self.home, ".cache", LEGACY)
        os.makedirs(legacy_dir)
        with open(os.path.join(legacy_dir, "steamwebhelper.sh.stock"), "wb") as f:
            f.write(self.stock_text)
        with open(self.helper, "wb") as f:
            f.write(b'#!/bin/bash\nexec ./steamwebhelper "$@" --disable-hang-monitor\n' + b"#" * 100 + b"\n")
        self.run_script("--restore")
        self.assertEqual(self.read(), self.stock_text)


if __name__ == "__main__":
    unittest.main()
