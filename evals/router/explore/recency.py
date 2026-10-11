"""Recency and conversation continuity (explorer: recency).

On real moments the message mostly goes to the session that finished last (the user just read what it said). Jev reads
"finished 3m ago" poorly, so these formats say recency in words, order options by it, or ask per recent session whether
`message` is the user's next message in that conversation."""
import json

import formats as F


def recency_words(idle_min, rank):
    """Categorical recency for a session that is not running; rank = its place among non-running sessions by recency."""
    if idle_min < 1:
        when = "just now"
    elif idle_min < 15:
        when = "a few minutes ago"
    elif idle_min < 90:
        when = "within the last hour"
    elif idle_min < 60 * 24:
        when = "hours ago"
    else:
        when = "days ago"
    return when


def ago_words(m):
    return recency_words(m, None)


def finished_by_recency(board):
    return sorted([s for s in board["sessions"] if not s.get("running")], key=lambda s: s.get("idle_min", 0))


def last_said(board, s):
    cards = [c for c in board.get("cards", []) if c["session"] == s["id"]]
    return (cards[-1]["text"] if cards else "") or s.get("summary", "") or s.get("activity", "")


def last_told(board, s):
    mine = [h for h in board.get("history", []) if h["to"] == s["id"]]
    return mine[-1] if mine else None


NEXT_QUESTIONS = {
    "next": "Is `message` the user's next message in `conversation`: what the user says back to it?",
    "reply": "Does `message` reply to the last thing said in `conversation`, or continue it?",
    "follow": ("Does `message` follow up on `conversation`: the user answering, questioning or reacting to what the "
               "session said last, or telling it more about the same work?"),
    "addressed": ("Is `message` addressed to the Claude Code session in `conversation`, about its work, rather than "
                  "about something else?"),
    "same": ("Is `message` about the same work as `conversation`: something the user says to that session next, "
             "not a different task or a question about the user's other sessions or settings?"),
}


def rec(case, rng=None, words=True, latest=False, order="lookout", nxt=0, told_words=True, latest_field=False,
        nxt_q="next", gates=True, cont=0, cont_q="a"):
    """v3-told (+ gates), with:
    words: "finished 3m ago" → "finished a few minutes ago", plus "latest": true on the session that finished last
    order: "lookout" (running first, then by recency) | "finished" (non-running by recency first, then running)
    nxt: for the N most recently finished sessions, a yes/no "is `message` the user's next message in this conversation?"
    latest_field: state names the session that finished last and what it said."""
    state, q, keymap = F.v2(case, rng=rng, told=True)
    board = case["board"]
    by = F.session_by_id(board)
    fin = finished_by_recency(board)
    rank = {s["id"]: i for i, s in enumerate(fin)}
    crit = q["route"]["criteria"]
    for name, dest in keymap.items():
        if dest not in by or not isinstance(crit.get(name), dict):
            continue
        s = by[dest]
        c = crit[name]
        if words and not s.get("running"):
            now = c["now"]
            ago_txt = F.ago(s.get("idle_min", 0))
            now = now.replace(ago_txt, ago_words(s.get("idle_min", 0)), 1)
            c["now"] = now
        if latest and rank.get(dest) == 0:
            c["the latest to finish"] = True
        if told_words and "the user last told it" in c:
            h = last_told(board, s)
            c["the user last told it"] = f"{h['you'][:160]} ({ago_words(h['ago_min'])})"
    if order == "finished" and rng is None:
        names = list(crit)
        sess = [n for n in names if keymap[n] in by]
        rest = [n for n in names if keymap[n] not in by]
        sess.sort(key=lambda n: (by[keymap[n]].get("running", False), by[keymap[n]].get("idle_min", 0)))
        q["route"]["criteria"] = {n: crit[n] for n in sess + rest}
    if latest_field and fin:
        s = fin[0]
        state["the session that finished last"] = {"name": [n for n, d in keymap.items() if d == s["id"]][0],
                                                   "it said": last_said(board, s)[:300]}
    for i, s in enumerate(fin[:nxt]):
        conv = []
        h = last_told(board, s)
        if h:
            conv.append({"user": h["you"][:300]})
        said = last_said(board, s)
        if said:
            conv.append({"session": said[:400]})
        if not conv:
            continue
        q[f"gate_next_{s['id']}"] = {"type": "noul", "instructions": {
            "question": NEXT_QUESTIONS[nxt_q], "conversation": conv}}
    if gates:
        q.update(F.GATES)
    q = {**q, "route": {**q["route"], "criteria": {k.replace(".", "_"): v for k, v in q["route"]["criteria"].items()}}}
    keymap = {k.replace(".", "_"): v for k, v in keymap.items()}
    if cont:
        names = {d: n for n, d in keymap.items()}
        crit, ckm = {}, {}
        for s in fin[:cont]:
            conv = {}
            h = last_told(board, s)
            if h:
                conv["the user told it"] = h["you"][:300]
            said = last_said(board, s)
            if said:
                conv["it said"] = said[:400]
            if not conv:
                continue
            crit[names[s["id"]]] = conv
            ckm[names[s["id"]]] = s["id"]
        if crit:
            crit["none"] = CONT_NONE
            q["cont"] = {"type": "choice", "instructions": CONT_INSTRUCTIONS[cont_q], "criteria": crit}
            keymap["cont"] = ckm
    return state, q, keymap


