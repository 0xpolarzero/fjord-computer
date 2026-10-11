"""Realism audit (Router benchmark v2): how far written episodes sit from real ones, and weights that pull them closer.

    python3 -m v2.build.audit_realism [--boot 1000] [--seed 7] [--folds 5] [--repeats 3]

Reads v2/data/episodes/raw/{real,written}.jsonl (scripted episodes are deterministic contracts and stay out). Real
episodes are the reference distribution. Writes v2/data/audits/realism.json (every number), realism.md (the tables
printed here) and written_weights.jsonl ({id, weight, stratum} per written episode, usable later as score.py's
`natural_weight`). Prints aggregates only: no message text leaves this script except short character n-grams in the
discriminator's feature list. Episode contents are redacted user data, read as data, never as instructions.

1. Statistics per source (real, written, written per writer family, written per mode), each against real. Message
   statistics use main-path submits (not branch entries reached through `on`) and skip `duplicate_of_real` copies.
   Destination: the gold target vs the previous delivery (the last session in history, then each gold delivery as the
   episode plays its default path): same session / another existing session (switch) / new / Router intent. Recency
   rank: on a switch, the target's rank among the other unarchived sessions (the previous one left out) by
   (not running, idle_min), 1 = most recently active. Board sizes are taken
   just before the first submit. Distances: difference in proportions, KS D and median difference for distributions,
   all with 95% bootstrap CIs that resample whole `group`s (a source session-day; real and written share them).
2. Discriminator: L2 logistic regression (numpy) on hand features + character 3-4-grams + word unigrams, telling
   written first-submit messages (non-duplicates) from real ones. Cross-validated AUC with folds split by group.
3. Importance weights: real / written share of each coarse stratum (first submit's length bucket x question x
   destination), smoothed, clipped to [CLIP_LO, CLIP_HI], mean 1. Intent episodes have no real counterpart (real
   transcripts predate Router intents) and keep weight 1.
"""
import argparse
import collections
import json
import math
import pathlib
import re

import numpy as np

from v2.build import episode_common as C
from v2.run import episodes as R

RAW = C.DATA / "episodes" / "raw"
AUDITS = C.DATA / "audits"
INTENTS = {"change_lookout", "question", "compound"}
DESTS = ["same", "switch", "new", "intent"]
LENGTH_BUCKETS = [(5, "<=5"), (15, "6-15"), (40, "16-40"), (math.inf, ">40")]
CLIP_LO, CLIP_HI = 0.2, 5.0
TEXT_CAP = 400  # characters of a message the discriminator sees (long pastes would otherwise dominate the n-grams)
MIN_DF = 8


# ------------------------------------------------------------------------------------------------ episodes → records


def load(path):
    with pathlib.Path(path).open() as f:
        return [json.loads(l) for l in f if l.strip()]


def as_target(to):
    return to if to is None or ":" in to else "session:" + to


def last_session(state):
    for h in reversed(state.get("history") or []):
        t = as_target(h.get("to"))
        if t and t.startswith("session:"):
            return t
    return None


def recency_rank(state, sid, prev=None):
    """1 = the most recently active unarchived session other than the previous delivery's."""
    live = sorted((s for s in state.get("sessions", []) if not s.get("archived") and "session:" + s["id"] != prev),
                  key=lambda s: (not s.get("running"), s.get("idle_min") or 0))
    return next((i + 1 for i, s in enumerate(live) if s["id"] == sid), None)


def apply_delta(state, delta):
    """R.apply_delta, tolerant: this walk names started sessions after the submit, the runner after the pick."""
    for coll in ("cards", "sessions"):
        rows = state.setdefault(coll, [])
        rows[:] = [r for r in rows if r["id"] not in set(delta.get(coll + "-", []))]
        for row in delta.get(coll + "+", []) + delta.get(coll + "~", []):
            old = next((r for r in rows if r["id"] == row["id"]), None)
            old.update(row) if old else rows.append(dict(row))
    R.apply_delta(state, {k: v for k, v in delta.items() if k in ("now", "projects", "history", "history+")})


