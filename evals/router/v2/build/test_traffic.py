"""The routing trace becomes outcomes, gold and frozen moments; summary shows no text (traffic.py). Synthetic traces only."""
import contextlib
import io
import json
import math
import pathlib
import tempfile
import unittest

from v2.build import traffic as T

SECRET = "zebra-secret-words"


def inputs(**kw):
    base = {
        "options": [{"target": "session:A", "name": "Docs", "session": "A"},
                    {"target": "answer:c1", "name": "Docs card", "session": "A"},
                    {"target": "session:B", "name": "CI", "session": "B"},
                    {"target": "new:lookout", "name": "New in lookout"},
                    {"target": "compound", "name": "Compound"}],
        "route": {"session:A": 0.5, "answer:c1": 0.1, "session:B": 0.2, "new:lookout": 0.1, "compound": 0.05,
                  "unclear": 0.05},
        "reply": {"A": 0.9}, "next": {"B": 0.3}, "gates": {"gate_compound": 0.2, "gate_you": 0.7},
        "lexical": {"f_said": {"A": 1.0, "B": 0.4}}, "latest": ["A", "B"], "running": [], "idle": {"A": 2, "B": 30},
        "lastTold": "B", "ranked": [{"target": "session:A", "p": 0.8}], "sureness": 0.95, "sure": True,
        "card": None, "request": "{}"}
    base.update(kw)
    return base


def decided(i, action="send", path="jev", target="session:A", at="2026-10-10T10:00:00Z", with_inputs=True, **kw):
    line = {"kind": "decided", "id": i, "at": at, "message": SECRET + " " + i, "path": path, "action": action,
            "target": target, **kw}
    if with_inputs:
        line["inputs"] = inputs()
    return line


def follow(kind, i, target=None, index=None, frm=None):
    return {"kind": kind, "id": i, "at": "2026-10-10T10:01:00Z", "target": target, "index": index, "from": frm}


def trace(lines, tail=""):
    d = tempfile.mkdtemp()
    p = pathlib.Path(d) / "router-trace.jsonl"
    p.write_text("".join(json.dumps(x) + "\n" for x in lines) + tail)
    return p


def records(lines, since=None, tail=""):
    got, bad = T.read(trace(lines, tail))
    joined, stats = T.join(got, since)
    return {r["id"]: r for r in (T.record(d, f) for d, f in joined)}, stats, bad


LINES = [
    decided("kept"),
    decided("ask-picked", action="ask"), follow("picked", "ask-picked", "session:A", 0, "session:A"),
    decided("ask-fixed", action="ask"), follow("corrected", "ask-fixed", "session:B", 2, "session:A"),
    decided("ask-open", action="ask"),
    decided("sent-fixed"), follow("corrected", "sent-fixed", "session:B", None, "session:A"),
    decided("sent-undone"), follow("cancelled", "sent-undone"),
    decided("rule", path="reply", target="answer:c1", with_inputs=False),
]


class GoldTests(unittest.TestCase):
    def setUp(self):
        self.r, self.stats, self.bad = records(LINES)

    def test_outcomes_and_gold(self):
        want = {"kept": ("kept", "session:A", "forbidden"), "ask-picked": ("picked", "session:A", "allowed"),
                "ask-fixed": ("corrected", "session:B", "required"), "ask-open": ("unanswered", None, None),
                "sent-fixed": ("corrected", "session:B", "required"), "sent-undone": ("cancelled", None, "required"),
                "rule": ("kept", "answer:c1", "forbidden")}
        for i, (out, intended, ask) in want.items():
            self.assertEqual((self.r[i]["outcome"], self.r[i]["gold"]["intended"], self.r[i]["gold"]["ask"]),
                             (out, intended, ask), i)

    def test_a_rule_path_has_no_frozen_moment(self):
        self.assertIsNone(self.r["rule"]["frozen"])
        self.assertNotIn("in_options", self.r["rule"]["gold"])
        self.assertTrue(self.r["ask-fixed"]["gold"]["in_options"])

    def test_the_correction_keeps_its_button_and_suggestion(self):
        self.assertEqual(self.r["ask-fixed"]["final"], {"target": "session:B", "index": 2, "from": "session:A"})