CONT_INSTRUCTIONS = {
    "a": ("Which of these conversations does `message` continue: the user replying to, asking about or adding to what "
          "that session said last? `none` if `message` starts something else."),
}
CONT_NONE = ("none of these: a new task, a question about the user's sessions or Lookout, a Lookout setting, several "
             "things at once, or a message for another session")


def _patch_reading():
    """run.reading, plus r['cont'] = {session: p} from the continuation choice."""
    import run
    if getattr(run.reading, "_recency", False):
        return
    orig = run.reading

    def reading(row):
        r = orig(row)
        a = row["answers"]
        if "cont" in a and "cont" not in r:
            km = row["keymap"].get("cont", {})
            r["cont"] = {km.get(k, k): p for k, p in a["cont"].get("probabilities", {}).items()}
        return r
    reading._recency = True
    run.reading = reading


FORMATS = {
    "rec-words": lambda c, rng=None: rec(c, rng),
    "rec-latest": lambda c, rng=None: rec(c, rng, latest=True),
    "rec-order": lambda c, rng=None: rec(c, rng, words=False, told_words=False, order="finished"),
    "rec-lfield": lambda c, rng=None: rec(c, rng, words=False, told_words=False, latest_field=True),
    "rec-next3": lambda c, rng=None: rec(c, rng, words=False, told_words=False, nxt=3),
}
for _q in ("reply", "follow", "addressed", "same"):
    FORMATS[f"rec-next3-{_q}"] = (lambda q_: lambda c, rng=None: rec(c, rng, words=False, told_words=False, nxt=3, nxt_q=q_))(_q)
FORMATS["rec-cont3"] = lambda c, rng=None: rec(c, rng, words=False, told_words=False, cont=3)


# ---------------------------------------------------------------- policies

def final(r):
    """The shipped policy (bench FINAL)."""
    import analyze
    import bench
    return analyze.policy("gates", **bench.FINAL)(r)


INTENT_KEYS = ("question", "compound", "change_lookout")


def nexts(r):
    g = r.get("gates") or {}
    return sorted(((k[len("gate_next_"):], v) for k, v in g.items() if k.startswith("gate_next_")), key=lambda x: -x[1])


def make_policy(a=0.5, m=0.3, block=None, conflict=0.7, agree=None):
    """The next-message check first: one recent session clearly says yes (≥ a, ahead of the others by m) → send to it,
    unless the route is sure (≥ conflict) of another session. agree: instead, send only when the route's top is that
    session or unclear, or is under `agree` (whatever it is). block: an intent send is asked instead when any recent
    session's next-message yes is at least this."""
    import run

    def pol(r):
        ns = nexts(r)
        if ns:
            best, y = ns[0]
            y2 = ns[1][1] if len(ns) > 1 else 0
            if y >= a and y - y2 >= m:
                top, p = max(r["dests"].items(), key=lambda x: x[1])
                if agree is not None:
                    if top in (best, "unclear") or p < agree:
                        return ("send", best)
                elif top != best and p >= conflict and top not in INTENT_KEYS and top != "unclear" and not top.startswith("new:"):
                    return ("ask", [best, top])
                else:
                    return ("send", best)
        k, w = final(r)
        if block is not None and k == "send" and w in INTENT_KEYS and ns and ns[0][1] >= block:
            return ("ask", run.ranked_targets(r)[:3])
        return (k, w)
    return pol


nx = make_policy()
nx_block = make_policy(block=0.4)
# best on realA without hurting synth/heldout/style (format rec-next3-addressed)
nx_best = make_policy(a=0.5, m=0.3, agree=0.4)


def intents_bar(pol, bar=0.85):
    """Lookout's own intents only when the route itself is at least `bar` sure of it (else ask)."""
    import run

    def p(r):
        k, w = pol(r)
        if k == "send" and w in INTENT_KEYS and r["dests"].get(w, 0) < bar:
            return ("ask", run.ranked_targets(r)[:3])
        return (k, w)
    return p


nx_best_bar85 = intents_bar(nx_best, 0.85)
nx_best_bar95 = intents_bar(nx_best, 0.95)


def cont_policy(a=0.5, c=0.6, block=None, other=None):
    """The continuation choice first: its top session p ≥ a, and the route agrees, says unclear, or is under c → send
    there. Else the shipped policy, except: an intent send is asked when the continuation's top session is ≥ block,
    and a send to another session is asked when it is ≥ other."""
    import run

    def pol(r):
        cs = sorted(((d, p) for d, p in (r.get("cont") or {}).items() if d != "none"), key=lambda x: -x[1])
        s, ps = cs[0] if cs else (None, 0)
        top, pt = max(r["dests"].items(), key=lambda x: x[1])
        if s and ps >= a and (top in (s, "unclear") or pt < c):
            return ("send", s)
        k, w = final(r)
        if k == "send" and s and w != s:
            if block is not None and w in INTENT_KEYS and ps >= block:
                return ("ask", run.ranked_targets(r)[:3])
            if other is not None and w not in INTENT_KEYS and ps >= other:
                return ("ask", run.ranked_targets(r)[:3])
        return (k, w)
    return pol


POLICIES = {
    "ct": lambda: cont_policy(),
}


def __getattr__(name):
    """Policies that need the continuation reading: bench.policy() gets them by name, after run is loaded."""
    if name in POLICIES:
        _patch_reading()
        return POLICIES[name]()
    raise AttributeError(name)
