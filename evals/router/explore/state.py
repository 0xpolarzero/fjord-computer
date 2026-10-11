"""Session state × message type: a terse message ("go", "yes", "commit it", "what does X mean?") is decidable only
against what each candidate's last message asked. Both are read in code (what Lookout has at send time: the message,
each session's last paragraph, its idle time), and their products are added to fuse3's conditional logit.

python3 -m explore.state diag            how often each state holds on the gold vs other candidates, per message type
python3 -m explore.state fit FORMAT      fit on realA + synth + styleA; scores on every set (realB, heldout honest)
python3 bench.py FORMAT --policy explore.state:NAME"""
import collections
import math
import re
import sys

from explore import fuse3
from explore import fusion as Fu

# ---------------------------------------------------------------- the message

AFF = re.compile(r"^\s*(yes|yep|yeah|yup|y|ok|okay|k|sure|go|go ahead|go for it|do it|do that|lgtm|approved?|alright|"
                 r"sounds good|perfect|great|good|nice|please|proceed|ship it|continue|carry on|let'?s go|let'?s do it|"
                 r"merge it|commit it|push it|publish it|release it|fine|correct|right|exactly|agreed?|oui|vas-y|ready)\b",
                 re.I)
NEG = re.compile(r"^\s*(no|nope|nah|don'?t|do not|not yet|stop|wait|cancel|hold on|never ?mind|non)\b", re.I)
PICK = re.compile(r"^\s*(\d{1,2}|[a-d]|option \w+|the (first|second|third|last|other) (one)?|first|second|third|both|"
                  r"neither|either|[a-d] and [a-d]|\d and \d)\s*([.,!:)-]|$)", re.I)
WH = re.compile(r"^\s*(what|why|how|where|when|which|who|is|are|does|do|did|can|could|should|would|will|was|were)\b", re.I)
REF = re.compile(r"\b(it|that|this|those|these|them|there|same)\b", re.I)


def msg_type(m):
    """One label per message, first match wins, plus its length class."""
    w = len(m.split())
    if PICK.search(m) and w <= 6:
        t = "pick"
    elif AFF.search(m) and w <= 8:
        t = "aff"
    elif NEG.search(m) and w <= 10:
        t = "neg"
    elif m.rstrip().endswith("?") or (WH.search(m) and w <= 12):
        t = "q"
    elif w > 25:
        t = "long"
    elif REF.search(m) and w <= 10:
        t = "ref"
    else:
        t = "other"
    return t, w


# ---------------------------------------------------------------- the session's last message

ASKS = re.compile(r"\?\s*(\*\*)?\s*$|\b(want me to|should i|shall i|do you want|which one|would you like|"
                  r"let me know|tell me|say \*{0,2}\"?\w+|your call|up to you|confirm|approve|if you agree)\b", re.I)
PROPOSE = re.compile(r"\b(want me to|shall i|should i|i can|i could|i'?ll|i will|i'?d|next step|next,|then i|if you want|"
                     r"if you'?d like|if you confirm|unless you|ready to|once you)\b", re.I)
CHOICE = re.compile(r"(\b(or|either|option|which|vs\.?|versus)\b.*\?|^\s*(\d[.)]|[-*] \*\*|[a-c][.)])\s)", re.I | re.M)
OPEN = re.compile(r"\b(uncommitted|not (yet )?committed|haven'?t (committed|pushed)|nothing (is )?committed|not pushed|"
                  r"before (i )?commit|commit (it|this|them)\??|ready to (commit|merge|push)|in the working tree)\b", re.I)
DONE = re.compile(r"\b(done|pushed|committed|merged|published|released|shipped|fixed|passes|passing|all \d+ tests|"
                  r"is live|installed|deployed|complete|finished|that'?s it)\b", re.I)
WAITS_USER = re.compile(r"\b(when you'?re ready|once you|you (need to|can|should|could) (now )?\w+|your turn|run it|"
                        r"try it|have a look|check it|send (me|any))\b", re.I)


