"""fusion: Jev's answers plus board priors (recency, waiting, told) in a small conditional-logit model.

P(dest) ∝ exp(w · f(dest)) over the candidate destinations, with f = Jev's log p and a few board features; send the
top destination when P clears a bar, else ask. A handful of weights, writable in Swift.

python3 bench.py FORMAT --policy explore.fusion:NAME   (NAME in POLICIES)
python3 -m explore.fusion fit FORMAT                     fit on realA (+ others), print weights and scores
"""
import collections
import math
import sys

import pathlib

import formats

HERE = pathlib.Path(__file__).parent.parent

INTENTS = ("question", "compound", "change_lookout")
_CASES = None


def cases_by_id():
    global _CASES
    if _CASES is None:
        import bench
        _CASES = {}
        for s in ("synth", "heldout", "real", "style"):
            for c in bench.load_set(s):
                _CASES[c["id"]] = c
    return _CASES


def _patch_reading():
    """Readings carry their row's id, so a policy can see the board (run.reading is wrapped once, lazily)."""
    import run
    if getattr(run.reading, "_fusion", False):
        return
    orig = run.reading

    def reading(row):
        r = dict(orig(row))
        r["_id"] = row["id"]
        km = row["keymap"]
        r["direct"] = row["answers"].get("fz_direct", {}).get("noul", 0)
        if "fz_about" in row["answers"]:
            r["direct"] = 1 - row["answers"]["fz_about"]["noul"]
        if "fz_who" in row["answers"]:
            r["direct"] = row["answers"]["fz_who"]["probabilities"].get("a session", 0)
        r["follows"] = {km[k]: v["noul"] for k, v in row["answers"].items() if k.startswith("fz_follows")}
        return r
    reading._fusion = True
    run.reading = reading


# ---------------------------------------------------------------- features

def board_facts(board):
    """Per session id: rank among finished (non-running) sessions by recency, idle minutes, running, waits, told rank."""
    ordered = formats.sessions_ordered(board)
    fin = sorted((s for s in ordered if not s.get("running")), key=lambda s: s.get("idle_min", 0))
    rank = {s["id"]: i for i, s in enumerate(fin)}
    waits = {c["session"] for c in formats.waiting_cards(board)}
    hist = sorted(board.get("history", []), key=lambda h: h["ago_min"])
    told = {}
    for i, h in enumerate(hist):
        told.setdefault(h["to"], (i, h["ago_min"]))
    facts = {}
    for s in ordered:
        facts[s["id"]] = dict(rank=rank.get(s["id"]), idle=s.get("idle_min", 0), running=bool(s.get("running")),
                              waits=s["id"] in waits, told=told.get(s["id"]))
    return facts, len(ordered), len(fin)


FEATURES = ["ov", "told10", "direct", "fol", "lp", "jtop", "fin0u", "fin1u", "told0u", "idle5u", "sess", "new", "question", "compound", "change_lookout",
            "fin0", "fin1", "fin2", "run", "idle5", "waits", "reply", "told0", "g_q", "g_c", "g_s"]


def overlap(case):
    """Per session: the share of the message's distinctive words (IDF over the board's sessions) found in its title,
    project, summary and cards."""
    import veto
    board = case["board"]
    texts = {}
    for s in formats.sessions_ordered(board):
        parts = [s["title"], s["project"], s.get("activity", ""), s.get("summary", "")]
        parts += [c["text"] for c in board.get("cards", []) if c["session"] == s["id"]]
        texts[s["id"]] = veto.meaningful(" ".join(parts))
    said = veto.meaningful(case["message"])
    n = max(len(texts), 1)
    idf = {w: math.log((n + 1) / (1 + sum(w in t for t in texts.values()))) for w in said}
    tot = sum(idf.values()) or 1
    return {d: sum(idf[w] for w in said if w in t) / tot for d, t in texts.items()}