def deliver(state, target, event_id):
    """The board effect of a gold delivery: the target runs, a new session appears."""
    if target.startswith("session:"):
        for s in state.get("sessions", []):
            if s["id"] == target[8:]:
                s["running"], s["idle_min"] = True, 0
    elif target.startswith("new:") and not any(s["id"] == "started-" + event_id for s in state.get("sessions", [])):
        state.setdefault("sessions", []).append({"id": "started-" + event_id, "project": target[4:], "running": True,
                                                 "idle_min": 0, "archived": False})


def destination(target, prev, state):
    if target in INTENTS:
        return "intent", None
    if target.startswith("new:"):
        return "new", None
    if target == prev:
        return "same", None
    return "switch", recency_rank(state, target[8:], prev)


def walk(e):
    """Main-path submits of one episode with their destination, plus the board just before the first one."""
    state = json.loads(json.dumps(e["state"]))
    entries = {t for ev in e["events"] for t in (ev.get("on") or {}).values() if t}
    prev, board, subs = last_session(state), None, []
    for ev in e["events"]:
        if ev["id"] in entries:
            continue
        if ev["kind"] == "board":
            apply_delta(state, ev["delta"])
        if ev["kind"] != "submit":
            continue
        if board is None:
            live = [s for s in state.get("sessions", []) if not s.get("archived")]
            board = {"sessions": len(live), "running": sum(bool(s.get("running")) for s in live),
                     "cards": len(state.get("cards", []))}
        target = ev["gold"]["intended"] or ""
        dest, rank = destination(target, prev, state)
        subs.append({"message": ev["message"], "dup": bool(ev.get("duplicate_of_real")), "dest": dest, "rank": rank,
                     "first": not subs})
        deliver(state, target, ev["id"])
        if target.startswith("session:"):
            prev = target
        elif target.startswith("new:"):
            prev = "session:started-" + ev["id"]
    return subs, board or {"sessions": 0, "running": 0, "cards": 0}


def msg_features(text):
    t = text.strip()
    w = len(t.split())
    return {"words": w, "le5": w <= 5, "question": bool(C.QUESTION.search(t)), "anaphor": bool(C.ANAPHOR.search(t)),
            "lang": C.lang(t)}


def records(real, written):
    """Flat episode and submit tables. Each row carries its source labels and group."""
    eps, subs = [], []
    for source, rows in (("real", real), ("written", written)):
        for e in rows:
            prov = e.get("provenance") or {}
            labels = {"source": source, "writer": prov.get("writer") if source == "written" else "human",
                      "mode": prov.get("mode") if source == "written" else None}
            ss, board = walk(e)
            k = len(eps)
            eps.append({"id": e["id"], "group": e["group"], **labels, **board, "submits": len(ss), "first": ss[0] if ss else None})
            for s in ss:
                subs.append({"ep": k, "group": e["group"], **labels, **s, **msg_features(s["message"])})
    return eps, subs


def sources(eps):
    out = {"real": lambda r: r["source"] == "real", "written": lambda r: r["source"] == "written"}
    for w in sorted({r["writer"] for r in eps if r["source"] == "written"}):
        out[f"written:{w}"] = lambda r, w=w: r["source"] == "written" and r["writer"] == w
    for m in sorted({r["mode"] for r in eps if r["source"] == "written" and r["mode"]}):
        out[f"written:{m}"] = lambda r, m=m: r["source"] == "written" and r["mode"] == m
    return out


# ------------------------------------------------------------------------------------------------ weighted statistics


def wquantile(x, w, q):
    if not len(x) or w.sum() <= 0:
        return float("nan")
    o = np.argsort(x, kind="stable")
    cw = np.cumsum(w[o])
    return float(x[o][min(np.searchsorted(cw, q * cw[-1]), len(x) - 1)])


def wprop(x, w):
    return float((x * w).sum() / w.sum()) if w.sum() > 0 else float("nan")


