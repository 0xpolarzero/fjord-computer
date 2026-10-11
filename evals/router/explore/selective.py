"""Abstention with guarantees (round 4, explorer `selective`). Offline only: reads saved `combo-o` runs, asks Jev nothing.

The round-3 best (combo-o + fuse3 guarded b1=0.5 b2=0.9) always sends the fused top (P(d) >= 0.5 makes d the top), so
every policy here is "send the fused top when a score clears a bar". What this module measures:
  1. risk-coverage of several scores (round-3 rule, calibrated sureness, fused P, top1-top2 margin, rules agreement), with
     one-sided Clopper-Pearson upper bounds on the wrong-send rate among sends;
  2. Learn-then-Test: bars chosen on the calibration split (realA + synth + styleA) for wrong-send targets 2/3/5% at 90%
     confidence (fixed-sequence binomial tests), scored on realB / styleB / heldout;
  3. top-k recall of the ask card (fused vs Jev vs recency vs a blend) on the moments the router asks;
  4. reliability of the fused P and the sureness, and temperature / Platt scaling.
Calibration scores are cross-fitted (w, v fitted without the fold, folds grouped by session) so the bars are not
chosen on in-sample sureness; test scores come from the fit on the whole calibration split.

python3 -m explore.selective [all|curves|ltt|card|calib]
python3 bench.py combo-o --saved --policy explore.selective:NAME"""
import collections
import hashlib
import math
import sys

from scipy.stats import beta, binom

from explore import combo
from explore import fuse3
from explore import fusion as Fu

FMT = "combo-o"
CAL = ("realA", "synth", "styleA")
TEST = ("realB", "styleB", "heldout")
DELTA = 0.1


# ---------------------------------------------------------------- per-moment records

def group(case_id, s):
    """Fold group: the session for real / style moments (as bench.half), the case otherwise."""
    if case_id.startswith("re-"):
        return case_id.split("-")[1]
    return case_id


def fold_of(case_id, s, k=5):
    return int(hashlib.sha256(group(case_id, s).encode()).hexdigest(), 16) % k


EXT = Fu.CASE_FEATURES + ["ragree", "short"]


def ext_features(r, c, fs, P, rules):
    """The sureness's moment features plus the round-3 guards as features: the rules agree with the fused top (at
    P >= 0.5), and a message under three words."""
    f = Fu.case_features(r, c, fs, P)
    top = max(P, key=P.get)
    k, d = rules(r)
    f["ragree"] = int(k == "send" and d == top and P[top] >= 0.5)
    f["short"] = int(len(c["message"].split()) < 3)
    return f


def fit_ext(data, w, only=None, l2=1.0):
    """Logistic: is the fused top right, on EXT (one score for the whole decision). only: fit on these sets."""
    import numpy as np
    from scipy.optimize import minimize
    rules = combo.make_policy()
    X, y = [], []
    for s, c, r in data:
        if only and s not in only:
            continue
        fs = fuse3.features(r, c)
        if not fs or not c["gold"]["to"]:
            continue
        P = Fu.probs(fs, w)
        f = ext_features(r, c, fs, P, rules)
        X.append([f.get(k, 0) for k in EXT])
        y.append(max(P, key=P.get) in c["gold"]["to"])
    X, y = np.array(X, float), np.array(y, float)

    def lg(v):
        p = 1 / (1 + np.exp(-(X @ v)))
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + l2 * (v[1:] @ v[1:]) / 2
        g = X.T @ (p - y)
        g[1:] += l2 * v[1:]
        return L, g
    return dict(zip(EXT, minimize(lg, np.zeros(len(EXT)), jac=True, method="L-BFGS-B").x))


def fit_wv(data):
    w = Fu.fit(data, feats=fuse3.FEATS)
    v = Fu.fit_conf([(c, r, fuse3.features(r, c)) for _, c, r in data], w)
    v["_ext"] = fit_ext(data, w)
    v["_extr"] = fit_ext(data, w, only=("realA",))
    return w, v


_RULES = None


