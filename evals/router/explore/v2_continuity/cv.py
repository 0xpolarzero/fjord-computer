"""Grouped cross-validated refit of a few fusion weights around the shipped ones, scored by free-running replay.

python3 -m explore.v2_continuity.cv NAME --fmt combo-o-told --free nxt,told0,nxt_t [--recal] [--l2 1] [--folds 5]

The shipped Swift weights stay fixed; only the `--free` features get a weight change (a new feature starts at 0),
fitted by conditional-logit NLL on real dev submits with an L2 penalty toward the shipped value. `--recal` also refits
the sureness's bias and lPtop the same way (logistic, around the shipped values). Folds are by episode `group`; each
episode is replayed with the weights fitted without its group. Records for fitting come from out/<rec>.rec.pkl (the
free-running replay of the same format under shipped weights). Writes out/cv_<NAME>.jsonl and prints the weights
fitted on every fold and on all dev."""
import argparse
import json
import math
import pickle
import random
import sys

import numpy as np
from scipy.optimize import minimize

from explore.v2_continuity import told as T
from explore.v2_continuity.replay import OUT, Variant, load


def legacy(t):
    return t[8:] if t and t.startswith("session:") else t


def design(records, features, w0, free):
    rows = []
    for rec in records:
        if rec.get("source") != "real-moment":
            continue
        fs = features(rec["reading"], rec["case"])
        gold = legacy(rec["gold"]["intended"])
        if not fs or gold not in fs:
            continue
        ds = list(fs)
        X = np.array([[fs[d].get(k, 0.0) for k in free] for d in ds], float)
        off = np.array([sum(w0.get(k, 0.0) * v for k, v in fs[d].items()) for d in ds], float)
        y = np.array([d == gold for d in ds], float)
        rows.append((rec["group"], X, off, y))
    return rows


def fit_logit(rows, k, l2):
    def lg(b):
        L, G = l2 * b @ b / 2, l2 * b.copy()
        for _, X, off, y in rows:
            s = off + X @ b
            s = s - s.max()
            e = np.exp(s)
            p = e / e.sum()
            L -= math.log(max((p * y).sum(), 1e-12))
            G += p @ X - y @ X
        return L, G
    return minimize(lg, np.zeros(k), jac=True, method="L-BFGS-B").x


def fit_recal(records, features, w, v0, final3, fusion, l2):
    """Deltas on the sureness's bias and lPtop (logistic around the shipped values)."""
    X, off, y = [], [], []
    for rec in records:
        if rec.get("source") != "real-moment":
            continue
        fs = features(rec["reading"], rec["case"])
        if not fs:
            continue
        P = fusion.probs(fs, w)
        top = max(P.items(), key=lambda x: x[1])[0]
        cf = final3.case_features(rec["reading"], rec["case"], fs, P)
        X.append([1.0, cf["lPtop"]])
        off.append(sum(v0.get(k, 0) * x for k, x in cf.items()))
        y.append(float(top == legacy(rec["gold"]["intended"])))
    X, off, y = np.array(X), np.array(off), np.array(y)

    def lg(b):
        z = off + X @ b
        p = 1 / (1 + np.exp(-z))
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + l2 * b @ b / 2
        return L, X.T @ (p - y) + l2 * b
    b = minimize(lg, np.zeros(2), jac=True, method="L-BFGS-B").x
    v = dict(v0)
    v["bias"] = v0.get("bias", 0) + b[0]
    v["lPtop"] = v0.get("lPtop", 0) + b[1]
    return v


def weights_for(records, var, free, l2, recal):
    w0, v0 = var.shipped
    features = var.mods[4].features
    rows = design(records, features, w0, free)
    b = fit_logit(rows, len(free), l2) if free else np.zeros(0)
    w = dict(w0)
    for k, x in zip(free, b):
        w[k] = round(w0.get(k, 0.0) + float(x), 2)
    v = dict(v0)
    if recal:
        v = fit_recal(records, features, w, v0, var.mods[6], var.mods[5], l2)
        v = {k: round(float(x), 2) for k, x in v.items()}
    return w, v


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("name")
    p.add_argument("--fmt", default="combo-o-told")
    p.add_argument("--rec", help="records file stem in out/ (default: told for combo-o-told, shipped for combo-o)")
    p.add_argument("--free", default="")
    p.add_argument("--recal", action="store_true")
    p.add_argument("--l2", type=float, default=1.0)
    p.add_argument("--folds", type=int, default=5)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--max-calls", type=int, default=0)
    a = p.parse_args(argv)
    free = [f for f in a.free.split(",") if f]
    rec = a.rec or ("told" if a.fmt == "combo-o-told" else "shipped")
    records = pickle.load(open(OUT / f"{rec}.rec.pkl", "rb"))
    var = Variant(a.fmt, trans=True, max_calls=a.max_calls)
    eps = load()
    groups = sorted({e["group"] for e in eps})
    rng = random.Random(a.seed)
    rng.shuffle(groups)
    fold_of = {g: i % a.folds for i, g in enumerate(groups)}
    fitted = {}
    for f in range(a.folds):
        train = [r for r in records if fold_of.get(r["group"]) != f]
        fitted[f] = weights_for(train, var, free, a.l2, a.recal)
    full = weights_for(records, var, free, a.l2, a.recal)
    results = []
    for e in eps:
        var.set_weights(*fitted[fold_of[e["group"]]])
        results.append(var.play(e))
    (OUT / f"cv_{a.name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    w0, v0 = var.shipped
    show = lambda w, base: {k: w[k] for k in sorted(w) if abs(w[k] - base.get(k, 0)) > 1e-9}
    report = {"name": a.name, "free": free, "recal": a.recal, "new_calls": var.system.new_calls,
              "folds": {f: [show(w, w0), show(v, v0)] for f, (w, v) in fitted.items()},
              "all_dev": [show(full[0], w0), show(full[1], v0)]}
    (OUT / f"cv_{a.name}.weights.json").write_text(json.dumps(report, indent=1))
    print(a.name, "new_calls", var.system.new_calls, "all_dev", json.dumps(report["all_dev"]))


if __name__ == "__main__":
    main()
