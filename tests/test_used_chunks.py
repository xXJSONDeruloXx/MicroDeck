import unittest

import helpers

DUMP = """Block size:               4096
Block count:              1024
First block:              0
Group 0: (Blocks 0-511)
  Primary superblock at 0
  Free blocks: 100-511
Group 1: (Blocks 512-1023)
  Backup superblock at 512
  Free blocks: 520-700, 800-1023
"""


class UsedChunksTest(unittest.TestCase):
    def setUp(self):
        self.mod = helpers.load("used_chunks", "usr", "local", "sbin", "mdeck-used-chunks")

    def test_parse_merges_free_ranges(self):
        bs, total, free = self.mod.parse(DUMP)
        self.assertEqual((bs, total), (4096, 1024))
        self.assertEqual(free, [(100, 511), (520, 700), (800, 1023)])

    def test_a_full_group_prints_an_empty_free_blocks_line(self):
        text = DUMP + "Group 2: (Blocks 1024-1535)\n  Free blocks: \n  Free inodes: 10-20\n"
        bs, total, free = self.mod.parse(text)
        self.assertEqual(free, [(100, 511), (520, 700), (800, 1023)])

    def test_chunks_cover_every_used_block(self):
        bs, total, free = self.mod.parse(DUMP)
        runs = self.mod.chunks(bs, total, free, total * bs)  # 4 MiB image, 256 blocks per MiB
        needed = {c for start, count in runs for c in range(start, start + count)}
        used = [b for b in range(total) if not any(a <= b <= z for a, z in free)]
        for block in used:
            self.assertIn(block // 256, needed)
        self.assertEqual(sorted(needed), [0, 2, 3])   # chunk 1 (blocks 256-511) is entirely free

    def test_fully_free_chunks_are_skipped(self):
        text = DUMP.replace("Free blocks: 100-511", "Free blocks: 256-511")
        bs, total, free = self.mod.parse(text)
        runs = self.mod.chunks(bs, total, free, total * bs)
        needed = {c for start, count in runs for c in range(start, start + count)}
        self.assertNotIn(1, needed)

    def test_runs_are_merged(self):
        runs = self.mod.chunks(4096, 2048, [], 2048 * 4096)
        self.assertEqual(runs, [(0, 8)])


if __name__ == "__main__":
    unittest.main()
