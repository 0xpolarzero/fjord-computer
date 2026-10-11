"""Explorer `intents`: how Lookout's own intents (question, compound, change_lookout) are offered and checked.

Every format here is the shipped `swift` one (v3-told + gates, dots in names made underscores) with one thing
changed about the intents or the gates, so each idea is measured on its own."""
import collections

import analyze
import formats
import run

INTENTS = ("question", "compound", "change_lookout")
SETS = ("synth", "heldout", "real", "realA", "realB", "style")

# ---------------------------------------------------------------- intent criteria

# A: plain strings, worded by who the message is addressed to.
CRIT_WORDED = {
    "question": ("A question to Lookout, the assistant that watches the board, about the board: which sessions are "
                 "working, done or waiting on the user, or what a session named in the third person is doing. Not a "
                 "question for a session about its own work or what it said"),
    "compound": ("Requests meant for two or more different places in one message: Lookout itself and a session, or "
                 "two different sessions. Not one long message with several points for one session"),
    "change_lookout": ("Change how Lookout itself behaves: its settings, notifications, inbox categories, rules or "
                       "groups. Not asking a session to build or change code"),
}

# B: structured criteria (what / not_for / examples), as TypeSafe's docs suggest for a subtle boundary.
CRIT_STRUCT = {
    "question": {
        "what": "A question to Lookout, the assistant that watches the board, about the board: which sessions are working, done or waiting on the user, or what a session named in the third person is doing",
        "not_for": "A question for a session about its own work, its code or what it said (\"did you…\", \"why does it…\", \"what does X mean?\")",
        "examples": ["anything waiting on me?", "is the release one finished?", "which session is doing the docs?"],
    },
    "compound": {
        "what": "Requests meant for two or more different places in one message: Lookout itself and a session, or two different sessions",
        "not_for": "One message with several points or steps, all for the same session",
        "examples": ["mute the bot notifications and tell the docs one to push", "tell the api one to merge and the web one to rebase"],
    },
    "change_lookout": {
        "what": "Change how Lookout itself behaves: its settings, notifications, inbox categories, rules or groups",
        "not_for": "Asking a session to build, fix or change code, even code of a Lookout feature",
        "examples": ["stop notifying me about drafts", "put the web sessions in one group"],
    },
}

# ---------------------------------------------------------------- gates

G_COMPOUND_TIGHT = {"type": "noul", "instructions": {
    "question": ("Does `message` ask for things meant for two or more different places: Lookout itself and a session, "
                 "or two different sessions it names? A message with several points or steps for one session is no.")}}
G_SETTING_TIGHT = {"type": "noul", "instructions": {
    "question": ("Does `message` ask Lookout to change how it behaves for the user (a setting turned on or off, its "
                 "notifications, an inbox category, a rule or a group)? Asking a session to build, fix or discuss such "
                 "a feature is no.")}}
G_ADDRESSED = {"type": "noul", "instructions": {
    "question": ("Is `message` addressed to Lookout, the assistant that manages the user's board of Claude Code "
                 "sessions (asking about the sessions, or to change Lookout's settings), rather than written to a "
                 "Claude Code session as part of its conversation with it?")}}
G_ADDRESSED_S = {"type": "noul", "instructions": {
    "question": "Is `message` addressed to Lookout, the assistant that manages the user's board, rather than to a Claude Code session?"},
    "criteria": {
        "true": {"what": "Talks about the sessions in the third person, asks about the board, or asks Lookout to change its settings",
                 "examples": ["is the docs one done?", "what's waiting on me", "mute bot notifications", "tell the api one to merge"]},
        "false": {"what": "Talks to one agent about its work: replies, instructions, questions about what it did or said",
                  "examples": ["did you push it?", "what does this error mean?", "go ahead", "fix the three points above"]}}}


NAMES_LONG = {"question": "question to Lookout about the board", "compound": "several things for different places",
              "change_lookout": "change a Lookout setting"}


def make(crit=None, gates=None, drop_intents=False, names=None):
    """swift with intent criteria `crit` (None: shipped), gates `gates` (None: shipped), no intents in the route, or
    the intents' option names `names` (intent → name)."""
    def build(case, rng=None):
        state, q, keymap = formats.v2(case, rng, told=True)
        cr = {}
        for k, v in q["route"]["criteria"].items():
            if k in INTENTS:
                if drop_intents:
                    keymap.pop(k, None)
                    continue
                v = crit[k] if crit else v
                if names:
                    keymap.pop(k)
                    keymap[names[k]] = k
                    k = names[k]
            cr[k] = v
        q = {**q, "route": {**q["route"], "criteria": {k.replace(".", "_"): v for k, v in cr.items()}}}
        q.update(formats.GATES if gates is None else gates)
        return state, q, {k.replace(".", "_"): v for k, v in keymap.items()}
    return build


