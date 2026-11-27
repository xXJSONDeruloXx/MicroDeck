import time
import unittest

import helpers


class FakeUinput:
    def __init__(self):
        self.events = []

    def send(self, etype, code, value):
        self.events.append((etype, code, value))

    def sync(self):
        pass


class DesktopPadTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("desktop_pad", "usr", "local", "bin", "mdeck-desktop-pad")
        d = object.__new__(self.mod.Desktop)
        d.mouse, d.kbd = FakeUinput(), FakeUinput()
        d.keys_mode = False
        d.dpad_held = {"up": 0.0, "down": 0.0, "left": 0.0, "right": 0.0}
        d.carry = [0.0] * 4
        d.start_down = None
        d.osk = None
        d.scroll_mode = False
        d.pad = type("P", (), {"stick": {}})()
        self.d = d

    def keys(self):
        return [(c, v) for t, c, v in self.d.kbd.events if t == self.mod.EV_KEY]

    def test_stick_has_a_dead_zone_and_keeps_its_sign(self):
        self.assertEqual(self.mod.shaped(0.1), 0.0)
        self.assertLess(self.mod.shaped(-0.9), 0)
        self.assertAlmostEqual(self.mod.shaped(1.0), 1.0)

    def test_a_and_b_click_the_left_and_right_button(self):
        self.d.press("south", 1)
        self.d.press("south", 0)
        self.d.press("east", 1)
        self.assertEqual([(c, v) for _, c, v in self.d.mouse.events if c in (self.mod.BTN_LEFT, self.mod.BTN_RIGHT)],
                         [(self.mod.BTN_LEFT, 1), (self.mod.BTN_LEFT, 0), (self.mod.BTN_RIGHT, 1)])

    def test_start_taps_the_menu_key_and_enters_keys_mode(self):
        self.d.press("start", 1)
        self.d.press("start", 0)
        self.assertEqual(self.keys(), [(self.mod.KEY_MENU, 1), (self.mod.KEY_MENU, 0)])
        self.assertTrue(self.d.keys_mode)

    def test_keys_mode_turns_the_dpad_into_arrows_and_a_into_enter(self):
        self.d.keys_mode = True
        self.d.press("down", 1)
        self.d.press("south", 1)
        self.assertEqual(self.keys()[0], (self.mod.KEY_DOWN, 1))
        self.assertIn((self.mod.KEY_ENTER, 1), self.keys())
        self.assertFalse(self.d.keys_mode)

    def test_dpad_moves_the_pointer_and_speeds_up_while_held(self):
        self.d.press("right", 1)
        self.d.dpad_held["right"] = time.monotonic() - 2.0
        self.d.motion(0.1)
        moved = [v for t, c, v in self.d.mouse.events if t == self.mod.EV_REL and c == self.mod.REL_X]
        self.assertEqual(moved, [int(self.mod.POINTER_MAX * 0.1)])

    def test_l2_makes_the_dpad_scroll(self):
        self.d.press("tl2", 1)
        self.d.press("down", 1)
        self.d.motion(1.0)
        self.assertTrue(any(c == self.mod.REL_WHEEL for t, c, v in self.d.mouse.events if t == self.mod.EV_REL))
        self.assertFalse(any(c == self.mod.REL_Y for t, c, v in self.d.mouse.events if t == self.mod.EV_REL))


if __name__ == "__main__":
    unittest.main()
