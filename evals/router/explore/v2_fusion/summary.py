"""One line per variant: Δ vs a base (default shipped) with paired group-bootstrap 95% CIs, from cached OOF predictions.

python3 -m explore.v2_fusion.summary [--base NAME] [--seed S] NAME ...
"""
import argparse
import pickle
import sys

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_fusion import experiments as X

KEYS = ["top1", "hit4", "auroc", "risk30", "risk40", "risk50", "cov5", "brier"]


def cell(k, r):
    a, b, d, lo, hi = r
    f = (lambda v: f"{v:+.3f}") if k in ("auroc", "brier") else (lambda v: f"{100 * v:+.1f}")
    star = "*" if (lo > 0 or hi < 0) else ""
    return f"{f(d)} [{f(lo)},{f(hi)}]{star}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+")
    ap.add_argument("--base", default="shipped")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--markdown", action="store_true")
    a = ap.parse_args()
    data = C.load()
    arr = {}
    for n in [a.base] + a.names:
        preds, _ = X.oof(data, n, seed=a.seed)
        arr[n] = C.arrays(data, preds)
    base = C.metrics(**arr[a.base])
    print(f"| variant | " + " | ".join(KEYS) + " |")
    print("|---|" + "---|" * len(KEYS))
    print(f"| {a.base} (abs) | " + " | ".join(
        (f"{base[k]:.3f}" if k in ("auroc", "brier") else f"{100 * base[k]:.1f}") for k in KEYS) + " |")
    for n in a.names:
        r = C.paired(data, arr[a.base], arr[n])
        print(f"| {n} | " + " | ".join(cell(k, r[k]) for k in KEYS) + " |")


if __name__ == "__main__":
    main()
