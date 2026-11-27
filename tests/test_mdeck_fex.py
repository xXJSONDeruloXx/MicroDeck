import gzip
import hashlib
import os
import tempfile
import unittest

import helpers


def write_platform(base, files):
    """A platform folder as Valve ships it: hash-named blobs under files/ and a manifest."""
    root = os.path.join(base, "files")
    lines = [b"#mtree", b". type=dir"]
    for rel, data in files.items():
        blob = hashlib.sha256(data).hexdigest()
        blob_rel = "%s/%s" % (blob[:2], blob[2:])
        os.makedirs(os.path.join(root, blob[:2]), exist_ok=True)
        with open(os.path.join(root, blob_rel), "wb") as f:
            f.write(data)
        parent = os.path.dirname(rel)
        if parent:
            lines.append(("./%s type=dir" % parent).encode())
        lines.append(("./%s type=file size=%d contents=%s" % (rel, len(data), blob_rel)).encode())
    lines.append(b"./lib/libalias.so.1 type=link link=libreal.so.1")
    with gzip.open(os.path.join(base, "usr-mtree.txt.gz"), "wb") as f:
        f.write(b"\n".join(lines) + b"\n")


class MdeckFexTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("mdeck_fex", "usr", "local", "bin", "mdeck-fex")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        t = self.tmp.name
        self.mod.HOME = t
        self.mod.STEAM = os.path.join(t, "Steam")
        self.mod.COMMON = os.path.join(self.mod.STEAM, "steamapps", "common")
        self.mod.STATE = os.path.join(t, "state")
        self.mod.RUNTIMES = ((os.path.join(self.mod.COMMON, "SteamLinuxRuntime_4"), "steamrt4_platform_"),
                             (os.path.join(self.mod.COMMON, "SteamLinuxRuntime_soldier"), "soldier_platform_"))

    def make_platform(self, tool, prefix, version, files):
        base = os.path.join(self.mod.COMMON, tool, prefix + version)
        os.makedirs(base)
        write_platform(base, files)
        return base

    def test_materialize_lays_out_files_and_links(self):
        base = self.make_platform("SteamLinuxRuntime_4", "steamrt4_platform_", "1", {
            "lib/x86_64-linux-gnu/libc.so.6": b"libc", "bin/sh": b"sh", "lib/libreal.so.1": b"real"})
        self.mod.materialize(base)
        root = os.path.join(base, "files")
        self.assertEqual(open(os.path.join(root, "bin", "sh"), "rb").read(), b"sh")
        self.assertEqual(open(os.path.join(root, "lib", "libalias.so.1"), "rb").read(), b"real")
        self.assertTrue(os.path.islink(os.path.join(root, "usr")))
        self.mod.materialize(base)  # idempotent

    def test_platform_preference_and_missing(self):
        self.assertIsNone(self.mod.platform_dir())
        old = self.make_platform("SteamLinuxRuntime_soldier", "soldier_platform_", "2.0.1", {"bin/sh": b"sh"})
        self.assertEqual(self.mod.platform_dir(), old)
        new = self.make_platform("SteamLinuxRuntime_4", "steamrt4_platform_", "4.0.1", {"bin/sh": b"sh"})
        self.assertEqual(self.mod.platform_dir(), new)

    def test_legacy_libraries_only_fill_gaps(self):
        base = self.make_platform("SteamLinuxRuntime_4", "steamrt4_platform_", "1", {"lib/i386-linux-gnu/libz.so.1": b"z"})
        self.mod.materialize(base)
        scout = os.path.join(self.mod.COMMON, "SteamLinuxRuntime", "steam-runtime")
        self.mod.SCOUT = scout
        folder = os.path.join(scout, "i386", "usr", "lib", "i386-linux-gnu")
        os.makedirs(folder)
        for name in ("libz.so.1", "libvorbisfile.so.3", "notes.txt"):
            open(os.path.join(folder, name), "wb").write(b"x")
        paths = self.mod.legacy_libraries(os.path.join(base, "files"))
        names = sorted(os.listdir(paths[0]))
        self.assertIn("libvorbisfile.so.3", names)
        self.assertNotIn("libz.so.1", names)
        self.assertNotIn("notes.txt", names)

    def test_guest_environment_drops_host_arm_libraries(self):
        fex = {"rootfs": "/r", "host_thunks": "/h", "guest_thunks": "/g", "platform": "/p"}
        base = self.make_platform("SteamLinuxRuntime_4", "steamrt4_platform_", "1", {"bin/sh": b"sh"})
        fex["rootfs"] = os.path.join(base, "files")
        env = self.mod.guest_environment(fex, {
            "LD_PRELOAD": "/home/s/.steam/bin32/gameoverlayrenderer.so:/usr/local/lib/lse/liblse_emu.so",
            "LD_LIBRARY_PATH": "/home/s/Steam/steamrtarm64:/opt/x86", "PATH": "/usr/bin"})
        self.assertNotIn("LD_PRELOAD", env)
        self.assertTrue(env["LD_LIBRARY_PATH"].startswith("/opt/x86"))
        self.assertNotIn("steamrtarm64", env["LD_LIBRARY_PATH"])
        self.assertEqual(env["FEX_ROOTFS"], fex["rootfs"])
        self.assertEqual(env["FEX_PORTABLE"], "1")


if __name__ == "__main__":
    unittest.main()
