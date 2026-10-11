"""Contract tests for meaning-preserving transforms and aggregate flip counts."""

import copy
import json
import sys
import types
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

from .metamorphic import (Inapplicable, decision_signature, evaluate_invariance,
                          transform_episode)


def episode():
    return {"schema": 2, "id": "fixture", "group": "day-one", "state": {
        "projects": ["alpha"], "sessions": [
            {"id": "s1", "title": "Caching", "project": "alpha", "running": False,
             "activity": "", "summary": "", "idle_min": 1, "turns": []},
            {"id": "s2", "title": "Search", "project": "alpha", "running": False,
             "activity": "", "summary": "", "idle_min": 4, "turns": []}],
        "cards": [{"id": "c1", "session": "s1", "kind": "asks", "text": "Proceed?", "options": []}],
        "history": [{"to": "session:s1", "you": "Add a regression", "ago_min": 4}]},
        "events": [{"id": "e1", "kind": "submit", "message": "Add another regression",
                    "context": {"replyTo": "c1", "pinned": "session:s1", "notTo": "session:s2"},
                    "gold": {"intended": "session:s1", "acceptable": ["session:s1"],
                             "clarify": ["session:s2"], "ask": "allowed"}}]}


class TransformationTests(unittest.TestCase):
    def test_ids_are_bijective_and_update_context_cards_history_gold_and_delta(self):
        base = episode()
        base["events"].append({"id": "e2", "kind": "board", "delta": {
            "sessions+": [{"id": "s3", "title": "Deploy"}],
            "cards+": [{"id": "c3", "session": "s3"}]}})
        original = copy.deepcopy(base)
        variant, inverse = transform_episode(base, "ids", seed=7)
        self.assertEqual(base, original)
        self.assertEqual(variant["group"], base["group"])
        self.assertEqual(variant["id"], base["id"])
        self.assertEqual(len(inverse), len(set(inverse.values())))
        renamed = variant["state"]["sessions"][0]["id"]
        self.assertEqual(inverse[renamed], "s1")
        self.assertEqual(variant["state"]["cards"][0]["session"], renamed)
        self.assertEqual(variant["state"]["history"][0]["to"], "session:" + renamed)
        self.assertEqual(variant["events"][0]["gold"]["intended"], "session:" + renamed)
        self.assertEqual(variant["events"][0]["context"]["pinned"], "session:" + renamed)
        self.assertEqual(inverse[variant["events"][1]["delta"]["cards+"][0]["id"]], "c3")

    def test_case_noise_and_typo_do_not_edit_board_or_gold(self):
        base = episode()
        for name in ("case", "typo"):
            variant, _ = transform_episode(base, name)
            self.assertNotEqual(variant["events"][0]["message"], base["events"][0]["message"])
            self.assertEqual(variant["state"], base["state"])
            self.assertEqual(variant["events"][0]["gold"], base["events"][0]["gold"])

    def test_id_collision_with_project_title_and_prose_preserves_task(self):
        base = episode()
        base.update(id="api", group="api", family="api", tags={"primary": "api", "flow": "api"})
        base["state"]["projects"] = ["api"]
        base["state"]["sessions"] = [{"id": "api", "title": "api", "project": "api",
            "running": False, "activity": "api", "summary": "api handles session:api",
            "idle_min": 1, "turns": [["api", "api answer:c_api"]]}]
        base["state"]["cards"] = [{"id": "c_api", "session": "api", "kind": "asks",
                                    "text": "api needs session:api", "options": ["api"]}]
        base["state"]["history"] = [{"to": "session:api", "corrected_from": "new:api", "you": "api"}]
        base["state"]["tasks"] = {"api": True}
        event = base["events"][0]
        event.update(id="api", message="tell api to check api and session:api", on={"ask": "api"},
                     context={"replyTo": "c_api", "pinned": "new:api", "pills": ["api"],
                              "shown": "session:api", "jev": {"top": "session:api", "ranked": [
                                  {"target": "session:api", "p": .8}, ["answer:c_api", .1], "new:api"]}},
                     gold={"intended": "session:api", "acceptable": ["session:api", "new:api"],
                           "clarify": ["answer:c_api"], "evidence": "api"})
        base["events"].append({"id": "board", "kind": "board", "delta": {
            "sessions~": [{"id": "api", "title": "api", "project": "api"}],
            "cards-": ["c_api"], "sessions-": ["api"], "projects": ["api"],
            "history+": [{"to": "session:api", "you": "api"}]}})
        variant, inverse = transform_episode(base, "ids")
        renamed = variant["state"]["sessions"][0]["id"]
        card_id = variant["state"]["cards"][0]["id"]
        self.assertNotEqual(renamed, "api")
        self.assertEqual(inverse[renamed], "api")
        self.assertEqual(variant["state"]["projects"], ["api"])
        self.assertEqual(variant["state"]["sessions"][0]["project"], "api")
        self.assertEqual(variant["state"]["sessions"][0]["title"], "api")
        self.assertEqual(variant["state"]["sessions"][0]["activity"], "api")
        self.assertEqual(variant["state"]["sessions"][0]["turns"], [["api", "api answer:" + card_id]])
        self.assertEqual(variant["state"]["cards"][0]["session"], renamed)
        self.assertEqual(variant["state"]["cards"][0]["options"], ["api"])
        self.assertEqual(variant["state"]["history"][0]["corrected_from"], "new:api")
        self.assertEqual(variant["state"]["tasks"], {renamed: True})
        changed = variant["events"][0]
        self.assertEqual(changed["message"], "tell api to check api and session:" + renamed)
        self.assertEqual(changed["context"]["pinned"], "new:api")
        self.assertEqual(changed["context"]["pills"], ["api"])
        self.assertEqual(changed["context"]["replyTo"], card_id)
        self.assertEqual(changed["context"]["jev"]["ranked"], [
            {"target": "session:" + renamed, "p": .8}, ["answer:" + card_id, .1], "new:api"])
        self.assertEqual(changed["gold"]["acceptable"], ["session:" + renamed, "new:api"])
        self.assertEqual(changed["gold"]["evidence"], "api")
        self.assertEqual(changed["id"], "api")
        self.assertEqual(changed["on"], {"ask": "api"})
        self.assertEqual(variant["id"], "api")
        self.assertEqual(variant["group"], "api")
        self.assertEqual(variant["tags"], base["tags"])
        delta = variant["events"][1]["delta"]
        self.assertEqual(delta["sessions~"], [{"id": renamed, "title": "api", "project": "api"}])
        self.assertEqual(delta["cards-"], [card_id])
        self.assertEqual(delta["sessions-"], [renamed])
        self.assertEqual(delta["projects"], ["api"])
        self.assertEqual(delta["history+"][0]["to"], "session:" + renamed)

    def test_typo_protects_address_start_project_and_session_title(self):
        base = episode()
        base["events"][0]["message"] = "start session alpha"
        with self.assertRaises(Inapplicable):
            transform_episode(base, "typo")
        base["events"][0]["message"] = "tell Caching to improve regression"
        variant, _ = transform_episode(base, "typo")
        self.assertTrue(variant["events"][0]["message"].startswith("tell Caching to "))

    def test_paraphrase_is_an_explicit_hook(self):
        base = episode()
        with self.assertRaises(Inapplicable):
            transform_episode(base, "paraphrase")
        variant, _ = transform_episode(base, "paraphrase", paraphrase=lambda _: "Add one more regression")
        self.assertEqual(variant["events"][0]["message"], "Add one more regression")
        self.assertEqual(variant["group"], base["group"])

    def test_title_reference_is_not_an_invariance(self):
        base = episode()
        base["events"][0]["message"] = "tell Caching to add regression"
        with self.assertRaises(Inapplicable):
            transform_episode(base, "title-noise")

    def test_title_noise_keeps_original_words(self):
        base = episode()
        variant, _ = transform_episode(base, "title-noise")
        for old, new in zip(base["state"]["sessions"], variant["state"]["sessions"]):
            self.assertTrue(new["title"].startswith(old["title"]))

    def test_irrelevant_sessions_are_visible_older_and_do_not_replace_any_session(self):
        base = episode()
        variant, _ = transform_episode(base, "irrelevant-sessions", extra_sessions=3)
        sessions = variant["state"]["sessions"]
        self.assertEqual(sessions[:2], base["state"]["sessions"])
        self.assertEqual(len(sessions), 5)
        self.assertTrue(all(not row["archived"] and row["idle_min"] > 4 for row in sessions[2:]))

    def test_irrelevant_sessions_cannot_evict_a_target_at_candidate_cap(self):
        base = episode()
        base["state"]["sessions"] = [dict(base["state"]["sessions"][0], id=f"s{i}") for i in range(20)]
        with self.assertRaises(Inapplicable):
            transform_episode(base, "irrelevant-sessions")

    def test_signatures_canonicalize_ids_and_ignore_ask_button_order(self):
        first = {"decision": "ask", "ranked": ["session:s1", "session:s2"]}
        second = {"decision": "ask", "ranked": [{"target": "session:x2"}, {"target": "session:x1"}]}
        self.assertEqual(decision_signature(first), decision_signature(second, {"x1": "s1", "x2": "s2"}))

    def test_flip_counts_and_branch_divergence_have_separate_denominators(self):
        base = episode()
        def runner(current, system):
            events = [{"id": "e1", "kind": "submit", "decision": "send", "target": "session:s1"}]
            if system.option_seed is not None:
                events[0]["target"] = "session:s2"
                events.append({"id": "correction", "kind": "submit", "decision": "send", "target": "session:s1"})
            return {"events": events}
        report = evaluate_invariance([base], types.SimpleNamespace(option_seed=None),
                                     transformations=["option-order", "paraphrase"], runner=runner)
        order = report["transformations"]["option-order"]
        self.assertEqual(order["event_pairs"], 1)
        self.assertEqual(order["event_flip_rate"], 1)
        self.assertEqual(order["branch_divergences"], 1)
        self.assertEqual(order["first_submit_flip_rate"], 1)
        self.assertEqual(report["transformations"]["paraphrase"]["skipped"], 1)

    def test_variants_share_one_budget_and_restore_the_option_seed(self):
        system = types.SimpleNamespace(option_seed=None, new_calls=0)
        def runner(current, active_system):
            active_system.new_calls += 1
            return {"events": [{"id": "e1", "kind": "submit", "decision": "send", "target": "session:s1"}]}
        evaluate_invariance([episode()], system, transformations=["option-order", "case"], runner=runner)
        self.assertEqual(system.new_calls, 3)
        self.assertIsNone(system.option_seed)

    def test_failed_variant_also_restores_the_option_seed(self):
        system = types.SimpleNamespace(option_seed=None)
        def runner(current, active_system):
            if active_system.option_seed is not None:
                raise RuntimeError("fixture failure")
            return {"events": []}
        with self.assertRaises(RuntimeError):
            evaluate_invariance([episode()], system, transformations=["option-order"], runner=runner)
        self.assertIsNone(system.option_seed)

    def test_permutations_reach_actual_jev_request(self):
        import formats
        import jev
        from explore import cal
        from .adapter import to_case
        formats.FORMATS.update(cal.FORMATS)
        base = episode()
        case = to_case(base["state"], base["events"][0])
        sent = []
        class Response:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self):
                return b'{"answers": {}}'
        def capture(request, **kwargs):
            body = json.loads(request.data)
            sent.append(list(body["questions"]["route"]["criteria"]))
            return Response()
        with patch.object(jev, "ordered", True), patch.object(jev, "key", return_value="fixture-key"), \
             patch.object(jev.urllib.request, "urlopen", side_effect=capture):
            for seed in (None, 7):
                state, questions, _ = formats.build("combo-o", case, shuffle_seed=seed)
                jev.ask(state, questions, cache=False)
        self.assertEqual(set(sent[0]), set(sent[1]))
        self.assertNotEqual(sent[0], sent[1])


if __name__ == "__main__":
    unittest.main()
