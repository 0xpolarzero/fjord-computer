"""Round 3 fusion: fuse2's features, plus
  bm    BM25 between the message and each session's recent turns, divided by the best session's (real cases: the
        transcript's last 2 turns before the moment, as Lookout can read them; written cases: the board's own text);
  bmtop the session whose BM25 is at least twice the next one's;
  lnull the log of the content-free route's p (explore/cal.py combo-cc), when the format asks it.

python3 -m explore.fuse3 fit FORMAT        fit on realA + synth + styleA; scores on every set, realB and heldout honest
python3 bench.py FORMAT --policy explore.fuse3:NAME"""
import json
import math
import pathlib
import sys

from explore import cal
from explore import fuse2
from explore import fusion as Fu
from real.lexical import bm25, words

HERE = pathlib.Path(__file__).parent.parent
_LEX = None
_base = fuse2.features


def lexical(case):
    """Per session id: BM25 / the best session's BM25."""
    global _LEX
    if _LEX is None:
        p = HERE / "real" / "data" / "lexical.json"
        _LEX = json.loads(p.read_text()) if p.exists() else {}
    if case["id"] in _LEX:
        return _LEX[case["id"]]
    b = case["board"]
    docs = {}
    for s in b["sessions"]:
        text = [s["title"], s.get("summary", ""), s.get("activity", "")]
        text += [c["text"] for c in b.get("cards", []) if c["session"] == s["id"]]
        text += [h["you"] for h in b.get("history", []) if h["to"] == s["id"]]
        docs[s["id"]] = words(" ".join(text))
    q = words(case["message"])
    sc = bm25(q, docs) if q else {}
    top = max(sc.values()) if sc else 0
    return {k: (v / top if top else 0) for k, v in sc.items()}


def features(r, case):
    out = _base(r, case)
    lex = lexical(case)
    ranked = sorted(lex.items(), key=lambda x: -x[1])
    second = ranked[1][1] if len(ranked) > 1 else 0
    null = r.get("null") or {}
    for d, f in out.items():
        if f.get("sess"):
            f["bm"] = lex.get(d, 0)
            f["bmtop"] = int(bool(ranked) and ranked[0][0] == d and ranked[0][1] > 0 and second <= 0.5)
        if null:
            f["lnull"] = math.log(max(null.get(d, 0), 1e-3))
    return out


Fu.features = features
FEATS = fuse2.FEATS + ["bm", "bmtop"]
FEATS_CC = FEATS + ["lnull"]


def make_guarded(w, v, b1=0.5, b2=0.9, min_words=3):
    """fuse2.make_hybrid's guarded decision, on this module's features."""
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
        if p >= b2 and len(case["message"].split()) >= min_words and top not in Fu.INTENTS:
            return ("send", top)
        return ("ask", sorted(P, key=lambda x: -P[x])[:3])
    pol.needs_case = True
    return pol


def fitted(fmt):
    feats = FEATS_CC if "cc" in fmt else FEATS
    w = Fu.fit(Fu.dataset(fmt, ["realA", "synth", "styleA"]), feats=feats)
    ev = Fu.load_eval(fmt, ["realA", "synth", "styleA"])
    v = Fu.fit_conf([x for s in ev for x in ev[s]], w)
    return w, v


def main():
    import bench
    import run
    Fu._patch_reading()
    cal._patch_reading()
    fmt = sys.argv[2]
    w, v = fitted(fmt)
    print({k: round(float(x), 2) for k, x in w.items()})
    print("conf", {k: round(float(x), 2) for k, x in v.items()})
    sets = {s: bench.load_set(s) for s in ("synth", "styleB", "realA", "realB", "heldout")}
    for b1, b2 in ((0.5, 0.85), (0.5, 0.9), (0.6, 0.9)):
        pol = make_guarded(w, v, b1, b2)
        print(f"guarded b1={b1} b2={b2}")
        for s, cases in sets.items():
            ids = {c["id"] for c in cases}
            whole = {"realA": "real", "realB": "real", "styleB": "style"}.get(s, s)
            rows = [r for r in run.load(f"{fmt}@{whole}") if r["id"] in ids and r["order"] == 0]
            print("    " + bench.line(s, bench.score(cases, rows, pol)))


if __name__ == "__main__":
    main()