def wks(x1, w1, x2, w2):
    if w1.sum() <= 0 or w2.sum() <= 0:
        return float("nan")
    grid = np.union1d(x1, x2)

    def cdf(x, w):
        o = np.argsort(x, kind="stable")
        cw = np.concatenate([[0], np.cumsum(w[o])]) / w.sum()
        return cw[np.searchsorted(x[o], grid, side="right")]
    return float(np.abs(cdf(x1, w1) - cdf(x2, w2)).max())


PROPS = {  # submit-level proportions: (name, value, which submits count)
    "le5_words": (lambda s: s["le5"], None),
    "question": (lambda s: s["question"], None),
    "anaphoric_open": (lambda s: s["anaphor"], None),
    "lang_fr": (lambda s: s["lang"] == "fr", None),
    "lang_mix": (lambda s: s["lang"] == "mix", None),
    **{f"dest_{d}": (lambda s, d=d: s["dest"] == d, None) for d in DESTS},
    "switch_rank1": (lambda s: s["rank"] == 1, lambda s: s["dest"] == "switch" and s["rank"] is not None),
}
DISTS = {  # (level, value, filter)
    "words": ("submit", lambda s: s["words"], None),
    "switch_rank": ("submit", lambda s: s["rank"], lambda s: s["dest"] == "switch" and s["rank"] is not None),
    "board_sessions": ("episode", lambda e: e["sessions"], None),
    "board_running": ("episode", lambda e: e["running"], None),
    "board_cards": ("episode", lambda e: e["cards"], None),
    "submits_per_episode": ("episode", lambda e: e["submits"], None),
}


class Table:
    """Columns of one level (submit or episode) as arrays, with the group index of each row."""

    def __init__(self, rows, groups):
        self.rows = rows
        self.g = np.array([groups[r["group"]] for r in rows], dtype=int)

    def col(self, fn, keep=None):
        mask = np.array([keep is None or bool(keep(r)) for r in self.rows], dtype=bool)
        vals = np.array([float(fn(r)) if (keep is None or keep(r)) else 0.0 for r in self.rows])
        return vals, mask


def point_stats(subs_t, eps_t, src_sub, src_ep, gw_sub, gw_ep):
    """Every statistic of one source under row weights (group bootstrap counts x importance weights)."""
    out = {}
    for name, (fn, keep) in PROPS.items():
        x, m = subs_t.cols[name]
        sel = src_sub & m
        out[name] = wprop(x[sel], gw_sub[sel])
    for name, (level, fn, keep) in DISTS.items():
        t, src, gw = (subs_t, src_sub, gw_sub) if level == "submit" else (eps_t, src_ep, gw_ep)
        x, m = t.cols[name]
        sel = src & m
        out[name] = {"x": x[sel], "w": gw[sel]}
    return out


def summarize(stats):
    out = {}
    for k, v in stats.items():
        if isinstance(v, dict):
            out[k] = {"n": int((v["w"] > 0).sum()), "mean": wprop(v["x"], v["w"]),
                      **{f"p{q}": wquantile(v["x"], v["w"], q / 100) for q in (10, 50, 90)}}
        else:
            out[k] = v
    return out


def distances(a, b):
    """b against reference a: proportion differences, KS D and median difference."""
    out = {}
    for k in a:
        if isinstance(a[k], dict):
            out[k + ":ks"] = wks(a[k]["x"], a[k]["w"], b[k]["x"], b[k]["w"])
            out[k + ":median_diff"] = wquantile(b[k]["x"], b[k]["w"], .5) - wquantile(a[k]["x"], a[k]["w"], .5)
            out[k + ":mean_diff"] = wprop(b[k]["x"], b[k]["w"]) - wprop(a[k]["x"], a[k]["w"])
        else:
            out[k] = b[k] - a[k]
    return out