def features(r, case):
    """{dest: feature vector dict} for every candidate destination (not `unclear`)."""
    board = case["board"]
    facts, n, nfin = board_facts(board)
    g = r.get("gates") or {}
    replies = r.get("replies") or {}
    u = r["dests"].get("unclear", 0)
    jtop = max(((d, p) for d, p in r["dests"].items() if d != "unclear"), key=lambda x: x[1], default=(None, 0))[0]
    ov = overlap(case)
    out = {}
    for d, p in r["dests"].items():
        if d == "unclear":
            continue
        f = {"lp": math.log(max(p, 1e-3)), "jtop": int(d == jtop)}
        if d in facts:
            x = facts[d]
            f["sess"] = 1
            if x["rank"] is not None and x["rank"] <= 2:
                f[f"fin{x['rank']}"] = 1
            f["run"] = int(x["running"])
            f["idle5"] = int(not x["running"] and x["idle"] <= 5)
            f["waits"] = int(x["waits"])
            f["reply"] = replies.get(d, 0)
            f["fol"] = (r.get("follows") or {}).get(d, 0)
            f["told0"] = int(x["told"] is not None and x["told"][0] == 0)
            f["told10"] = int(x["told"] is not None and x["told"][1] < 10)
            f["ov"] = ov.get(d, 0)
            for k in ("fin0", "fin1", "told0", "idle5"):
                f[k + "u"] = f.get(k, 0) * u
        elif d.startswith("new:"):
            f["new"] = 1
        elif d in INTENTS:
            f[d] = 1
            f["ilong"] = int(len(case["message"]) > 80)
            f["intent"] = 1
            f["gate"] = g.get({"question": "gate_question", "compound": "gate_compound", "change_lookout": "gate_setting"}[d], 0)
            dq = min(max(r.get("direct", 0), 0.01), 0.99)
            f["direct"] = math.log(dq / (1 - dq)) * (d == "question")
            f["g_q"] = g.get("gate_question", 0) * (d == "question")
            f["g_c"] = g.get("gate_compound", 0) * (d == "compound")
            f["g_s"] = g.get("gate_setting", 0) * (d == "change_lookout")
        out[d] = f
    return out


def probs(fs, w):
    s = {d: sum(w.get(k, 0) * v for k, v in f.items()) for d, f in fs.items()}
    m = max(s.values())
    e = {d: math.exp(v - m) for d, v in s.items()}
    z = sum(e.values())
    return {d: v / z for d, v in e.items()}


# ---------------------------------------------------------------- policies

def make_policy(w, bar=0.7, bar_new=None, bar_intent=None, lead=0.0):
    def pol(r):
        case = cases_by_id()[r["_id"]]
        fs = features(r, case)
        if not fs:
            return ("ask", [])
        P = probs(fs, w)
        ranked = sorted(P.items(), key=lambda x: -x[1])
        top, p = ranked[0]
        second = ranked[1][1] if len(ranked) > 1 else 0
        b = bar
        if top.startswith("new:") and bar_new is not None:
            b = bar_new
        if top in INTENTS and bar_intent is not None:
            b = bar_intent
        if p >= b and p - second >= lead:
            return ("send", top)
        return ("ask", [d for d, _ in ranked[:3]])
    return pol


# Fitted on realA + synth + styleA (swift format), rounded. A destination's score: Jev's log p times 0.86 plus what the
# board says about it; P = softmax over destinations (sessions, new sessions, Lookout's intents; not `unclear`).
W = {"lp": 0.86,                                # Jev's route probability (log, floored at 0.001)
     "fin0": 1.51, "fin1": 1.67, "fin2": 0.86,  # the 1st / 2nd / 3rd most recently finished session
     "run": -1.46,                              # still running
     "reply": 1.04,                             # Jev's "is it the answer to this session's card?" yes
     "told0": 0.85,                             # the session the user last wrote to
     "idle5u": 2.89,                            # finished ≤ 5 min ago, times Jev's `unclear` p (the prior takes over)
     "new": 0.04,                               # a new session
     "intent": -0.18, "question": -2.84,        # Lookout's own intents, `question` more so
     "gate": 3.39,                              # the intent's own yes/no gate (question / compound / setting)
     "ilong": -2.18}                            # an intent for a message over 80 characters
# How sure to be of the top: logistic on the moment as a whole.
V = {"bias": 1.81, "lPtop": 0.93,               # the fused top's log-odds
     "u": -0.88,                                # Jev's `unclear` p
     "lenlog": -0.31,                           # log(1 + characters): long messages are harder
     "recent2": -0.42}                          # two or more sessions finished in the last 5 minutes


