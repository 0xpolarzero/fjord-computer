"""fusion.py's conditional logit, fed the combined format's signals too (combo.py): the "next message in this
conversation?" yes per latest session, the second-person gate against Lookout's intents, the tight compound gate.

python3 -m explore.fuse2 fit [FORMAT]   fit on realA + synth + styleA, sweep bars, print weights and scores
python3 bench.py combo --policy explore.fuse2:NAME"""
import math
import sys

from explore import fusion as Fu

_base_features = Fu.features


def features(r, case):
    out = _base_features(r, case)
    g = r.get("gates") or {}
    for d, f in out.items():
        if f.get("sess"):
            f["nxt"] = g.get(f"gate_next_{d}", 0)
        elif d in Fu.INTENTS:
            f["you"] = g.get("gate_you", 0)
            if d == "compound":
                f["c2"] = g.get("gate_compound2", 0)
    return out


Fu.features = features  # fusion's fit/evaluate read this module-level name

FEATS = Fu.SMALL + ["nxt", "you", "c2"]


def fit(fmt="combo", train=("realA", "synth", "styleA"), feats=FEATS, l2=1.0):
    return Fu.fit(Fu.dataset(fmt, list(train)), feats=feats, l2=l2)


# Fitted on realA + synth + styleA (format combo), rounded. A destination's score is Jev's log p times 0.86 plus what
# the board and the in-call checks say about it; P = softmax over destinations.
W2 = {"lp": 0.86,                                   # Jev's route probability (log, floored at 0.001)
      "fin0": 0.83, "fin1": 1.32, "fin2": 0.49,     # 1st / 2nd / 3rd most recently finished session
      "run": -1.5,                                  # still running
      "reply": 1.03,                                # "is it the answer to this session's card?" yes
      "told0": 0.88,                                # the session the user last wrote to
      "fin0u": 1.26, "idle5u": 2.41,                # latest / finished ≤ 5 min ago, times Jev's `unclear` p
      "nxt": 0.95,                                  # "is it the user's next message in this conversation?" yes
      "new": -0.01,
      "question": -0.83, "compound": 0.58, "change_lookout": 0.39,
      "g_c": 1.94, "g_s": 2.52, "c2": 0.08,         # an intent's own gate
      "you": -1.57,                                 # "does it speak to one agent as you?" yes, against intents
      "ilong": -1.87}                               # an intent for a message over 80 characters
# How sure the fused top is right: logistic on the moment.
V2 = {"bias": 1.58, "lPtop": 0.83, "lgap": 0.12, "agree": 0.3, "u": -0.99, "lenlog": -0.28, "recent2": -0.33,
      "top_fin0": 0.04, "top_intent": 0.14, "top_new": 0.47, "top_reply": 0.39}


def make_hybrid(b1=0.5, b2=0.9, w=W2, v=V2, min_words=0, fused_intents=True):
    """The combined rules' send when the fusion gives it ≥ b1; else the fusion's top at calibrated sureness ≥ b2.
    The fusion's own pick needs `min_words` words ("ok" goes nowhere on recency alone) and, unless `fused_intents`,
    is never one of Lookout's intents."""
    from explore import combo
    rules = combo.make_policy()

    def pol(r, case):
        fs = features(r, case)
        if not fs:
            return ("ask", [])
        k, d = rules(r)
        P = Fu.probs(fs, w)
        if k == "send" and P.get(d, 0) >= b1:
            return ("send", d)
        top, p = Fu.confidence(r, case, fs, w, v)
        if p >= b2 and len(case["message"].split()) >= min_words and (fused_intents or top not in Fu.INTENTS):
            return ("send", top)
        return ("ask", sorted(P, key=lambda x: -P[x])[:3])
    pol.needs_case = True
    return pol


hybrid = make_hybrid()
hybrid85 = make_hybrid(b2=0.85)
guarded = make_hybrid(min_words=3, fused_intents=False)
guarded85 = make_hybrid(b2=0.85, min_words=3, fused_intents=False)


def hybrid_sets(ev, w, v, b1, b2):
    """The combined rules' send when the fusion gives that destination at least b1; else the fusion's top when its
    calibrated sureness is at least b2; else ask."""
    from explore import combo
    rules = combo.make_policy()
    out = {}
    for s, items in ev.items():
        t = {"n": 0, "right": 0, "wrong": 0, "needless": 0}
        for c, r, fs in items:
            gold = set(c["gold"]["to"])
            ask_ok = c["gold"].get("ask_ok") or not gold
            t["n"] += 1
            send = None
            if fs:
                k, d = rules(r)
                P = Fu.probs(fs, w)
                if k == "send" and P.get(d, 0) >= b1:
                    send = d
                else:
                    top, p = Fu.confidence(r, c, fs, w, v)
                    if p >= b2:
                        send = top
            if send:
                t["right" if send in gold else "wrong"] += 1
            else:
                t["needless"] += not ask_ok
        out[s] = tuple(100 * t[k] / t["n"] for k in ("right", "wrong", "needless"))
    return out


def main():
    Fu._patch_reading()
    fmt = sys.argv[2] if len(sys.argv) > 2 else "combo"
    w = fit(fmt)
    print({k: round(float(x), 2) for k, x in w.items()})
    ev = Fu.load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
    items = [x for s in ("realA", "synth", "styleA") for x in ev[s]]
    v = Fu.fit_conf(items, w)
    print("conf", {k: round(float(x), 2) for k, x in v.items()})
    for bar in (0.75, 0.8, 0.85, 0.9):
        res = Fu.evaluate(ev, w, bar=bar, v=v)
        print(f"conf bar={bar}: " + "  ".join(f"{s}:{r[0]:.0f}/{r[1]:.1f}/{r[2]:.0f}" for s, r in res.items()))
    for b1 in (0.3, 0.5, 0.6, 0.7):
        for b2 in (0.8, 0.85, 0.9):
            res = hybrid_sets(ev, w, v, b1, b2)
            print(f"hybrid b1={b1} b2={b2}: " + "  ".join(f"{s}:{a:.0f}/{b:.1f}/{c:.0f}" for s, (a, b, c) in res.items()))


if __name__ == "__main__":
    main()
