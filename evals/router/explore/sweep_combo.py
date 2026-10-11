"""Sweep make_recent_policy on saved runs: utility (right − λ·wrong) averaged over tuning sets; report the held-back set.
python3 -m explore.sweep_combo FORMAT [--lam 5] [--tune synth,style,realA] [--test realB]"""
import argparse
import itertools

import bench
import run
from explore import combo


def rows_for(fmt, s, cases):
    ids = {c["id"] for c in cases}
    whole = {"realA": "real", "realB": "real"}.get(s, s)
    return [r for r in run.load(f"{fmt}@{whole}") if r["id"] in ids]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fmt")
    ap.add_argument("--lam", type=float, default=5)
    ap.add_argument("--tune", default="synth,style,realA")
    ap.add_argument("--test", default="realB")
    a = ap.parse_args()
    sets = {}
    for s in a.tune.split(",") + a.test.split(","):
        cases = bench.load_set(s)
        sets[s] = (cases, rows_for(a.fmt, s, cases))
    grid = itertools.product((3, 5, 99), (0.8, 0.9), (2, 3, 99), (0.6, 0.8), (0.5, 0.6), (0.3, 0.4, 0.5), (0.6, 0.7, 0.8))
    results = []
    for near, far, card_near, newb, a_next, agree, p_min in grid:
        pol = combo.make_recent_policy(near=near, far_bar=far, card_near=card_near, new_bar_recent=newb, a=a_next,
                                       agree=agree, base={"p_min": p_min})
        scores = {s: bench.score(c, r, pol) for s, (c, r) in sets.items()}
        util = sum((scores[s]["right"] - a.lam * scores[s]["wrong"]) / scores[s]["n"] for s in a.tune.split(",")) / len(a.tune.split(","))
        results.append((util, dict(near=near, far_bar=far, card_near=card_near, new_bar_recent=newb, a=a_next, agree=agree, p_min=p_min), scores))
    results.sort(key=lambda x: -x[0])
    for util, params, scores in results[:8]:
        print(f"utility {100 * util:5.1f} {params}")
        for s, t in scores.items():
            print("    " + bench.line(s, t))


if __name__ == "__main__":
    main()