def make_conf_policy(w, v, bar):
    def pol(r):
        case = cases_by_id()[r["_id"]]
        fs = features(r, case)
        if not fs:
            return ("ask", [])
        top, p = confidence(r, case, fs, w, v)
        if p >= bar:
            return ("send", top)
        P = probs(fs, w)
        return ("ask", sorted(P, key=lambda d: -P[d])[:3])
    return pol


def make_hybrid_policy(w, v, b1, b2):
    """The shipped policy's send when the fusion gives that destination ≥ b1; else the fused top at sureness ≥ b2."""
    conf = make_conf_policy(w, v, b2)
    shipped = []

    def pol(r):
        if not shipped:
            import bench
            shipped.append(bench.policy("final"))
        k, d = shipped[0](r)
        if k == "send":
            fs = features(r, cases_by_id()[r["_id"]])
            if fs and probs(fs, w).get(d, 0) >= b1:
                return ("send", d)
        return conf(r)
    return pol


POLICIES = {
    "hybrid6": make_hybrid_policy(W, V, 0.6, 0.85),
    "hybrid7": make_hybrid_policy(W, V, 0.7, 0.88),
    "hybrid8": make_hybrid_policy(W, V, 0.8, 0.88),
    "fused": make_policy(W, bar=0.85),               # the fused P alone
    "fused_conf": make_conf_policy(W, V, bar=0.85),  # the fused top, sent when the calibrated sureness ≥ 0.85
    "fused_conf88": make_conf_policy(W, V, bar=0.88),
}


def __getattr__(name):
    if name in POLICIES:
        _patch_reading()
        return POLICIES[name]
    raise AttributeError(name)


FOLLOWS_Q = ("Is `message` the user's next message to this session: a reply or follow-up to what it `last said`, "
             "or more work on what it was doing?")


def last_said(board, s):
    cards = [c for c in board.get("cards", []) if c["session"] == s["id"]]
    return (cards[-1]["text"][:400] if cards else "") or s.get("summary", "")[:400] or s.get("activity", "")[:400]


def with_follows(base, k=3):
    """`base` plus one yes/no per recent finished session: is the message its next turn? Same call, asked in parallel."""
    def build(case, rng=None):
        state, q, keymap = formats.FORMATS[base](case, rng=rng)
        board = case["board"]
        fin = sorted((s for s in formats.sessions_ordered(board) if not s.get("running")), key=lambda s: s.get("idle_min", 0))
        q, keymap = dict(q), dict(keymap)
        for i, s in enumerate(fin[:k]):
            q[f"fz_follows{i}"] = {"type": "noul", "instructions": {"question": FOLLOWS_Q, "session": {
                "title": s["title"], "project": s["project"], "last said": last_said(board, s)}}}
            keymap[f"fz_follows{i}"] = s["id"]
        return state, q, keymap
    return build


DIRECT_Q = ("Is `message` spoken to a Claude Code session about its own work (it talks to “you”, asks what it said or did, "
            "or carries on that conversation), rather than asking about the user's sessions from outside (which ones are "
            "running or waiting, is the X one done) or about Lookout itself?")


def with_direct(base):
    def build(case, rng=None):
        state, q, keymap = FORMATS[base](case, rng=rng) if base in FORMATS else formats.FORMATS[base](case, rng=rng)
        return state, {**q, "fz_direct": {"type": "noul", "instructions": {"question": DIRECT_Q}}}, keymap
    return build


WHO = {"type": "choice", "instructions": "Who is `message` spoken to?", "criteria": {
    "a session": ("the Claude Code session the user is working with, about its work: it talks to “you”, asks what it said, "
                  "meant, found or did, or carries on that conversation"),
    "the assistant": ("the user's assistant, about the sessions from outside: names them as “the X one” or as a group "
                      "(“is the CI one done?”, “which ones are running?”, “what's waiting on me?”), or asks to change "
                      "Lookout's inbox, groups or settings"),
}}