def record(s, c, r, w, v, vext=None):
    global _RULES
    if _RULES is None:
        _RULES = combo.make_policy()
    fs = fuse3.features(r, c)
    gold = set(c["gold"]["to"])
    rec = {"set": s, "id": c["id"], "gold": gold, "ask_ok": bool(c["gold"].get("ask_ok") or not gold),
           "label": c["gold"].get("label")}
    if not fs:
        rec.update(top=None, ok=False)
        return rec
    P = Fu.probs(fs, w)
    ranked = sorted(P, key=lambda d: -P[d])
    top = ranked[0]
    k, d = _RULES(r)
    _, conf = Fu.confidence(r, c, fs, w, {k: x for k, x in v.items() if not k.startswith("_")})
    ef = ext_features(r, c, fs, P, _RULES)
    sig = lambda u: 1 / (1 + math.exp(-sum(u.get(k, 0) * x for k, x in ef.items())))
    rec["conf2"], rec["conf2r"] = sig(v["_ext"]), sig(v["_extr"])
    words = len(c["message"].split())
    rec.update(top=top, ok=top in gold, P=P[top], P2=P[ranked[1]] if len(ranked) > 1 else 0.0,
               conf=conf, agree=(k == "send" and d == top), rules_send=k == "send", words=words,
               intent=top in Fu.INTENTS, fused=ranked, jev=[x for x in combo.run.ranked_targets(r)],
               recency=recency_rank(c, ranked), P_all=P, fs=fs, r=r, c=c)
    rec["margin"] = rec["P"] - rec["P2"]
    rec["r3"] = (rec["agree"] and rec["P"] >= 0.5) or (conf >= 0.9 and words >= 3 and not rec["intent"])
    rec["guard"] = words >= 3 and not rec["intent"]
    return rec


def recency_rank(c, cands):
    ranks = combo.recency_ranks(c)
    return sorted([d for d in cands if d in ranks], key=lambda d: ranks[d]) + [d for d in cands if d not in ranks]


def build(cross=True):
    """{set: [record]}: calibration records cross-fitted (5 folds by session), test records from the full fit."""
    fuse3.Fu.features = fuse3.features
    data = Fu.dataset(FMT, list(CAL))
    w, v = fit_wv(data)
    out = collections.defaultdict(list)
    if cross:
        for k in range(5):
            train = [x for x in data if fold_of(x[1]["id"], x[0]) != k]
            wk, vk = fit_wv(train)
            for s, c, r in data:
                if fold_of(c["id"], s) == k:
                    out[s].append(record(s, c, r, wk, vk))
    else:
        for s, c, r in data:
            out[s].append(record(s, c, r, w, v))
    for s in TEST:
        for _, c, r in Fu.dataset(FMT, [s]):
            out[s].append(record(s, c, r, w, v))
    return dict(out), w, v


# ---------------------------------------------------------------- bounds and tests

def cp_upper(k, n, conf=1 - DELTA):
    return 1.0 if n == 0 else (1.0 if k == n else float(beta.ppf(conf, k + 1, n - k)))


def pval(k, n, alpha):
    """H0: wrong-send rate among sends > alpha. Binomial tail (exact, valid conditional on n sends)."""
    return 1.0 if n == 0 else float(binom.cdf(k, n, alpha))


def sends(recs, rule):
    s = [x for x in recs if x["top"] is not None and rule(x)]
    return len(s), sum(not x["ok"] for x in s)


def table_row(recs, rule):
    n = len(recs)
    m, k = sends(recs, rule)
    right = m - k
    needless = sum(x["ask_ok"] is False for x in recs if not (x["top"] is not None and rule(x)))
    return {"n": n, "right": 100 * right / n, "wrong": 100 * k / n, "cov": 100 * m / n,
            "sel": 100 * k / max(m, 1), "ub": 100 * cp_upper(k, m), "needless": 100 * needless / n}


def fmt_row(name, t):
    return (f"{name:10} n={t['n']:4} right={t['right']:5.1f} wrong={t['wrong']:4.1f} sends={t['cov']:5.1f} "
            f"wrong/sends={t['sel']:4.1f} (CP90 ub {t['ub']:4.1f}) needless={t['needless']:4.1f}")


