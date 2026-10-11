"""Learning from the user's own history (round 4, "personal").

Real moments are replayed in time order. Before each moment the router may use every EARLIER real moment's true
destination (as Lookout learns it from sends the user keeps, corrections, and answered asks), never this moment's or
later ones. Three ways to use them, on top of fuse3's guarded policy (format combo-o):

  (a) map    refit the fusion weights w (and the sureness logistic v) by MAP: the user's past moments' likelihood plus
             a Gaussian prior centred on the global weights, precision `lam`;
  (b) knn    a feature per destination: how much more often messages like this one (tf-idf cosine over the user's past
             messages) went to a destination of the same role (latest finished, 2nd, 3rd, older, new session) than
             the user's base rate, log lift; its weight learned online from 0;
  (c) thr    the sureness bar b2 picked online on the user's own prequential record (maximise right - C*wrong).

python3 -m explore.personal curve [PRIOR]   learning curves, fixed vs online, on the later part of the timeline
python3 -m explore.personal sweep           lam / knn / thr sweep on realA (prequential), realB reported
python3 -m explore.personal final           the chosen configuration on every set
PRIOR: ship (fuse3's weights, fitted on realA + synth + styleA) or noreal (fitted on synth + styleA only: a new user)."""
import collections
import math
import re
import sys

import numpy as np
from scipy.optimize import minimize

import bench
from explore import cal
from explore import combo
from explore import fuse3
from explore import fusion as Fu

FMT = "combo-o"
ROLES = ("fin0", "fin1", "fin2", "fin3", "run", "new", "intent")
_RULES = combo.make_policy()


# ---------------------------------------------------------------- data

def load(sets):
    Fu._patch_reading()
    cal._patch_reading()
    return Fu.load_eval(FMT, sets)


def global_fit(train):
    w = Fu.fit(Fu.dataset(FMT, list(train)), feats=fuse3.FEATS)
    ev = Fu.load_eval(FMT, list(train))
    v = Fu.fit_conf([x for s in ev for x in ev[s]], w)
    return w, v


def role(d, case):
    facts, _, _ = Fu.board_facts(case["board"])
    if d in facts:
        x = facts[d]
        if x["running"]:
            return "run"
        return f"fin{min(x['rank'], 3)}"
    if d.startswith("new:"):
        return "new"
    return "intent"


def toks(text):
    return re.findall(r"[^\W_]+", (text or "").lower())


# ---------------------------------------------------------------- (b) kNN over the user's past messages

class Knn:
    """The user's past messages and the role their destination had on the board then."""

    def __init__(self, k=10, alpha=2.0):
        self.k, self.alpha = k, alpha
        self.msgs, self.roles = [], []
        self.df = collections.Counter()

    def add(self, message, r):
        t = set(toks(message))
        self.msgs.append(t)
        self.roles.append(r)
        self.df.update(t)

    def _vec(self, t):
        n = len(self.msgs)
        return {w: math.log((n + 1) / (1 + self.df[w])) + 1 for w in t}

    def lift(self, message):
        """{role: log(p_knn(role) / p_base(role))}; {} with no history."""
        n = len(self.msgs)
        if n < 5:
            return {}
        base = collections.Counter(self.roles)
        q = self._vec(set(toks(message)))
        qn = math.sqrt(sum(x * x for x in q.values())) or 1
        sims = []
        for t, r in zip(self.msgs, self.roles):
            v = self._vec(t)
            vn = math.sqrt(sum(x * x for x in v.values())) or 1
            s = sum(q[w] * v[w] for w in q if w in v) / (qn * vn)
            if s > 0:
                sims.append((s, r))
        sims.sort(key=lambda x: -x[0])
        top = sims[:self.k]
        z = sum(s for s, _ in top)
        out = {}
        for ro in ROLES:
            pb = (base[ro] + 0.5) / (n + 0.5 * len(ROLES))
            pk = (sum(s for s, r in top if r == ro) + self.alpha * pb) / (z + self.alpha)
            out[ro] = math.log(pk / pb)
        return out


def add_knn(fs, case, lift):
    for d, f in fs.items():
        f["knn"] = lift.get(role(d, case), 0.0) if lift else 0.0
    return fs