def with_who(base):
    def build(case, rng=None):
        state, q, keymap = FORMATS[base](case, rng=rng) if base in FORMATS else formats.FORMATS[base](case, rng=rng)
        return state, {**q, "fz_who": WHO}, keymap
    return build


ABOUT = {"type": "noul", "instructions": {"question": (
    "Does `message` speak about the user's sessions from the outside: it names one by a nickname or topic (“the CI one”, "
    "“the notch session”), asks about several (“which ones”, “anything”), or asks what is waiting on the user?")}}


def with_about(base):
    def build(case, rng=None):
        state, q, keymap = FORMATS[base](case, rng=rng) if base in FORMATS else formats.FORMATS[base](case, rng=rng)
        return state, {**q, "fz_about": ABOUT}, keymap
    return build


FORMATS = {"fz-f3": with_follows("swift")}
FORMATS["fz-f3d"] = with_direct("fz-f3")
FORMATS["fz-f3w"] = with_who("fz-f3")
FORMATS["fz-f3a"] = with_about("fz-f3")


# ---------------------------------------------------------------- fitting (conditional logit, L2, numpy)

def dataset(fmt, sets):
    import bench
    import run
    data = []
    for s in sets:
        src = {"realA": "real", "realB": "real", "styleA": "style", "styleB": "style"}.get(s, s)
        rows = run.load(f"{fmt}@{src}")
        keep = {c["id"] for c in bench.load_set(s)}
        for row in rows:
            if row["id"] not in keep:
                continue
            case = cases_by_id()[row["id"]]
            r = dict(run.reading(row))
            r["_id"] = row["id"]
            data.append((s, case, r))
    return data


def fit(data, l2=1.0, set_weight=None, feats=FEATURES, iters=300):
    import numpy as np
    idx = {k: i for i, k in enumerate(feats)}
    groups = []
    for s, case, r in data:
        gold = set(case["gold"]["to"])
        fs = features(r, case)
        ds = list(fs)
        if not gold & set(ds):
            continue
        X = np.zeros((len(ds), len(feats)))
        for j, d in enumerate(ds):
            for k, v in fs[d].items():
                if k in idx:
                    X[j, idx[k]] = v
        y = np.array([d in gold for d in ds], float)
        groups.append((X, y, (set_weight or {}).get(s, 1.0)))
    w = np.zeros(len(feats))
    w[idx["lp"]] = 1.0

    def loss_grad(w):
        L, G = l2 * w @ w / 2, l2 * w
        for X, y, sw in groups:
            s = X @ w
            s -= s.max()
            e = np.exp(s)
            p = e / e.sum()
            pg = (p * y).sum()
            L -= sw * math.log(max(pg, 1e-12))
            # d/dw -log sum_gold p = E_p[x] - E_{p|gold}[x]
            G += sw * (p @ X - ((p * y) / pg) @ X)
        return L, G
    from scipy.optimize import minimize  # noqa
    res = minimize(loss_grad, w, jac=True, method="L-BFGS-B", options={"maxiter": iters})
    return dict(zip(feats, res.x))


CASE_FEATURES = ["bias", "lPtop", "lgap", "ljev", "agree", "u", "lenlog", "recent2", "top_fin0", "top_intent", "top_new",
                 "top_reply", "top_fol"]


def case_features(r, case, fs, P):
    """What says how sure to be of the fused top, as features of the whole moment."""
    ranked = sorted(P.items(), key=lambda x: -x[1])
    top, p = ranked[0]
    second = ranked[1][1] if len(ranked) > 1 else 0
    jt = max(((d, q) for d, q in r["dests"].items() if d != "unclear"), key=lambda x: x[1])
    facts, n, nfin = board_facts(case["board"])
    recent = sum(1 for x in facts.values() if not x["running"] and x["idle"] <= 5)
    f = fs[top]
    return {"bias": 1, "lPtop": math.log(p / max(1 - p, 1e-4)), "lgap": math.log(max(p - second, 1e-3)),
            "ljev": math.log(max(r["dests"].get(top, 0), 1e-3)), "agree": int(jt[0] == top),
            "u": r["dests"].get("unclear", 0), "lenlog": math.log(1 + len(case["message"])), "recent2": int(recent >= 2),
            "top_fin0": f.get("fin0", 0), "top_intent": int(top in INTENTS), "top_new": f.get("new", 0),
            "top_reply": f.get("reply", 0), "top_fol": f.get("fol", 0)}


