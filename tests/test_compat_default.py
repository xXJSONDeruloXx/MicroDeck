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
        self.mod = helpers.load("compat_default", "usr", "local", "bin", "mdeck-compat-default")
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

    def test_seed_moves_the_tool_name_from_before_the_rename_over(self):
        legacy = "sx" + "x-fex"
        entry = '\t\t\t\t\t"777"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' % legacy
        with open(self.mod.CONFIG, "w") as f:
            f.write(MAPPING.replace('\t\t\t\t\t"8400"\n', entry + '\t\t\t\t\t"8400"\n', 1))
        self.mod.seed()
        text = open(self.mod.CONFIG).read()
        self.assertNotIn('"%s"' % legacy, text)
        self.assertEqual(self.mod.read_mapping(text)["777"], "mdeck-fex")

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
        self.assertEqual(mapping["219150"], "mdeck-fex")
        self.assertEqual(mapping["8400"], "proton-armv8-proton-11.0-3")
        self.assertNotIn("500", mapping)
        first = open(self.mod.CONFIG).read()
        self.mod.seed()
        self.assertEqual(open(self.mod.CONFIG).read(), first)

    def test_seed_does_not_override_a_manual_choice(self):
        self.install("219150", "hotline", {"Hotline": helpers.ELF_I386})
        self.mod.seed()
        text = open(self.mod.CONFIG).read().replace('"mdeck-fex"', '"proton-experimental"')
        open(self.mod.CONFIG, "w").write(text)
        self.mod.seed()
        self.assertEqual(self.mod.read_mapping(open(self.mod.CONFIG).read())["219150"], "proton-experimental")


class Direct3D11Test(unittest.TestCase):
    """Games that ask for Direct3D 11 get DXVK in their launch options; the session default (WineD3D) cannot create the device."""

    def setUp(self):
        self.mod = helpers.load("compat_default", "usr", "local", "bin", "mdeck-compat-default")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.mod.STEAM = os.path.join(self.tmp.name, "Steam")

    def game(self, files):
        folder = os.path.join(self.tmp.name, "game")
        for rel, data in files.items():
            path = os.path.join(folder, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
        return folder

    def test_a_program_that_creates_a_d3d11_device_needs_it(self):
        folder = self.game({"Game.exe": b"MZ" + b"\0" * 2000 + b"D3D11CreateDevice" + b"\0" * 100})
        self.assertTrue(self.mod.needs_d3d11(folder))

    def test_a_dll_in_a_subfolder_is_found(self):
        folder = self.game({"Game.exe": b"MZ" + b"\0" * 4000, "Game_Data/UnityPlayer.dll": b"MZ" + b"\0" * 3000 + b"d3d11.dll"})
        self.assertTrue(self.mod.needs_d3d11(folder))

    def test_a_direct3d9_game_does_not(self):
        folder = self.game({"Game.exe": b"MZ" + b"\0" * 2000 + b"Direct3DCreate9" + b"\0" * 100})
        self.assertFalse(self.mod.needs_d3d11(folder))

    def write_config(self, options):
        path = os.path.join(self.mod.STEAM, "userdata", "1", "config")
        os.makedirs(path)
        lines = [
            '"UserLocalConfigStore"', '{', '"Software"', '{', '"Valve"', '{', '"Steam"', '{', '"apps"', '{',
            '"777"', '{', '"cloud"', '{', '"last_sync_state" "synchronized"', '}',
            '"LaunchOptions" "%s"' % options, '}',
            '"888"', '{', '"LaunchOptions" ""', '}',
            '}', '}', '}', '}', '}',
        ]
        with open(os.path.join(path, "localconfig.vdf"), "w") as f:
            f.write(chr(10).join(lines) + chr(10))

    def test_launch_options_the_user_set_are_read_and_empty_ones_are_not(self):
        self.write_config("-novid %command%")
        self.assertEqual(self.mod.launch_options("777"), "-novid %command%")
        self.assertEqual(self.mod.launch_options("888"), "")
        self.assertEqual(self.mod.launch_options("999"), "")


class PressInstallTest(unittest.TestCase):
    """The daemon presses Install on Steam's dialog for a missing tool: a SteamOS note first, then the install dialog."""

    def setUp(self):
        self.mod = helpers.load("compat_default", "usr", "local", "bin", "mdeck-compat-default")
        self.calls = []
        self.mod.time.sleep = lambda s: None

    def stub(self, replies):
        class R:
            def __init__(self, out):
                self.stdout = out
        it = iter(replies)

        def fake(js):
            self.calls.append(js)
            return R(next(it, ""))
        self.mod.mdeck_ui = fake

    def test_two_dialogs_are_confirmed_and_the_tool_name_is_in_the_script(self):
        self.stub(["", "clicked", "", "clicked"])
        self.assertTrue(self.mod.press_install("Steam Linux Runtime 4.0"))
        self.assertIn('"Steam Linux Runtime 4.0"', self.calls[0])
        self.assertEqual(len(self.calls), 4)  # stops after the second click

    def test_no_dialog_means_nothing_was_pressed(self):
        self.stub([])
        self.assertFalse(self.mod.press_install("FEX"))
        self.assertEqual(len(self.calls), 14)


if __name__ == "__main__":
    unittest.main()
