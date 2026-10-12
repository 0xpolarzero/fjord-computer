"""Frozen real-dev moments -> extra features (A3, A4), conditional-logit and sureness fits in grouped CV, metrics with
a paired group bootstrap. Everything is offline: no Jev call, no episode replay after extract.py.
"""
import collections
import math
import pickle
import sys

import numpy as np
from scipy.optimize import minimize

sys.dont_write_bytecode = True

from v2.run import adapter, episodes as E

W0, V0 = E._shipped_weights()
RANK_FEATS = sorted(W0)
CASE_FEATS = list(V0)
INTENTS = ("question", "compound", "change_fjord")
_MODS = None


def mods():
    """formats, run, lexical, fusion, final3 as the replay installs them."""
    global _MODS
    if _MODS is None:
        formats, _, run, _, lexical, fusion, final3 = E._legacy_modules("combo-o", "explore.final3:best")
        _MODS = formats, run, lexical, fusion, final3
    return _MODS


# ---------------------------------------------------------------- extra features

def _idf_cov(case, cfg, lexical):
    """Per session: IDF-weighted share of the message's tokens found in its BM25 document (main LEX config)."""
    cfg = {**lexical.DEFAULT, **cfg}
    q = set(lexical.toks(case["message"], cfg["stemming"]))
    sess = case["board"]["sessions"]
    if not q or not sess:
        return {s["id"]: 0.0 for s in sess}
    docs = {s["id"]: lexical.session_tf(case, s, cfg) for s in sess}
    n = len(docs)
    df = collections.Counter(w for tf in docs.values() for w in tf if w in q)
    idf = {w: math.log(1 + (n - df.get(w, 0) + 0.5) / (df.get(w, 0) + 0.5)) for w in q}
    tot = sum(idf.values()) or 1
    return {d: sum(idf[w] for w in q if tf.get(w, 0) > 0) / tot for d, tf in docs.items()}


def family(case):
    """Session id -> its same-title family (same project, same lowercased title), itself included."""
    fam = collections.defaultdict(list)
    for s in case["board"]["sessions"]:
        fam[(s.get("project", ""), s["title"].strip().lower())].append(s["id"])
    return {sid: ids for ids in fam.values() for sid in ids}


def extras(m):
    """Adds per-destination extra features into a copy of m['fs'] and returns (fs, moment_extras)."""
    _, _, lexical, _, _ = mods()
    case, r = m["case"], m["reading"]
    fs = {d: dict(f) for d, f in m["fs"].items()}
    raw = {"lex": lexical.lex(case, lexical.STATE["cfg"])}
    for name, cfg in lexical.FIELDS.items():
        raw[name] = lexical.lex(case, cfg)
    best = {k: max(v.values(), default=0) for k, v in raw.items()}
    cov = _idf_cov(case, lexical.STATE["cfg"], lexical)
    fam = family(case)
    dests = r["dests"]
    for d, f in fs.items():
        if not f.get("sess"):
            continue
        for name in lexical.FIELDS:
            f["r_" + name] = math.log1p(raw[name].get(d, 0))                 # absolute strength of this field
            f["s_" + name] = f.get(name, 0) * math.log1p(best[name])         # ratio x the field's best strength
        f["s_lex"] = f.get("bm", 0) * math.log1p(best["lex"])
        f["cov"] = cov.get(d, 0)
        sib = [x for x in fam.get(d, [d]) if x != d and x in dests]
        p = dests.get(d, 0)
        mass = p + sum(dests.get(x, 0) for x in sib)
        f["sib"] = int(bool(sib))
        f["lpfam"] = math.log(max(mass, 1e-3)) - math.log(max(p, 1e-3))     # 0 without a sibling
    # Jev's own pick and its confidence, per destination
    route = m["answer"].get("route", {})
    chosen = m["keymap"].get(route.get("choice"), route.get("choice"))
    for d, f in fs.items():
        f["jchoice"] = int(d == chosen)
        f["jchoice_conf"] = float(route.get("confidence", 0) or 0) * (d == chosen)
    # moment-level
    ps = sorted((p for d, p in dests.items() if d != "unclear"), reverse=True)
    sp = sorted((p for d, p in dests.items() if fs.get(d, {}).get("sess")), reverse=True)
    allp = np.array([p for p in dests.values()], float)
    allp = allp / allp.sum() if allp.sum() > 0 else allp
    ent = -sum(p * math.log(p) for p in allp if p > 0) / math.log(max(len(allp), 2))
    mx = dict(jconf=float(route.get("confidence", 0) or 0), jent=ent,
              jmargin=(ps[0] - ps[1]) if len(ps) > 1 else (ps[0] if ps else 0),
              jsmargin=(sp[0] - sp[1]) if len(sp) > 1 else (sp[0] if sp else 0),
              bm_best=math.log1p(best["lex"]), said_best=math.log1p(best["f_said"]))
    return fs, mx