def fit_conf(items, w, l2=1.0, feats=CASE_FEATURES):
    """Logistic regression: is the fused top destination right? items: [(case, reading, features)]."""
    import numpy as np
    from scipy.optimize import minimize
    X, y = [], []
    for c, r, fs in items:
        if not fs or not c["gold"]["to"]:
            continue
        P = probs(fs, w)
        top = max(P.items(), key=lambda x: x[1])[0]
        cf = case_features(r, c, fs, P)
        X.append([cf.get(k, 0) for k in feats])
        y.append(top in c["gold"]["to"])
    X, y = np.array(X, float), np.array(y, float)

    def lg(v):
        z = X @ v
        p = 1 / (1 + np.exp(-z))
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + l2 * (v[1:] @ v[1:]) / 2
        g = X.T @ (p - y)
        g[1:] += l2 * v[1:]
        return L, g
    res = minimize(lg, np.zeros(len(feats)), jac=True, method="L-BFGS-B")
    return dict(zip(feats, res.x))


def confidence(r, c, fs, w, v):
    P = probs(fs, w)
    cf = case_features(r, c, fs, P)
    z = sum(v.get(k, 0) * x for k, x in cf.items())
    return max(P.items(), key=lambda x: x[1])[0], 1 / (1 + math.exp(-z))


def load_eval(fmt, sets):
    """{set: [(case, reading, features)]}"""
    out = {}
    for s in sets:
        out[s] = [(c, r, features(r, c)) for _, c, r in dataset(fmt, [s])]
    return out


TYPES = collections.defaultdict(collections.Counter)


def evaluate(ev, w, bar=0.7, bar_new=None, bar_intent=None, lead=0.0, v=None):
    """{set: (right%, wrong%, needless%, fused top1%)} as bench scores them."""
    res = {}
    for s, items in ev.items():
        t = collections.Counter()
        for c, r, fs in items:
            gold = set(c["gold"]["to"])
            ask_ok = c["gold"].get("ask_ok") or not gold
            t["n"] += 1
            if not fs:
                t["needless"] += not ask_ok
                continue
            P = probs(fs, w)
            ranked = sorted(P.items(), key=lambda x: -x[1])
            top, p = ranked[0]
            if v is not None:
                top, p = confidence(r, c, fs, w, v)
                ranked = [(top, p)]
            t["top1"] += top in gold
            gt = "none" if not gold else "intent" if gold & set(INTENTS) else "new" if any(g.startswith("new:") for g in gold) else "sess"
            TYPES[s]["n_" + gt] += 1
            b = bar_new if top.startswith("new:") and bar_new is not None else bar_intent if top in INTENTS and bar_intent is not None else bar
            if p >= b and p - (ranked[1][1] if len(ranked) > 1 else 0) >= lead:
                t["right" if top in gold else "wrong"] += 1
                TYPES[s]["right_" + gt] += top in gold
                t["wi"] += top not in gold and top in INTENTS
                t["wn"] += top not in gold and top.startswith("new:")
            else:
                t["needless"] += not ask_ok
        n = t["n"]
        res[s] = tuple(round(100 * t[k] / n, 1) for k in ("right", "wrong", "needless", "top1", "wi", "wn"))
    return res


def show(res):
    return "  ".join(f"{s}:{r[0]:.0f}/{r[1]:.1f}({r[4]:.1f}i{r[5]:.1f}n)/{r[2]:.0f}/{r[3]:.0f}" for s, r in res.items())


SMALL = ["lp", "fin0", "fin1", "fin2", "run", "reply", "told0", "fin0u", "idle5u", "new", "question", "compound",
         "change_lookout", "g_q", "g_c", "g_s", "ilong"]


def decide(P, case, bar=0.8, bar_intent=None, maxlen=None):
    top, p = max(P.items(), key=lambda x: x[1])
    if top in INTENTS:
        if maxlen is not None and len(case["message"]) > maxlen:
            return False, top
        return p >= (bar_intent if bar_intent is not None else bar), top
    return p >= bar, top


