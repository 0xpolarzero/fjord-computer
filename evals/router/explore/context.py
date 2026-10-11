"""Explorer `context`: what each session is described by.

Real boards only carry a session's title, its last answer's last paragraph (the card) and your last message to it. Here
each option can also say what the session was first asked, more of its last answer, and so on. The richer fields for real
(and Router-style) boards are derived from real/data/corpus.jsonl as it stood at the moment of each case:

  python3 -m explore.context derive      →  real/data/ctx_extra.json  (case id → session id → fields)
  python3 -m explore.context bench FMT [--policy ...] [--sets ...]   (bench.py, importing formats first)

Synth/heldout boards have no corpus; there the formats fall back to what the board has (its summary/activity)."""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
EXTRA_PATH = HERE / "real" / "data" / "ctx_extra.json"
_extra = None

# Long random-looking tokens (keys the board redaction can miss, e.g. "hex.alnum" keys).
TOKEN = re.compile(r"\b(?=[A-Za-z0-9._-]*\d)(?=[A-Za-z0-9._-]*[A-Za-z])[A-Za-z0-9._-]{28,}\b")


# ---------------------------------------------------------------- derivation from the corpus

def derive():
    sys.path.insert(0, str(HERE / "real"))
    import boards as rb
    import bisect
    import glob
    sessions = rb.load()
    by = {}
    for s in sessions:
        by.setdefault(s["id"][:8], []).append(s)

    def red(t):
        return TOKEN.sub("[redacted]", rb.redact(t or ""))

    def at(s, now):
        """As boards.state_at sees the session (its `done` turn is the card's), plus what it was first asked."""
        st = rb.state_at(s, now)
        if st is None:
            return None
        i = s["turns"].index(st["turn"])
        return {"first": red(s["turns"][0]["you"])[:600], "n": i + 1,
                "said": red(st["done"]["said"])[-2500:] if st["done"] else "",
                "said_head": red(st["done"]["said"])[:600] if st["done"] else "",
                "yous": [red(t["you"])[:300] for t in s["turns"][max(0, i - 2):i + 1]], "running": st["running"]}

    real = [json.loads(l) for l in open(HERE / "real" / "data" / "real.jsonl")]
    out, fp = {}, {}
    for c in real:
        t0 = rb.ts(c["at"])
        gold = c["gold"]["to"][0]
        e = {}
        for s in c["board"]["sessions"]:
            now = t0 - 1e-3 if s["id"] == gold else t0
            cands = [x for x in by.get(s["id"], []) if x["title"][:80] == s["title"] or len(by[s["id"]]) == 1]
            for x in cands:
                st = at(x, now)
                if st:
                    e[s["id"]] = st
                    break
        out[c["id"]] = e
        fp[frozenset((s["id"], s["idle_min"]) for s in c["board"]["sessions"])] = c["id"]
    for f in glob.glob(str(HERE / "real" / "data" / "routerstyle_*.jsonl")):
        for line in open(f):
            if line.strip():
                c = json.loads(line)
                k = frozenset((s["id"], s["idle_min"]) for s in c["board"]["sessions"])
                if k in fp:
                    out[c["id"]] = out[fp[k]]
    EXTRA_PATH.write_text(json.dumps(out, ensure_ascii=False))
    print(len(out), "cases")


def extra(case):
    global _extra
    if _extra is None:
        _extra = json.loads(EXTRA_PATH.read_text()) if EXTRA_PATH.exists() else {}
    return _extra.get(case["id"], {})


# ---------------------------------------------------------------- text helpers

def paragraphs(text):
    return [p.strip() for p in re.split(r"\n\s*\n", text or "") if p.strip()]


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", text or "").strip()) if s.strip()]


def clip(text, n, keep=False):
    text = (text or "").strip() if keep else re.sub(r"\s+", " ", text or "").strip()
    return text[:n]


KEEP = True


