import unittest

import helpers


class UiResumeTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("mdeck_cli", "usr", "local", "bin", "mdeck")
        self.mod.time.sleep = lambda s: None
        self.calls = []

    def stub(self, replies):
        it = iter(replies)

        def fake(expression, want="SharedJSContext", timeout=20):
            self.calls.append((want, expression))
            reply = next(it)
            if isinstance(reply, Exception):
                raise reply
            return reply
        self.mod.cdp_eval = fake

    def test_asks_the_ui_that_has_the_store_to_resume(self):
        self.stub(["resumed"])
        self.assertEqual(self.mod.ui_resume(), "resumed")
        self.assertEqual(self.calls[0][0], "SharedJSContext")
        self.assertIn("InitiateResume", self.calls[0][1])
        self.assertIn("m_bSuspending", self.calls[0][1])   # only when Steam started the sleep

    def test_waits_for_a_ui_that_is_not_answering_yet(self):
        self.stub([SystemExit("no target"), OSError("refused"), "idle"])
        self.assertEqual(self.mod.ui_resume(), "idle")
        self.assertEqual(len(self.calls), 3)

    def test_gives_up_when_the_ui_never_answers(self):
        self.mod.time.time = iter(range(0, 1000, 5)).__next__
        self.stub([OSError("refused")] * 100)
        self.assertIsNone(self.mod.ui_resume(timeout=20))


if __name__ == "__main__":
    unittest.main()
