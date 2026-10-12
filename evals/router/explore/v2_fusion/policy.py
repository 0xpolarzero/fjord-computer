"""The shipped final3 decision (rules guard, sure 0.9, short-reply 0.95, then RouterDispatcher's post-Jev overrides) run on
a variant's out-of-fold P and sureness, on the frozen real-dev moments. Click loss per submit: right 0, ask with the
intended target on the card 1, ask without it 4, wrong send 25.

python3 -m explore.v2_fusion.policy [--sure 0.9] NAME ...
"""
import argparse
import sys

import numpy as np

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_fusion import experiments as X
from v2.run import adapter

LOSS = dict(right=0, ask_hit=1, ask_miss=4, wrong=25)


def decide(x, P, top, p, sure=0.9, short=0.95, rules_sure=0.6, agrees=0.5, no_run=False):
    _, _, _, _, final3 = C.mods()
    k, d = x.m["rule"]
    case, state = x.m["case"], x.m["state"]
    nw = len(case["message"].split())
    kind, what = "ask", None
    if k == "send" and P.get(d, 0) >= agrees and top == d and p >= rules_sure:
        kind, what = "send", d
    elif top not in C.INTENTS and not (no_run and x.fs[top].get("run")):
        if p >= sure and nw >= 3:
            kind, what = "send", top
        elif nw < 3 and p >= short and x.fs[top].get("sess") and final3.terse_ok(case, top):
            kind, what = "send", top
    ranking = sorted(P.items(), key=lambda t: -t[1])
    if kind == "send":
        ranking = [(what, P.get(what, 0))] + [t for t in ranking if t[0] != what]
    ranked = [{"target": adapter.canonical_target(t, state), "score": q} for t, q in ranking[:4]]
    dec = {"decision": kind, "target": adapter.canonical_target(what, state) if what else None,
           "top": adapter.canonical_target(what or top, state), "ranked": ranked, "sureness": p,
           "sure": kind != "ask", "assisted": True}
    res = C.E.rules.post_jev(state, case["message"], case["context"], dec, ranked=ranked)
    return res


def outcome(x, res, P):
    gold = x.m["gold"]
    if res["decision"] == "ask":
        return "ask_hit" if gold["intended"] in C.card(x, P) else "ask_miss"
    return "right" if res.get("target") in gold.get("acceptable", [gold["intended"]]) else "wrong"


def run(data, preds, **kw):
    out = []
    for x, p in zip(data, preds):
        res = decide(x, p["P"], p["top"], p["s"], **kw)
        out.append(outcome(x, res, p["P"]))
    return out


def summarize(outs):
    o = np.array(outs)
    return {"loss": float(np.mean([LOSS[k] for k in o])), "right": float((o == "right").mean()),
            "wrong": float((o == "wrong").mean()), "ask": float(np.isin(o, ["ask_hit", "ask_miss"]).mean()),
            "ask_hit4": float((o == "ask_hit").sum() / max(np.isin(o, ["ask_hit", "ask_miss"]).sum(), 1)),
            "wrong_per_send": float((o == "wrong").sum() / max(np.isin(o, ["right", "wrong"]).sum(), 1))}


def paired(data, a, b, B=2000):
    A, Bm = summarize(a), summarize(b)
    a, b = np.array(a), np.array(b)
    d = {k: [] for k in A}
    for idx in C.resamples(data, B):
        sa, sb = summarize(a[idx]), summarize(b[idx])
        for k in A:
            d[k].append(sb[k] - sa[k])
    return {k: (A[k], Bm[k], Bm[k] - A[k], np.percentile(d[k], 2.5), np.percentile(d[k], 97.5)) for k in A}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+")
    ap.add_argument("--sure", type=float, default=0.9)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--no-run", action="store_true", help="the fused pick alone never sends to a running session")
    a = ap.parse_args()
    data = C.load()
    base_preds, _ = X.oof(data, "shipped")
    base = run(data, base_preds)
    # fidelity: the replica against the replay's own shipped decisions
    same = sum((r == "ask") == (x.shipped["decision"] == "ask") for r, x in zip(
        [("ask" if o.startswith("ask") else "send") for o in base], data))
    print(f"replica agrees with the replay's ask/send on {same}/{len(data)}")
    keys = ["loss", "right", "wrong", "ask", "ask_hit4", "wrong_per_send"]
    print("| variant | " + " | ".join(keys) + " |\n|---|" + "---|" * len(keys))
    sb = summarize(base)
    print("| shipped (abs) | " + " | ".join(f"{sb[k]:.3f}" if k == "loss" else f"{100 * sb[k]:.1f}" for k in keys) + " |")
    for n in a.names:
        preds, _ = X.oof(data, n, seed=a.seed)
        r = paired(data, base, run(data, preds, sure=a.sure, no_run=a.no_run))
        cells = []
        for k in keys:
            A, Bv, dd, lo, hi = r[k]
            f = (lambda v: f"{v:+.3f}") if k == "loss" else (lambda v: f"{100 * v:+.1f}")
            cells.append(f"{f(dd)} [{f(lo)},{f(hi)}]" + ("*" if lo > 0 or hi < 0 else ""))
        print(f"| {n} (sure {a.sure}) | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