# ---------------------------------------------------------------- dataset

class Moment:
    __slots__ = ("m", "dests", "canon", "fs", "mx", "y", "group", "source", "nwords", "shipped", "weight")


def load(path="/tmp/v2_fusion_moments.pkl", sources=("real-moment",)):
    mods()
    M = pickle.load(open(path, "rb"))
    out = []
    for m in M:
        if m["source"] not in sources or not m["fs"]:
            continue
        x = Moment()
        x.m = m
        x.fs, x.mx = extras(m)
        x.dests = list(x.fs)
        x.canon = [adapter.canonical_target(d, m["state"]) or d for d in x.dests]
        g = m["gold"]["intended"]
        x.y = x.canon.index(g) if g in x.canon else None
        x.group, x.source = m["group"], m["source"]
        x.nwords = len(m["case"]["message"].split())
        x.shipped = m["shipped"]
        x.weight = 1.0
        out.append(x)
    return out


def X_of(x, feats):
    return np.array([[x.fs[d].get(k, 0.0) for k in feats] for d in x.dests], float)


# ---------------------------------------------------------------- ranking model (conditional logit)

def fit_rank(data, feats, w0, lam, free=None, offset=None):
    """argmin NLL + lam/2 |w - w0|^2 over `free` coordinates (others fixed at w0). offset: per-moment fixed score."""
    idx = [i for i, k in enumerate(feats) if free is None or k in free]
    w0 = np.array([w0.get(k, 0.0) for k in feats], float)
    rows = [(X_of(x, feats), x.y, x.weight) for x in data if x.y is not None]

    def f(z):
        w = w0.copy()
        w[idx] = z
        L = lam * ((z - w0[idx]) @ (z - w0[idx])) / 2
        G = np.zeros(len(feats))
        for X, y, sw in rows:
            s = X @ w
            s -= s.max()
            e = np.exp(s)
            p = e / e.sum()
            L -= sw * math.log(max(p[y], 1e-12))
            G += sw * (p @ X - X[y])
        return L, G[idx] + lam * (z - w0[idx])
    res = minimize(f, w0[idx], jac=True, method="L-BFGS-B", options={"maxiter": 500})
    w = w0.copy()
    w[idx] = res.x
    return dict(zip(feats, w))


def probs(x, w):
    s = {d: sum(w.get(k, 0) * v for k, v in x.fs[d].items()) for d in x.dests}
    mx = max(s.values())
    e = {d: math.exp(v - mx) for d, v in s.items()}
    z = sum(e.values())
    return {d: v / z for d, v in e.items()}


# ---------------------------------------------------------------- sureness (logistic on the moment)