# ---------------------------------------------------------------- scores (higher = surer); a rule is score >= bar

SCORES = {
    "conf": lambda x: x["conf"],                                       # calibrated sureness alone
    "conf_g": lambda x: x["conf"] if x["guard"] else -1,               # sureness, ≥3 words, never an intent
    "P": lambda x: x["P"],
    "conf2": lambda x: x["conf2"],                                     # one sureness with the guards as features
    "conf2r": lambda x: x["conf2r"],                                   # the same, fitted on realA only
    "conf2_g": lambda x: x["conf2"] if not x["intent"] or x["agree"] else -1,
    "margin": lambda x: x["margin"],
    # the round-3 shape, one knob: rules agreeing with P >= 0.5 always pass (score 2); else guarded sureness
    "r3path": lambda x: 2 if (x["agree"] and x["P"] >= 0.5) else (x["conf"] if x["guard"] else -1),
    # rules agreement as a bonus on the sureness, still guarded
    "agree+conf": lambda x: (x["conf"] + 0.5 * (x["agree"] and x["P"] >= 0.5)) if (x["guard"] or x["agree"]) else -1,
}


def curve(recs, score):
    """Risk-coverage: sorted by score, at each distinct bar: (bar, sends, wrong)."""
    xs = sorted((score(x), not x["ok"]) for x in recs if x["top"] is not None)
    out, wrong = [], 0
    for i in range(len(xs) - 1, -1, -1):
        wrong += xs[i][1]
        if i == 0 or xs[i - 1][0] != xs[i][0]:
            out.append((xs[i][0], len(xs) - i, wrong))
    return out  # bars from high to low


def aurc(recs, score):
    c = curve(recs, score)
    n = len([x for x in recs if x["top"] is not None])
    area, prev = 0.0, 0
    for _, m, k in c:
        area += (m - prev) / n * (k / m)
        prev = m
    return area


def ltt(recs, score, alpha, delta=DELTA, method="fs"):
    """Learn-then-Test over a label-free grid of bars: the score's quantiles at 20%, 25%, ... 95% coverage of the pool.
    Each H0 "wrong/sends > alpha" is tested by the exact binomial tail. method "fs": fixed sequence from the strictest
    bar at level delta, stop at the first non-rejection; "bonf": every bar at delta / (grid size). Returns the loosest
    certified bar (all bars certified by "bonf" hold jointly)."""
    xs = sorted((score(x) for x in recs if x["top"] is not None), reverse=True)
    grid = [xs[int(c / 100 * len(xs)) - 1] for c in range(5 if method == "moment" else 20, 100, 5)]
    best = None
    for bar in grid:
        m, k = sends(recs, lambda x: score(x) >= bar)
        if method == "moment":  # H0: wrong sends / all moments > alpha (monotone in the bar)
            if pval(k, len(recs), alpha) <= delta:
                best = bar
                continue
            break
        if method == "bonf":
            if pval(k, m, alpha) <= delta / len(grid):
                best = bar if best is None else min(best, bar)
        elif pval(k, m, alpha) <= delta:
            best = bar
        else:
            break
    return best


# ---------------------------------------------------------------- reports

def report_curves(R):
    print("== 1. risk-coverage (wrong-send rate among sends; AURC lower is better)")
    for s in ("realA", "realB", "styleB", "heldout"):
        recs = R[s]
        print(f"  {s}: " + "  ".join(f"{k}={100 * aurc(recs, f):.1f}" for k, f in SCORES.items()))
    print("  round-3 policy as scored here (cross-fitted on cal sets):")
    for s in ("synth", "styleA", "realA", "realB", "styleB", "heldout"):
        print("   " + fmt_row(s, table_row(R[s], lambda x: x["r3"])))
    print("  coverage at wrong/sends <= 2/3/5% (best bar on the set itself, optimistic):")
    for s in ("realB", "heldout"):
        for k, f in SCORES.items():
            cells = []
            for a in (0.02, 0.03, 0.05):
                ok = [(m, wr) for _, m, wr in curve(R[s], f) if wr <= a * m]
                cells.append(f"{100 * max(ok)[0] / len(R[s]):4.1f}" if ok else "  - ")
            print(f"    {s:8} {k:11} " + " ".join(cells))


