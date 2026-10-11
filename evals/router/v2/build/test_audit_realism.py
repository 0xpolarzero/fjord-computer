"""Realism audit on small synthetic fixtures (audit_realism.py): destinations, group bootstrap, AUC, weights, outputs."""
import contextlib
import io
import json
import pathlib
import random
import tempfile
import unittest

import numpy as np

from v2.build import audit_realism as A


def session(sid, idle, running=False):
    return {"id": sid, "title": sid, "project": "p", "running": running, "idle_min": idle, "archived": False}


def state(last="a"):
    return {"now": "2026-10-01T00:00:00Z", "projects": ["p"],
            "sessions": [session("a", 1), session("b", 5), session("c", 30), session("d", 60)],
            "cards": [{"id": "a#t1", "session": "a", "kind": "done"}],
            "history": [{"ago_min": 1, "you": "earlier", "to": last}]}


def submit(eid, message, intended, dup=False, on=None):
    ev = {"id": eid, "kind": "submit", "message": message, "context": {},
          "gold": {"intended": intended, "acceptable": [intended], "clarify": [], "ask": None}}
    if dup:
        ev["duplicate_of_real"] = True
    if on:
        ev["on"] = on
    return ev


def episode(eid, group, events, source="real", writer="claude", mode="goal", last="a"):
    prov = {"source": "real-moment", "writer": "human"} if source == "real" else \
        {"source": "goal", "writer": writer, "mode": mode}
    return {"id": eid, "group": group, "provenance": prov, "tags": {"primary": "x", "flow": "single", "lang": "en"},
            "state": state(last), "events": events}


class WalkTests(unittest.TestCase):
    def test_destinations_follow_the_previous_delivery(self):
        e = episode("e", "g", [submit("e1", "go on", "session:a"), submit("e2", "and in c?", "session:c"),
                               submit("e3", "start one", "new:p"), submit("e4", "tweak lookout", "change_lookout"),
                               submit("e5", "more", "session:started-e3")])
        subs, _ = A.walk(e)
        self.assertEqual([s["dest"] for s in subs], ["same", "switch", "new", "intent", "same"])

    def test_switch_rank_leaves_the_previous_session_out(self):
        # a was last; c is 30 min idle, behind b (5 min): rank 2 among b, c, d.
        subs, _ = A.walk(episode("e", "g", [submit("e1", "x", "session:c")]))
        self.assertEqual(subs[0]["rank"], 2)

    def test_a_delivery_makes_its_target_most_recent(self):
        subs, _ = A.walk(episode("e", "g", [submit("e1", "x", "session:d"), submit("e2", "y", "session:a")]))
        self.assertEqual([s["rank"] for s in subs], [3, 1])  # after e1, d is previous; a (1 min) leads b, c

    def test_branch_entries_are_skipped_and_the_board_is_read_before_the_first_submit(self):
        events = [{"id": "e0", "kind": "board", "delta": {"cards+": [{"id": "b#t1", "session": "b"}],
                                                          "sessions~": [{"id": "b", "running": True}]}},
                  submit("e1", "x", "session:a", on={"wrong": "e2"}), submit("e2", "no, b", "session:b"),
                  submit("e3", "next", "session:a")]
        subs, board = A.walk(episode("e", "g", events))
        self.assertEqual([s["message"] for s in subs], ["x", "next"])
        self.assertEqual(board, {"sessions": 4, "running": 1, "cards": 2})

    def test_a_delta_naming_a_started_session_the_walk_also_made_is_tolerated(self):
        events = [submit("e1", "new thing", "new:p"),
                  {"id": "e2", "kind": "board", "delta": {"sessions+": [session("started-e1", 0, True)]}},
                  submit("e3", "more", "session:started-e1")]
        subs, _ = A.walk(episode("e", "g", events))
        self.assertEqual(subs[1]["dest"], "same")


def corpus(n_groups=30, per=4, shift=False, seed=0):
    """Real and written episodes over shared groups; written messages differ in style only when shift is set."""
    rng = random.Random(seed)
    verbs, things = ["fix", "check", "run", "update", "review"], ["the tests", "this bug", "the build", "docs", "CI"]
    real, written = [], []
    for g in range(n_groups):
        for i in range(per):
            for out, src in ((real, "real"), (written, "written")):
                v, t = rng.choice(verbs), rng.choice(things)
                text = f"Can you {v} {t}?" if src == "real" or not shift else f"pls {v} {t} quickly."
                target = rng.choice(["session:a", "session:b"])
                out.append(episode(f"{src}-{g}-{i}", f"g{g}", [submit("e1", text, target)], source=src,
                                   writer=rng.choice(["claude", "gpt"]), mode=rng.choice(["goal", "rewrite"])))
    return real, written


