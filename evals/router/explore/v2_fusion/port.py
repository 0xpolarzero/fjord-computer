"""Fit a variant on all dev real moments (the weights to port, rounded to 2 decimals as Swift carries them) and check it
on the written/scripted dev moments it never saw: top-1 per source, and the shipped decision's outcomes per source.

python3 -m explore.v2_fusion.port NAME
"""
import collections
import json
import sys

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_fusion import experiments as X
from explore.v2_fusion import policy as Pol


def preds_with(data, w, v):
    out = []
    for x in data:
        P = C.probs(x, w)
        top, cf = C.moment_feats(x, P)
        out.append(dict(top=top, P=P, s=C.sure_of(cf, v), ok=C.correct(x, top)))
    return out


def main(name):
    real = C.load()
    w, v, lam = C.fit_full(real, X.VARIANTS[name])
    w = {k: round(float(x), 2) for k, x in w.items()}
    v = {k: round(float(x), 2) for k, x in v.items()}
    print("lambda", lam)
    print("weights", json.dumps({k: x for k, x in w.items()}))
    print("changed", json.dumps({k: (C.W0.get(k, 0), x) for k, x in w.items() if abs(C.W0.get(k, 0) - x) >= 0.01}))
    print("sureness", json.dumps(v))
    other = C.load(sources=("real-rewrite", "goal", "scripted"))
    by = collections.defaultdict(list)
    for x in other:
        by[x.source].append(x)
    print("| source | n | shipped top1 | variant top1 | shipped loss / wrong% | variant loss / wrong% |")
    print("|---|---|---|---|---|---|")
    for src, xs in sorted(by.items()):
        a = preds_with(xs, C.W0, C.V0)
        b = preds_with(xs, w, v)
        oa, ob = Pol.run(xs, a), Pol.run(xs, b)
        sa, sb = Pol.summarize(oa), Pol.summarize(ob)
        ta = sum(p["ok"] for p in a) / len(xs)
        tb = sum(p["ok"] for p in b) / len(xs)
        print(f"| {src} | {len(xs)} | {100 * ta:.1f} | {100 * tb:.1f} | {sa['loss']:.2f} / {100 * sa['wrong']:.1f} | "
              f"{sb['loss']:.2f} / {100 * sb['wrong']:.1f} |")
    # in-sample sanity on real with the rounded weights (not an honest estimate)
    a, b = preds_with(real, C.W0, C.V0), preds_with(real, w, v)
    print("real in-sample top1", sum(p["ok"] for p in a) / len(real), sum(p["ok"] for p in b) / len(real))


if __name__ == "__main__":
    main(sys.argv[1])