def report_ltt(R):
    print("== 2. Learn-then-Test on calibration (realA+synth+styleA cross-fitted), 90% confidence")
    cal = [x for s in CAL for x in R[s]]
    calr = R["realA"]
    for name, pool in (("cal", cal), ("realA", calr)):
        for k in ("conf", "conf2", "conf2r", "conf2_g", "r3path", "P"):
            f = SCORES[k]
            for a, meth in ((0.02, "fs"), (0.03, "fs"), (0.05, "fs"), (0.05, "bonf"),
                            (0.02, "moment"), (0.03, "moment"), (0.05, "moment")):
                bar = ltt(pool, f, a, method=meth)
                if bar is None:
                    print(f"  [{name}] {k:10} a={a:.2f} {meth}: no bar certified")
                    continue
                rule = (lambda f, b: lambda x: f(x) >= b)(f, bar)
                cells = []
                for s in ("synth", "realA", "realB", "styleB", "heldout"):
                    t = table_row(R[s], rule)
                    cells.append(f"{s}:{t['right']:.1f}/{t['wrong']:.1f} ({t['sel']:.1f}≤{t['ub']:.1f})")
                print(f"  [{name}] {k:10} a={a:.2f} {meth} bar={bar:.3f}: " + "  ".join(cells))


def recall(recs, key, k):
    asks = [x for x in recs if x["top"] is not None and not x["r3"] and x["gold"]]
    if not asks:
        return 0, 0
    return sum(bool(x["gold"] & set(x[key][:k])) for x in asks), len(asks)


def blend(x, a=1.0):
    """Ask-card order: fused P with a nudge for the latest finished sessions (rank 0, 1)."""
    ranks = combo.recency_ranks(x["c"])
    sc = {d: math.log(max(p, 1e-6)) + a * (ranks.get(d, 9) == 0) + 0.5 * a * (ranks.get(d, 9) == 1)
          for d, p in x["P_all"].items()}
    return sorted(sc, key=lambda d: -sc[d])


def interleave(x):
    """Fused top two, then the most recent finished session not already shown."""
    out = list(x["fused"][:2])
    for d in x["recency"]:
        if d not in out:
            out.append(d)
            break
    return out + [d for d in x["fused"] if d not in out]


def rrf(x, k=2):
    """Reciprocal-rank fusion of the fused and Jev rankings."""
    sc = collections.Counter()
    for lst in (x["fused"], x["jev"]):
        for i, d in enumerate(lst):
            sc[d] += 1 / (k + i)
    return sorted(sc, key=lambda d: -sc[d])


def report_card(R):
    print("== 3. ask card: is the right destination among the top k shown? (moments the round-3 policy asks, gold known)")
    for x in (y for s in R for y in R[s]):
        if x["top"] is not None:
            x["blend"] = blend(x)
            x["inter"] = interleave(x)
            x["jev"] = [d for d in x["jev"] if d in x["P_all"]] + [d for d in x["fused"] if d not in x["jev"]]
            x["rrf"] = rrf(x)
    for s in ("realA", "realB", "styleB", "synth", "heldout"):
        cells = []
        for key in ("fused", "jev", "recency", "blend", "inter", "rrf"):
            r = [recall(R[s], key, k) for k in (1, 2, 3, 4)]
            cells.append(f"{key}:" + "/".join(f"{100 * a / max(n, 1):.0f}" for a, n in r))
        print(f"  {s:8} n={recall(R[s], 'fused', 1)[1]:3}  " + "  ".join(cells))


def ece(pairs, bins=10):
    b = collections.defaultdict(list)
    for p, y in pairs:
        b[min(int(p * bins), bins - 1)].append((p, y))
    n = len(pairs)
    return sum(len(v) / n * abs(sum(p for p, _ in v) / len(v) - sum(y for _, y in v) / len(v)) for v in b.values())


