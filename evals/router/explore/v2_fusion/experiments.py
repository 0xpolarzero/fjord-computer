"""A3 / A4 / A8 variants on top of shipped final3, grouped 10-fold CV on dev real moments, paired group bootstrap.

python3 -m explore.v2_fusion.experiments [NAME ...]     (default: every variant; OOF predictions cached in /tmp)
"""
import json
import pickle
import sys
import time
from pathlib import Path

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C

CACHE = Path("/tmp/v2_fusion_oof")
CACHE.mkdir(exist_ok=True)
LAMS = [0.3, 1.0, 3.0, 10.0, 30.0]
WIDE = [0.03, 0.1, 0.3, 1.0, 3.0, 10.0]
RF = C.RANK_FEATS
VF = C.CASE_FEATS
A4_RANK_RAW = ["r_f_said", "r_f_old", "r_f_you", "r_f_title"]
A4_RANK_SCALED = ["s_f_said", "s_f_old", "s_f_you", "s_f_title"]
A4_SURE = ["top_lbm", "bm_best", "bmgap_raw", "top_cov"]
A3_SURE_JEV = ["jconf", "jent", "jmargin", "jsmargin"]
A3_SURE_SIB = ["top_famshare", "top_sib"]
VSURE = dict(feats=VF, lam=1.0)


def V(name, rank=None, sure=None):
    return C.Variant(name, rank, sure)


VARIANTS = {
    "shipped": V("shipped"),
    # A8: refit on real dev
    "A8.sure": V("A8.sure", None, VSURE),
    "A8.full": V("A8.full", dict(feats=RF, lams=LAMS), VSURE),
    # A4: BM25 absolute strength (ranking: shipped weights frozen, only the new weights free)
    "A4.raw": V("A4.raw", dict(feats=RF + A4_RANK_RAW, free=set(A4_RANK_RAW), lams=[1.0]), VSURE),
    "A4.scaled": V("A4.scaled", dict(feats=RF + A4_RANK_SCALED, free=set(A4_RANK_SCALED), lams=[1.0]), VSURE),
    "A4.lbm": V("A4.lbm", dict(feats=RF + ["lbm"], free={"lbm"}, lams=[1.0]), VSURE),
    "A4.cov": V("A4.cov", dict(feats=RF + ["cov"], free={"cov"}, lams=[1.0]), VSURE),
    "A4.sure": V("A4.sure", None, dict(feats=VF + A4_SURE, lam=1.0)),
    # A3: Jev signals already paid for
    "A3.fam": V("A3.fam", dict(feats=RF + ["lpfam", "sib"], free={"lpfam", "sib"}, lams=[1.0]), VSURE),
    "A3.sure_jev": V("A3.sure_jev", None, dict(feats=VF + A3_SURE_JEV, lam=1.0)),
    "A3.sure_sib": V("A3.sure_sib", None, dict(feats=VF + A3_SURE_SIB, lam=1.0)),
    "A3.sure_all": V("A3.sure_all", None, dict(feats=VF + A3_SURE_JEV + A3_SURE_SIB, lam=1.0)),
    # A8 full with A4 raw free on top (ranking fully refit)
    "A8+A4.raw": V("A8+A4.raw", dict(feats=RF + A4_RANK_RAW, lams=LAMS), VSURE),
    "A8.wide": V("A8.wide", dict(feats=RF, lams=WIDE), VSURE),
    "A8.runfixed": V("A8.runfixed", dict(feats=RF, free=set(RF) - {"run"}, lams=LAMS), VSURE),
    "A8+lex": V("A8+lex", dict(feats=RF + ["lbm", "cov"], lams=LAMS), VSURE),
    "A8+sure": V("A8+sure", dict(feats=RF, lams=LAMS), dict(feats=VF + A4_SURE + A3_SURE_JEV, lam=1.0)),
    "A8+sure_a4": V("A8+sure_a4", dict(feats=RF, lams=LAMS), dict(feats=VF + A4_SURE, lam=1.0)),
    "A8+sure_a3": V("A8+sure_a3", dict(feats=RF, lams=LAMS), dict(feats=VF + A3_SURE_JEV, lam=1.0)),
    "A8+lex+sure_a4": V("A8+lex+sure_a4", dict(feats=RF + ["lbm", "cov"], lams=LAMS), dict(feats=VF + A4_SURE, lam=1.0)),
    # A8 with written dev episodes added to the ranking fit (what the shipped mix did): real+written, and written at 0.2
    "A8.mix": V("A8.mix", dict(feats=RF, lams=LAMS), VSURE),
    "A8.mix02": V("A8.mix02", dict(feats=RF, lams=LAMS), VSURE),
}
SESS = ["lp", "fin0", "fin1", "fin2", "run", "reply", "told0", "fin0u", "idle5u", "nxt", "f_said", "f_old", "f_you",
        "f_title"]