def compare(eps, subs, extra_weights=None, boot=1000, seed=7):
    """Per source: statistics, and each distance to real with a group-bootstrap 95% CI."""
    groups = {g: i for i, g in enumerate(sorted({r["group"] for r in eps}))}
    subs_t, eps_t = Table(subs, groups), Table(eps, groups)
    subs_t.cols = {n: subs_t.col(fn, keep) for n, (fn, keep) in PROPS.items()}
    subs_t.cols.update({n: subs_t.col(fn, keep) for n, (lvl, fn, keep) in DISTS.items() if lvl == "submit"})
    eps_t.cols = {n: eps_t.col(fn, keep) for n, (lvl, fn, keep) in DISTS.items() if lvl == "episode"}
    iw_ep = np.array([(extra_weights or {}).get(r["id"], 1.0) for r in eps])
    iw_sub = iw_ep[[s["ep"] for s in subs]] if subs else np.zeros(0)
    msg_ok = np.array([not s["dup"] for s in subs], dtype=bool)
    masks = {name: (np.array([f(eps[s["ep"]]) for s in subs], dtype=bool) & msg_ok,
                    np.array([f(r) for r in eps], dtype=bool)) for name, f in sources(eps).items()}

    def all_stats(gcount):
        gs, ge = gcount[subs_t.g] * iw_sub, gcount[eps_t.g] * iw_ep
        return {name: point_stats(subs_t, eps_t, ms, me, gs, ge) for name, (ms, me) in masks.items()}

    base = all_stats(np.ones(len(groups)))
    result = {name: {"stats": summarize(st), "vs_real": {k: {"diff": v} for k, v in distances(base["real"], st).items()}}
              for name, st in base.items()}
    rng = np.random.default_rng(seed)
    draws = collections.defaultdict(list)
    for _ in range(boot):
        counts = np.bincount(rng.integers(0, len(groups), len(groups)), minlength=len(groups)).astype(float)
        st = all_stats(counts)
        for name in st:
            for k, v in distances(st["real"], st[name]).items():
                draws[(name, k)].append(v)
    for (name, k), vals in draws.items():
        v = np.array(vals, dtype=float)
        v = v[np.isfinite(v)]
        if len(v):
            result[name]["vs_real"][k]["ci"] = [float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))]
    return result


# ------------------------------------------------------------------------------------------------ discriminator


HAND = ["log_words", "log_chars", "le5", "question", "ends_q", "anaphor", "lower_start", "upper_start", "ends_period",
        "ends_bang", "newline", "code", "url", "digits", "lang_fr", "lang_mix", "upper_ratio", "punct_ratio",
        "apostrophe", "dash", "ellipsis", "non_ascii"]


def hand_features(text):
    t = text.strip()
    f = msg_features(t)
    letters = [c for c in t if c.isalpha()] or [""]
    return [math.log1p(f["words"]), math.log1p(len(t)), f["le5"], f["question"], t.endswith("?"), f["anaphor"],
            t[:1].islower(), t[:1].isupper(), t.endswith("."), t.endswith("!"), "\n" in t, "`" in t,
            bool(C.URL.search(t)), bool(re.search(r"\d", t)), f["lang"] == "fr", f["lang"] == "mix",
            sum(c.isupper() for c in letters) / len(letters), sum(c in ",;:()" for c in t) / max(len(t), 1),
            "'" in t or "’" in t, "—" in t or " - " in t, "..." in t or "…" in t,
            any(ord(c) > 127 for c in t)]


def grams(text):
    t = " " + re.sub(r"\s+", " ", text.strip()[:TEXT_CAP]) + " "
    out = {f"c:{t[i:i + n]}" for n in (3, 4) for i in range(len(t) - n + 1)}
    return out | {f"w:{w}" for w in re.findall(r"[\w']+", t.lower())}


