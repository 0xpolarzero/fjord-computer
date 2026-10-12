"""A8 refit: the four lexical weights (f_said, f_old, f_you, f_title) refitted in 10-fold CV grouped by `group` on dev
real moments, for base turns and for a variant's turns, every other weight shipped. Paired group bootstrap against
shipped-on-base and against refit-on-base (the fair comparison: same procedure, only the turn boundary differs).

python3 -m explore.v2_turns.refit VARIANT [--seeds 0,1,2] [--sure]
"""
import argparse
import sys

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_turns import analyze as A

LEX = ["f_said", "f_old", "f_you", "f_title"]
LAMS = [0.3, 1.0, 3.0, 10.0, 30.0]


def arrays(data, preds):
    return {"s": np.array([p["s"] for p in preds]), "ok": np.array([p["ok"] for p in preds], bool),
            "hit": np.array([x.m["gold"]["intended"] in C.card(x, p["P"]) for x, p in zip(data, preds)], bool)}


def slice_paired(data, a, b, mask):
    idx = np.nonzero(mask)[0]
    sub = [data[i] for i in idx]
    pick = lambda d: {k: v[idx] for k, v in d.items()}
    return C.paired(sub, pick(a), pick(b))


def fmt(r, k, scale=100):
    A_, B_, d, lo, hi = r[k]
    star = "*" if lo > 0 or hi < 0 else ""
    return f"{scale * A_:.1f} -> {scale * B_:.1f}: {scale * d:+.1f} [{scale * lo:+.1f}, {scale * hi:+.1f}]{star}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variant")
    ap.add_argument("--seeds", default="0,1,2")
    ap.add_argument("--sure", action="store_true", help="refit the sureness too (shipped features)")
    a = ap.parse_args()
    mb, mv = A.moments("base"), A.moments(a.variant)
    keys = sorted(set(mb) & set(mv))
    db, dv = [mb[k] for k in keys], [mv[k] for k in keys]
    run = np.array([A.slices(x)["target running"] for x in db])
    anyrun = np.array([A.slices(x)["any running"] for x in db])
    sure = dict(feats=C.CASE_FEATS, lam=1.0) if a.sure else None
    spec = dict(feats=C.RANK_FEATS, free=set(LEX), lams=LAMS)
    ship = arrays(db, [A.per_moment(x) for x in db])
    plain = arrays(dv, [A.per_moment(x) for x in dv])
    for seed in map(int, a.seeds.split(",")):
        pb, ib = C.run_variant(db, C.Variant("lex-base", spec, sure), seed=seed)
        pv, iv = C.run_variant(dv, C.Variant("lex-" + a.variant, spec, sure), seed=seed)
        if not a.sure:  # shipped sureness on the refit P (no intent table here: dev real has no intent gold)
            pass
        rb, rv = arrays(db, pb), arrays(dv, pv)
        print(f"\n### seed {seed}  (fold weights base: " +
              ", ".join(f"{k} {np.mean([i['w'][k] for i in ib]):.2f}" for k in LEX) + "; variant: " +
              ", ".join(f"{k} {np.mean([i['w'][k] for i in iv]):.2f}" for k in LEX) + ")")
        for name, x, y in (("refit-base vs shipped", ship, rb), ("refit-variant vs shipped", ship, rv),
                           ("refit-variant vs refit-base", rb, rv), ("plain variant vs shipped", ship, plain)):
            r = C.paired(db, x, y)
            rr = slice_paired(db, x, y, run)
            ra = slice_paired(db, x, y, anyrun)
            print(f"| {name} | top-1 {fmt(r, 'top1')} | hit@4 {fmt(r, 'hit4')} | AUROC {fmt(r, 'auroc')} | "
                  f"top-1 target running {fmt(rr, 'top1')} | top-1 any running {fmt(ra, 'top1')} |")


if __name__ == "__main__":
    main()
