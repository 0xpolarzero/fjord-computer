"""Split labelled episodes into dev, calib and sealed by group (BENCHMARK.md, "Splits and sealing").

    python3 v2/build/split.py [--inputs v2/data/episodes/labelled/*.jsonl] [--seed 20261011]

A group is a source session-day: every episode drawn from it (real, scripted, written, and a scripted sibling with its
base) lands in the same split, so nothing tuned on dev has a near-copy in sealed. Sealed is filled first, group by
group, preferring groups that cover message families and flows still short of their quota (40 per family, 60 per
flow); then calib takes its share, and dev the rest. Writes v2/data/episodes/{dev,calib,sealed}/episodes.jsonl and
prints only counts per split, family and flow (no episode content).
"""
import argparse
import collections
import glob
import json
import pathlib
import random

V2 = pathlib.Path(__file__).resolve().parents[1]
SHARES = {"sealed": 0.4, "calib": 0.2}
FAMILY_QUOTA, FLOW_QUOTA = 40, 60


def units(episodes):
    """Episodes per group; a sibling joins its base's group."""
    group_of = {e["id"]: e["group"] for e in episodes}
    out = collections.defaultdict(list)
    for e in episodes:
        base = e.get("base") or (e.get("provenance") or {}).get("base")
        out[group_of.get(base, e["group"])].append(e)
    return out


def family(e):
    return (e.get("tags") or {}).get("primary") or e.get("family")


def flow(e):
    return (e.get("tags") or {}).get("flow") or "single"


def split(episodes, seed=20261011):
    groups = units(episodes)
    order = sorted(groups)
    random.Random(seed).shuffle(order)
    total = len(episodes)
    assigned, counts = {}, {name: 0 for name in ("sealed", "calib", "dev")}
    have = {"family": collections.Counter(), "flow": collections.Counter()}

    # A thin family can't give sealed 40 and leave dev any: its quota is at most half of what exists.
    totals = {"family": collections.Counter(map(family, episodes)), "flow": collections.Counter(map(flow, episodes))}
    quota = {"family": lambda k: min(FAMILY_QUOTA, totals["family"][k] // 2),
             "flow": lambda k: min(FLOW_QUOTA, totals["flow"][k] // 2)}

    def need(group):
        members = groups[group]
        return sum(have["family"][family(e)] < quota["family"](family(e)) for e in members) + \
               sum(have["flow"][flow(e)] < quota["flow"](flow(e)) for e in members)

    remaining = list(order)
    while remaining and counts["sealed"] < SHARES["sealed"] * total:
        # The group that fills the most unmet quota; ties keep the seeded order.
        best = max(remaining, key=lambda g: (need(g) / len(groups[g]) if need(g) else 0, -remaining.index(g)))
        remaining.remove(best)
        assigned[best] = "sealed"
        counts["sealed"] += len(groups[best])
        for e in groups[best]:
            have["family"][family(e)] += 1
            have["flow"][flow(e)] += 1
    for group in remaining:
        name = "calib" if counts["calib"] < SHARES["calib"] * total else "dev"
        assigned[group] = name
        counts[name] += len(groups[group])
    return {name: [e for g in order if assigned[g] == name for e in groups[g]] for name in ("dev", "calib", "sealed")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", nargs="*", default=[str(V2 / "data/episodes/labelled/*.jsonl")])
    parser.add_argument("--seed", type=int, default=20261011)
    parser.add_argument("--dry-run", action="store_true", help="print the counts, write nothing")
    args = parser.parse_args()
    episodes = [json.loads(line) for pattern in args.inputs for path in sorted(glob.glob(pattern))
                for line in open(path) if line.strip()]
    parts = split(episodes, args.seed)
    report = {}
    for name, members in parts.items():
        if not args.dry_run:
            folder = V2 / "data/episodes" / name
            folder.mkdir(parents=True, exist_ok=True)
            with (folder / "episodes.jsonl").open("w") as f:
                f.writelines(json.dumps(e, ensure_ascii=False) + "\n" for e in members)
        report[name] = {"episodes": len(members), "groups": len({e["group"] for e in members}),
                        "submits": sum(ev["kind"] == "submit" for e in members for ev in e["events"]),
                        "sources": dict(collections.Counter((e.get("provenance") or {}).get("source") for e in members))}
    sealed = parts["sealed"]
    report["sealed_short"] = {
        "families": {k: v for k, v in collections.Counter(map(family, sealed)).items() if v < FAMILY_QUOTA},
        "flows": {k: v for k, v in collections.Counter(map(flow, sealed)).items() if v < FLOW_QUOTA}}
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