def last_text(board, sid):
    cards = [c for c in board.get("cards", []) if c["session"] == sid]
    return cards[-1]["text"] if cards else ""


def sess_state(text, kind=None):
    t = text or ""
    asks = bool(ASKS.search(t)) or kind in ("question", "approval", "plan", "asks")
    return {"asks": int(asks), "prop": int(bool(PROPOSE.search(t))), "choice": int(bool(CHOICE.search(t))),
            "open": int(bool(OPEN.search(t))), "done": int(bool(DONE.search(t)) and not asks),
            "wuser": int(bool(WAITS_USER.search(t))), "qmark": int(t.rstrip(" *").endswith("?")), "empty": int(not t)}


def states(case):
    b = case["board"]
    kinds = {c["session"]: c["kind"] for c in b.get("cards", [])}
    return {s["id"]: sess_state(last_text(b, s["id"]), kinds.get(s["id"])) for s in b["sessions"]}


# ---------------------------------------------------------------- features

TYPES = ("aff", "neg", "pick", "q", "ref", "long", "other")
STATES = ("asks", "prop", "choice", "open", "done", "wuser", "qmark")


def features(r, case):
    out = fuse3.features(r, case)
    t, nw = msg_type(case["message"])
    short = int(nw < 5)
    st = states(case)
    b = case["board"]
    idle = {s["id"]: (0 if s.get("running") else s.get("idle_min", 0)) for s in b["sessions"]}
    # how many candidates are in each state: a lone asker matters more than one of five
    n_in = {k: sum(x[k] for x in st.values()) for k in STATES}
    for d, f in out.items():
        if not f.get("sess"):
            if d.startswith("new:"):
                f["new_short"] = short
                f["new_terse"] = int(t in ("aff", "neg", "pick", "ref"))
            elif d in Fu.INTENTS:
                f["int_terse"] = int(t in ("aff", "neg", "pick", "ref"))
            continue
        s = st.get(d) or sess_state("")
        f["lidle"] = math.log1p(idle.get(d, 0))
        f["lidle_s"] = f["lidle"] * short
        for k in STATES:
            f["s_" + k] = s[k]
        f["s_asks1"] = int(s["asks"] and n_in["asks"] == 1)
        for tt in TYPES:
            on = int(t == tt)
            if not on:
                continue
            for k in STATES:
                f[f"{tt}x{k}"] = s[k]
        # terse = a reply that only makes sense against a question
        terse = int(t in ("aff", "neg", "pick", "ref") or short)
        f["terse_asks"] = terse * s["asks"]
        f["terse_asks1"] = terse * f["s_asks1"]
        f["terse_prop"] = terse * s["prop"]
        f["terse_fin0"] = terse * f.get("fin0", 0)
        f["terse_lidle"] = terse * f["lidle"]
    return out


Fu.features = features
BASE = fuse3.FEATS
INTER = ["lidle", "lidle_s", "terse_asks", "terse_asks1", "terse_prop", "terse_fin0", "terse_lidle",
         "affxasks", "affxprop", "affxopen", "negxasks", "pickxchoice", "pickxasks", "qxasks", "qxdone", "refxasks",
         "refxprop", "refxwuser", "longxasks", "otherxwuser", "otherxasks", "s_asks", "s_prop", "s_done", "s_asks1",
         "new_short", "new_terse", "int_terse"]
SETS = {
    "base": BASE,
    "idle": BASE + ["lidle", "lidle_s"],
    "state": BASE + ["s_asks", "s_prop", "s_done", "s_asks1", "s_open", "s_wuser"],
    "terse": BASE + ["terse_asks", "terse_asks1", "terse_prop", "terse_fin0", "terse_lidle", "lidle", "new_terse",
                     "int_terse"],
    "all": BASE + INTER,
    "terse2": BASE + ["terse_asks", "terse_asks1", "terse_prop", "terse_fin0", "terse_lidle", "lidle", "new_terse",
                      "int_terse", "affxprop", "affxasks", "pickxchoice", "pickxasks", "negxasks", "qxasks"],
    "lean": BASE + ["terse_asks1", "new_terse", "int_terse"],
}