# ---------------------------------------------------------------- (a) MAP fits

def _matrix(fs, gold, feats):
    ds = list(fs)
    if not gold & set(ds):
        return None
    idx = {k: i for i, k in enumerate(feats)}
    X = np.zeros((len(ds), len(feats)))
    for j, d in enumerate(ds):
        for k, x in fs[d].items():
            if k in idx:
                X[j, idx[k]] = x
    return X, np.array([d in gold for d in ds], float)


def fit_map(items, w0, lam, feats):
    """argmin -Σ log P(gold) + lam/2 |w - w0|² over the user's past moments [(case, reading, fs)]."""
    groups = [g for c, r, fs in items if fs for g in [_matrix(fs, set(c["gold"]["to"]), feats)] if g]
    m = np.array([w0.get(k, 0.0) for k in feats])
    if not groups:
        return dict(w0)

    def lg(w):
        dw = w - m
        L, G = lam * dw @ dw / 2, lam * dw
        for X, y in groups:
            s = X @ w
            s -= s.max()
            e = np.exp(s)
            p = e / e.sum()
            pg = (p * y).sum()
            L -= math.log(max(pg, 1e-12))
            G = G + p @ X - ((p * y) / pg) @ X
        return L, G
    res = minimize(lg, m.copy(), jac=True, method="L-BFGS-B", options={"maxiter": 200})
    return {**w0, **dict(zip(feats, res.x))}


def fit_conf_map(items, w, v0, lam):
    feats = Fu.CASE_FEATURES
    X, y = [], []
    for c, r, fs in items:
        if not fs or not c["gold"]["to"]:
            continue
        P = Fu.probs(fs, w)
        top = max(P.items(), key=lambda x: x[1])[0]
        cf = Fu.case_features(r, c, fs, P)
        X.append([cf.get(k, 0) for k in feats])
        y.append(top in c["gold"]["to"])
    if not X:
        return dict(v0)
    X, y = np.array(X, float), np.array(y, float)
    m = np.array([v0.get(k, 0.0) for k in feats])

    def lg(v):
        z = X @ v
        p = 1 / (1 + np.exp(-z))
        dv = v - m
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + lam * dv @ dv / 2
        return L, X.T @ (p - y) + lam * dv
    res = minimize(lg, m.copy(), jac=True, method="L-BFGS-B")
    return dict(zip(feats, res.x))


# ---------------------------------------------------------------- the decision (fuse3's guarded policy)

def decide(c, r, fs, w, v, b1=0.5, b2=0.9, min_words=3):
    """(send dest or None, the fused top, its sureness, whether the rules' send went through)."""
    if not fs:
        return None, None, 0.0, False
    k, d = _RULES(r)
    P = Fu.probs(fs, w)
    top, p = Fu.confidence(r, c, fs, w, v)
    if k == "send" and P.get(d, 0) >= b1:
        return d, top, p, True
    if p >= b2 and len(c["message"].split()) >= min_words and top not in Fu.INTENTS:
        return top, top, p, False
    return None, top, p, False


def best_bar(record, C, grid=(0.8, 0.85, 0.88, 0.9, 0.92, 0.94, 0.96, 0.98)):
    """(c) The bar b2 that maximises right - C*wrong over the user's own past (prequential) record."""
    best, bu = None, -1e9
    for b in grid:
        u = 0
        for rules_send, rules_ok, p, top_ok, eligible in record:
            if rules_send:
                u += 1 if rules_ok else -C
            elif eligible and p >= b:
                u += 1 if top_ok else -C
        if u > bu + 1e-9:
            best, bu = b, u
    return best


# ---------------------------------------------------------------- the replay