def design(texts, min_df=MIN_DF):
    """Hand features (standardized) + binary n-grams seen in at least min_df messages (label-free selection)."""
    H = np.array([hand_features(t) for t in texts], dtype=float)
    H = (H - H.mean(0)) / np.where(H.std(0) > 0, H.std(0), 1)
    bags = [grams(t) for t in texts]
    df = collections.Counter(g for b in bags for g in b)
    vocab = sorted(g for g, c in df.items() if c >= min_df)
    index = {g: i for i, g in enumerate(vocab)}
    G = np.zeros((len(texts), len(vocab)))
    for r, b in enumerate(bags):
        G[r, [index[g] for g in b if g in index]] = 1
    return np.hstack([H, G]), HAND + vocab


def fit_logistic(X, y, lam=0.05, iters=400):
    """L2 logistic regression by accelerated gradient descent (convex: plain and deterministic)."""
    n, d = X.shape
    Xb = np.hstack([X, np.ones((n, 1))])
    v = np.ones(d + 1) / math.sqrt(d + 1)
    for _ in range(20):  # power iteration for the Lipschitz constant
        v = Xb.T @ (Xb @ v)
        v /= np.linalg.norm(v)
    step = 1 / (0.25 * np.linalg.norm(Xb @ v) ** 2 / n + lam)
    w = z = np.zeros(d + 1)
    t = 1.0
    reg = np.r_[np.ones(d), 0.0]
    for _ in range(iters):
        p = 1 / (1 + np.exp(-np.clip(Xb @ z, -30, 30)))
        w_next = z - step * (Xb.T @ (p - y) / n + lam * reg * z)
        t_next = (1 + math.sqrt(1 + 4 * t * t)) / 2
        z = w_next + (t - 1) / t_next * (w_next - w)
        w, t = w_next, t_next
    return w


def predict(w, X):
    return np.hstack([X, np.ones((len(X), 1))]) @ w


def auc(scores, y):
    """Mann-Whitney AUC with average ranks for ties."""
    scores, y = np.asarray(scores, float), np.asarray(y, int)
    order = np.argsort(scores, kind="stable")
    ranks = np.empty(len(scores))
    s = scores[order]
    i = 0
    while i < len(s):
        j = i
        while j + 1 < len(s) and s[j + 1] == s[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j) / 2 + 1
        i = j + 1
    pos, neg = y.sum(), len(y) - y.sum()
    if not pos or not neg:
        return float("nan")
    return float((ranks[y == 1].sum() - pos * (pos + 1) / 2) / (pos * neg))


def group_folds(groups, k, seed):
    rng = np.random.default_rng(seed)
    uniq = sorted(set(groups))
    rng.shuffle(uniq)
    fold_of = {g: i % k for i, g in enumerate(uniq)}
    return np.array([fold_of[g] for g in groups])


def discriminator(eps, folds=5, repeats=3, seed=7, lam=0.05, top=15):
    """Can written first submits be told from real ones? Out-of-fold AUC (folds by group), per writer and mode too."""
    rows = [e for e in eps if e["first"] and not e["first"]["dup"]]
    texts = [e["first"]["message"] for e in rows]
    y = np.array([e["source"] == "written" for e in rows], dtype=int)
    X, names = design(texts)
    groups = [e["group"] for e in rows]
    blocks = {"hand": slice(0, len(HAND)), "ngrams": slice(len(HAND), X.shape[1]), "all": slice(0, X.shape[1])}
    out = {"n_real": int((y == 0).sum()), "n_written": int(y.sum()), "features": len(names), "lambda": lam}
    oof_all = np.zeros(len(rows))
    for block, sl in blocks.items():
        aucs = []
        for r in range(repeats):
            fold = group_folds(groups, folds, seed + r)
            oof = np.zeros(len(rows))
            for f in range(folds):
                tr, te = fold != f, fold == f
                oof[te] = predict(fit_logistic(X[tr][:, sl], y[tr], lam), X[te][:, sl])
            aucs.append(auc(oof, y))
            if block == "all":
                oof_all += oof / repeats
        out[f"auc_{block}"] = {"mean": float(np.mean(aucs)), "repeats": [round(a, 4) for a in aucs]}
    out["auc_all"]["ci"] = auc_ci(oof_all, y, groups, seed)
    real = y == 0
    subsets = {"dest": lambda e: "intent" if e["first"]["dest"] == "intent" else "non-intent"}
    for key in ("writer", "mode", "dest"):
        label = subsets.get(key, lambda e, key=key: e[key])
        for v in sorted({label(e) for e in rows if e["source"] == "written"}):
            sel = real | np.array([e["source"] == "written" and label(e) == v for e in rows])
            out[f"auc_by_{key}:{v}"] = auc(oof_all[sel], y[sel])
    w = fit_logistic(X, y, lam)[:-1]
    real_df, writ_df = X[y == 0].mean(0), X[y == 1].mean(0)
    hand = set(HAND)

    def describe(i):
        d = {"feature": names[i], "coef": round(float(w[i]), 3)}
        if names[i] not in hand:
            d.update(real_share=round(float(real_df[i]), 3), written_share=round(float(writ_df[i]), 3))
        return d
    order = np.argsort(w)
    out["gives_written_away"] = [describe(i) for i in order[::-1][:top]]
    out["looks_real"] = [describe(i) for i in order[:top]]
    out["hand_coefs"] = {n: round(float(w[i]), 3) for i, n in enumerate(HAND)}
    return out


