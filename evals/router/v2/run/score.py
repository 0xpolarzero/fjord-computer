"""Score Router v2 replay traces without importing private transcript loaders.

Loss is charged once per submit, including misdeliveries later repaired. An ask's
loss includes its first selection click; observed pick events are counted once in
``clicks`` and do not add that same click to loss again. Extra explicit recovery
clicks can be supplied as ``recovery_clicks`` on a submit trace.

The specification gives a source mixture, but no deployment message-family
prevalence or completion budget. ``natural`` therefore uses the stated source
shares (renormalized over observed sources), or explicit ``natural_weight`` /
``weight`` on every episode. It is a provisional source mixture, not a claim of
measured Router traffic. ``stress`` gives each primary message family equal total
weight. Both weights are frozen before resampling whole source ``group`` clusters.
Completion uses the runner's assertion and ``click_budget`` when supplied; absent
that field, the earlier design's two routing clicks per submit is the default.

Run from evals/router: python3 -m v2.run.score traces.jsonl
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import random
from typing import Any, Iterable

SOURCE_SHARES = {"real-moment": 0.25, "real-rewrite": 0.30, "goal": 0.35, "scripted": 0.10}
SEALED = Path(__file__).resolve().parent.parent / "data" / "episodes" / "sealed"
AUTOMATIC = frozenset({"send", "start", "intent"})
METRICS = ("loss", "loss_per_submit", "wrong_all", "wrong_sends", "coverage",
           "hit_at_1", "hit_at_4", "ranking_hit_at_1", "ranking_hit_at_4",
           "episode_wrong_rate", "clicks", "completion_within_budget")


def _ratio(numerator: float, denominator: float) -> float | None:
    return numerator / denominator if denominator else None


def _ranked_targets(trace: dict[str, Any]) -> list[str]:
    # ranked contains the actual displayed order, not a fresh sort by score.
    return [item.get("target") if isinstance(item, dict) else item
            for item in trace.get("ranked", [])]


def event_score(trace: dict[str, Any], wrong_cost: float = 25) -> dict[str, Any]:
    """Return one submit's loss/counts. Board changes and picks are not submits.

    A required ask forbids every automatic action, even one whose destination
    coincides with the hidden intended target. Other automatic actions are right
    only when their destination belongs to ``acceptable``. Ask-card hits use the
    intended target, as BENCHMARK.md requires, rather than competing ``clarify``
    targets. Consequential wrong actions cost 100 at every sensitivity setting.
    """
    if trace.get("kind", "submit") != "submit":
        raise ValueError("event_score expects a submit trace")
    if not math.isfinite(wrong_cost) or wrong_cost < 0:
        raise ValueError("wrong_cost must be a finite nonnegative number")
    gold = trace.get("gold")
    if not isinstance(gold, dict):
        raise ValueError("submit trace requires gold")
    decision = trace.get("decision")
    if decision not in AUTOMATIC | {"ask"}:
        raise ValueError(f"unknown submit decision: {decision!r}")
    ask_policy = gold.get("ask", "allowed")
    if ask_policy not in {"required", "allowed", "forbidden"}:
        raise ValueError(f"unknown ask policy: {ask_policy!r}")
    intended = gold.get("intended")
    ranked = _ranked_targets(trace)
    hit1 = intended is not None and bool(ranked) and ranked[0] == intended
    hit4 = intended is not None and intended in ranked[:4]
    automatic = decision in AUTOMATIC
    wrong = automatic and (ask_policy == "required" or trace.get("target") not in gold.get("acceptable", []))
    if wrong:
        loss = 100 if gold.get("consequential", False) else wrong_cost
    elif automatic:
        loss = 0
    elif not hit4:
        loss = 4
    else:
        loss = 2 if ask_policy == "forbidden" else 1
    recovery = trace.get("recovery_clicks", 0)
    if not isinstance(recovery, (int, float)) or not math.isfinite(recovery) or recovery < 0:
        raise ValueError("recovery_clicks must be a finite nonnegative number")
    return {"loss": loss + recovery, "wrong": int(wrong), "automatic": int(automatic),
            "ask": int(not automatic), "right": int(automatic and not wrong),
            "hit_at_1": int(hit1), "hit_at_4": int(hit4),
            "needless_ask": int(not automatic and ask_policy == "forbidden"),
            "consequential_wrong": int(wrong and gold.get("consequential", False))}


def episode_score(result: dict[str, Any], wrong_cost: float = 25) -> dict[str, Any]:
    """Reduce one replay to additive sufficient statistics for cluster scoring."""
    scores = [event_score(event, wrong_cost) for event in result.get("events", [])
              if event.get("kind") == "submit"]
    totals = {key: sum(score[key] for score in scores) for key in
              ("loss", "wrong", "automatic", "ask", "right", "needless_ask", "consequential_wrong")}
    for rank in (1, 4):
        key = f"hit_at_{rank}"
        totals[key] = sum(score[key] for score in scores if score["ask"])
        totals[f"ranking_{key}"] = sum(score[key] for score in scores)
    clicks = sum(event.get("clicks", 1 if event.get("kind") == "pick" else 0)
                 for event in result.get("events", []))
    if not isinstance(clicks, (int, float)) or not math.isfinite(clicks) or clicks < 0:
        raise ValueError("click counts must be finite and nonnegative")
    budget = result.get("click_budget", 2 * len(scores))
    if not isinstance(budget, (int, float)) or not math.isfinite(budget) or budget < 0:
        raise ValueError("click_budget must be finite and nonnegative")
    totals.update(submits=len(scores), clicks=clicks, episode_wrong=int(totals["wrong"] > 0),
                  completion=int(bool(result.get("completion", False))),
                  completion_within_budget=int(bool(result.get("completion", False)) and clicks <= budget))
    return totals


def primary(result: dict[str, Any]) -> str:
    return str(result.get("tags", {}).get("primary") or result.get("family") or "unknown")


def _source(result: dict[str, Any]) -> str:
    return str(result.get("provenance", {}).get("source") or "unknown")


def _validate_results(results: list[dict[str, Any]]) -> None:
    ids: set[str] = set()
    for result in results:
        if not result.get("id") or not result.get("group"):
            raise ValueError("every episode result requires nonempty id and independence group")
        if result["id"] in ids:
            raise ValueError(f"duplicate episode id: {result['id']}")
        ids.add(result["id"])


def episode_weights(results: list[dict[str, Any]], mix: str) -> list[float]:
    """Fixed episode weights. Multiplying all weights by a constant is harmless."""
    if mix == "stress":
        counts: dict[str, int] = defaultdict(int)
        for result in results:
            counts[primary(result)] += 1
        return [1 / counts[primary(result)] for result in results]
    if mix != "natural":
        raise ValueError(f"unknown mix: {mix}")
    explicit = [result.get("natural_weight", result.get("weight")) for result in results]
    if any("natural_weight" in result or "weight" in result for result in results):
        if not all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0 for value in explicit):
            raise ValueError("explicit natural weights must be finite, positive, and present on every episode")
        return [float(value) for value in explicit]
    counts: dict[str, int] = defaultdict(int)
    for result in results:
        counts[_source(result)] += 1
    if all(source in SOURCE_SHARES for source in counts):
        return [SOURCE_SHARES[_source(result)] / counts[_source(result)] for result in results]
    # Mixing unrecognized sources into a defined source prior would invent mass.
    return [1.0 for _ in results]


def aggregate(stats: list[dict[str, Any]], weights: list[float], indices: Iterable[int] | None = None) -> dict[str, Any]:
    """Aggregate fixed weights; duplicate indices implement bootstrap clusters."""
    chosen = list(range(len(stats))) if indices is None else list(indices)
    mass = sum(weights[index] for index in chosen)
    keys = ("loss", "wrong", "automatic", "ask", "submits", "clicks", "hit_at_1", "hit_at_4",
            "ranking_hit_at_1", "ranking_hit_at_4", "episode_wrong", "completion_within_budget")
    sums = {key: sum(weights[index] * stats[index][key] for index in chosen) for key in keys}
    return {"loss": _ratio(sums["loss"], mass),
            "loss_per_submit": _ratio(sums["loss"], sums["submits"]),
            "wrong_all": _ratio(sums["wrong"], sums["submits"]),
            "wrong_sends": _ratio(sums["wrong"], sums["automatic"]),
            "coverage": _ratio(sums["automatic"], sums["submits"]),
            "hit_at_1": _ratio(sums["hit_at_1"], sums["ask"]),
            "hit_at_4": _ratio(sums["hit_at_4"], sums["ask"]),
            "ranking_hit_at_1": _ratio(sums["ranking_hit_at_1"], sums["submits"]),
            "ranking_hit_at_4": _ratio(sums["ranking_hit_at_4"], sums["submits"]),
            "episode_wrong_rate": _ratio(sums["episode_wrong"], mass),
            "clicks": _ratio(sums["clicks"], mass),
            "completion_within_budget": _ratio(sums["completion_within_budget"], mass)}


def percentile(values: list[float], probability: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = probability * (len(ordered) - 1)
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def group_indices(results: list[dict[str, Any]]) -> list[list[int]]:
    groups: dict[str, list[int]] = defaultdict(list)
    for index, result in enumerate(results):
        groups[str(result["group"])].append(index)
    return [groups[group] for group in sorted(groups)]


def bootstrap_intervals(results: list[dict[str, Any]], stats: list[dict[str, Any]],
                        weights: list[float], replicates: int, seed: int) -> dict[str, Any]:
    groups = group_indices(results)
    values: dict[str, list[float]] = {key: [] for key in METRICS}
    rng = random.Random(seed)
    for _ in range(replicates if groups else 0):
        sampled = [index for _ in groups for index in rng.choice(groups)]
        report = aggregate(stats, weights, sampled)
        for key, value in report.items():
            if value is not None:
                values[key].append(value)
    return {key: {"low": percentile(samples, .025), "high": percentile(samples, .975),
                  "valid_replicates": len(samples)} for key, samples in values.items()}


def _summary(results: list[dict[str, Any]], stats: list[dict[str, Any]],
             bootstrap: int, seed: int,
             weights_by_mix: dict[str, list[float]] | None = None) -> dict[str, Any]:
    counts = {key: sum(item[key] for item in stats) for key in
              ("loss", "submits", "wrong", "automatic", "ask", "clicks", "needless_ask", "consequential_wrong")}
    counts.update(episodes=len(results), groups=len(group_indices(results)),
                  episodes_with_wrong=sum(item["episode_wrong"] for item in stats),
                  completed=sum(item["completion"] for item in stats),
                  completed_within_budget=sum(item["completion_within_budget"] for item in stats))
    report: dict[str, Any] = {"counts": counts}
    for mix in ("natural", "stress"):
        weights = weights_by_mix[mix] if weights_by_mix is not None else episode_weights(results, mix)
        report[mix] = aggregate(stats, weights)
        if bootstrap:
            report[mix]["ci95"] = bootstrap_intervals(results, stats, weights, bootstrap, seed)
    return report


def evaluate(results: Iterable[dict[str, Any]], bootstrap: int = 2000, seed: int = 7) -> dict[str, Any]:
    """Return aggregate-only metrics, slices, 95% group CIs and cost sensitivity.

    Undefined ratios and intervals are JSON null, never NaN. Every reporting
    slice is independently cluster-resampled. Families/slices with fewer than 40
    episodes or groups, and flows with fewer than 60, are explicitly exploratory.
    """
    if not isinstance(bootstrap, int) or bootstrap < 0:
        raise ValueError("bootstrap must be a nonnegative integer")
    results = list(results)
    _validate_results(results)
    stats = [episode_score(result) for result in results]
    weights_by_mix = {mix: episode_weights(results, mix) for mix in ("natural", "stress")}
    report = _summary(results, stats, bootstrap, seed, weights_by_mix)
    report["exploratory"] = len(results) < 40 or report["counts"]["groups"] < 40
    observed_sources = sorted({_source(result) for result in results})
    explicit = any("natural_weight" in result or "weight" in result for result in results)
    source_prior = bool(results) and all(source in SOURCE_SHARES for source in observed_sources)
    report["method"] = {
        "loss_unit": "mean total episode click-equivalent loss; loss_per_submit also reported",
        "natural": "explicit episode weights" if explicit else (
            "spec source shares, renormalized over observed sources" if source_prior else "observed episode mix"),
        "natural_limitation": "No measured Router message-family prevalence supplied; this is not a deployment estimate.",
        "source_shares": SOURCE_SHARES,
        "observed_sources": observed_sources,
        "missing_sources": sorted(set(SOURCE_SHARES) - set(observed_sources)),
        "stress": "equal mass per primary message family; equal episode weights within family",
        "bootstrap": {"replicates": bootstrap, "seed": seed, "unit": "group", "weights": "fixed before resampling"},
        "hit_at": "intended target in actual ask-card order; denominator asked submits",
        "clicks": "observed pick events or explicit event clicks, counted once",
        "completion_budget": "episode click_budget, default two routing clicks per submit",
    }
    buckets: dict[str, dict[str, list[int]]] = {kind: defaultdict(list) for kind in ("family", "flow", "slice")}
    for index, result in enumerate(results):
        tags = result.get("tags", {})
        buckets["family"][primary(result)].append(index)
        buckets["flow"][str(tags.get("flow") or "unknown")].append(index)
        for name in sorted(set(tags.get("slices", []))):
            buckets["slice"][str(name)].append(index)
    for kind, members in buckets.items():
        report[f"by_{kind}"] = {}
        for name, indices in sorted(members.items()):
            subset = [results[index] for index in indices]
            slice_weights = {mix: [weights[index] for index in indices]
                             for mix, weights in weights_by_mix.items()}
            summary = _summary(subset, [stats[index] for index in indices], bootstrap, seed, slice_weights)
            minimum = 60 if kind == "flow" else 40
            summary["exploratory"] = len(subset) < minimum or summary["counts"]["groups"] < minimum
            summary["exploratory_minimum"] = minimum
            report[f"by_{kind}"][name] = summary
    report["sensitivity"] = {}
    for cost in (10, 25, 100):
        cost_stats = [episode_score(result, wrong_cost=cost) for result in results]
        report["sensitivity"][str(cost)] = _summary(results, cost_stats, bootstrap, seed, weights_by_mix)
    return report


def load_results(path: str | Path) -> list[dict[str, Any]]:
    """Read a development trace file; sealed storage has one evaluator only."""
    path = Path(path)
    resolved, sealed = path.resolve(), SEALED.resolve()
    if resolved == sealed or sealed in resolved.parents:
        raise ValueError("sealed files may only be evaluated with v2.run.seal")
    with path.open(encoding="utf-8") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate Router v2 trace scoring (group-clustered intervals).")
    parser.add_argument("results", help="episode replay results JSONL")
    parser.add_argument("--bootstrap", type=int, default=2000, help="group bootstrap replicates (default: 2000)")
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    print(json.dumps(evaluate(load_results(args.results), args.bootstrap, args.seed), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