G_YOU = {"type": "noul", "instructions": {
    "question": ("Does `message` speak to one agent as \"you\" about its own work (\"did you…\", \"your end\", \"what "
                 "are you waiting for\", \"you said…\"), or reply to something it just said?")}}
G_CONV = {"type": "noul", "instructions": {
    "question": ("Is `message` written to one Claude Code agent in the middle of its work (a reply, an instruction, or "
                 "a question about what it did or said), rather than about the user's sessions as a group or about "
                 "Lookout's own settings?")}}
G_QUESTION_BOARD = {"type": "noul", "instructions": {
    "question": ("Is `message` a question about the user's board of sessions, answerable from it alone: which sessions "
                 "are working, done or waiting, or what a session named in the third person is doing? A question to "
                 "an agent about its own work, its code or what it said is no.")}}

CRIT_WORDED_YOU = {**CRIT_WORDED, "question": CRIT_WORDED["question"] + " (\"did you…\", \"what are you waiting for\", \"what does X mean\")"}

ALL_GATES = {**formats.GATES, "gate_compound2": G_COMPOUND_TIGHT, "gate_setting2": G_SETTING_TIGHT,
             "gate_addr": G_ADDRESSED, "gate_addrs": G_ADDRESSED_S}

GATES_B = {**formats.GATES, "gate_compound2": G_COMPOUND_TIGHT, "gate_you": G_YOU}

FORMATS = {
    "in-worded": make(CRIT_WORDED),
    "in-struct": make(CRIT_STRUCT),
    # every gate asked at once (they are answered in parallel), so policies can pick among them offline
    "in-worded-allg": make(CRIT_WORDED, ALL_GATES),
    "in-nointents-allg": make(None, ALL_GATES, drop_intents=True),
    "in-worded-g2": make(CRIT_WORDED, {**formats.GATES, "gate_compound2": G_COMPOUND_TIGHT, "gate_you": G_YOU,
                                       "gate_conv": G_CONV, "gate_qboard": G_QUESTION_BOARD}),
    "in-wordedyou-g2": make(CRIT_WORDED_YOU, {**formats.GATES, "gate_compound2": G_COMPOUND_TIGHT, "gate_you": G_YOU,
                                              "gate_conv": G_CONV, "gate_qboard": G_QUESTION_BOARD}),
    "in-names": make(None, GATES_B, names=NAMES_LONG),
    "in-worded-names": make(CRIT_WORDED, GATES_B, names=NAMES_LONG),
    "in-worded-b": make(CRIT_WORDED, GATES_B),
}

# ---------------------------------------------------------------- policies

FINAL = dict(p_min=0.7, lead=0, reply=0.5, reply_other=0.4, p_new=0.6, p_intent=0.6, conflict=0.5, g_compound=0.75,
             g_setting=0.75, g_question=2)
def final(r):
    return analyze.policy("gates", **FINAL)(r)


def _without_intents(r):
    """The reading with Lookout's intents taken out of the route and the rest renormalized; gates turned off."""
    keep = {d: p for d, p in r["dests"].items() if d not in INTENTS}
    total = sum(keep.values()) or 1
    dests = {d: p / total for d, p in keep.items()}
    return {**r, "dests": dests, "options": sorted(dests.items(), key=lambda x: -x[1]), "gates": {}}


def gated_policy(gc=0.75, gc2=0.0, gs=0.75, gs2=0.0, q_gate=0.0, veto=None, veto_gate="gate_conv", base=None, intents_from_route=True,
                 q_send=2, q_send_gate="gate_question", hold=None,
                 hold_gates=("gate_question", "gate_setting", "gate_compound"), renorm=False, c_cap=2):
    """hold: a session send waits (asks) when one of `hold_gates` says yes at least this sure but not enough to decide."""
    """The shipped policy with Lookout's intents checked by gates:
    compound when gate_compound ≥ gc and gate_compound2 ≥ gc2; change_lookout when gate_setting ≥ gs and gate_setting2 ≥ gs2;
    an intent the route picks needs gate_question ≥ q_gate (for question); any intent is vetoed when `veto_gate` ≥ veto."""
    params = {**FINAL, **(base or {}), "g_compound": 2, "g_setting": 2, "g_question": 2}
    inner = analyze.policy("gates", **params)

    def pol(r):
        g = r.get("gates") or {}
        vetoed = veto is not None and g.get(veto_gate, 0) >= veto
        if not vetoed:
            one = max((p for d, p in r["dests"].items() if d not in INTENTS and d != "unclear"), default=0)
            if g.get("gate_compound", 0) >= gc and g.get("gate_compound2", 1) >= gc2 and one < c_cap:
                return ("send", "compound")
            if g.get("gate_setting", 0) >= gs and g.get("gate_setting2", 1) >= gs2:
                return ("send", "change_lookout")
            if g.get(q_send_gate, 0) >= q_send:
                return ("send", "question")
        k, w = inner(r)
        if k == "send" and w not in INTENTS and hold is not None and max(g.get(x, 0) for x in hold_gates) >= hold:
            return ("ask", run.ranked_targets(r)[:3])
        if k == "send" and w in INTENTS:
            if vetoed or not intents_from_route or (w == "question" and g.get("gate_question", 0) < q_gate):
                if renorm:
                    return pol(_without_intents(r))
                return ("ask", run.ranked_targets(r)[:3])
        return k, w
    return pol