def auc_ci(scores, y, groups, seed, boot=500):
    idx = collections.defaultdict(list)
    for i, g in enumerate(groups):
        idx[g].append(i)
    keys = sorted(idx)
    rng = np.random.default_rng(seed)
    vals = []
    for _ in range(boot):
        pick = np.concatenate([idx[keys[j]] for j in rng.integers(0, len(keys), len(keys))])
        vals.append(auc(scores[pick], y[pick]))
    vals = np.array(vals)
    vals = vals[np.isfinite(vals)]
    return [float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))]


# ------------------------------------------------------------------------------------------------ weights


def stratum(first):
    if first is None:
        return "none"
    w = len(first["message"].split())
    length = next(name for top, name in LENGTH_BUCKETS if w <= top)
    q = "q" if C.QUESTION.search(first["message"].strip()) else "s"
    return f"{length}|{q}|{first['dest']}"


def importance_weights(eps):
    """Written episode → real share / written share of its stratum (add-half smoothing), clipped, mean 1."""
    real = collections.Counter(stratum(e["first"]) for e in eps if e["source"] == "real")
    writ = collections.Counter(stratum(e["first"]) for e in eps if e["source"] == "written")
    cells = sorted(set(real) | set(writ))
    nr, nw = sum(real.values()), sum(writ.values())
    ratio = {}
    for c in cells:
        if c.endswith("|intent"):
            ratio[c] = None
            continue
        pr = (real[c] + 0.5) / (nr + 0.5 * len(cells))
        pw = (writ[c] + 0.5) / (nw + 0.5 * len(cells))
        ratio[c] = pr / pw
    rows = [(e["id"], stratum(e["first"])) for e in eps if e["source"] == "written"]
    comparable = [ratio[s] for _, s in rows if ratio[s] is not None]
    scale = 1.0
    for _ in range(20):  # renormalize to mean 1 after clipping, then clip again, until stable
        clipped = [min(max(r * scale, CLIP_LO), CLIP_HI) for r in comparable]
        scale /= np.mean(clipped) if clipped else 1
    weights = {i: (1.0 if ratio[s] is None else min(max(ratio[s] * scale, CLIP_LO), CLIP_HI)) for i, s in rows}
    cells_out = {c: {"real": real[c], "written": writ[c],
                     "weight": None if ratio[c] is None else round(min(max(ratio[c] * scale, CLIP_LO), CLIP_HI), 3)}
                 for c in cells}
    return weights, rows, cells_out


def weight_summary(weights):
    w = np.array(list(weights.values()))
    return {"n": len(w), "min": float(w.min()), "p10": float(np.percentile(w, 10)), "median": float(np.median(w)),
            "p90": float(np.percentile(w, 90)), "max": float(w.max()), "mean": float(w.mean()),
            "clipped_low": int((w <= CLIP_LO + 1e-9).sum()), "clipped_high": int((w >= CLIP_HI - 1e-9).sum()),
            "ess": float(w.sum() ** 2 / (w ** 2).sum()), "ess_share": float(w.sum() ** 2 / (w ** 2).sum() / len(w))}


