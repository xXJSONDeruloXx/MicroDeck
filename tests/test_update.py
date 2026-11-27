import os
import subprocess
import tempfile
import unittest

import helpers

SCRIPT = helpers.script("usr", "local", "sbin", "sxx-update")


def run(current, snippet, state_files=None):
    with tempfile.TemporaryDirectory() as d:
        release = os.path.join(d, "release")
        with open(release, "w") as f:
            f.write(current + "\n")
        for name, text in (state_files or {}).items():
            with open(os.path.join(d, name), "w") as f:
                f.write(text)
        env = dict(os.environ, SXX_UPDATE_SOURCED="1", SXX_RELEASE_FILE=release, SXX_UPDATE_STATE=d)
        return subprocess.run(["bash", "-c", '. "%s"; %s' % (SCRIPT.replace("\\", "/"), snippet)], env=env,
                              capture_output=True, text=True)


class UpdateTest(unittest.TestCase):
    def newer(self, current, tag, state=None):
        return run(current, 'newer "%s"' % tag, state).returncode == 0

    def test_version_comparison(self):
        self.assertTrue(self.newer("v0.4.0", "v0.5.0"))
        self.assertTrue(self.newer("v0.9.0", "v0.10.0"))
        self.assertFalse(self.newer("v0.5.0", "v0.5.0"))
        self.assertFalse(self.newer("v0.5.0", "v0.4.0"))

    def test_dev_builds_are_never_offered_updates(self):
        self.assertFalse(self.newer("dev", "v9.9.9"))

    def test_a_tag_rolled_back_from_is_not_offered_again(self):
        self.assertFalse(self.newer("v0.4.0", "v0.5.0", {"bad": "v0.5.0"}))
        self.assertTrue(self.newer("v0.4.0", "v0.6.0", {"bad": "v0.5.0"}))

    def test_reconcile_drops_images_of_another_release(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "installed"))
            open(os.path.join(d, "installed", "tag"), "w").write("v0.3.0")
            open(os.path.join(d, "trial"), "w").write("1")
            release = os.path.join(d, "release")
            open(release, "w").write("v0.5.0\n")
            env = dict(os.environ, SXX_UPDATE_SOURCED="1", SXX_RELEASE_FILE=release, SXX_UPDATE_STATE=d)
            subprocess.run(["bash", "-c", '. "%s"; reconcile' % SCRIPT.replace("\\", "/")], env=env, check=True)
            self.assertFalse(os.path.exists(os.path.join(d, "installed")))
            self.assertFalse(os.path.exists(os.path.join(d, "trial")))


class SteamosHookTest(unittest.TestCase):
    """Steam calls `steamos-update --enable-duplicate-detection check`: the verb is not the first argument."""

    def call(self, *args):
        with tempfile.TemporaryDirectory() as d:
            release = os.path.join(d, "release")
            with open(release, "w") as f:
                f.write("v0.4.0\n")
            env = dict(os.environ, SXX_RELEASE_FILE=release, SXX_UPDATE_STATE=d, SXX_UPDATE_API="http://127.0.0.1:9/none")
            return subprocess.run(["bash", SCRIPT, "steamos", *args], env=env, capture_output=True, text=True, timeout=60)

    def test_duplicate_detection_probe(self):
        self.assertEqual(self.call("--supports-duplicate-detection").returncode, 0)

    def test_check_with_a_flag_first_is_a_check_not_an_install(self):
        r = self.call("--enable-duplicate-detection", "check")
        self.assertEqual(r.returncode, 7)  # the release server is unreachable: "no update", and nothing was downloaded
        self.assertNotIn("downloading", r.stderr)


if __name__ == "__main__":
    unittest.main()