def best(r):
    """Best found (with format in-worded-g2): compound needs the shipped gate ≥ 0.75 and the tight one ≥ 0.5; any of
    Lookout's intents is vetoed (ask) when gate_you ≥ 0.5 (the message talks to one agent about its own work)."""
    return gated_policy(gc2=0.5, veto=0.5, veto_gate="gate_you")(r)


# ---------------------------------------------------------------- scoring many policies over saved runs

def _rows(fmt, s):
    import bench
    if s in ("realA", "realB"):
        return [r for r in run.load(f"{fmt}@real") if bench.half(r["id"]) == s]
    return run.load(f"{fmt}@{s}")


def table(fmt, pols, sets=SETS):
    import bench
    if callable(pols):
        pols = [("policy", pols)]
    for name, pol in pols:
        print(f"== {fmt} / {name}")
        for s in sets:
            try:
                rows = _rows(fmt, s)
            except FileNotFoundError:
                continue
            print("  " + bench.line(s, bench.score(bench.load_set(s), rows, pol)))


def gate_stats(fmt, gate, intents, ts=(0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9), sets=("synth", "heldout", "style", "realA", "realB")):
    """How often `gate` says yes ≥ t: on cases whose gold is one of `intents` (want high) and on the rest (want low)."""
    import bench
    print(f"-- {fmt} {gate} for {intents}")
    for s in sets:
        by = {c["id"]: c for c in bench.load_set(s)}
        pos, neg = [], []
        for row in _rows(fmt, s):
            v = run.reading(row)["gates"].get(gate, 0)
            (pos if set(by[row["id"]]["gold"]["to"]) & set(intents) else neg).append(v)
        f = lambda xs, t: f"{100 * sum(x >= t for x in xs) / max(len(xs), 1):3.0f}"
        print(f"  {s:8} pos n={len(pos):3} " + " ".join(f(pos, t) for t in ts) + f" | neg n={len(neg):3} " + " ".join(f(neg, t) for t in ts))


def compare(fa, pa, fb, pb, setname):
    """Cases where policy pa on format fa and pb on fb disagree in outcome (right / wrong / ask)."""
    import bench
    by = {c["id"]: c for c in bench.load_set(setname)}

    def outcome(fmt, pol):
        out = {}
        for row in _rows(fmt, setname):
            k, w = pol(run.reading(row))
            out[row["id"]] = ("right" if w in by[row["id"]]["gold"]["to"] else "WRONG") if k == "send" else "ask", w if k == "send" else ""
        return out
    a, b = outcome(fa, pa), outcome(fb, pb)
    for i in a:
        if a[i][0] != b.get(i, ("?",))[0]:
            print(f"{a[i][0]:5} {a[i][1][:14]:14} -> {b[i][0]:5} {b[i][1][:14]:14} gold={by[i]['gold']['to']} {by[i]['message'][:90]!r}")


def diag(fmt, pol=final, setname="real", show=0, kind=None):
    import bench
    cases = bench.load_set(setname)
    by = {c["id"]: c for c in cases}
    cnt = collections.Counter()
    ex = []
    for row in _rows(fmt, setname):
        r = run.reading(row)
        k, w = pol(r)
        c = by[row["id"]]
        if k == "send" and w not in c["gold"]["to"]:
            g = r.get("gates") or {}
            kk = w if w in INTENTS else "session/new"
            cnt[kk] += 1
            if kind is None or kind == kk:
                ex.append((w, c["gold"]["to"], c["gold"].get("label"),
                           ",".join(f"{n[5:]}={v:.2f}" for n, v in g.items() if v >= 0.5), c["message"][:140].replace("\n", " ")))
    print(cnt)
    for e in ex[:show]:
        print(e)
