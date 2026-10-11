"""Pooled k-fold cross-validation: both case sets, settings chosen on k-1 folds by utility (right − λ·wrong, a needless
ask costing nothing beyond the right send it misses), scored on the fold left out. Repeated over shuffles.

python3 cv.py FORMAT [FORMAT...] [--lam 5] [--folds 5] [--repeats 4] [--families ...]"""
import argparse
import random
import statistics

import analyze
import run


def per_case(cases, rows, pol):
    by = {c["id"]: c for c in cases}
    out = {}
    for row in rows:
        s = run.score([by[row["id"]]], [row], pol)
        out.setdefault(row["id"], []).append((s["right"], s["wrong"], s["miss"]))
    return {k: tuple(sum(x[i] for x in v) / len(v) for i in range(3)) for k, v in out.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("formats", nargs="+")
    ap.add_argument("--lam", type=float, default=5)
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--repeats", type=int, default=4)
    ap.add_argument("--families", default="lead,risk,guard,gates")
    a = ap.parse_args()
    cases = run.load_cases() + run.load_cases("heldout/*.jsonl")
    for fmt in a.formats:
        rows = run.load(fmt) + run.load(fmt + "-ho")
        for fam in a.families.split(","):
            grid = analyze.FAMILIES[fam]
            tables = [per_case(cases, rows, analyze.policy(fam, **p)) for p in grid]
            ids = sorted(tables[0])
            res = []
            for rep in range(a.repeats):
                rng = random.Random(rep)
                order = ids[:]
                rng.shuffle(order)
                for f in range(a.folds):
                    test = set(order[f::a.folds])
                    train = [i for i in ids if i not in test]

                    def util(t, sel):
                        return sum(t[i][0] - a.lam * t[i][1] for i in sel) / len(sel)
                    k = max(range(len(grid)), key=lambda j: util(tables[j], train))
                    t = tables[k]
                    res.append((statistics.mean(t[i][0] for i in test), statistics.mean(t[i][1] for i in test),
                                statistics.mean(t[i][2] for i in test), util(t, test)))
            m = [statistics.mean(x[j] for x in res) for j in range(4)]
            sd = statistics.pstdev(x[3] for x in res)
            print(f"{fmt:12} {fam:6} λ={a.lam:<3} test: right={m[0]:5.1f}% wrong={m[1]:4.1f}% miss={m[2]:5.1f}% "
                  f"utility={m[3]:5.1f} (±{sd:.1f} across folds)")


if __name__ == "__main__":
    main()