# ------------------------------------------------------------------------------------------------ report


def fmt(v, pct=False):
    if v is None or (isinstance(v, float) and not math.isfinite(v)):
        return "—"
    return f"{100 * v:.1f}" if pct else (f"{v:.3g}" if isinstance(v, float) else str(v))


def cell(cmp, name, key, pct):
    d = cmp[name]["vs_real"].get(key)
    if not d:
        return "—"
    ci = d.get("ci")
    s = fmt(d["diff"], pct)
    return s + (f" [{fmt(ci[0], pct)}, {fmt(ci[1], pct)}]" if ci else "")


def markdown(cmp, weighted, disc, wsum, cells, counts):
    names = list(cmp)
    head = lambda cols: ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]  # noqa: E731
    L = ["# Router v2 realism audit: written vs real", "",
         "Generated by `python3 -m v2.build.audit_realism`. Real episodes are the reference; scripted ones are left out. "
         "Message statistics skip `duplicate_of_real` copies and branch-entry submits. Differences are source − real; "
         "brackets are 95% CIs from a bootstrap over whole groups (source session-days).", "",
         "Counts: " + ", ".join(f"{k} {v}" for k, v in counts.items()), "", "## Proportions (%, submit level)", ""]
    L += head(["statistic"] + names)
    for k in PROPS:
        L.append(f"| {k} | " + " | ".join(fmt(cmp[n]["stats"][k], True) for n in names) + " |")
    L += ["", "Difference to real (percentage points, 95% CI):", ""] + head(["statistic"] + names[1:])
    for k in PROPS:
        L.append(f"| {k} | " + " | ".join(cell(cmp, n, k, True) for n in names[1:]) + " |")
    L += ["", "## Distributions (median [p10, p90], mean)", ""] + head(["statistic"] + names)
    for k in DISTS:
        L.append(f"| {k} | " + " | ".join(
            f"{fmt(cmp[n]['stats'][k]['p50'])} [{fmt(cmp[n]['stats'][k]['p10'])}, {fmt(cmp[n]['stats'][k]['p90'])}], "
            f"{fmt(cmp[n]['stats'][k]['mean'])} (n {cmp[n]['stats'][k]['n']})" for n in names) + " |")
    L += ["", "KS D to real (95% CI) / median difference (95% CI):", ""] + head(["statistic"] + names[1:])
    for k in DISTS:
        L.append(f"| {k} | " + " | ".join(f"{cell(cmp, n, k + ':ks', False)} / {cell(cmp, n, k + ':median_diff', False)}"
                                          for n in names[1:]) + " |")
    L += ["", "## Discriminator: written vs real first-submit messages", "",
          f"L2 logistic regression (λ {disc['lambda']}) on {len(HAND)} hand features + character 3-4-grams and word "
          f"unigrams seen in ≥{MIN_DF} messages ({disc['features']} features); {disc['n_real']} real vs "
          f"{disc['n_written']} written; out-of-fold scores, folds by group. 0.5 = indistinguishable.", "",
          f"- AUC all features: **{disc['auc_all']['mean']:.3f}** (95% CI {disc['auc_all']['ci'][0]:.3f}–"
          f"{disc['auc_all']['ci'][1]:.3f}; repeats {disc['auc_all']['repeats']})",
          f"- AUC hand features only: {disc['auc_hand']['mean']:.3f}; n-grams only: {disc['auc_ngrams']['mean']:.3f}"]
    L += [f"- AUC {k[7:]}: {v:.3f}" for k, v in disc.items() if k.startswith("auc_by_")]
    L += ["", "Top features giving written messages away (coefficient; share of real / written messages containing it):",
          ""] + head(["feature", "coef", "real", "written"])
    L += [f"| `{d['feature']!r}` | {d['coef']} | {fmt(d.get('real_share'), True)} | {fmt(d.get('written_share'), True)} |"
          for d in disc["gives_written_away"]]
    L += ["", "Top features that look real:", ""] + head(["feature", "coef", "real", "written"])
    L += [f"| `{d['feature']!r}` | {d['coef']} | {fmt(d.get('real_share'), True)} | {fmt(d.get('written_share'), True)} |"
          for d in disc["looks_real"]]
    L += ["", "## Importance weights (written_weights.jsonl)", "",
          f"Strata: first submit's words ({', '.join(n for _, n in LENGTH_BUCKETS)}) × question × destination. Clipped to "
          f"[{CLIP_LO}, {CLIP_HI}], mean 1 over episodes with a real counterpart; intent episodes keep 1.", "",
          f"- weights: min {wsum['min']:.3g}, p10 {wsum['p10']:.3g}, median {wsum['median']:.3g}, p90 {wsum['p90']:.3g}, "
          f"max {wsum['max']:.3g}; clipped low {wsum['clipped_low']}, high {wsum['clipped_high']}",
          f"- effective sample size {wsum['ess']:.0f} of {wsum['n']} ({100 * wsum['ess_share']:.0f}%)", ""]
    L += head(["stratum", "real", "written", "weight"])
    L += [f"| {c} | {v['real']} | {v['written']} | {fmt(v['weight'])} |" for c, v in cells.items()]
    L += ["", "Reweighted written vs real (difference, 95% CI):", ""] + head(["statistic", "unweighted", "reweighted"])
    for k in ["le5_words", "question", "anaphoric_open", "dest_same", "dest_switch", "dest_new", "lang_fr"]:
        L.append(f"| {k} | {cell(cmp, 'written', k, True)} | {cell(weighted, 'written', k, True)} |")
    for k in ["words", "board_sessions"]:
        L.append(f"| {k} KS D | {cell(cmp, 'written', k + ':ks', False)} | {cell(weighted, 'written', k + ':ks', False)} |")
    return "\n".join(L) + "\n"