def make_guarded(w, v, b1=0.5, b2=0.9, min_words=3, terse_bar=None, terse_states=("s_asks",), terse_any=False):
    """fuse3's guarded decision. With `terse_bar`, a message under `min_words` words may still go to the fused top
    session when its sureness clears `terse_bar` and that session's last message asks something."""
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
        nw = len(case["message"].split())
        if top not in Fu.INTENTS:
            if p >= b2 and nw >= min_words:
                return ("send", top)
            if terse_bar is not None and nw < min_words and p >= terse_bar and (
                    terse_any or any(fs[top].get(k) for k in terse_states)):
                return ("send", top)
        return ("ask", sorted(P, key=lambda x: -P[x])[:3])
    pol.needs_case = True
    return pol


def fitted(fmt, feats, l2=1.0):
    w = Fu.fit(Fu.dataset(fmt, ["realA", "synth", "styleA"]), feats=feats, l2=l2)
    ev = Fu.load_eval(fmt, ["realA", "synth", "styleA"])
    v = Fu.fit_conf([x for s in ev for x in ev[s]], w)
    return w, v


def scored(fmt, pol, sets):
    import bench
    import run
    out = {}
    for s, cases in sets.items():
        ids = {c["id"] for c in cases}
        whole = {"realA": "real", "realB": "real", "styleB": "style", "styleA": "style"}.get(s, s)
        rows = [r for r in run.load(f"{fmt}@{whole}") if r["id"] in ids and r["order"] == 0]
        out[s] = bench.score(cases, rows, pol)
    return out


def short_split(fmt, pol, cases):
    """right / wrong / needless on messages under 5 words vs the rest."""
    import run
    by = {c["id"]: c for c in cases}
    t = collections.Counter()
    for row in run.load(f"{fmt}@real"):
        if row["id"] not in by or row["order"]:
            continue
        c = by[row["id"]]
        k, d = pol(run.reading(row), c)
        g = "short" if len(c["message"].split()) < 5 else "rest"
        t[g + "n"] += 1
        if k == "send":
            t[g + ("right" if d in c["gold"]["to"] else "wrong")] += 1
        else:
            t[g + "needless"] += c["gold"].get("label") == "clear"
    return "  ".join(f"{g}: n={t[g + 'n']} {t[g + 'right']}/{t[g + 'wrong']}/{t[g + 'needless']}" for g in ("short", "rest"))


def diag():
    """Per message type: share of gold vs other session candidates in each state (realA + styleA + synth)."""
    import bench
    tab = collections.defaultdict(collections.Counter)
    for s in ("realA", "styleA", "synth"):
        for c in bench.load_set(s):
            t, nw = msg_type(c["message"])
            gold = set(c["gold"]["to"])
            st = states(c)
            for sid, x in st.items():
                g = "gold" if sid in gold else "other"
                tab[(s, t)][g + "_n"] += 1
                for k in STATES:
                    tab[(s, t)][g + "_" + k] += x[k]
    for (s, t), c in sorted(tab.items()):
        gn, on = max(c["gold_n"], 1), max(c["other_n"], 1)
        print(f"{s:6} {t:6} gold n={c['gold_n']:3} " + " ".join(
            f"{k}:{100 * c['gold_' + k] / gn:3.0f}/{100 * c['other_' + k] / on:3.0f}" for k in STATES))