def replay(real, w0, v0, lam=None, lam_v=None, knn=False, thr_C=None, thr_min=60, every=1, b2=0.9, k=10, max_labels=None, b2_personal=None, min_labels=50):
    """Prequential replay of the real moments in time order. lam=None: the global model, fixed (with knn, only the
    knn weight is learnt: lam huge on every other weight). Returns per moment (case, send)."""
    items = sorted(real, key=lambda x: x[0]["at"])
    feats = fuse3.FEATS + (["knn"] if knn else [])
    kn = Knn(k=k)
    past, record, out, raw = [], [], [], []
    w, v = dict(w0), dict(v0)
    for i, (c, r, fs) in enumerate(items):
        if knn:
            fs = add_knn({d: dict(f) for d, f in fs.items()}, c, kn.lift(c["message"]))
        if past and i % every == 0 and (lam is not None or knn) and (max_labels is None or len(past) <= max_labels):
            lw = lam if lam is not None else 1e4
            w = fit_map(past, w0, lw, feats) if lam is not None else _fit_knn_only(past, w0, lw, feats)
            if lam_v is not None:
                v = fit_conf_map(past, w, v0, lam_v)
        bar = b2 if b2_personal is None or len(past) < min_labels else b2_personal
        if thr_C is not None and len(record) >= thr_min:
            bar = best_bar(record, thr_C)
        send, top, p, via_rules = decide(c, r, fs, w, v, b2=bar)
        gold = set(c["gold"]["to"])
        k_, d_ = _RULES(r)
        eligible = len(c["message"].split()) >= 3 and top is not None and top not in Fu.INTENTS
        record.append((via_rules, via_rules and send in gold, p, top in gold, eligible))
        out.append((c, send))
        raw.append((c, send if via_rules else None, top, p, eligible))
        past.append((c, r, fs))
        if knn:
            kn.add(c["message"], role(c["gold"]["to"][0], c) if c["gold"]["to"] else "intent")
    replay.raw = raw
    return out, w, v


def at_bar(raw, b2):
    """The replay's decisions with the fusion's own pick at sureness bar b2 (the rules' sends unchanged)."""
    return [(c, rs if rs is not None else (top if eligible and p >= b2 else None)) for c, rs, top, p, eligible in raw]


def frontier(name, raw, bars=(0.8, 0.85, 0.9, 0.93, 0.96, 1.01), cut=300):
    print(name)
    for b in bars:
        rows = at_bar(raw, b)
        late = rows[cut:]
        print(f"   b2={b:4}  realA {fmt_t(tally(split(rows, 'realA')))} | realB {fmt_t(tally(split(rows, 'realB')))} | "
              f"late A {fmt_t(tally(split(late, 'realA')))} | late B {fmt_t(tally(split(late, 'realB')))}", flush=True)


def _fit_knn_only(past, w0, lam, feats):
    w0k = {**w0, "knn": 0.0}
    # only the knn weight moves: every other weight pinned by a stiff prior; knn's own prior is weak (precision 1)
    groups = [g for c, r, fs in past if fs for g in [_matrix(fs, set(c["gold"]["to"]), feats)] if g]
    m = np.array([w0k.get(k, 0.0) for k in feats])
    prec = np.array([1.0 if k == "knn" else lam for k in feats])

    def lg(w):
        dw = w - m
        L, G = (prec * dw) @ dw / 2, prec * dw
        for X, y in groups:
            s = X @ w
            s -= s.max()
            e = np.exp(s)
            p = e / e.sum()
            pg = (p * y).sum()
            L -= math.log(max(pg, 1e-12))
            G = G + p @ X - ((p * y) / pg) @ X
        return L, G
    res = minimize(lg, m.copy(), jac=True, method="L-BFGS-B", options={"maxiter": 200})
    return {**w0k, **dict(zip(feats, res.x))}


def tally(rows):
    t = collections.Counter()
    for c, send in rows:
        gold = set(c["gold"]["to"])
        ask_ok = c["gold"].get("ask_ok") or not gold
        t["n"] += 1
        if send is None:
            t["ask"] += 1
            t["needless"] += not ask_ok
        else:
            t["right" if send in gold else "wrong"] += 1
    return t


def fmt_t(t):
    n = max(t["n"], 1)
    return f"n={t['n']:3} {100 * t['right'] / n:5.1f}/{100 * t['wrong'] / n:4.1f}/{100 * t['needless'] / n:4.1f}"


def split(rows, which):
    return [x for x in rows if bench.half(x[0]["id"]) == which]


