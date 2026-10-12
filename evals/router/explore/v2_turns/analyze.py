"""A8 metrics: a variant's frozen moments and replay traces against base (both from explore.v2_turns.extract), paired by
(episode, event), paired bootstrap 95% CI resampling `group`. Fixed (shipped) weights; ranking = fused P argmax.

python3 -m explore.v2_turns.analyze VARIANT [VARIANT ...]
"""
import collections
import json
import pickle
import sys

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from v2.run import score as S

D = "/tmp/v2_turns"
B = 2000


def moments(mode):
    data = C.load(f"{D}/{mode}.pkl")
    return {(x.m["episode"], x.m["event"]): x for x in data}


def traces(mode):
    out = {}
    for line in open(f"{D}/{mode}.results.jsonl"):
        r = json.loads(line)
        for t in r["events"]:
            if t.get("kind", "submit") == "submit" and "gold" in t:
                out[(r["id"], t["id"] if "id" in t else t.get("event"))] = (r["group"], S.event_score(t))
    return out


def per_moment(x):
    P = C.probs(x, C.W0)
    top = max(P, key=P.get)
    s = x.shipped.get("sureness")
    if s is None:
        s = C.sure_of(C.moment_feats(x, P)[1], C.V0)
    return dict(top=top, P=P, s=float(s), ok=C.correct(x, top),
                hit=x.m["gold"]["intended"] in C.card(x, P))


def slices(x):
    st = x.m["state"]
    run = {"session:" + s["id"] for s in st["sessions"] if s.get("running")}
    return {"all": True, "target running": x.m["gold"]["intended"] in run, "any running": bool(run)}


def boot(groups, a, b, fn, seed=7):
    g = collections.defaultdict(list)
    for i, k in enumerate(groups):
        g[k].append(i)
    keys = sorted(g)
    rng = np.random.default_rng(seed)
    d = []
    for _ in range(B):
        idx = np.concatenate([g[keys[j]] for j in rng.integers(0, len(keys), len(keys))])
        va, vb = fn(a[idx]), fn(b[idx])
        if not (np.isnan(va) or np.isnan(vb)):
            d.append(vb - va)
    return fn(a), fn(b), float(np.percentile(d, 2.5)), float(np.percentile(d, 97.5))


def row(name, A, Bv, lo, hi, scale=100, fmt="{:.1f}"):
    f = lambda v: fmt.format(scale * v)
    star = "*" if lo > 0 or hi < 0 else ""
    return f"| {name} | {f(A)} | {f(Bv)} | {'+' if Bv - A >= 0 else ''}{f(Bv - A)} [{f(lo)}, {f(hi)}]{star} |"


def compare(variant, base="base"):
    mb, mv = moments(base), moments(variant)
    keys = sorted(set(mb) & set(mv))
    print(f"\n## {variant} vs {base}: {len(keys)} paired moments (base {len(mb)}, variant {len(mv)})")
    pb = {k: per_moment(mb[k]) for k in keys}
    pv = {k: per_moment(mv[k]) for k in keys}
    changed_fs = sum(any(abs(mb[k].fs[d].get(f, 0) - mv[k].fs.get(d, {}).get(f, 0)) > 1e-12
                         for d in mb[k].fs for f in ("f_said", "f_old", "f_you", "f_title", "bm")) for k in keys)
    flips = collections.Counter((pb[k]["ok"], pv[k]["ok"]) for k in keys if pb[k]["top"] != pv[k]["top"])
    print(f"moments with any lexical feature changed: {changed_fs}; top changed: "
          f"{sum(pb[k]['top'] != pv[k]['top'] for k in keys)} (wrong->right {flips[(False, True)]}, "
          f"right->wrong {flips[(True, False)]}, wrong->wrong {flips[(False, False)]})")
    print("| metric | base | variant | delta [95% CI] |\n|---|---|---|---|")
    for sl in ("all", "target running", "any running"):
        ks = [k for k in keys if slices(mb[k])[sl]]
        grp = [mb[k].group for k in ks]
        for met in ("ok", "hit"):
            a = np.array([pb[k][met] for k in ks], float)
            b = np.array([pv[k][met] for k in ks], float)
            print(row(f"{'top-1' if met == 'ok' else 'hit@4'} ({sl}, n={len(ks)})", *boot(grp, a, b, np.mean)))
    grp = [mb[k].group for k in keys]
    s_a = np.array([pb[k]["s"] for k in keys]); s_b = np.array([pv[k]["s"] for k in keys])
    ok_a = np.array([pb[k]["ok"] for k in keys]); ok_b = np.array([pv[k]["ok"] for k in keys])
    idx = np.arange(len(keys))
    au = boot(grp, idx, idx, lambda i: C.auroc(s_a[i], ok_a[i]))
    au_b = boot(grp, idx, idx, lambda i: C.auroc(s_b[i], ok_b[i]))
    # paired AUROC delta
    gmap = collections.defaultdict(list)
    for i, g in enumerate(grp):
        gmap[g].append(i)
    gk = sorted(gmap)
    rng = np.random.default_rng(7)
    d = []
    for _ in range(B):
        ii = np.concatenate([gmap[gk[j]] for j in rng.integers(0, len(gk), len(gk))])
        d.append(C.auroc(s_b[ii], ok_b[ii]) - C.auroc(s_a[ii], ok_a[ii]))
    d = np.array(d); d = d[~np.isnan(d)]
    print(row("sureness AUROC (x100)", au[0], au_b[0], np.percentile(d, 2.5), np.percentile(d, 97.5)))
    # replay traces: loss per submit, wrong sends
    tb, tv = traces(base), traces(variant)
    tk = sorted(set(tb) & set(tv))
    grp = [tb[k][0] for k in tk]
    for met, sc, fm in (("loss", 1, "{:.3f}"), ("wrong", 100, "{:.1f}"), ("automatic", 100, "{:.1f}"),
                        ("hit_at_4", 100, "{:.1f}")):
        a = np.array([tb[k][1][met] for k in tk], float)
        b = np.array([tv[k][1][met] for k in tk], float)
        label = {"loss": "loss/submit", "wrong": "wrong sends % of submits", "automatic": "sends % of submits",
                 "hit_at_4": "replay ranked hit@4"}[met]
        print(row(f"{label} (n={len(tk)})", *boot(grp, a, b, np.mean), scale=sc, fmt=fm))


if __name__ == "__main__":
    for v in sys.argv[1:]:
        compare(v)