def show(fmt, feats="base", which="realA", only="short"):
    """Print the asks on clear moments and the wrong sends, with the gold's and the top's states."""
    import bench
    import run
    w, v = fitted(fmt, SETS[feats])
    pol = make_guarded(w, v)
    by = {c["id"]: c for c in bench.load_set(which)}
    src = {"realA": "real", "realB": "real", "styleA": "style", "styleB": "style"}.get(which, which)
    for row in run.load(f"{fmt}@{src}"):
        if row["id"] not in by or row["order"]:
            continue
        c = by[row["id"]]
        if only == "short" and len(c["message"].split()) >= 5:
            continue
        r = run.reading(row)
        k, d = pol(r, c)
        gold = c["gold"]["to"]
        bad = (k == "send" and d not in gold) or (k == "ask" and c["gold"].get("label") == "clear")
        if not bad:
            continue
        fs = features(r, c)
        P = Fu.probs(fs, w)
        top, p = Fu.confidence(r, c, fs, w, v)
        g = gold[0] if gold else None
        st = states(c)

        def ks(x):
            return "".join(k[0] for k in STATES if (st.get(x) or {}).get(k))

        def fin(x):
            return [i for i in range(3) if (fs.get(x) or {}).get(f"fin{i}")]
        print(f"{k:4} {c['id']:16} {str(c['gold'].get('label')):9} {msg_type(c['message'])[0]:5} conf={p:.2f} "
              f"top={str(top)[:8]} P={P[top]:.2f} st={ks(top)} fin={fin(top)} | gold={str(g)[:8]} P={P.get(g, 0):.2f} "
              f"st={ks(g)} fin={fin(g)} jev={r['dests'].get(g, 0):.2f} :: {c['message'][:90]!r}")


def main():
    import bench
    Fu._patch_reading()
    cmd = sys.argv[1]
    if cmd == "diag":
        return diag()
    if cmd == "show":
        return show(sys.argv[2], *sys.argv[3:])
    if cmd == "terse":
        fmt = sys.argv[2]
        sets = {s: bench.load_set(s) for s in ("synth", "styleA", "styleB", "realA", "realB", "heldout")}
        for name in sys.argv[3].split(","):
            w, v = fitted(fmt, SETS[name])
            for tb, ts_, any_ in ((None, (), False), (0.9, ("s_asks",), False), (0.95, ("s_asks", "s_prop", "s_wuser"), False),
                                  (0.9, ("s_asks", "s_prop", "s_wuser"), False), (0.95, (), True), (0.9, (), True)):
                pol = make_guarded(w, v, terse_bar=tb, terse_states=ts_, terse_any=any_)
                res = scored(fmt, pol, sets)
                print(f"{name:6} terse={tb} {','.join(ts_) or ('any' if any_ else '-'):20} " + "  ".join(
                    f"{s}:{100 * t['right'] / t['n']:.1f}/{100 * t['wrong'] / t['n']:.1f}/{100 * t['needless'] / t['n']:.0f}"
                    for s, t in res.items()))
        return
    fmt = sys.argv[2]
    which = sys.argv[3].split(",") if len(sys.argv) > 3 else list(SETS)
    sets = {s: bench.load_set(s) for s in ("synth", "styleB", "realA", "realB", "heldout")}
    for name in which:
        w, v = fitted(fmt, SETS[name])
        print(f"### {name}", {k: round(float(x), 2) for k, x in w.items() if k not in fuse3.FEATS})
        for b1, b2, tb in ((0.5, 0.9, None), (0.5, 0.85, None), (0.5, 0.9, 0.9), (0.5, 0.9, 0.95)):
            pol = make_guarded(w, v, b1, b2, terse_bar=tb)
            res = scored(fmt, pol, sets)
            print(f"  b1={b1} b2={b2} terse={tb}  " + "  ".join(
                f"{s}:{100 * t['right'] / t['n']:.1f}/{100 * t['wrong'] / t['n']:.1f}/{100 * t['needless'] / t['n']:.0f}"
                for s, t in res.items()) + "   realA " + short_split(fmt, pol, sets["realA"]))


if __name__ == "__main__":
    main()


_POL = {}


def __getattr__(name):
    """best: lean features + the terse rule, fitted on realA + synth + styleA (format combo-o)."""
    if name in ("best", "base_terse"):
        if name not in _POL:
            Fu._patch_reading()
            w, v = fitted("combo-o", SETS["lean" if name == "best" else "base"])
            _POL[name] = make_guarded(w, v, terse_bar=0.95, terse_states=("s_asks", "s_prop", "s_wuser"))
        return _POL[name]
    raise AttributeError(name)