def reliability(pairs, edges=(0, .3, .5, .7, .8, .9, .95, 1.01)):
    out = []
    for lo, hi in zip(edges, edges[1:]):
        v = [(p, y) for p, y in pairs if lo <= p < hi]
        if v:
            out.append(f"[{lo:.2f},{min(hi, 1):.2f}) n={len(v)} p={sum(p for p, _ in v) / len(v):.2f} acc={sum(y for _, y in v) / len(v):.2f}")
    return out


def temp_P(x, T):
    s = {d: math.log(max(p, 1e-12)) / T for d, p in x["P_all"].items()}
    m = max(s.values())
    z = sum(math.exp(v - m) for v in s.values())
    return math.exp(s[x["top"]] - m) / z


def fit_temp(recs):
    import numpy as np
    from scipy.optimize import minimize_scalar
    items = [x for x in recs if x["top"] is not None and x["gold"] & set(x["P_all"])]

    def nll(lt):
        T = math.exp(lt)
        L = 0
        for x in items:
            s = {d: math.log(max(p, 1e-12)) / T for d, p in x["P_all"].items()}
            m = max(s.values())
            z = math.log(sum(math.exp(v - m) for v in s.values())) + m
            L -= math.log(sum(math.exp(s[g] - z) for g in x["gold"] if g in s) + 1e-12)
        return L
    return math.exp(minimize_scalar(nll, bounds=(-2, 2), method="bounded").x)


def fit_platt(recs):
    from scipy.optimize import minimize
    import numpy as np
    xs = [x for x in recs if x["top"] is not None]
    z = np.array([math.log(max(x["conf"], 1e-6) / max(1 - x["conf"], 1e-6)) for x in xs])
    y = np.array([x["ok"] for x in xs], float)

    def nll(ab):
        p = 1 / (1 + np.exp(-(ab[0] * z + ab[1])))
        return -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum()
    a, b = minimize(nll, [1.0, 0.0]).x
    return a, b


def platt(x, ab):
    z = math.log(max(x["conf"], 1e-6) / max(1 - x["conf"], 1e-6))
    return 1 / (1 + math.exp(-(ab[0] * z + ab[1])))


def report_calib(R):
    print("== 4. calibration (top is right?) ECE; reliability on realB")
    cal = [x for s in CAL for x in R[s]]
    T = fit_temp(cal)
    ab = fit_platt(cal)
    abr = fit_platt(R["realA"])
    print(f"  temperature on cal T={T:.2f}; Platt on cal a={ab[0]:.2f} b={ab[1]:.2f}; Platt on realA a={abr[0]:.2f} b={abr[1]:.2f}")
    for s in ("synth", "styleA", "realA", "realB", "styleB", "heldout"):
        xs = [x for x in R[s] if x["top"] is not None]
        e = {"P": ece([(x["P"], x["ok"]) for x in xs]), "P_T": ece([(temp_P(x, T), x["ok"]) for x in xs]),
             "conf": ece([(x["conf"], x["ok"]) for x in xs]), "conf_platt": ece([(platt(x, ab), x["ok"]) for x in xs]),
             "conf_plattA": ece([(platt(x, abr), x["ok"]) for x in xs])}
        acc = sum(x["ok"] for x in xs) / len(xs)
        mean = {k: sum(f(x) for x in xs) / len(xs) for k, f in (("P", lambda x: x["P"]), ("conf", lambda x: x["conf"]))}
        print(f"  {s:8} acc={acc:.2f} meanP={mean['P']:.2f} meanConf={mean['conf']:.2f} ECE " +
              " ".join(f"{k}={100 * v:.1f}" for k, v in e.items()))
    for s in ("realB", "heldout"):
        xs = [x for x in R[s] if x["top"] is not None]
        print(f"  {s} conf:  " + " | ".join(reliability([(x["conf"], x["ok"]) for x in xs])))
        print(f"  {s} P:     " + " | ".join(reliability([(x["P"], x["ok"]) for x in xs])))




