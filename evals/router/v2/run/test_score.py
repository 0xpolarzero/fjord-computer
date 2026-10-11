"""Regression contracts for harm, asks, recovery, weighting, and dependence."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from v2.run.compare import compare, mcnemar_exact
from v2.run.score import SEALED, episode_score, evaluate, event_score, load_results


def submit(decision="send", target="session:a", *, ask="allowed", consequential=False, ranked=None):
    return {"id": "e1", "kind": "submit", "decision": decision, "target": target,
            "ranked": ranked or [], "gold": {"intended": "session:a", "acceptable": ["session:a"],
                                             "ask": ask, "consequential": consequential}}


def episode(episode_id, group, events, family="next-instruction", source="scripted", **extra):
    return {"id": episode_id, "group": group, "family": "semantic-example", "events": events,
            "tags": {"primary": family, "flow": "single", "slices": []},
            "provenance": {"source": source}, "completion": True, **extra}


class LossTests(unittest.TestCase):
    def test_required_ask_does_not_authorize_hidden_goal_send(self):
        self.assertEqual(event_score(submit(ask="required"))["loss"], 25)

    def test_consequential_wrong_has_fixed_cost_in_sensitivity(self):
        trace = submit(target="session:b", consequential=True)
        for cost in (10, 25, 100):
            self.assertEqual(event_score(trace, cost)["loss"], 100)

    def test_ask_cost_depends_on_actual_first_four_and_ask_policy(self):
        hit = ["session:b", {"target": "session:a", "score": .2}]
        self.assertEqual(event_score(submit("ask", None, ask="allowed", ranked=hit))["loss"], 1)
        self.assertEqual(event_score(submit("ask", None, ask="forbidden", ranked=hit))["loss"], 2)
        fifth = ["session:b", "session:c", "session:d", "session:e", "session:a"]
        self.assertEqual(event_score(submit("ask", None, ranked=fifth))["loss"], 4)

    def test_recovery_retains_harm_and_pick_click_is_not_charged_twice(self):
        result = episode("e", "g", [submit(target="session:b"),
                                      submit("ask", None, ranked=["session:a"]),
                                      {"kind": "pick", "target": "session:a"}, submit()])
        scored = episode_score(result)
        self.assertEqual((scored["loss"], scored["wrong"], scored["clicks"]), (26, 1, 1))
        result["click_budget"] = 0
        self.assertEqual(episode_score(result)["completion_within_budget"], 0)

    def test_a_submit_copied_from_a_real_moment_is_not_scored_twice(self):
        result = episode("e", "g", [{**submit(target="session:b"), "duplicate_of_real": True}, submit()])
        scored = episode_score(result)
        self.assertEqual((scored["submits"], scored["wrong"], scored["loss"]), (1, 0, 0))

    def test_missing_ask_has_two_actual_escape_clicks_and_no_duplicate_base_loss(self):
        result = episode("e", "g", [submit("ask", None), {"kind": "pick", "clicks": 2}])
        scored = episode_score(result)
        self.assertEqual((scored["loss"], scored["clicks"]), (4, 2))


class AggregateTests(unittest.TestCase):
    def test_sealed_result_loader_refuses_before_any_open(self):
        for path in (SEALED, SEALED / "traces.jsonl", SEALED / "nested" / "traces.jsonl"):
            with patch.object(Path, "open", side_effect=AssertionError("opened sealed")):
                with self.assertRaisesRegex(ValueError, "sealed"):
                    load_results(path)

    def test_empty_and_no_send_ratios_are_json_null(self):
        self.assertIsNone(evaluate([], bootstrap=20)["natural"]["loss"])
        ask_only = evaluate([episode("e", "g", [submit("ask", None, ranked=["session:a"])])], bootstrap=20)
        self.assertIsNone(ask_only["natural"]["wrong_sends"])
        json.dumps(ask_only, allow_nan=False)

    def test_stress_equalizes_primary_families(self):
        results = [episode("a", "ga", [submit(target="session:b")], family="approval"),
                   episode("b", "gb", [submit()], family="next-instruction"),
                   episode("c", "gc", [submit()], family="next-instruction")]
        scored = evaluate(results, bootstrap=0)
        self.assertAlmostEqual(scored["natural"]["loss"], 25 / 3)
        self.assertEqual(scored["stress"]["loss"], 12.5)

    def test_source_mixture_uses_declared_shares_not_fixture_counts(self):
        results = [episode("a", "ga", [submit(target="session:b")], source="real-moment"),
                   episode("b", "gb", [submit()], source="scripted"),
                   episode("c", "gc", [submit()], source="scripted")]
        scored = evaluate(results, bootstrap=0)
        self.assertAlmostEqual(scored["natural"]["loss"], 25 * .25 / .35)
        self.assertIn("renormalized", scored["method"]["natural"])

    def test_group_bootstrap_cannot_split_correlated_episode_siblings(self):
        results = [episode("a", "same", [submit(target="session:b")]), episode("b", "same", [submit()])]
        interval = evaluate(results, bootstrap=100)["natural"]["ci95"]["loss"]
        self.assertEqual((interval["low"], interval["high"]), (12.5, 12.5))

    def test_explicit_weight_cannot_be_missing_or_null(self):
        for weight in (None, -1, float("nan")):
            with self.assertRaises(ValueError):
                evaluate([episode("a", "g", [submit()], natural_weight=weight)], bootstrap=0)
        with self.assertRaises(ValueError):
            evaluate([episode("a", "ga", [submit()], natural_weight=1),
                      episode("b", "gb", [submit()])], bootstrap=0)

    def test_flow_quota_is_sixty_independent_episodes(self):
        results = [episode(str(index), str(index), [submit()]) for index in range(50)]
        report = evaluate(results, bootstrap=0)
        self.assertFalse(report["by_family"]["next-instruction"]["exploratory"])
        self.assertTrue(report["by_flow"]["single"]["exploratory"])


class ComparisonTests(unittest.TestCase):
    def test_paired_cluster_sampling_and_group_mcnemar(self):
        baseline = [episode("a", "same", [submit(target="session:b")]),
                    episode("b", "same", [submit(target="session:b")])]
        candidate = [episode("b", "same", [submit()]), episode("a", "same", [submit()])]
        report = compare(baseline, candidate, bootstrap=100)
        self.assertEqual(report["natural"]["delta"]["loss"], -25)
        self.assertEqual(report["natural"]["ci95"]["loss"]["high"], -25)
        self.assertEqual(report["mcnemar"]["baseline_only_wrong"], 1)
        self.assertIsNone(report["mcnemar_episodes"])
        self.assertEqual(report["sensitivity"]["10"]["natural"]["delta_loss"], -10)

    def test_pairing_refuses_missing_or_reassigned_episode(self):
        baseline = [episode("a", "g", [submit()])]
        with self.assertRaises(ValueError):
            compare(baseline, [])
        with self.assertRaises(ValueError):
            compare(baseline, [episode("a", "different", [submit()])])

    def test_exact_mcnemar_and_no_discordance(self):
        self.assertEqual(mcnemar_exact(0, 0), 1)
        self.assertEqual(mcnemar_exact(6, 0), .03125)
        self.assertEqual(mcnemar_exact(3, 3), 1)
        self.assertEqual(mcnemar_exact(0, 6), mcnemar_exact(6, 0))


if __name__ == "__main__":
    unittest.main()