def moment_feats(x, P):
    _, _, _, fusion, _ = mods()
    cf = dict(fusion.case_features(x.m["reading"], x.m["case"], x.fs, P))
    top = max(P.items(), key=lambda t: t[1])[0]
    f = x.fs[top]
    cf.update(x.mx)
    cf["jconf_agree"] = x.mx["jconf"] * cf["agree"]
    cf["top_lbm"] = f.get("lbm", 0)
    cf["top_cov"] = f.get("cov", 0)
    cf["top_sib"] = f.get("sib", 0)
    cf["top_run"] = f.get("run", 0)
    cf["top_told0"] = f.get("told0", 0)
    cf["top_nxt"] = f.get("nxt", 0)
    fam = family(x.m["case"])
    cf["top_famshare"] = sum(P.get(s, 0) for s in fam.get(top, []) if s != top)
    others = [g.get("lbm", 0) for d, g in x.fs.items() if d != top and g.get("sess")]
    cf["bmgap_raw"] = (f.get("lbm", 0) - max(others, default=0)) if f.get("sess") else 0
    return top, cf


def fit_sure(rows, feats, v0, lam):
    """rows: [(cf, correct)]. Logistic, L2 toward v0 on everything but bias."""
    X = np.array([[cf.get(k, 0) for k in feats] for cf, _ in rows], float)
    y = np.array([c for _, c in rows], float)
    v0a = np.array([v0.get(k, 0.0) for k in feats], float)
    pen = np.array([0.0 if k == "bias" else 1.0 for k in feats])

    def f(v):
        z = X @ v
        p = 1 / (1 + np.exp(-z))
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + lam * (pen * (v - v0a) ** 2).sum() / 2
        return L, X.T @ (p - y) + lam * pen * (v - v0a)
    res = minimize(f, v0a, jac=True, method="L-BFGS-B")
    return dict(zip(feats, res.x))


def sure_of(cf, v):
    z = sum(v.get(k, 0) * val for k, val in cf.items())
    return 1 / (1 + math.exp(-max(min(z, 50), -50)))


# ---------------------------------------------------------------- the ask card (as RouterSystem builds it)

_SYS = None


def card(x, P, spec="top1,other,recent"):
    global _SYS
    if _SYS is None or _SYS.card != spec:
        _SYS = E.RouterSystem(cache_only=True, card=spec)
    _, _, lexical, _, _ = mods()
    state = x.m["state"]
    what = sorted(P, key=lambda d: -P[d])[:4]
    order = list(dict.fromkeys(adapter.canonical_target(t, state) or t for t in what))
    order = [t for t in order if E.rules._ranked(state, [t])]
    return _SYS._card(order, x.m["case"], state, lexical)[:4]


# ---------------------------------------------------------------- grouped CV

def folds(data, k=10, seed=0):
    groups = sorted({x.group for x in data})
    rng = np.random.default_rng(seed)
    rng.shuffle(groups)
    gi = {g: i % k for i, g in enumerate(groups)}
    return [gi[x.group] for x in data]


class Variant:
    """A ranking spec + a sureness spec.
    rank: None (shipped W) or dict(feats=[...], free=None|set, lams=[...])
    sure: None (shipped V on the variant's P) or dict(feats=[...], lams=[...])"""
    def __init__(self, name, rank=None, sure=None):
        self.name, self.rank, self.sure = name, rank, sure


def _fit_rank_cv(train, spec, inner_k=5, seed=0):
    """Pick lambda by inner grouped CV NLL, then fit on all of train."""
    lams = spec.get("lams", [3.0])
    feats = spec["feats"]
    if len(lams) > 1:
        fi = folds(train, inner_k, seed + 101)
        best = None
        for lam in lams:
            nll = 0
            for f in range(inner_k):
                tr = [x for x, q in zip(train, fi) if q != f]
                te = [x for x, q in zip(train, fi) if q == f and x.y is not None]
                w = fit_rank(tr, feats, W0, lam, spec.get("free"))
                nll -= sum(math.log(max(probs(x, w)[x.dests[x.y]], 1e-12)) for x in te)
            if best is None or nll < best[0]:
                best = (nll, lam)
        lam = best[1]
    else:
        lam = lams[0]
    return fit_rank(train, feats, W0, lam, spec.get("free")), lam