def describe_said(said, mode, n, head=None):
    if mode == "last":
        p = paragraphs(said)
        return clip(p[-1] if p else "", n, KEEP)
    if mode == "last2":
        return clip("\n\n".join(paragraphs(said)[-2:]), n, KEEP)
    if mode == "fl":
        ss = sentences(head or said)[:1] + sentences(said)[-1:] if head and head != said[:len(head)] else sentences(said)
        if len(ss) <= 2:
            return clip(" ".join(ss), n)
        return clip(ss[0], n // 2) + " … " + clip(ss[-1], n // 2)
    if mode == "first":
        return clip(" ".join(paragraphs(head or said)[:1]), n)
    raise ValueError(mode)


def norm(t):
    return re.sub(r"\W+", "", t or "")


def same_turn(e, card):
    p = paragraphs(e["said"])
    a = re.sub(r"\W+", "", (p[-1] if p else "")[:200])
    b = re.sub(r"\W+", "", card["text"][:200])
    n = min(len(a), len(b), 120)
    return n > 0 and a[:n] == b[:n] or (n == 0 and a == b)


# ---------------------------------------------------------------- the format

import formats as F  # noqa: E402

WAITING = ("question", "plan", "asks", "approval")


def ctx(case, rng=None, said="last", said_n=300, first=0, told=160, told_ago=True, told_k=1, kind=True, project=True, title=True,
        status=True, ago=True, recent_h=None, gates=True, replies=True, unclear=True, intents=True):
    board = case["board"]
    ex = extra(case)
    ordered, names = F.session_options(board)
    cards = {}
    for c in board.get("cards", []):
        cards.setdefault(c["session"], []).append(c)
    waits = {c["session"] for c in F.waiting_cards(board)}
    hist = board.get("history", [])
    if recent_h is not None:
        told_recent = {h["to"] for h in hist if h["ago_min"] <= recent_h * 60}
        keep = [s for s in ordered if s.get("running") or s["id"] in waits or s.get("idle_min", 0) <= recent_h * 60
                or s["id"] in told_recent]
        ordered = keep or ordered[:1]
    entries = []
    if not title:
        names = {s["id"]: f"session {i + 1}" for i, s in enumerate(ordered)}
    for s in ordered:
        crit = {}
        if kind:
            crit["kind"] = "Claude Code session"
        if not title:
            crit["title"] = s["title"]
        if project:
            crit["project"] = s["project"]
        e = ex.get(s["id"])
        mine = cards.get(s["id"], [])
        w = [c for c in mine if c["kind"] in WAITING]
        if w:
            mine = [c for c in mine if c is not w[-1]] + [w[-1]]
        m = [h for h in hist if h["to"] == s["id"]]
        if e and ((mine and not s.get("running") and not same_turn(e, mine[-1]))
                  or (m and norm(e["yous"][-1])[:100] != norm(m[-1]["you"])[:100])):
            e = None  # the corpus doesn't match what the board shows: use the board alone
        if first and (e or s.get("first")):
            crit["first asked"] = clip((e or s)["first"], first)
        # now: waiting / working / finished, with more of its last answer when the corpus has it
        if s.get("running"):
            now = "working" + (f": {s['activity'][:300]}" if s.get("activity") else "")
        else:
            text = ""
            if e and e.get("said") and (said != "last" or said_n > 300):
                text = describe_said(e["said"], said, said_n, e.get("said_head"))
            elif mine:
                text = mine[-1]["text"][:said_n]
            else:
                text = s.get("summary", "")[:said_n]
            if w:
                c = w[-1]
                verb = {"question": "asks you a question", "plan": "waits for you to approve its plan", "asks": "asks you something",
                        "approval": "asks your OK"}[c["kind"]]
                if c.get("options"):
                    text += " Options: " + " / ".join(c["options"])
                now = f"{verb}: {text}"
            else:
                stuck = mine and mine[-1]["kind"] == "stuck"
                lead = ("stuck" if stuck else "finished") + (f" {F.ago(s.get('idle_min', 0))}" if ago else "")
                now = lead + (f": {text}" if text else "")
        if status:
            crit["now"] = now
        if told and m:
            crit["the user last told it"] = m[-1]["you"][:told] + (f" ({F.ago(m[-1]['ago_min'])})" if told_ago else "")
        if told_k > 1 and e and len(e["yous"]) > 1:
            crit["the user told it before"] = [clip(y, told) for y in e["yous"][-told_k:-1]]
        entries.append((names[s["id"]], s["id"], crit))
    for p in board["projects"]:
        entries.append((f"new session in {p}", f"new:{p}", {"kind": "new session", "project": p} if kind else {"project": p}))
    if intents:
        for k, v in F.INTENTS.items():
            entries.append((k, k, v))
    if unclear:
        entries.append(("unclear", "unclear", F.UNCLEAR_V2))
    if rng:
        rng.shuffle(entries)
    keymap = {n.replace(".", "_"): d for n, d, _ in entries}
    q = {"route": {"type": "choice", "instructions": F.ROUTE_INSTRUCTIONS_V2,
                   "criteria": {n.replace(".", "_"): c for n, _, c in entries}}}
    if replies:
        for i, c in enumerate(F.waiting_cards(board)):
            s = F.session_by_id(board)[c["session"]]
            card = {"session": s["title"], "asks": c["text"][:400]}
            if c.get("options"):
                card["options"] = c["options"]
            q[f"answers{i}"] = {"type": "noul", "instructions": {
                "question": "Is `message` the user's answer to `card`: a reply to what it asks?", "card": card}}
            keymap[f"answers{i}"] = c["session"]
    if gates:
        q.update(F.GATES)
    return {"message": case["message"]}, q, keymap


def variant(**kw):
    return lambda case, rng=None: ctx(case, rng, **kw)


FORMATS = {
    "ctx-base": variant(),
    "ctx-l2": variant(said="last2", said_n=450),
    "ctx-fl": variant(said="fl", said_n=300),
    "ctx-s600": variant(said_n=600),
    "ctx-first": variant(first=200),
    "ctx-first-l2": variant(first=200, said="last2", said_n=450),
    "ctx-notitle": variant(title=False),
    "ctx-lean": variant(kind=False),
    "ctx-noproj": variant(project=False),
    "ctx-noago": variant(ago=False),
    "ctx-told300": variant(told=300),
    "ctx-notold": variant(told=0),
    "ctx-r3": variant(recent_h=3),
    "ctx-r1": variant(recent_h=1),
    # not yet run (TypeSafe credits ran out): the user's last 3 messages to each session, with the last 2 paragraphs
    "ctx-you3": variant(told_k=3),
    "ctx-l2-you3": variant(said="last2", said_n=450, told_k=3),
    "ctx-first-l2-you3": variant(first=200, said="last2", said_n=450, told_k=3),
}


# ---------------------------------------------------------------- policies

LOW = {"question", "compound", "change_lookout"}


def make_policy(p_session=0.7, lead=0.0, p_new=0.6, p_intent=0.6, g_setting=0.75, g_compound=2.0, reply=0.5,
                reply_other=0.4, reply_agree=False, conflict=0.5):
    """Lookout's `final` with its parts as knobs: gates first, then a card's answer check, then the route by risk.
    reply_agree: a card's answer check only sends when the route's top session is that card's (or is not a session)."""
    def pol(r):
        ranked = sorted(r["dests"].items(), key=lambda x: -x[1])
        top, p = ranked[0]
        second = ranked[1][1] if len(ranked) > 1 else 0
        ask = ("ask", [d for d, _ in ranked if d not in ("unclear",)][:3])
        g = r.get("gates") or {}
        if g.get("gate_compound", 0) >= g_compound:
            return ("send", "compound")
        if g.get("gate_setting", 0) >= g_setting:
            return ("send", "change_lookout")
        if r.get("replies"):
            ys = sorted(r["replies"].items(), key=lambda x: -x[1])
            if ys[0][1] >= reply and (len(ys) < 2 or ys[1][1] <= reply_other):
                is_session = top not in LOW and top != "unclear" and not top.startswith("new:")
                if is_session and top != ys[0][0] and (reply_agree or p >= conflict):
                    return ask
                return ("send", ys[0][0])
        if top == "unclear":
            return ask
        if top in LOW:
            return ("send", top) if p >= p_intent else ask
        if top.startswith("new:"):
            return ("send", top) if p >= p_new else ask
        return ("send", top) if p >= p_session and p - second >= lead else ask
    return pol


final = make_policy()


# The policy sees only the reading; to also see the board (recency), remember the row each reading came from.
import run as _run  # noqa: E402

_orig_reading = _run.reading
_last = {}
_cases = {}


def _reading(row):
    _last["row"] = row
    return _orig_reading(row)


_run.reading = _reading


def case_of(row_id):
    if not _cases:
        import bench
        for s in ("synth", "heldout", "real", "style"):
            for c in bench.load_set(s):
                _cases[c["id"]] = c
    return _cases[row_id]


def recent_ids(board, k):
    ss = sorted(board["sessions"], key=lambda s: s.get("idle_min", 0))
    return [s["id"] for s in ss[:k]]


def make_recent_policy(k=2, p_far=0.95, **kw):
    """make_policy, but a send to a session that isn't one of the k most recently active needs p_far."""
    base = make_policy(**kw)

    def pol(r):
        out = base(r)
        if out[0] == "send" and out[1] not in LOW and not out[1].startswith("new:"):
            board = case_of(_last["row"]["id"])["board"]
            if out[1] not in recent_ids(board, k) and r["dests"].get(out[1], 0) < p_far:
                ranked = sorted(r["dests"].items(), key=lambda x: -x[1])
                return ("ask", [d for d, _ in ranked if d != "unclear"][:3])
        return out
    return pol


if __name__ == "__main__":
    if sys.argv[1] == "derive":
        derive()
    elif sys.argv[1] == "bench":
        import bench
        sys.argv = ["bench.py"] + sys.argv[2:]
        bench.main()
