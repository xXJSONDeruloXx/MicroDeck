import os
import tempfile
import unittest

import helpers


class BatteryTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("battery", "usr", "local", "sbin", "mdeck-battery")

    def test_decisions(self):
        d = self.mod.decide
        self.assertEqual(d("Discharging", 80, False), None)
        self.assertEqual(d("Discharging", 15, False), "cap")
        self.assertEqual(d("Discharging", 12, True), None)          # already capped
        self.assertEqual(d("Discharging", 5, True), "poweroff")
        self.assertEqual(d("Discharging", 3, False), "poweroff")
        self.assertEqual(d("Charging", 3, False), None)             # on the charger: never shut down
        self.assertEqual(d("Full", 100, False), None)
        self.assertEqual(d("Charging", 10, True), "uncap")          # plugged in lifts the cap
        self.assertEqual(d("Discharging", 21, True), "uncap")       # recovered well above the threshold
        self.assertEqual(d("Discharging", 18, True), None)          # no flapping near the threshold
        self.assertEqual(d(None, 50, False), None)

    def test_cap_and_restore(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ("policy0", "policy4"):
                os.makedirs(os.path.join(d, n))
                with open(os.path.join(d, n, "cpuinfo_max_freq"), "w") as f:
                    f.write("1416000")
                with open(os.path.join(d, n, "scaling_max_freq"), "w") as f:
                    f.write("1416000")
            self.mod.CPUFREQ = d
            self.mod.set_cap(1008000)
            self.assertEqual(open(os.path.join(d, "policy0", "scaling_max_freq")).read(), "1008000")
            self.mod.set_cap(None)
            self.assertEqual(open(os.path.join(d, "policy4", "scaling_max_freq")).read(), "1416000")


if __name__ == "__main__":
    unittest.main()
