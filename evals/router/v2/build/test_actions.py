"""Action gold (v2/ACTIONS.md): targets parse, project onto today's destinations, and written gold follows the board."""
import random
import unittest

from v2.build import actions_common as A
from v2.build import actions_written as W
from v2.build.actions_relabel import actions_for
from v2.run.episodes import validate_episode


def board():
    sessions = [
        {"id": "a1", "title": "Fix login flow", "project": "lookout", "running": True, "waits_on_you": False},
        {"id": "b2", "title": "Docs pass", "project": "lcu", "running": False, "waits_on_you": False},
        {"id": "c3", "title": "Release notes", "project": "lookout", "running": False, "waits_on_you": False},
        {"id": "d4", "title": "Release notes", "project": "lcu", "running": False, "waits_on_you": False},
        {"id": "e5", "title": "Bench rerun", "project": "lcu", "running": True, "waits_on_you": False},
        {"id": "f6", "title": "Idle thing", "project": "lcu", "running": False, "waits_on_you": False},
    ]
    cards = [{"id": "b2#t3", "session": "b2", "kind": "done", "created_min_ago": 4},
             {"id": "c3#t1", "session": "c3", "kind": "done", "created_min_ago": 9},
             {"id": "d4#t2", "session": "d4", "kind": "asks", "created_min_ago": 2},
             {"id": "f6#w1", "session": "f6", "kind": "question", "created_min_ago": 1}]
    return {"group": "g:1", "id": "ep", "state": {"now": "x", "projects": ["lcu", "lookout"], "sessions": sessions,
                                                  "cards": cards, "history": []}}


class ActionTests(unittest.TestCase):
    def test_parse_and_legacy(self):
        st = board()["state"]
        self.assertEqual(A.parse("session:a1"), ("say", "session", "a1"))
        self.assertEqual(A.legacy("answer:card:d4#t2", st), "session:d4")
        self.assertEqual(A.legacy("ack:card:b2#t3", st), "change_fjord")
        self.assertEqual(A.legacy("stop:session:a1", st), "change_fjord")
        self.assertEqual(A.legacy("start:new:lcu", st), "new:lcu")
        self.assertEqual(A.legacy("ask_fjord", st), "question")
        with self.assertRaises(ValueError):
            A.parse("poke:session:a1")

    def test_interrupt_never_accepts_a_plain_send(self):
        g = A.gold("interrupt:session:a1", ["interrupt:session:a1"], board()["state"])
        self.assertEqual(g["intended"], "session:a1")
        self.assertEqual(g["acceptable"], [])

    def test_proposals_accept_their_class(self):
        g = A.gold("archive:card:b2#t3", ["archive:card:b2#t3"], board()["state"])
        self.assertIn("configure", g["acceptable_actions"])
        self.assertEqual(g["acceptable"], ["change_fjord"])

    def test_written_gold_follows_the_board(self):
        b = W.Board(board())
        self.assertEqual({s["id"] for s in b.pool("done")}, {"b2"})
        self.assertEqual({s["id"] for s in b.pool("running_multi")}, {"a1", "e5"})
        self.assertEqual({s["id"] for s in b.pool("dup")}, {"c3"})
        self.assertEqual({s["id"] for s in b.pool("nocard")}, set())
        bare = W.make_gold("stop_bare", b, b.running[0], None, "stop-bare-several")
        self.assertEqual((bare["ask"], bare["acceptable_actions"]), ("required", []))
        dup = W.make_gold("ack_dup", b, b.pool("dup")[0], None, "dup-bare")
        self.assertEqual(dup["acceptable_actions"], ["ack:card:c3#t1"])    # d4's card asks: not a worth-a-look card
        form = W.make_gold("reply", b, next(s for s in b.live if s["id"] == "f6"), None, "seen-then-do")
        self.assertEqual(form["acceptable_actions"], ["answer:card:f6#w1"])

    def test_cases_validate(self):
        eps = W.build("t", [("seen", 1, "done", "ack", ["seen {t}"], []),
                            ("stop", 1, "running", "stop", ["stop {t}"], [])], [W.Board(board())], random.Random(1))
        for e in eps:
            validate_episode(e)
        self.assertEqual(eps[0]["events"][0]["gold"]["intended_action"], "ack:card:b2#t3")

    def test_relabel_mapping(self):
        st = board()["state"]
        self.assertEqual(actions_for("session:d4", st, {}), ["answer:card:d4#t2", "say:session:d4"])
        self.assertEqual(actions_for("session:f6", st, {"form_answer": True}), ["answer:card:f6#w1"])
        self.assertEqual(actions_for("session:a1", st, {"after_interrupt": True}), ["interrupt:session:a1"])
        self.assertEqual(actions_for("session:b2", st, {}), ["say:session:b2"])


if __name__ == "__main__":
    unittest.main()
