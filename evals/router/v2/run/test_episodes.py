"""Behavior tests for branching, mutable boards and the private-data seam."""
import copy
from pathlib import Path
import unittest
from unittest.mock import patch

from . import adapter, episodes


def state():
    return {"projects": ["api", "docs"], "sessions": [
        {"id": "a", "title": "API", "project": "api", "summary": "old", "idle_min": 1,
         "turns": [["cursor", "Pagination handles invalid cursors."]]},
        {"id": "d", "title": "Docs", "project": "docs", "idle_min": 20, "turns": []}],
        "cards": [], "history": []}


def submit(identity, message="more", target="session:a", on=None):
    return {"id": identity, "kind": "submit", "message": message, "context": {},
            "gold": {"intended": target, "acceptable": [target], "clarify": [], "ask": "allowed"},
            "on": on or {}}


class ScriptedSystem:
    name = "scripted"

    def __init__(self, actions):
        self.actions, self.seen = actions, []

    def decide(self, board, event):
        self.seen.append(copy.deepcopy(board))
        kind, target = self.actions[event["id"]]
        return {"decision": kind, "target": target,
                "ranked": [{"target": "session:a", "score": .8}, {"target": "session:d", "score": .2}],
                "path": "jev"}


class EpisodesTests(unittest.TestCase):
    def episode(self, events):
        return {"schema": 2, "id": "test", "group": "source-day", "state": state(), "events": events}

    def test_ask_pick_skips_wrong_branch_and_records_original_message(self):
        ep = self.episode([submit("first", "use SQLite", on={"ask": "pick", "wrong": "correction"}),
            {"id": "pick", "kind": "pick", "target": "session:a"}, submit("correction"), submit("follow")])
        system = ScriptedSystem({"first": ("ask", None), "follow": ("send", "session:a")})
        result = episodes.play_episode(ep, system)
        self.assertEqual([event["id"] for event in result["events"]], ["first", "pick", "follow"])
        self.assertEqual(system.seen[1]["history"][-1]["you"], "use SQLite")
        self.assertTrue(result["completion"])
        self.assertEqual(ep["state"]["history"], [])

    def test_wrong_branch_retains_wrong_delivery_and_correction(self):
        ep = self.episode([submit("first", on={"ask": "pick", "wrong": "correction"}),
            {"id": "pick", "kind": "pick", "target": "session:a"}, submit("correction")])
        system = ScriptedSystem({"first": ("send", "session:d"), "correction": ("send", "session:a")})
        result = episodes.play_episode(ep, system)
        self.assertEqual([event["id"] for event in result["events"]], ["first", "correction"])
        self.assertTrue(result["events"][0]["wrong"])
        self.assertEqual(result["final_state"]["history"][-1]["corrected_from"], "session:d")
        self.assertTrue(result["completion"])

    def test_unrelated_success_does_not_resolve_a_misdelivery(self):
        system = ScriptedSystem({"first": ("send", "session:d"), "follow": ("send", "session:d")})
        result = episodes.play_episode(self.episode([submit("first"), submit("follow", target="session:d")]), system)
        self.assertFalse(result["completion"])
        self.assertNotIn("corrected_from", result["final_state"]["history"][-1])

    def test_correction_does_not_resolve_an_older_unanswered_ask(self):
        ep = self.episode([submit("ask"), submit("wrong", on={"wrong": "fix"}), submit("fix")])
        system = ScriptedSystem({"ask": ("ask", None), "wrong": ("send", "session:d"), "fix": ("send", "session:a")})
        self.assertFalse(episodes.play_episode(ep, system)["completion"])

    def test_delivered_turn_strips_pill_and_router_aside_but_history_preserves_input(self):
        event = submit("first", "@api SQLite (@router no rush)")
        event["context"]["pills"] = ["api"]
        result = episodes.play_episode(self.episode([event]), ScriptedSystem({"first": ("send", "session:a")}))
        self.assertEqual(result["final_state"]["sessions"][0]["turns"][-1][0], "SQLite")
        self.assertEqual(result["final_state"]["history"][-1]["you"], event["message"])

    def test_board_delta_is_seen_only_when_it_occurs(self):
        ep = self.episode([submit("first"), {"id": "board", "kind": "board", "delta": {
            "sessions~": [{"id": "a", "summary": "new", "running": False}],
            "cards+": [{"id": "q", "session": "a", "kind": "question", "text": "Which?"}]}}, submit("follow")])
        system = ScriptedSystem({"first": ("send", "session:a"), "follow": ("send", "session:a")})
        episodes.play_episode(ep, system)
        self.assertEqual(system.seen[0]["sessions"][0]["summary"], "old")
        self.assertEqual(system.seen[1]["cards"][0]["text"], "Which?")

    def test_typed_follow_is_new_message_and_does_not_resolve_pending_ask(self):
        system = ScriptedSystem({"first": ("ask", None), "follow": ("send", "session:d")})
        result = episodes.play_episode(self.episode([submit("first"), submit("follow", target="session:d")]), system)
        self.assertFalse(result["completion"])
        self.assertEqual(result["final_state"]["history"][0]["to"], "session:d")

    def test_stale_pick_cannot_deliver(self):
        ep = self.episode([submit("first", on={"ask": "board"}),
            {"id": "board", "kind": "board", "delta": {"sessions-": ["a"]}},
            {"id": "pick", "kind": "pick", "target": "session:a"}])
        result = episodes.play_episode(ep, ScriptedSystem({"first": ("ask", None)}))
        self.assertFalse(result["events"][-1]["accepted"])
        self.assertFalse(result["completion"])
        self.assertEqual(result["final_state"]["history"], [])

    def test_cycle_fails_without_running_a_message_twice(self):
        ep = self.episode([submit("first", on={"right": "first"})])
        with self.assertRaisesRegex(ValueError, "cycle"):
            episodes.play_episode(ep, ScriptedSystem({"first": ("send", "session:a")}))

    def test_sealed_loader_refuses_before_opening(self):
        with patch.object(Path, "open", side_effect=AssertionError("opened sealed")):
            with self.assertRaisesRegex(ValueError, "sealed"):
                episodes.load_episodes(episodes.SEALED)

    def test_board_only_episode_is_not_an_enrolled_goal(self):
        with self.assertRaisesRegex(ValueError, "submit"):
            episodes.validate_episode(self.episode([{"id": "board", "kind": "board", "delta": {}}]))