class StatsTests(unittest.TestCase):
    def test_same_distribution_gives_small_differences_with_cis_around_zero(self):
        eps, subs = A.records(*corpus())
        cmp = A.compare(eps, subs, boot=200)
        q = cmp["written"]["vs_real"]["question"]
        self.assertEqual(q["diff"], 0)
        self.assertLessEqual(q["ci"][0], 0)
        self.assertGreaterEqual(q["ci"][1], 0)

    def test_duplicates_of_real_messages_stay_out_of_message_statistics(self):
        real, written = corpus(n_groups=5, per=2)
        written.append(episode("dup", "g0", [submit("e1", "word " * 50, "session:a", dup=True)], source="written"))
        eps, subs = A.records(real, written)
        cmp = A.compare(eps, subs, boot=0)
        self.assertEqual(cmp["written"]["stats"]["words"]["n"], 10)
        self.assertEqual(cmp["written"]["stats"]["submits_per_episode"]["n"], 11)

    def test_wks_and_wquantile(self):
        x = np.array([1.0, 2, 3, 4])
        self.assertEqual(A.wks(x, np.ones(4), x, np.ones(4)), 0)
        self.assertEqual(A.wks(x, np.ones(4), x + 10, np.ones(4)), 1)
        self.assertEqual(A.wquantile(x, np.array([0, 0, 0, 1.0]), .5), 4)


class DiscriminatorTests(unittest.TestCase):
    def test_auc(self):
        self.assertEqual(A.auc([0.1, 0.2, 0.8, 0.9], [0, 0, 1, 1]), 1)
        self.assertEqual(A.auc([0.9, 0.8, 0.2, 0.1], [0, 0, 1, 1]), 0)
        self.assertEqual(A.auc([0.5, 0.5, 0.5, 0.5], [0, 1, 0, 1]), 0.5)

    def test_folds_keep_groups_whole(self):
        groups = [f"g{i % 7}" for i in range(50)]
        fold = A.group_folds(groups, 3, 1)
        for g in set(groups):
            self.assertEqual(len({f for f, h in zip(fold, groups) if h == g}), 1)

    def test_style_shift_is_detected_and_its_features_named(self):
        eps, _ = A.records(*corpus(shift=True))
        d = A.discriminator(eps, repeats=1)
        self.assertGreater(d["auc_all"]["mean"], 0.95)
        self.assertTrue(any("pls" in f["feature"] for f in d["gives_written_away"]))

    def test_same_generator_is_near_chance(self):
        eps, _ = A.records(*corpus(seed=3))
        self.assertLess(abs(A.discriminator(eps, repeats=1)["auc_all"]["mean"] - 0.5), 0.15)


class WeightTests(unittest.TestCase):
    def test_weights_pull_toward_real_strata_and_leave_intents_alone(self):
        real = [episode(f"r{i}", f"g{i}", [submit("e1", "Is it done?" if i < 30 else "fix it", "session:a")])
                for i in range(40)]
        written = [episode(f"w{i}", f"g{i}", [submit("e1", "Is it done?" if i < 10 else "fix it", "session:a")],
                           source="written") for i in range(40)]
        written.append(episode("wi", "gx", [submit("e1", "change lookout", "change_lookout")], source="written"))
        eps, _ = A.records(real, written)
        w, rows, cells = A.importance_weights(eps)
        self.assertEqual(w["wi"], 1.0)
        self.assertGreater(w["w0"], 1)
        self.assertLess(w["w20"], 1)
        comparable = [v for k, v in w.items() if k != "wi"]
        self.assertAlmostEqual(np.mean(comparable), 1, places=6)
        self.assertTrue(all(A.CLIP_LO <= v <= A.CLIP_HI for v in w.values()))
        self.assertLess(A.weight_summary(w)["ess"], len(w))


class OutputTests(unittest.TestCase):
    def test_writes_three_files_and_never_a_whole_message(self):
        real, written = corpus(n_groups=12, per=3)
        secret = "Please migrate the zanzibar ledger before friday"
        real[0]["events"][0]["message"] = secret
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            for name, rows in (("real", real), ("written", written)):
                (tmp / f"{name}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                A.main(["--real", str(tmp / "real.jsonl"), "--written", str(tmp / "written.jsonl"),
                        "--out", str(tmp / "audits"), "--boot", "20", "--repeats", "1"])
            files = {p.name: p.read_text() for p in (tmp / "audits").iterdir()}
            self.assertEqual(set(files), {"realism.json", "realism.md", "written_weights.jsonl"})
            self.assertEqual(len(files["written_weights.jsonl"].splitlines()), len(written))
            for text in [out.getvalue(), *files.values()]:
                self.assertNotIn("zanzibar ledger", text)


if __name__ == "__main__":
    unittest.main()
