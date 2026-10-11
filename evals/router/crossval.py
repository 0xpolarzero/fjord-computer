"""Choose a policy's settings on one case set (best right sends within a wrong-send budget), score them on the other.

python3 crossval.py FORMAT [FORMAT...] [--budget 2] [--families lead,risk,guard,gates]
Expects runs/FORMAT.jsonl (main cases) and runs/FORMAT-ho.jsonl (held-out)."""
import argparse

import analyze
import run


def best(cases, rows, family, budget):
    scored = []
    for params in analyze.FAMILIES[family]:
        s = run.score(cases, rows, analyze.policy(family, **params))
        if s["wrong"] <= budget:
            scored.append((s["right"], -s["wrong"], params))
    return max(scored, key=lambda x: (x[0], x[1]))[2] if scored else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("formats", nargs="+")
    ap.add_argument("--budget", type=float, default=2.0)
    ap.add_argument("--families", default="lead,risk,guard,gates")
    a = ap.parse_args()
    main_cases, ho_cases = run.load_cases(), run.load_cases("heldout/*.jsonl")
    for fmt in a.formats:
        sets = {"main": (main_cases, run.load(fmt)), "ho": (ho_cases, run.load(fmt + "-ho"))}
        for fam in a.families.split(","):
            for train, test in (("main", "ho"), ("ho", "main")):
                params = best(*sets[train], fam, a.budget)
                if params is None:
                    continue
                s = run.score(*sets[test], analyze.policy(fam, **params))
                t = run.score(*sets[train], analyze.policy(fam, **params))
                print(f"{fmt:12} {fam:6} tuned on {train:4} → {test:4}: right={s['right']:5}% wrong={s['wrong']:4}% "
                      f"miss={s['miss']:5}%   (on {train}: right={t['right']}% wrong={t['wrong']}%)")


if __name__ == "__main__":
    main()