class RobustnessTests(unittest.TestCase):
    def test_partial_last_line_unknown_kind_orphan_and_duplicate(self):
        lines = [decided("x", target="session:A"), decided("x", target="session:B"),
                 {"kind": "teleported", "id": "x"}, follow("picked", "ghost", "session:A"), {"no": "kind"}]
        r, stats, bad = records(lines, tail='{"kind": "decided", "id": "half')
        self.assertEqual(list(r), ["x"])
        self.assertEqual(r["x"]["target"], "session:B")  # the later line wins
        self.assertEqual(bad, 2)
        self.assertEqual(stats["duplicate_ids"], 1)
        self.assertEqual(stats["orphan_followups"], 1)
        self.assertEqual(stats["unknown_kind:teleported"], 1)

    def test_since_filters_on_the_decision_and_keeps_its_late_follow_up(self):
        lines = [decided("old", at="2026-09-01T10:00:00Z"), decided("new", action="ask", at="2026-10-11T23:00:00Z"),
                 follow("picked", "new", "session:A")]
        r, _, _ = records(lines, since=T.parse_at("2026-10-01"))
        self.assertEqual(list(r), ["new"])
        self.assertEqual(r["new"]["outcome"], "picked")

    def test_a_missing_trace_is_empty(self):
        self.assertEqual(T.read("/nonexistent/router-trace.jsonl"), ([], 0))


class FeatureTests(unittest.TestCase):
    def test_features_follow_route_fusion(self):
        fs = T.features(inputs(), "short")
        a, card, b = fs["session:A"], fs["answer:c1"], fs["session:B"]
        self.assertAlmostEqual(a["lp"], math.log(0.5))
        self.assertEqual((a.get("fin0"), a["reply"], a["f_said"], a["fin0u"], a["idle5u"]), (1, 0.9, 1.0, 0.05, 0.05))
        self.assertEqual((card.get("fin0"), card["reply"]), (1, 0.9))  # a card's answer is its session's
        self.assertEqual((b.get("fin1"), b.get("told0"), b["nxt"], b["idle5u"]), (1, 1, 0.3, 0))
        self.assertEqual(fs["new:lookout"], {"lp": math.log(0.1), "new": 1})
        self.assertEqual((fs["compound"]["g_c"], fs["compound"]["you"], fs["compound"]["ilong"]), (0.2, 0.7, 0))
        self.assertNotIn("unclear", fs)

    def test_running_is_not_idle(self):
        fs = T.features(inputs(running=["A"], latest=["B"]), "x")
        self.assertEqual((fs["session:A"].get("run"), fs["session:A"]["idle5u"], fs["session:A"].get("fin0")), (1, 0, None))

    def test_frozen_carries_facts_and_shipped(self):
        fz = T.frozen(decided("k"))
        self.assertEqual(fz["facts"]["targetOf"], {"A": "session:A", "B": "session:B"})
        self.assertEqual(fz["shipped"]["sureness"], 0.95)
        self.assertEqual(fz["reading"]["dests"]["unclear"], 0.05)


class OutputTests(unittest.TestCase):
    def test_summary_counts_without_text(self):
        got, bad = T.read(trace(LINES))
        joined, stats = T.join(got)
        s = T.summary(joined, stats, bad)
        self.assertNotIn(SECRET, json.dumps(s))
        self.assertEqual(s["asks"]["n"], 3)
        self.assertEqual((s["asks"]["picked"], s["asks"]["corrected"], s["asks"]["unanswered"]), (1, 1, 1))
        self.assertEqual(s["asks"]["button_index"], {"0": 1, "2": 1})
        self.assertEqual((s["sends"]["n"], s["sends"]["kept"], s["sends"]["corrected_later"],
                          s["sends"]["cancelled_later"]), (4, 2, 1, 1))
        self.assertEqual(s["sends"]["sureness"], {">=0.93": 3})  # the rule's send has no inputs

    def test_summary_command_prints_no_text(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            T.main(["summary", "--trace", str(trace(LINES))])
        self.assertNotIn(SECRET, buf.getvalue())
        self.assertEqual(json.loads(buf.getvalue())["routings"], 7)

    def test_export_refuses_to_write_outside_data(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            T.main(["export", "--trace", str(trace(LINES)), "--out", tempfile.mkdtemp() + "/out.jsonl"])

    def test_data_is_gitignored(self):
        self.assertIn("data/", (T.V2 / ".gitignore").read_text().split())


if __name__ == "__main__":
    unittest.main()