VARIANTS.update({
    # dev real has no intent gold and 20 new-session golds: keep those weights at shipped, refit the session side only
    "A8.sess": V("A8.sess", dict(feats=RF, free=set(SESS), lams=LAMS), VSURE),
    "A8.sess_nolp": V("A8.sess_nolp", dict(feats=RF, free=set(SESS) - {"lp"}, lams=LAMS), VSURE),
    "A8.sess+lex": V("A8.sess+lex", dict(feats=RF + ["lbm", "cov"], free=set(SESS) | {"lbm", "cov"}, lams=LAMS), VSURE),
    "A8.sess+sure_kind": V("A8.sess+sure_kind", dict(feats=RF, free=set(SESS), lams=LAMS),
                           dict(feats=VF + ["top_run", "top_told0", "top_nxt"], lam=1.0)),
    "A8.sess+sure_cov": V("A8.sess+sure_cov", dict(feats=RF, free=set(SESS), lams=LAMS),
                          dict(feats=VF + ["top_cov", "top_lbm"], lam=1.0)),
    "A8.sess+sure_jev": V("A8.sess+sure_jev", dict(feats=RF, free=set(SESS), lams=LAMS),
                          dict(feats=VF + ["jconf", "jsmargin"], lam=1.0)),
    "A8.sure_kind": V("A8.sure_kind", None, dict(feats=VF + ["top_run", "top_told0", "top_nxt"], lam=1.0)),
})
VARIANTS.update({
    "A8.few": V("A8.few", dict(feats=RF, free={"run", "nxt", "reply", "fin0", "fin2", "f_you"}, lams=LAMS), VSURE),
    "A8.sess_lam10": V("A8.sess_lam10", dict(feats=RF, free=set(SESS), lams=[10.0]), VSURE),
    "A8.sess_lam30": V("A8.sess_lam30", dict(feats=RF, free=set(SESS), lams=[30.0]), VSURE),
    "A8.mix02.sess": V("A8.mix02.sess", dict(feats=RF, free=set(SESS), lams=LAMS), VSURE),
    "A8.mix05": V("A8.mix05", dict(feats=RF, lams=LAMS), VSURE),
})
VARIANTS.update({
    "A3.choice": V("A3.choice", dict(feats=RF + ["jchoice", "jchoice_conf"], free={"jchoice", "jchoice_conf"}, lams=[1.0]),
                   VSURE),
    "A8.few+choice": V("A8.few+choice", dict(feats=RF + ["jchoice", "jchoice_conf"],
                                             free={"run", "nxt", "reply", "fin0", "fin2", "f_you", "jchoice", "jchoice_conf"},
                                             lams=LAMS), VSURE),
    "A8.few+lex": V("A8.few+lex", dict(feats=RF + ["lbm", "cov"],
                                       free={"run", "nxt", "reply", "fin0", "fin2", "f_you", "lbm", "cov"}, lams=LAMS), VSURE),
    "A8.few+sure_a4": V("A8.few+sure_a4", dict(feats=RF, free={"run", "nxt", "reply", "fin0", "fin2", "f_you"}, lams=LAMS),
                        dict(feats=VF + A4_SURE, lam=1.0)),
    "A8.few+sure_a3": V("A8.few+sure_a3", dict(feats=RF, free={"run", "nxt", "reply", "fin0", "fin2", "f_you"}, lams=LAMS),
                        dict(feats=VF + A3_SURE_JEV + A3_SURE_SIB, lam=1.0)),
})
EXTRA = {"A8.mix02.sess": 0.2, "A8.mix05": 0.5, "A8.mix": 1.0, "A8.mix02": 0.2}
_WRITTEN = None


def written():
    global _WRITTEN
    if _WRITTEN is None:
        _WRITTEN = C.load(sources=("real-rewrite", "goal", "scripted"))
    return _WRITTEN


def oof(data, name, seed=0):
    path = CACHE / f"{name}.s{seed}.pkl"
    if path.exists():
        return pickle.load(open(path, "rb"))
    t = time.time()
    extra = ()
    if name in EXTRA:
        extra = written()
        for x in extra:
            x.weight = EXTRA[name]
    preds, info = C.run_variant(data, VARIANTS[name], seed=seed, extra=extra)
    pickle.dump((preds, info), open(path, "wb"))
    print(f"  {name} seed {seed}: {time.time() - t:.0f}s", file=sys.stderr)
    return preds, info


def fmt(k, v):
    if k in ("auroc", "brier"):
        return f"{v:.3f}"
    return f"{100 * v:.1f}"


def table(data, base, var, arrs):
    res = C.paired(data, arrs[base], arrs[var])
    lines = [f"| metric | {base} | {var} | Δ | 95% CI |", "|---|---|---|---|---|"]
    for k in C.METRICS:
        a, b, d, lo, hi = res[k]
        flag = ""
        if C.BETTER[k] and (lo > 0 or hi < 0):
            flag = " **better**" if (d * C.BETTER[k]) > 0 else " **worse**"
        lines.append(f"| {k} | {fmt(k, a)} | {fmt(k, b)} | {fmt(k, d)} | [{fmt(k, lo)}, {fmt(k, hi)}]{flag} |")
    return "\n".join(lines), res


def main(names):
    data = C.load()
    arrs = {}
    out = {}
    for name in names:
        preds, info = oof(data, name)
        arrs[name] = C.arrays(data, preds)
        if info[0]["lam"] is not None:
            out.setdefault("lams", {})[name] = [i["lam"] for i in info]
    for name in names:
        if name == "shipped":
            continue
        txt, res = table(data, "shipped", name, arrs)
        print(f"\n### {name} vs shipped\n\n{txt}")
        out[name] = res
    for name in names:
        rows, ece = C.reliability(arrs[name]["s"], arrs[name]["ok"])
        print(f"\nreliability {name}: ECE {ece:.3f} " + "  ".join(f"[{lo:.2f},{hi:.2f}) n={n} pred {p:.2f} obs {o:.2f}"
                                                          for lo, hi, n, p, o in rows))
    json.dump(out, open(CACHE / "results.json", "w"), indent=1, default=float)


if __name__ == "__main__":
    main(sys.argv[1:] or list(VARIANTS))