def _oof_P(train, spec, k=5, seed=0, extra=()):
    """Out-of-fold P inside the training set, so the sureness is fitted on P as it behaves on unseen moments."""
    if spec is None:
        return [probs(x, W0) for x in train]
    fi = folds(train, k, seed + 202)
    P = [None] * len(train)
    for f in range(k):
        held = {x.group for x, q in zip(train, fi) if q == f}
        tr = [x for x, q in zip(train, fi) if q != f] + [x for x in extra if x.group not in held]
        w, _ = _fit_rank_cv(tr, {**spec, "lams": [spec.get("lam_inner", 3.0)]})
        for i, (x, q) in enumerate(zip(train, fi)):
            if q == f:
                P[i] = probs(x, w)
    return P


def correct(x, top):
    return x.y is not None and x.dests[x.y] == top


def run_variant(data, var, k=10, seed=0, extra=()):
    """Out-of-fold predictions: per moment (top, P, sureness). Returns list of dicts and fitted params per fold."""
    out = [None] * len(data)
    fi = folds(data, k, seed)
    info = []
    for f in range(k):
        test_groups = {x.group for x, q in zip(data, fi) if q == f}
        train = [x for x, q in zip(data, fi) if q != f]
        # extra (written) moments train the ranking only, never from a test group
        rank_train = train + [x for x in extra if x.group not in test_groups]
        test = [(i, x) for i, (x, q) in enumerate(zip(data, fi)) if q == f]
        if var.rank is None:
            w, lam = W0, None
        else:
            w, lam = _fit_rank_cv(rank_train, var.rank, seed=seed)
        v = V0
        if var.sure is not None:
            # lam_inner for the inner OOF P: reuse the chosen outer lambda
            spec = None if var.rank is None else {**var.rank, "lam_inner": lam}
            Ptr = _oof_P(train, spec, seed=seed, extra=[x for x in extra if x.group not in test_groups])
            rows = []
            for x, P in zip(train, Ptr):
                top, cf = moment_feats(x, P)
                rows.append((cf, correct(x, top)))
            v = fit_sure(rows, var.sure["feats"], V0, var.sure.get("lam", 1.0))
        info.append(dict(w=w, v=v, lam=lam))
        for i, x in test:
            P = probs(x, w)
            top, cf = moment_feats(x, P)
            out[i] = dict(top=top, P=P, s=sure_of(cf, v), ok=correct(x, top))
    return out, info


def fit_full(data, var, seed=0):
    """The weights to port: fit on all of dev real."""
    if var.rank is None:
        w, lam = W0, None
    else:
        w, lam = _fit_rank_cv(data, var.rank, seed=seed)
    v = V0
    if var.sure is not None:
        spec = None if var.rank is None else {**var.rank, "lam_inner": lam}
        rows = []
        for x, P in zip(data, _oof_P(data, spec, seed=seed)):
            top, cf = moment_feats(x, P)
            rows.append((cf, correct(x, top)))
        v = fit_sure(rows, var.sure["feats"], V0, var.sure.get("lam", 1.0))
    return w, v, lam


# ---------------------------------------------------------------- metrics

def auroc(s, ok):
    s, ok = np.asarray(s, float), np.asarray(ok, bool)
    npos, nneg = ok.sum(), (~ok).sum()
    if npos == 0 or nneg == 0:
        return float("nan")
    order = np.argsort(s, kind="mergesort")
    ranks = np.empty(len(s))
    ss = s[order]
    i = 0
    r = np.arange(1, len(s) + 1, dtype=float)
    # average ranks for ties
    while i < len(s):
        j = i
        while j + 1 < len(s) and ss[j + 1] == ss[i]:
            j += 1
        r[i:j + 1] = (i + j + 2) / 2
        i = j + 1
    ranks[order] = r
    return float((ranks[ok].sum() - npos * (npos + 1) / 2) / (npos * nneg))


