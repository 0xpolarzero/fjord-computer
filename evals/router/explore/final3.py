"""Round 3's decision, the explorers' winners together (what Lookout ships):
- lexical.py: BM25 between the message and each session per field (its last answer, what you last told it, its older
  turns halving with age, its title) as four fusion features; a rules' send also needs the fused top to be the same
  destination at calibrated sureness ≥ 0.6;
- state.py: a message under 3 words may go to the fused top session at sureness ≥ 0.95 when that session's last message
  asks or proposes something (it is what "go", "yes" answer).

python3 -m explore.final3            fit on realA + synth + styleA, print weights, score every set
python3 bench.py combo-o --saved --policy explore.final3:best"""
import sys

from explore import combo
from explore import fusion as Fu
from explore import lexical as L
from explore import state as S

_case_features = L.case_features


def case_features(r, case, fs, P):
    """lexical's moment features, with `agree` tie-inclusive: Jev often gives several sessions the same small p, and
    which of them is "his top" was dictionary order."""
    cf = _case_features(r, case, fs, P)
    top = max(P.items(), key=lambda x: x[1])[0]
    best = max((p for d, p in r["dests"].items() if d != "unclear"), default=0)
    cf["agree"] = int(r["dests"].get(top, 0) >= best)
    return cf


C1 = 0.6
B1, B2 = 0.5, 0.93  # B2 as Lookout ships it (RouteFusion.sure), raised from 0.9 in round 4
TERSE_BAR = 0.95
MIN_WORDS = 3


def terse_ok(case, sid):
    st = S.sess_state(S.last_text(case["board"], sid), next((c["kind"] for c in case["board"].get("cards", [])
                                                              if c["session"] == sid), None))
    return st["asks"] or st["prop"]


def make(w, v):
    rules = combo.make_policy()

    def pol(r, case):
        fs = L.features(r, case)
        if not fs:
            return ("ask", [])
        k, d = rules(r)
        P = Fu.probs(fs, w)
        top, p = Fu.confidence(r, case, fs, w, v)
        if k == "send" and P.get(d, 0) >= B1 and top == d and p >= C1:
            return ("send", d)
        nw = len(case["message"].split())
        if top not in Fu.INTENTS:
            if p >= B2 and nw >= MIN_WORDS:
                return ("send", top)
            if nw < MIN_WORDS and p >= TERSE_BAR and fs[top].get("sess") and terse_ok(case, top):
                return ("send", top)
        return ("ask", sorted(P, key=lambda x: -P[x])[:4])
    pol.needs_case = True
    return pol


_FIT = {}


def fitted(fmt="combo-o"):
    """Weights rounded to 2 decimals, as Lookout carries them (RouteFusion): what is measured is what ships."""
    if fmt not in _FIT:
        L.install()
        Fu.case_features = case_features
        L.STATE["fields"] = True
        w, v = L.fitted(fmt, L.FEATS_FIELDS, Fu.CASE_FEATURES)
        _FIT[fmt] = ({k: round(float(x), 2) for k, x in w.items()}, {k: round(float(x), 2) for k, x in v.items()})
    return _FIT[fmt]


def __getattr__(name):
    if name == "best":
        return make(*fitted())
    raise AttributeError(name)


def main():
    w, v = fitted()
    print("W =", {k: round(float(x), 2) for k, x in w.items() if abs(x) >= 0.005})
    print("V =", {k: round(float(x), 2) for k, x in v.items() if abs(x) >= 0.005})
    L.table("combo-o", make(w, v))


if __name__ == "__main__":
    main()
