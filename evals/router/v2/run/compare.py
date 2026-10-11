"""Paired Router v2 comparisons, preserving source-group dependence.

Loss differences are candidate minus baseline (negative favors the candidate).
McNemar's exact binomial test is run on independent *group* indicators of any
wrong automatic action. An episode-level test is additionally reported only when
each group contains exactly one episode. Treating correlated rewrites or turns
as independent episode outcomes would manufacture significance.

Run from evals/router: python3 -m v2.run.compare baseline.jsonl candidate.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
from typing import Any, Iterable

from .score import (_validate_results, aggregate, episode_score, episode_weights,
                    group_indices, load_results, percentile)


def mcnemar_exact(baseline_only: int, candidate_only: int) -> float:
    """Two-sided exact conditional binomial p-value for discordant pairs."""
    if baseline_only < 0 or candidate_only < 0:
        raise ValueError("discordance counts cannot be negative")
    count = baseline_only + candidate_only
    if not count:
        return 1.0
    limit = min(baseline_only, candidate_only)
    term = 1
    tail = term
    for index in range(limit):
        term = term * (count - index) // (index + 1)
        tail += term
    return min(1.0, (2 * tail) / (1 << count))


def _discordance(baseline: list[bool], candidate: list[bool], unit: str) -> dict[str, Any]:
    baseline_only = sum(left and not right for left, right in zip(baseline, candidate))
    candidate_only = sum(right and not left for left, right in zip(baseline, candidate))
    return {"unit": unit, "pairs": len(baseline), "baseline_only_wrong": baseline_only,
            "candidate_only_wrong": candidate_only,
            "both_wrong": sum(left and right for left, right in zip(baseline, candidate)),
            "neither_wrong": sum(not left and not right for left, right in zip(baseline, candidate)),
            "p_value_exact_two_sided": mcnemar_exact(baseline_only, candidate_only)}


def compare(baseline: Iterable[dict[str, Any]], candidate: Iterable[dict[str, Any]],
            bootstrap: int = 2000, seed: int = 7) -> dict[str, Any]:
    """Compare identical enrolled episodes with paired source-cluster bootstrap.

    Pairing requires equal episode IDs and independence groups. Candidate results
    use baseline metadata/weights: selecting a new result mix is not a paired
    experiment. Sensitivity preserves consequential-wrong cost at 100.
    """
    if not isinstance(bootstrap, int) or bootstrap < 0:
        raise ValueError("bootstrap must be a nonnegative integer")
    baseline = list(baseline)
    candidate = list(candidate)
    _validate_results(baseline)
    _validate_results(candidate)
    left_by_id = {result["id"]: result for result in baseline}
    right_by_id = {result["id"]: result for result in candidate}
    if left_by_id.keys() != right_by_id.keys():
        raise ValueError("paired comparison requires exactly the same episode IDs")
    baseline = [left_by_id[episode_id] for episode_id in sorted(left_by_id)]
    candidate = [right_by_id[result["id"]] for result in baseline]
    for left, right in zip(baseline, candidate):
        if left["group"] != right["group"]:
            raise ValueError(f"independence group differs for episode {left['id']}")
        for key in ("tags", "provenance", "family", "natural_weight", "weight", "click_budget"):
            if left.get(key) != right.get(key):
                raise ValueError(f"paired episode metadata {key!r} differs for {left['id']}")
    groups = group_indices(baseline)
    left_stats = [episode_score(result) for result in baseline]
    right_stats = [episode_score(result) for result in candidate]
    report: dict[str, Any] = {
        "paired_episodes": len(baseline), "groups": len(groups),
        "direction": "candidate minus baseline; negative loss is better",
        "method": {"bootstrap_replicates": bootstrap, "seed": seed, "bootstrap_unit": "group",
                   "weights": "fixed baseline source/family weights before paired resampling",
                   "mcnemar": "any wrong automatic action per group; group independence must hold",
                   "multiplicity": "No multiple-comparison adjustment; preregister confirmatory comparisons."},
    }
    for mix in ("natural", "stress"):
        weights = episode_weights(baseline, mix)
        left_report = aggregate(left_stats, weights)
        right_report = aggregate(right_stats, weights)
        delta = {key: right_report[key] - left_report[key]
                 if right_report[key] is not None and left_report[key] is not None else None
                 for key in left_report}
        samples: dict[str, list[float]] = {key: [] for key in delta}
        rng = random.Random(seed)
        for _ in range(bootstrap if groups else 0):
            indices = [index for _ in groups for index in rng.choice(groups)]
            left_draw = aggregate(left_stats, weights, indices)
            right_draw = aggregate(right_stats, weights, indices)
            for key in samples:
                if left_draw[key] is not None and right_draw[key] is not None:
                    samples[key].append(right_draw[key] - left_draw[key])
        report[mix] = {"baseline": left_report, "candidate": right_report, "delta": delta,
                       "ci95": {key: {"low": percentile(values, .025), "high": percentile(values, .975),
                                      "valid_replicates": len(values)} for key, values in samples.items()}}
    left_wrong = [bool(item["wrong"]) for item in left_stats]
    right_wrong = [bool(item["wrong"]) for item in right_stats]
    report["mcnemar"] = _discordance([any(left_wrong[index] for index in group) for group in groups],
                                     [any(right_wrong[index] for index in group) for group in groups], "group")
    report["mcnemar_episodes"] = (_discordance(left_wrong, right_wrong, "episode")
                                    if all(len(group) == 1 for group in groups) else None)
    if report["mcnemar_episodes"] is None:
        report["mcnemar_episodes_note"] = "Omitted: multiple episodes share groups and are not independent."
    report["sensitivity"] = {}
    for cost in (10, 25, 100):
        left_cost = [episode_score(result, cost) for result in baseline]
        right_cost = [episode_score(result, cost) for result in candidate]
        report["sensitivity"][str(cost)] = {}
        for mix in ("natural", "stress"):
            weights = episode_weights(baseline, mix)
            left_loss = aggregate(left_cost, weights)["loss"]
            right_loss = aggregate(right_cost, weights)["loss"]
            samples = []
            rng = random.Random(seed)
            for _ in range(bootstrap if groups else 0):
                indices = [index for _ in groups for index in rng.choice(groups)]
                left_draw = aggregate(left_cost, weights, indices)["loss"]
                right_draw = aggregate(right_cost, weights, indices)["loss"]
                if left_draw is not None and right_draw is not None:
                    samples.append(right_draw - left_draw)
            report["sensitivity"][str(cost)][mix] = {
                "delta_loss": right_loss - left_loss if right_loss is not None and left_loss is not None else None,
                "ci95": {"low": percentile(samples, .025), "high": percentile(samples, .975),
                         "valid_replicates": len(samples)}}
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Paired Router v2 group-bootstrap and exact McNemar comparison.")
    parser.add_argument("baseline", help="baseline episode results JSONL")
    parser.add_argument("candidate", help="candidate episode results JSONL")
    parser.add_argument("--bootstrap", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    print(json.dumps(compare(load_results(args.baseline), load_results(args.candidate), args.bootstrap, args.seed),
                     indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