def sel_risk(s, ok, cov):
    s, ok = np.asarray(s, float), np.asarray(ok, bool)
    n = max(1, int(round(cov * len(s))))
    order = np.argsort(-s, kind="mergesort")[:n]
    return float(1 - ok[order].mean())


def cov_at(s, ok, risk):
    """Largest share of moments sendable (best sureness first) with a wrong rate ≤ risk among them."""
    order = np.argsort(-np.asarray(s, float), kind="mergesort")
    wrong = np.cumsum(~np.asarray(ok, bool)[order])
    k = np.arange(1, len(order) + 1)
    good = np.nonzero(wrong / k <= risk)[0]
    return float((good[-1] + 1) / len(order)) if len(good) else 0.0


def metrics(s, ok, hit):
    s, ok, hit = np.asarray(s, float), np.asarray(ok, bool), np.asarray(hit, bool)
    return {"top1": float(ok.mean()), "hit4": float(hit.mean()), "auroc": auroc(s, ok),
            "risk30": sel_risk(s, ok, 0.3), "risk40": sel_risk(s, ok, 0.4), "risk50": sel_risk(s, ok, 0.5),
            "cov5": cov_at(s, ok, 0.05), "brier": float(((s - ok) ** 2).mean()),
            "sends90": float((s >= 0.9).mean()), "wrong90": float((~ok[s >= 0.9]).mean()) if (s >= 0.9).any() else 0.0}


METRICS = ["top1", "hit4", "auroc", "risk30", "risk40", "risk50", "cov5", "brier", "sends90", "wrong90"]
BETTER = {"top1": 1, "hit4": 1, "auroc": 1, "risk30": -1, "risk40": -1, "risk50": -1, "cov5": 1, "brier": -1,
          "sends90": 0, "wrong90": 0}


def resamples(data, B=2000, seed=7):
    groups = collections.defaultdict(list)
    for i, x in enumerate(data):
        groups[x.group].append(i)
    keys = sorted(groups)
    rng = np.random.default_rng(seed)
    for _ in range(B):
        pick = rng.integers(0, len(keys), len(keys))
        yield np.concatenate([groups[keys[j]] for j in pick])


def paired(data, a, b, B=2000, seed=7):
    """a, b: dicts of arrays s, ok, hit. -> {metric: (A, B, delta, lo, hi)}"""
    A, Bm = metrics(**a), metrics(**b)
    deltas = collections.defaultdict(list)
    for idx in resamples(data, B, seed):
        ma = metrics(a["s"][idx], a["ok"][idx], a["hit"][idx])
        mb = metrics(b["s"][idx], b["ok"][idx], b["hit"][idx])
        for k in METRICS:
            deltas[k].append(mb[k] - ma[k])
    out = {}
    for k in METRICS:
        d = np.array(deltas[k])
        d = d[~np.isnan(d)]
        out[k] = (A[k], Bm[k], Bm[k] - A[k], float(np.percentile(d, 2.5)), float(np.percentile(d, 97.5)))
    return out


def arrays(data, preds, spec="top1,other,recent"):
    s = np.array([p["s"] for p in preds])
    ok = np.array([p["ok"] for p in preds], bool)
    hit = np.array([x.m["gold"]["intended"] in card(x, p["P"], spec) for x, p in zip(data, preds)], bool)
    return {"s": s, "ok": ok, "hit": hit}


def reliability(s, ok, edges=(0, 0.5, 0.7, 0.8, 0.9, 0.95, 1.0001)):
    rows = []
    ece = 0
    for lo, hi in zip(edges, edges[1:]):
        sel = (s >= lo) & (s < hi)
        if sel.any():
            rows.append((lo, min(hi, 1), int(sel.sum()), float(s[sel].mean()), float(ok[sel].mean())))
            ece += sel.sum() / len(s) * abs(s[sel].mean() - ok[sel].mean())
    return rows, float(ece)
