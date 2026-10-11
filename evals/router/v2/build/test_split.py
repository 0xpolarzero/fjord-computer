"""Splits keep groups whole, keep siblings with their base, and favour thin families in sealed (split.py)."""
import unittest

from v2.build.split import split


def ep(i, group, family="next-instruction", flow="single", base=None):
    return {"id": f"e{i}", "group": group, "tags": {"primary": family, "flow": flow},
            "events": [{"kind": "submit"}], **({"base": base} if base else {})}


class SplitTests(unittest.TestCase):
    def setUp(self):
        self.episodes = [ep(i, f"g{i % 50}") for i in range(200)]
        self.episodes += [ep(1000 + i, f"rare{i}", family="rare") for i in range(5)]
        self.episodes += [ep(2000, "elsewhere", base="e3")]

    def test_a_group_never_spans_two_splits(self):
        where = {}
        for name, members in split(self.episodes).items():
            for e in members:
                self.assertEqual(where.setdefault(e["group"], name), name)

    def test_a_sibling_stays_with_its_base(self):
        where = {e["id"]: name for name, members in split(self.episodes).items() for e in members}
        self.assertEqual(where["e2000"], where["e3"])

    def test_every_episode_is_placed_once_and_sealed_takes_its_share(self):
        parts = split(self.episodes)
        self.assertEqual(sum(map(len, parts.values())), len(self.episodes))
        self.assertGreaterEqual(len(parts["sealed"]), 0.4 * len(self.episodes))

    def test_sealed_takes_half_of_a_thin_family_first(self):
        # 10 rare episodes over 200 common ones: a random 40% would often miss half, the quota doesn't.
        episodes = [ep(i, f"g{i % 50}") for i in range(200)] + [ep(1000 + i, f"rare{i}", family="rare") for i in range(10)]
        for seed in range(5):
            sealed = split(episodes, seed)["sealed"]
            self.assertGreaterEqual(sum(e["tags"]["primary"] == "rare" for e in sealed), 5)


if __name__ == "__main__":
    unittest.main()