def score_sets(ev, w, **kw):
    out = {}
    for s, items in ev.items():
        t = collections.Counter()
        for c, r, fs in items:
            gold = set(c["gold"]["to"])
            ask_ok = c["gold"].get("ask_ok") or not gold
            t["n"] += 1
            send, top = decide(probs(fs, w), c, **kw) if fs else (False, None)
            if send:
                t["right" if top in gold else "wrong"] += 1
            else:
                t["needless"] += not ask_ok
        out[s] = tuple(100 * t[k] / t["n"] for k in ("right", "wrong", "needless"))
    return out


def hybrid_sets(ev, w, b1, b2, maxlen=None, qdirect=None):
    """Send Jev's own pick (the shipped policy) when the fusion agrees with it at b1, or the fusion's pick at b2."""
    import bench
    final = bench.policy("final")
    out = {}
    for s, items in ev.items():
        t = collections.Counter()
        for c, r, fs in items:
            gold = set(c["gold"]["to"])
            ask_ok = c["gold"].get("ask_ok") or not gold
            t["n"] += 1
            send = None
            if fs:
                P = probs(fs, w)
                top, p = max(P.items(), key=lambda x: x[1])
                k, d = final(r)
                veto = d in INTENTS and maxlen and len(c["message"]) > maxlen
                veto = veto or (d == "question" and qdirect is not None and r.get("direct", 0) > qdirect)
                if k == "send" and P.get(d, 0) >= b1 and not veto:
                    send = d
                elif p >= b2 and top not in INTENTS:
                    send = top
            if send:
                t["right" if send in gold else "wrong"] += 1
                t["wi"] += send not in gold and send in INTENTS
            else:
                t["needless"] += not ask_ok
        out[s] = tuple(100 * t[k] / t["n"] for k in ("right", "wrong", "needless", "wi"))
    return out


def grid(fmt, feats, train=("realA", "synth", "styleA")):
    w = fit(dataset(fmt, list(train)), feats=feats)
    print({k: round(float(x), 2) for k, x in w.items()})
    ev = load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
    for bar in (0.75, 0.8, 0.85, 0.9):
        for bi in (None, 0.6, 0.7, 0.8):
            for ml in (None, 80, 120):
                res = score_sets(ev, w, bar=bar, bar_intent=bi, maxlen=ml)
                print(f"bar={bar} bi={bi} ml={ml}  " + "  ".join(f"{s}:{a:.0f}/{b:.1f}/{c:.0f}" for s, (a, b, c) in res.items()))
    return w