def report(name, rows, cut=300):
    """realA, realB, and the later part of the timeline (moments after the first `cut`), per half."""
    late = rows[cut:]
    print(f"{name:34} realA {fmt_t(tally(split(rows, 'realA')))} | realB {fmt_t(tally(split(rows, 'realB')))} | "
          f"late A {fmt_t(tally(split(late, 'realA')))} | late B {fmt_t(tally(split(late, 'realB')))}", flush=True)


# ---------------------------------------------------------------- commands

def early_fit(real, cut=300, half=None):
    """The global fit with only the first `cut` real moments in time (realA's, or both halves) + synth + styleA: an
    honest prior for every later moment."""
    items = sorted(real, key=lambda x: x[0]["at"])[:cut]
    ids = {c["id"] for c, _, _ in items if half is None or bench.half(c["id"]) == half}
    data = [x for x in Fu.dataset(FMT, ["synth", "styleA"])] + [x for x in Fu.dataset(FMT, ["real"]) if x[1]["id"] in ids]
    w = Fu.fit(data, feats=fuse3.FEATS)
    ev = Fu.load_eval(FMT, ["synth", "styleA"])
    v = Fu.fit_conf([x for s in ev for x in ev[s]] + [x for x in real if x[0]["id"] in ids], w)
    return w, v


def weighted_fit(k, train=("realA", "synth", "styleA"), wset="realA"):
    """The global fit with the user's real moments counted k times (both the fusion and the sureness logistic)."""
    w = Fu.fit(Fu.dataset(FMT, list(train)), feats=fuse3.FEATS, set_weight={wset: k})
    ev = Fu.load_eval(FMT, list(train))
    v = Fu.fit_conf([x for s in ev for x in ev[s] * (int(k) if s == wset else 1)], w)
    return w, v


_POL = {}


def __getattr__(name):
    """bench.py --policy explore.personal:realK[_bB]  (real moments ×K in the fit; sureness bar B/100, default 90)."""
    if name.startswith("real") and name not in _POL:
        Fu._patch_reading()
        cal._patch_reading()
        k, _, b = name[4:].partition("_b")
        w, v = weighted_fit(float(k))
        _POL[name] = fuse3.make_guarded(w, v, b2=int(b) / 100 if b else 0.9)
    if name in _POL:
        return _POL[name]
    raise AttributeError(name)


def _globals():
    return {"ship": global_fit(("realA", "synth", "styleA")), "noreal": global_fit(("synth", "styleA"))}