class StartedSessionDeltaTests(unittest.TestCase):
    """A started-<event> session exists only if the policy started it (episodes.apply_delta)."""

    def state(self, *sessions):
        return {"sessions": [{"id": s} for s in sessions], "cards": []}

    def test_updates_to_a_session_the_policy_never_started_are_skipped(self):
        state = self.state("a")
        episodes.apply_delta(state, {"sessions~": [{"id": "started-e1", "running": False}],
                                     "cards+": [{"id": "started-e1#t1", "session": "started-e1"}]})
        self.assertEqual(([s["id"] for s in state["sessions"]], state["cards"]), (["a"], []))

    def test_re_adding_a_started_session_merges(self):
        state = self.state("started-e1")
        episodes.apply_delta(state, {"sessions+": [{"id": "started-e1", "title": "t"}]})
        self.assertEqual(state["sessions"], [{"id": "started-e1", "title": "t"}])

    def test_other_identities_stay_strict(self):
        with self.assertRaises(ValueError):
            episodes.apply_delta(self.state("a"), {"sessions~": [{"id": "b"}]})
        with self.assertRaises(ValueError):
            episodes.apply_delta(self.state("a"), {"sessions+": [{"id": "a"}]})


class AdapterTests(unittest.TestCase):
    def test_turns_feed_bm25_without_any_corpus_read(self):
        lexical = adapter.install_lexical()
        case = adapter.to_case(state(), message="invalid pagination cursor")
        self.assertEqual(lexical.past_turns(case, "a"), [("cursor", "Pagination handles invalid cursors.")])
        self.assertGreater(lexical.scores(case)["a"], lexical.scores(case)["d"])
        with self.assertRaisesRegex(RuntimeError, "disabled"):
            lexical.corpus()

    def test_state_and_event_changes_invalidate_lexical_case_id(self):
        board = state()
        before = adapter.to_case(board, message="cursor")
        board["sessions"][0]["turns"].append(["follow", "new response"])
        after = adapter.to_case(board, message="cursor")
        self.assertNotEqual(before["id"], after["id"])

    def test_pills_narrow_before_candidate_caps_and_omit_gold(self):
        event = submit("event")
        event["context"]["pills"] = ["docs"]
        case = adapter.to_case(state(), event)
        self.assertEqual([s["id"] for s in case["board"]["sessions"]], ["d"])
        self.assertNotIn("gold", case)

    def test_display_name_pill_resolves_to_folder_key(self):
        board = state()
        board["projects"] = ["/code/api", "/code/docs"]
        for session in board["sessions"]:
            session["project"] = "/code/" + session["project"]
        case = adapter.to_case(board, message="update the guide", context={"pills": ["docs"]})
        self.assertEqual(case["board"]["projects"], ["/code/docs"])
        self.assertEqual([s["id"] for s in case["board"]["sessions"]], ["d"])


if __name__ == "__main__":
    unittest.main()
