import os
import tempfile
import unittest

import helpers

MAPPING = (
    '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
    '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n'
    '\t\t\t\t\t"8400"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton-armv8-proton-11.0-3"\n'
    '\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n'
    '\t\t\t\t\t"0"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton-armv8-proton-11.0-3"\n'
    '\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"75"\n\t\t\t\t\t}\n'
    '\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n'
)


class CompatDefaultTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("compat_default", "usr", "local", "bin", "sxx-compat-default")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.steam = os.path.join(self.tmp.name, "Steam")
        os.makedirs(os.path.join(self.steam, "config"))
        os.makedirs(os.path.join(self.steam, "steamapps", "common"))
        self.mod.STEAM = self.steam
        self.mod.CONFIG = os.path.join(self.steam, "config", "config.vdf")
        with open(self.mod.CONFIG, "w") as f:
            f.write(MAPPING)

    def install(self, appid, name, files, state=4):
        apps = os.path.join(self.steam, "steamapps")
        with open(os.path.join(apps, "appmanifest_%s.acf" % appid), "w") as f:
            f.write('"AppState"\n{\n\t"appid"\t\t"%s"\n\t"StateFlags"\t\t"%d"\n\t"installdir"\t\t"%s"\n}\n' % (appid, state, name))
        folder = os.path.join(apps, "common", name)
        for rel, data in files.items():
            path = os.path.join(folder, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)

    def test_read_mapping(self):
        self.assertEqual(self.mod.read_mapping(MAPPING), {"8400": "proton-armv8-proton-11.0-3", "0": "proton-armv8-proton-11.0-3"})

    def test_linux_only_detection(self):
        self.install("1", "linuxgame", {"game": helpers.ELF_X86_64, "data/a.txt": b"x"})
        self.install("2", "windowsgame", {"game.exe": b"MZ", "lib/x.so": helpers.ELF_X86_64})
        self.install("3", "armgame", {"game": helpers.ELF_ARM64})
        found = {app: self.mod.is_linux_x86_only(folder) for app, folder in self.mod.installed_apps()}
        self.assertEqual(found, {"1": True, "2": False, "3": False})

    def test_incomplete_installs_and_tools_are_ignored(self):
        self.install("4", "half", {"game": helpers.ELF_X86_64}, state=1026)
        self.install("3127680", "FEX-Emu", {"usr/bin/FEX": helpers.ELF_ARM64})
        self.assertEqual([a for a, _ in self.mod.installed_apps()], [])

    def test_seed_maps_linux_games_once_and_keeps_existing(self):
        self.install("219150", "hotline", {"Hotline": helpers.ELF_I386})
        self.install("8400", "gw", {"gw.exe": b"MZ"})
        self.install("500", "winonly", {"a.exe": b"MZ"})
        self.mod.seed()
        mapping = self.mod.read_mapping(open(self.mod.CONFIG).read())
        self.assertEqual(mapping["219150"], "sxx-fex")
        self.assertEqual(mapping["8400"], "proton-armv8-proton-11.0-3")
        self.assertNotIn("500", mapping)
        first = open(self.mod.CONFIG).read()
        self.mod.seed()
        self.assertEqual(open(self.mod.CONFIG).read(), first)

    def test_seed_does_not_override_a_manual_choice(self):
        self.install("219150", "hotline", {"Hotline": helpers.ELF_I386})
        self.mod.seed()
        text = open(self.mod.CONFIG).read().replace('"sxx-fex"', '"proton-experimental"')
        open(self.mod.CONFIG, "w").write(text)
        self.mod.seed()
        self.assertEqual(self.mod.read_mapping(open(self.mod.CONFIG).read())["219150"], "proton-experimental")


if __name__ == "__main__":
    unittest.main()