def main():
    _patch_reading()
    cmd, fmt = sys.argv[1], sys.argv[2]
    if cmd == "hybrid":
        w = fit(dataset(fmt, ["realA", "synth", "styleA"]), feats=sys.argv[3].split(",") if len(sys.argv) > 3 else SMALL)
        ev = load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
        for b1 in (0.5, 0.6, 0.7, 0.8):
            for b2 in (0.85, 0.9):
                for ml in (None, 80):
                    for qd in (None, 0.1, 0.2):
                        res = hybrid_sets(ev, w, b1, b2, ml, qd)
                        print(f"b1={b1} b2={b2} ml={ml} qd={qd} " + "  ".join(f"{s}:{a:.0f}/{b:.1f}({i:.1f})/{c:.0f}" for s, (a, b, c, i) in res.items()))
    if cmd == "grid":
        grid(fmt, sys.argv[3].split(",") if len(sys.argv) > 3 else SMALL)
    if cmd == "conf":
        feats, cfeats = sys.argv[3].split(","), sys.argv[4].split(",")
        train = ["realA", "synth", "styleA"]
        w = fit(dataset(fmt, train), feats=feats)
        ev = load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
        v = fit_conf([x for s in train for x in ev[s]], w, feats=cfeats)
        print({k: round(float(x), 2) for k, x in w.items()})
        print({k: round(float(x), 2) for k, x in v.items()})
        for bar in (0.75, 0.8, 0.85, 0.88, 0.9):
            print(f"cbar={bar} " + show(evaluate(ev, w, bar, v=v)))
        import json
        (HERE / "runs" / f"fusion-{fmt}-conf.json").write_text(json.dumps({"w": {k: float(x) for k, x in w.items()}, "v": {k: float(x) for k, x in v.items()}}))
    if cmd == "bars":
        feats = sys.argv[3].split(",")
        w = fit(dataset(fmt, ["realA", "synth", "styleA"]), feats=feats)
        print({k: round(float(x), 2) for k, x in w.items()})
        ev = load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
        for bar in (0.8, 0.85, 0.88, 0.9, 0.92):
            res = score_sets(ev, w, bar=bar)
            print(f"bar={bar} " + "  ".join(f"{s}:{a:.0f}/{b:.1f}/{c:.0f}" for s, (a, b, c) in res.items()))
    if cmd == "fit":
        train = sys.argv[3].split(",") if len(sys.argv) > 3 else ["realA"]
        sw = dict(x.split("=") for x in sys.argv[4].split(",")) if len(sys.argv) > 4 else {}
        sw = {k: float(v) for k, v in sw.items()}
        w = fit(dataset(fmt, train), set_weight=sw)
        print({k: round(float(v), 2) for k, v in w.items()})
        ev = load_eval(fmt, ["synth", "styleA", "styleB", "realA", "realB"])
        print("right/wrong/needless/top1")
        for bar in (0.5, 0.6, 0.7, 0.8, 0.85, 0.9):
            print(f"bar {bar:4}  " + show(evaluate(ev, w, bar)))
        tr = [x for s in train for x in load_eval(fmt, [s])[s]]
        v = fit_conf(tr, w)
        print("conf", {k: round(float(x), 2) for k, x in v.items()})
        import json
        (HERE / "runs" / f"fusion-{fmt}.json").write_text(json.dumps({"w": {k: float(x) for k, x in w.items()}, "v": {k: float(x) for k, x in v.items()}}))
        for bar in (0.6, 0.7, 0.8, 0.85, 0.9, 0.93):
            TYPES.clear()
            print(f"cbar {bar:4} " + show(evaluate(ev, w, bar, v=v)))
            if "-t" in sys.argv:
                print("     ", "  ".join(f"{s}: " + " ".join(f"{k}={100 * T['right_' + k] / T['n_' + k]:.0f}%/{T['n_' + k]}" for k in ("sess", "new", "intent") if T["n_" + k]) for s, T in TYPES.items()))
    if cmd == "diag":
        for which in sys.argv[3].split(","):
            t = collections.Counter()
            for c, r, fs in load_eval(fmt, [which])[which]:
                fol = r.get("follows") or {}
                gold = set(c["gold"]["to"])
                if not fol or not gold & set(fol):
                    t["gold_not_in_k"] += 1
                    continue
                t["n"] += 1
                facts, _, _ = board_facts(c["board"])
                t["fol_argmax"] += max(fol, key=fol.get) in gold
                t["lp_argmax"] += max(fol, key=lambda d: r["dests"].get(d, 0)) in gold
                t["fin0"] += min(fol, key=lambda d: facts[d]["rank"]) in gold
                t["fol_gold_mean"] += sum(fol[d] for d in fol if d in gold)
                t["fol_other_mean"] += sum(fol[d] for d in fol if d not in gold) / max(len(fol) - 1, 1)
            print(which, {k: (v if k in ("n", "gold_not_in_k") else round(v / t["n"], 2)) for k, v in t.items()})
    if cmd == "rules":
        for which in sys.argv[3].split(","):
            t = collections.Counter()
            for c, r, fs in load_eval(fmt, [which])[which]:
                gold = set(c["gold"]["to"])
                t["n"] += 1
                for d, f in fs.items():
                    for name, ok in (("fin0", f.get("fin0")), ("fin0&told0", f.get("fin0") and f.get("told0")), ("told10", f.get("told10")), ("told10&fin0", f.get("told10") and f.get("fin0")),
                                     ("told10&fin01", f.get("told10") and (f.get("fin0") or f.get("fin1"))), ("told10&jtop", f.get("told10") and f.get("jtop")),
                                     ("told0&fin01&jtop", f.get("told0") and (f.get("fin0") or f.get("fin1")) and f.get("jtop")),
                                     ("told0", f.get("told0")), ("fin0&idle5", f.get("fin0") and f.get("idle5")),
                                     ("fin0&told0&jtop", f.get("fin0") and f.get("told0") and f.get("jtop")),
                                     ("fin0&jtop", f.get("fin0") and f.get("jtop")), ("fin1&jtop", f.get("fin1") and f.get("jtop")),
                                     ("jtop&lp>-.36", f.get("jtop") and f["lp"] > -0.36), ("sess&jtop&lp>-.36", f.get("sess") and f.get("jtop") and f["lp"] > -0.36),
                                     ("sess&jtop&lp>-.1", f.get("sess") and f.get("jtop") and f["lp"] > -0.1), ("int&jtop&lp>-.36", d in INTENTS and f.get("jtop") and f["lp"] > -0.36),
                                     ("new&jtop&lp>-.5", f.get("new") and f.get("jtop") and f["lp"] > -0.5), ("fin0&jtop&lp>-.36", f.get("fin0") and f.get("jtop") and f["lp"] > -0.36),
                                     ("fin012&jtop&lp>-.36", (f.get("fin0") or f.get("fin1") or f.get("fin2")) and f.get("jtop") and f["lp"] > -0.36),
                                     ("fin0&told0&jtop&lp>-.7", f.get("fin0") and f.get("told0") and f.get("jtop") and f["lp"] > -0.7)):
                        if ok:
                            t[name + " fires"] += 1
                            t[name + " right"] += d in gold
            n = t.pop("n")
            print(which, n, "  ".join(f"{k[:-6]}: {100 * t[k] / n:.0f}% fires, {100 * t[k[:-6] + ' right'] / max(t[k], 1):.0f}% right" for k in t if k.endswith("fires")))
    if cmd == "intents":
        import statistics as st
        for which in sys.argv[3].split(","):
            rows = []
            for c, r, fs in load_eval(fmt, [which])[which]:
                jt, jp = max(((d, q) for d, q in r["dests"].items() if d != "unclear"), key=lambda x: x[1])
                if jt not in INTENTS or jp < 0.6:
                    continue
                fol = r.get("follows") or {}
                g = r.get("gates") or {}
                if "-v" in sys.argv:
                    print("   ", jt in c["gold"]["to"], jt, round(r.get("direct", 0), 2), repr(c["message"][:150]))
                rows.append(dict(right=jt in c["gold"]["to"], fol=max(fol.values(), default=0), g=g.get("gate_" + {"question": "question", "compound": "compound", "change_lookout": "setting"}[jt], 0),
                                 direct=r.get("direct", 0), len=len(c["message"]), bestsess=max((q for d, q in r["dests"].items() if d in fs and fs[d].get("sess")), default=0), kind=jt))
            for right in (True, False):
                rs = [x for x in rows if x["right"] == right]
                if rs:
                    print(which, "right" if right else "wrong", len(rs), ">.2:", sum(x["direct"] > .2 for x in rs), "len>60", sum(x["len"] > 60 for x in rs), "len>80", sum(x["len"] > 80 for x in rs), ">.1:", sum(x["direct"] > .1 for x in rs), ">.15:", sum(x["direct"] > .15 for x in rs), {k: round(st.median(x[k] for x in rs), 2) for k in ("fol", "g", "direct", "len", "bestsess")}, collections.Counter(x["kind"] for x in rs))
    if cmd == "errors":
        import json
        m = json.loads((HERE / "runs" / f"fusion-{fmt}.json").read_text()); w, v = m["w"], m["v"]
        bar = float(sys.argv[3]); which = sys.argv[4]
        for c, r, fs in load_eval(fmt, [which])[which]:
            if not fs:
                continue
            P = probs(fs, w)
            top, p = confidence(r, c, fs, w, v)
            gold = c["gold"]["to"]
            if p >= bar and top not in gold:
                g = gold[0] if gold else None
                print(f"{c['id']:18} {c['gold'].get('label')} p={p:.2f} top={top[:12]:12} {fs[top]} | gold={str(g)[:12]} P={P.get(g, 0):.2f} {fs.get(g)} | jevtop={max(r['dests'].items(), key=lambda x: x[1])} :: {c['message'][:140]!r}")


if __name__ == "__main__":
    main()
