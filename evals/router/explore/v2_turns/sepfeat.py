"""A8 as its own feature: base moments plus f_rsaid = a running session's f_said read on its last completed answer
(variant `prev`, 0 for sessions not running), its weight alone fitted (shipped weights fixed) in 10-fold CV grouped by
`group`; optionally the four lexical weights free too. Paired group bootstrap vs shipped.

python3 -m explore.v2_turns.sepfeat [--seeds 0,1,2]
"""
import argparse
import sys

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_turns import analyze as A
from explore.v2_turns import refit as R


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="0,1,2")
    a = ap.parse_args()
    mb, mv = A.moments("base"), A.moments("prev")
    keys = sorted(set(mb) & set(mv))
    data = [mb[k] for k in keys]
    for k, x in zip(keys, data):
        xv = mv[k]
        running = {s["id"] for s in x.m["state"]["sessions"] if s.get("running")}
        for d, f in x.fs.items():
            if f.get("sess"):
                f["f_rsaid"] = xv.fs[d].get("f_said", 0) if d in running else 0.0
    run = np.array([A.slices(x)["target running"] for x in data])
    anyrun = np.array([A.slices(x)["any running"] for x in data])
    ship = R.arrays(data, [A.per_moment(x) for x in data])
    feats = C.RANK_FEATS + ["f_rsaid"]
    for seed in map(int, a.seeds.split(",")):
        for name, free in (("f_rsaid alone", {"f_rsaid"}), ("f_rsaid + 4 lexical", {"f_rsaid", *R.LEX})):
            preds, info = C.run_variant(data, C.Variant(name, dict(feats=feats, free=free, lams=R.LAMS)), seed=seed)
            r = R.arrays(data, preds)
            p, pr, pa = C.paired(data, ship, r), R.slice_paired(data, ship, r, run), R.slice_paired(data, ship, r, anyrun)
            w = np.mean([i["w"]["f_rsaid"] for i in info])
            print(f"| seed {seed} {name} (w f_rsaid {w:+.2f}) | top-1 {R.fmt(p, 'top1')} | hit@4 {R.fmt(p, 'hit4')} | "
                  f"AUROC {R.fmt(p, 'auroc')} | target running {R.fmt(pr, 'top1')} | any running {R.fmt(pa, 'top1')} |")


if __name__ == "__main__":
    main()