def main():
    cmd = sys.argv[1]
    ev = load(["real"])
    real = ev["real"]
    G = _globals()
    if cmd == "sweep":
        for pname in ("ship", "noreal"):
            w0, v0 = G[pname]
            report(f"{pname} fixed", replay(real, w0, v0)[0])
            report(f"{pname} knn only", replay(real, w0, v0, knn=True, every=10)[0])
            for lam in (3, 10, 30, 100):
                report(f"{pname} map lam={lam}", replay(real, w0, v0, lam=lam, lam_v=lam, every=10)[0])
                report(f"{pname} map lam={lam} +knn", replay(real, w0, v0, lam=lam, lam_v=lam, knn=True, every=10)[0])
            for C in (3, 5, 10):
                report(f"{pname} thr C={C}", replay(real, w0, v0, thr_C=C)[0])
    if cmd == "frontier":
        for pname in ("ship", "noreal"):
            w0, v0 = G[pname]
            for n, kw in (("fixed", {}), ("knn only", dict(knn=True)), ("map10", dict(lam=10, lam_v=10)),
                          ("map10 w only", dict(lam=10)), ("map10 +knn", dict(lam=10, lam_v=10, knn=True)),
                          ("map3", dict(lam=3, lam_v=3))):
                replay(real, w0, v0, every=5, **kw)
                frontier(f"{pname} {n}", replay.raw)
    if cmd == "final":
        # The chosen configuration: the global weights (fuse3, guarded b1=0.5 b2=0.9) until the user has 50 labels,
        # then a personal MAP layer (lam=10 on w and v, prior = the global weights, refit every 5 labels) at b2=0.85.
        best = dict(lam=10, lam_v=10, every=5, b2_personal=0.85, min_labels=50)
        print("written sets (no history: the global model) as bench.py ... --policy explore.fuse3 guarded b1=0.5 b2=0.9")
        for pname in ("ship", "noreal"):
            w0, v0 = G[pname]
            for n, kw in (("fixed", {}), ("personal", best)):
                rows = replay(real, w0, v0, **kw)[0]
                late = rows[300:]
                print(f"prior {pname:6} {n:8}  realA {fmt_t(tally(split(rows, 'realA')))} | realB {fmt_t(tally(split(rows, 'realB')))}"
                      f" | late {fmt_t(tally(late))}", flush=True)
        w0, v0 = early_fit(real, 300)
        for n, kw in (("fixed", {}), ("personal", best)):
            late = replay(real, w0, v0, **kw)[0][300:]
            print(f"prior early  {n:8}  late {fmt_t(tally(late))} | late A {fmt_t(tally(split(late, 'realA')))} | "
                  f"late B {fmt_t(tally(split(late, 'realB')))}", flush=True)
    if cmd == "early":
        # Honest for every moment after the cut: the prior saw only moments before it (both halves).
        w0, v0 = early_fit(real, 300)
        bars = (0.8, 0.85, 0.9, 0.93, 0.96)
        for n, kw in (("fixed", {}), ("map3", dict(lam=3, lam_v=3)), ("map10", dict(lam=10, lam_v=10)),
                      ("map30", dict(lam=30, lam_v=30)), ("map10 +knn", dict(lam=10, lam_v=10, knn=True)),
                      ("knn only", dict(knn=True))):
            replay(real, w0, v0, every=5, **kw)
            print(f"early prior, {n}: late (moments 300+) all / A / B")
            for b in bars:
                rows = at_bar(replay.raw, b)[300:]
                print(f"   b2={b:4}  {fmt_t(tally(rows))} | {fmt_t(tally(split(rows, 'realA')))} | {fmt_t(tally(split(rows, 'realB')))}", flush=True)
    if cmd == "labels":
        # How many labels it takes: learn from the first N moments only, then freeze; score moments 300+.
        lam = float(sys.argv[2]) if len(sys.argv) > 2 else 3
        refs = {"ship fixed": replay(real, *G["ship"])[0] and replay.raw, "noreal fixed": replay(real, *G["noreal"])[0] and replay.raw}
        for b in (0.85, 0.9):
            for n, raw in refs.items():
                rows = at_bar(raw, b)[300:]
                print(f"b2={b} {n:22} late all {fmt_t(tally(rows))} | late A {fmt_t(tally(split(rows, 'realA')))} | late B {fmt_t(tally(split(rows, 'realB')))}")
        for N in (10, 25, 50, 100, 150, 200, 300):
            for pname in ("noreal", "ship"):
                replay(real, *G[pname], lam=lam, lam_v=lam, every=5, max_labels=N)
                for b in (0.85, 0.9):
                    rows = at_bar(replay.raw, b)[300:]
                    print(f"b2={b} {pname} map{lam:g} N={N:3}   late all {fmt_t(tally(rows))} | late A {fmt_t(tally(split(rows, 'realA')))} | late B {fmt_t(tally(split(rows, 'realB')))}", flush=True)
    if cmd == "curve":
        pname = sys.argv[2] if len(sys.argv) > 2 else "noreal"
        w0, v0 = G[pname]
        confs = [("fixed", {}), ("map30", dict(lam=30, lam_v=30)), ("map10", dict(lam=10, lam_v=10)),
                 ("map30+knn", dict(lam=30, lam_v=30, knn=True))]
        res = {n: replay(real, w0, v0, every=10, **kw)[0] for n, kw in confs}
        print(f"prior {pname}: right/wrong/needless per block of 100 moments in time order (A and B together)")
        for s in range(0, len(real), 100):
            print(f"  {s:3}-{s + 99:3}  " + "  ".join(f"{n}: {fmt_t(tally(rows[s:s + 100]))}" for n, rows in res.items()))


if __name__ == "__main__":
    main()