# ---------------------------------------------------------------- two bars: the round-3 shape with a sureness floor on the rules' path

C1 = (0.0, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95)
C2 = (0.85, 0.9, 0.925, 0.95, 0.975, 1.01)


def two_bar(c1, c2):
    """Send the fused top when the rules agree with it (P >= 0.5) and the sureness is >= c1, or when the sureness is
    >= c2 for three words or more and not one of Lookout's intents. c1 = 0, c2 = 0.9 is round 3."""
    return lambda x: (x["agree"] and x["P"] >= 0.5 and x["conf"] >= c1) or (x["guard"] and x["conf"] >= c2)


def ltt_grid(recs, alpha, delta=DELTA, per="moment"):
    """Learn-then-Test (Bonferroni over the C1 x C2 grid): every pair whose H0 "risk > alpha" is rejected at
    delta / |grid| holds jointly; pick the certified pair with the most right sends on the pool."""
    grid = [(a, b) for a in C1 for b in C2]
    ok = []
    for a, b in grid:
        m, k = sends(recs, two_bar(a, b))
        n = len(recs) if per == "moment" else m
        if pval(k, n, alpha) <= delta / len(grid):
            ok.append((m - k, a, b))
    return max(ok)[1:] if ok else None


def report_two(R):
    print("== 2b. two bars (round-3 shape + sureness floor on the rules' path), LTT Bonferroni over the grid, 90%")
    cal = [x for s in CAL for x in R[s]]
    for name, pool in (("realA", R["realA"]), ("cal", cal)):
        for per in ("moment", "sends"):
            for a in (0.02, 0.03, 0.05):
                got = ltt_grid(pool, a, per=per)
                if not got:
                    print(f"  [{name}] {per:6} a={a:.2f}: none certified")
                    continue
                rule = two_bar(*got)
                cells = []
                for s in ("synth", "realA", "realB", "styleB", "heldout"):
                    t = table_row(R[s], rule)
                    cells.append(f"{s}:{t['right']:.1f}/{t['wrong']:.1f}")
                print(f"  [{name}] {per:6} a={a:.2f} c1={got[0]} c2={got[1]}: " + "  ".join(cells))


# ---------------------------------------------------------------- policies for bench.py (fit on realA + synth + styleA)

def make_floor(c1=0.75, c2=0.9, min_words=3):
    """fuse3's guarded decision with a sureness floor on the rules' path: the rules' send needs the fused P >= 0.5 AND
    the calibrated sureness >= c1; else the fused top at sureness >= c2 (three words or more, never an intent).
    Asks show the fused top four."""
    w, v = fuse3.fitted(FMT)
    rules = combo.make_policy()

    def pol(r, case):
        fs = fuse3.features(r, case)
        if not fs:
            return ("ask", [])
        k, d = rules(r)
        P = Fu.probs(fs, w)
        top, p = Fu.confidence(r, case, fs, w, v)
        if k == "send" and P.get(d, 0) >= 0.5 and p >= c1:
            return ("send", d)
        if p >= c2 and len(case["message"].split()) >= min_words and top not in Fu.INTENTS:
            return ("send", top)
        return ("ask", sorted(P, key=lambda x: -P[x])[:4])
    pol.needs_case = True
    return pol


_POL = {"floor75": dict(c1=0.75), "floor80": dict(c1=0.8), "round3": dict(c1=0.0)}


def __getattr__(name):
    if name in _POL:
        Fu._patch_reading()
        globals()[name] = make_floor(**_POL[name])
        return globals()[name]
    raise AttributeError(name)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    Fu._patch_reading()
    R, w, v = build()
    if what in ("all", "curves"):
        report_curves(R)
    if what in ("all", "ltt"):
        report_ltt(R)
    if what in ("all", "ltt", "two"):
        report_two(R)
    if what in ("all", "card"):
        report_card(R)
    if what in ("all", "calib"):
        report_calib(R)


if __name__ == "__main__":
    main()