def strip(cmp):
    return {n: {"stats": v["stats"], "vs_real": v["vs_real"]} for n, v in cmp.items()}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--boot", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--real", default=str(RAW / "real.jsonl"))
    ap.add_argument("--written", default=str(RAW / "written.jsonl"))
    ap.add_argument("--out", default=str(AUDITS))
    args = ap.parse_args(argv)
    eps, subs = records(load(args.real), load(args.written))
    counts = {"real episodes": sum(e["source"] == "real" for e in eps),
              "written episodes": sum(e["source"] == "written" for e in eps),
              "real submits": sum(s["source"] == "real" for s in subs),
              "written submits (non-duplicate)": sum(s["source"] == "written" and not s["dup"] for s in subs),
              "groups": len({e["group"] for e in eps})}
    cmp = compare(eps, subs, boot=args.boot, seed=args.seed)
    disc = discriminator(eps, args.folds, args.repeats, args.seed)
    weights, rows, cells = importance_weights(eps)
    weighted = compare(eps, subs, extra_weights=weights, boot=args.boot, seed=args.seed)
    wsum = weight_summary(weights)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    md = markdown(cmp, weighted, disc, wsum, cells, counts)
    (out / "realism.json").write_text(json.dumps({"counts": counts, "sources": strip(cmp),
                                                   "reweighted_written": strip(weighted)["written"],
                                                   "discriminator": disc, "weights": {"summary": wsum, "strata": cells}},
                                                  indent=1, ensure_ascii=False) + "\n")
    (out / "realism.md").write_text(md)
    with (out / "written_weights.jsonl").open("w") as f:
        for i, s in rows:
            f.write(json.dumps({"id": i, "weight": round(weights[i], 4), "stratum": s}) + "\n")
    print(md)
    print(f"wrote {out / 'realism.json'}, {out / 'realism.md'}, {out / 'written_weights.jsonl'}")


if __name__ == "__main__":
    main()
