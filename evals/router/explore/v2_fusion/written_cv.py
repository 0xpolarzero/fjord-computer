"""Secondary check: written / scripted dev moments, out of fold. Folds are by group over real + written together, so a
variant that trains on written episodes (mix) never sees the test group's written moments either. Real-only variants
train on real only; the sureness is always fitted on real only.

python3 -m explore.v2_fusion.written_cv NAME ...
"""
import collections
import sys

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_fusion import experiments as X
from explore.v2_fusion import policy as Pol


def run(real, written, name, k=10, seed=0):
    var = X.VARIANTS[name]
    wt = X.EXTRA.get(name, 0.0)
    groups = sorted({x.group for x in real} | {x.group for x in written})
    rng = np.random.default_rng(seed)
    rng.shuffle(groups)
    gi = {g: i % k for i, g in enumerate(groups)}
    preds = {}
    for f in range(k):
        tr_r = [x for x in real if gi[x.group] != f]
        tr_w = [x for x in written if gi[x.group] != f] if wt > 0 else []
        for x in tr_w:
            x.weight = wt
        if var.rank is None:
            w, lam = C.W0, None
        else:
            w, lam = C._fit_rank_cv(tr_r + tr_w, var.rank, seed=seed)
        v = C.V0
        if var.sure is not None:
            spec = None if var.rank is None else {**var.rank, "lam_inner": lam}
            rows = []
            for x, P in zip(tr_r, C._oof_P(tr_r, spec, seed=seed, extra=tr_w)):
                top, cf = C.moment_feats(x, P)
                rows.append((cf, C.correct(x, top)))
            v = C.fit_sure(rows, var.sure["feats"], C.V0, var.sure.get("lam", 1.0))
        for i, x in enumerate(written):
            if gi[x.group] == f:
                P = C.probs(x, w)
                top, cf = C.moment_feats(x, P)
                preds[i] = dict(top=top, P=P, s=C.sure_of(cf, v), ok=C.correct(x, top))
    return [preds[i] for i in range(len(written))]


def main(names):
    real = C.load()
    written = C.load(sources=("real-rewrite", "goal", "scripted"))
    by = collections.defaultdict(list)
    for i, x in enumerate(written):
        by[x.source].append(i)
    base = [dict(top=t, P=P, s=C.sure_of(cf, C.V0), ok=C.correct(x, t))
            for x in written for P in [C.probs(x, C.W0)] for t, cf in [C.moment_feats(x, P)]]
    rows = {"shipped": base}
    for n in names:
        rows[n] = run(real, written, n)
    print("| variant | " + " | ".join(f"{s} top1 / loss / wrong%" for s in sorted(by)) + " |")
    print("|---|" + "---|" * len(by))
    for n, pr in rows.items():
        cells = []
        for s in sorted(by):
            idx = by[s]
            xs = [written[i] for i in idx]
            ps = [pr[i] for i in idx]
            o = Pol.summarize(Pol.run(xs, ps))
            cells.append(f"{100 * np.mean([p['ok'] for p in ps]):.1f} / {o['loss']:.2f} / {100 * o['wrong']:.1f}")
        print(f"| {n} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main(sys.argv[1:])
