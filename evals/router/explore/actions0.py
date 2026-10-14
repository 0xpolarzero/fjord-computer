"""Stage 0 of the Router redesign (D3): a kill test of Router actions read from per-target yes/no checks, before any new
data is built. Two variants, both on top of the shipped route request (`capabilities-x-archive-reopen`, unchanged) and
today's policy (`explore.final3:best`, Swift weights, no refit):

actions-0   in the same Jev call: ack_i per worth-a-look card (≤20), stop_i per running session (≤8), `instead`.
            Overlay: T = today's fused top. stop(T) if T running, stop_T ≥ .9, lead ≥ .4, gate_you < .5 (interrupt if
            instead ≥ .6); else ack(T's card) if ack ≥ .85, lead ≥ .4 and the route isn't ≥ .5 sure of another session;
            else today's outcome. A check firing on another session than T → ask. When T is no session (a Router intent,
            a new session), the firing check names the target ("lenient"; `literal` and `keep` readings recorded too).
actions-0-placebo  the same checks reworded, in another order.
actions-o   the design lead's revision: ack/dismiss on a shortlist of ≤8 cards (+ open cards named in the message),
            stop on running sessions not waiting on you (≤6), globals nothing_to_say and urgent; verb = argmax of T's
            checks over bars (ack .8, dismiss .85, stop .9), interrupt = urgent ≥ .9 and T running; a standing-out check
            elsewhere overrides T when the route is unclear or < .4; a simulated second call on every card / session when
            a global fires and no shortlisted check stands out.

Each submit also records the shipped decision on the same state, the shipped route answer, and (real sets) the shipped
request asked again (sample 1) as Jev's own repeat noise.

python3 -m explore.actions0 run SET VARIANT [--workers 6] [--max-calls N]   SET: ack, ack_actions, real_A, real_B
python3 -m explore.actions0 report                                            tables from v2/data/exp/out/actions0/
Only gitignored data is read or written (v2/data/exp, v2/run/cache, cache)."""
import argparse
import copy
import hashlib
import json
import math
import os
import pathlib
import re
import sys
from concurrent.futures import ProcessPoolExecutor

os.environ["JEV_ORDERED"] = "1"
HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
EXP = HERE / "v2" / "data" / "exp"
OUT = EXP / "out" / "actions0"
SHIPPED = "capabilities-x-archive-reopen"
INTENTS = {"change_fjord", "question", "compound", "unclear"}

# ------------------------------------------------------------------ wording

A0 = {
    "ack": ("Does `message` say the user has seen or read `card` (its session's report) and ask nothing more of that "
            "session? No for a reply, an instruction, a negation ('haven't seen it yet') or a quote."),
    "stop": ("Does `message` ask that `session` stop or abandon what it is doing right now (halt, abort, interrupt, "
             "cancel the run)? No for 'stop using X in the code' or any instruction about the work's content."),
    "instead": "Besides stopping, does `message` say what to do next or instead?",
}
A0P = {
    "ack": ("Is `message` the user telling us they have already looked at or gone through `card` (the report from that "
            "session), with nothing further wanted from the session? Answer no if it is a reply, a request, something "
            "quoted, or a negation such as 'not read it yet'."),
    "stop": ("Is `message` a request to halt `session` at once: interrupt it, abort or cancel the run it is doing? Answer "
             "no for anything about what the work itself should contain, such as 'stop using X in the code'."),
    "instead": "Apart from stopping something, does `message` tell what should happen next or in its place?",
}
AO = {
    "ack": "Does `message` say the user has seen/read/noted this card and needs nothing more from it?",
    "dismiss": "Does `message` ask to archive or drop this card, because the user will handle it or doesn't need it?",
    "stop": "Does `message` ask to stop or interrupt what this session is doing now?",
    "nothing_to_say": ("Is `message` only an acknowledgement, with nothing for a session to do or read?"),
    "urgent": ("Does `message` ask a session to stop or change what it is doing right now, not after it finishes?"),
}

WORD = re.compile(r"[a-z0-9]+")
STOPWORDS = set("the and for with this that from into you your please can could would should will what when where which "
                "who why how about then than them they have has had not are was were its our out all any some just also "
                "now new session project card does did but yes too there here let one get make use need want like ok "
                "okay thanks to in on it is of at an be do go me my no so up us we or if as by i a".split())


def words(text):
    return [w for w in WORD.findall((text or "").lower()) if len(w) >= 3 and w not in STOPWORDS]


def scrub(x):
    from explore.capabilities import _scrub
    return _scrub(x)


def sessions_by_id(case):
    return {s["id"]: s for s in case["board"]["sessions"]}


def looks(case):
    """Worth-a-look cards (done, shown, live session), newest first."""
    by = sessions_by_id(case)
    cards = [c for c in case["board"]["cards"] if c["kind"] == "done" and c["session"] in by]
    return sorted(cards, key=lambda c: (c.get("created_min_ago", 0), c["id"]))


def working(case, waiting_too=True):
    out = [s for s in case["board"]["sessions"] if s.get("running") and (waiting_too or not s.get("waits_on_you"))]
    return sorted(out, key=lambda s: (s.get("idle_min", 0), s["id"]))


def card_info(case, c):
    s = sessions_by_id(case)[c["session"]]
    return {"session": s["title"], "report": c.get("text", "")[:400]}


def session_info(s):
    return {"title": s["title"], "project": s.get("project", ""), "now": "working: " + (s.get("activity") or "")}


def a0_extras(case, wording, placebo=False):
    qs, m = [], {}
    for i, c in enumerate(looks(case)[:20]):
        qs.append((f"ack_{i}", {"type": "noul", "instructions": {"question": wording["ack"], "card": card_info(case, c)}}))
        m[f"ack_{i}"] = ("ack", c["id"], c["session"])
    for i, s in enumerate(working(case)[:8]):
        qs.append((f"stop_{i}", {"type": "noul", "instructions": {"question": wording["stop"], "session": session_info(s)}}))
        m[f"stop_{i}"] = ("stop", None, s["id"])
    qs.append(("instead", {"type": "noul", "instructions": {"question": wording["instead"]}}))
    m["instead"] = ("instead", None, None)
    if placebo:  # another order: instead, the stops, then the cards newest last
        acks = [q for q in qs if q[0].startswith("ack_")]
        stops = [q for q in qs if q[0].startswith("stop_")]
        qs = [qs[-1]] + stops + acks[::-1]
    return dict(qs), m


def overlap(msg_words, c, case):
    s = sessions_by_id(case)[c["session"]]
    return len(set(msg_words) & set(words(s["title"] + " " + c.get("text", ""))))


def named_cards(case):
    """Open cards (any kind) whose session title is named by its words in the message (at least half of them, ≥1)."""
    msg = set(words(case["message"]))
    by = sessions_by_id(case)
    out = []
    for c in case["board"]["cards"]:
        s = by.get(c["session"])
        if not s:
            continue
        tw = set(words(s["title"]))
        if tw and len(tw & msg) >= max(1, math.ceil(len(tw) / 2)):
            out.append(c)
    return out


def shortlist(case):
    """≤8 worth-a-look cards: the 4 newest, then up to 4 by word overlap with the message (title + text), then newest."""
    cards = looks(case)
    mw = words(case["message"])
    out = cards[:4]
    by_lex = sorted([c for c in cards if overlap(mw, c, case) > 0], key=lambda c: -overlap(mw, c, case))
    for c in by_lex:
        if len(out) >= 8:
            break
        if c not in out:
            out.append(c)
    for c in cards:
        if len(out) >= 8:
            break
        if c not in out:
            out.append(c)
    return out


def ao_extras(case, full=None):
    """full: None (the first call), or {"cards": True/False, "sessions": True/False} for the simulated second call."""
    qs, m = {}, {}
    by = sessions_by_id(case)
    if full is None:
        acks = shortlist(case)
        dismiss = list(acks) + [c for c in named_cards(case) if c not in acks]
        stops = working(case, waiting_too=False)[:6]
    else:
        open_cards = sorted(case["board"]["cards"], key=lambda c: (c.get("created_min_ago", 0), c["id"]))
        open_cards = [c for c in open_cards if c["session"] in by][:30]
        acks = open_cards if full["cards"] else []
        dismiss = open_cards if full["cards"] else []
        stops = sorted(case["board"]["sessions"], key=lambda s: (s.get("idle_min", 0), s["id"]))[:30] if full["sessions"] else []
    for i, c in enumerate(acks):
        qs[f"ack{i}"] = {"type": "noul", "instructions": {"question": AO["ack"], "card": card_info(case, c)}}
        m[f"ack{i}"] = ("ack", c["id"], c["session"])
    for i, c in enumerate(dismiss):
        qs[f"dismiss{i}"] = {"type": "noul", "instructions": {"question": AO["dismiss"], "card": card_info(case, c)}}
        m[f"dismiss{i}"] = ("dismiss", c["id"], c["session"])
    for i, s in enumerate(stops):
        qs[f"stop{i}"] = {"type": "noul", "instructions": {"question": AO["stop"], "session": session_info(s)}}
        m[f"stop{i}"] = ("stop", None, s["id"])
    if full is None:
        for k in ("nothing_to_say", "urgent"):
            qs[k] = {"type": "noul", "instructions": {"question": AO[k]}}
            m[k] = (k, None, None)
    return qs, m


VERB = {
    "say": ("words for a session to read or act on (\"tell it to push\", \"run the tests again\"); \"stop using X in the "
            "code\" is say"),
    "ack": "only says they've seen/read/got it; asks nothing (\"seen the docs\", \"got it, read the headlines\")",
    "dismiss": ("doesn't need the card, will handle it, archive it (\"I'll do the theme one myself\", \"archive the login "
                "card\")"),
    "stop": "halt what a session is doing now (\"stop the CI session\", \"abort what it's doing\")",
    "restore": "bring back an archived card (\"reopen the docs card\", \"put that card back\")",
    "mute": "mute or unmute a project's sessions (\"mute microsandbox\", \"unmute lcu\")",
    "configure": "change a setting or Triage's categories, rules or groups (\"turn off notifications\")",
    "ask_fjord": "a question for Fjord about what is going on (\"is the CI one done?\", \"what's left?\")",
    "several": "two or more of these at once (\"seen the docs, and tell the CI one to push\")",
}
# verbs-o's typing-time prediction: the base request's fused ranking on the same board (set by decide before the call).
_PRE = {}


def vo_extras(case):
    """verbs-o: the global `verb` choice, ack<i> per worth-a-look card (≤12; over 12: the predicted top-3 sessions' cards,
    then word overlap, then newest), dismiss<i> per open card of the predicted top-3 sessions, stop<i> per running session
    (≤6)."""
    pre = _PRE.get(case["id"], {})
    top = [t[8:] for t, _ in sorted(pre.items(), key=lambda x: -x[1]) if t.startswith("session:")]
    rank = {sid: i for i, sid in enumerate(top[:3])}
    cards = looks(case)
    if len(cards) > 12:
        mw = words(case["message"])
        cards = sorted(cards, key=lambda c: (rank.get(c["session"], 99), -overlap(mw, c, case),
                                             c.get("created_min_ago", 0)))[:12]
    by = sessions_by_id(case)
    dismiss = [c for c in case["board"]["cards"] if c["session"] in rank and c["session"] in by]
    stops = working(case)[:6]
    qs = {"verb": {"type": "choice", "instructions": {"question": "What does the user's `message` do?"},
                   "criteria": dict(VERB)}}
    m = {}
    for i, c in enumerate(cards):
        qs[f"ack{i}"] = {"type": "noul", "instructions": {"question": AO["ack"], "card": card_info(case, c)}}
        m[f"ack{i}"] = ("ack", c["id"], c["session"])
    for i, c in enumerate(dismiss):
        qs[f"dismiss{i}"] = {"type": "noul", "instructions": {"question": AO["dismiss"], "card": card_info(case, c)}}
        m[f"dismiss{i}"] = ("dismiss", c["id"], c["session"])
    for i, s in enumerate(stops):
        qs[f"stop{i}"] = {"type": "noul", "instructions": {"question": AO["stop"], "session": session_info(s)}}
        m[f"stop{i}"] = ("stop", None, s["id"])
    return qs, m


def overlay_vo(T, sureness, cs, verb, running):
    """T's checks decide (say = 1 − max); the global verb breaks ties (< .05) and speaks for targets without checks."""
    T_sid = T[8:] if T and T.startswith("session:") else None
    gv = max(verb.items(), key=lambda x: x[1]) if verb else ("say", 1.0)
    mine = {}
    for k, card, sid, p in cs:
        if sid == T_sid and (k not in mine or p > mine[k][0]):
            mine[k] = (p, card)
    out = {"global_verb": gv[0], "global_p": gv[1], "verb": verb, "action": None}
    if not mine:
        if T_sid and gv[0] != "say" and gv[1] >= 0.8:
            out.update(action="ask-noverb")
        return out
    cand = {k: p for k, (p, _) in mine.items()}
    cand["say"] = 1 - max(cand.values())
    ranked = sorted(cand.items(), key=lambda x: -x[1])
    v = ranked[0][0]
    if len(ranked) > 1 and ranked[0][1] - ranked[1][1] < 0.05:
        v = max(ranked[:2], key=lambda x: verb.get(x[0], 0))[0]
    out["argmax"] = v
    if v in ("ack", "dismiss"):
        if (sureness or 0) >= 0.9 and cand[v] >= 0.85:
            out.update(action=v, session=T_sid, card=mine[v][1])
    elif v == "stop":
        others = [p for k, _, sid, p in cs if k == "stop" and sid != T_sid]
        if cand["stop"] >= 0.9 and running.get(T_sid) and all(p <= 0.4 for p in others):
            out.update(action="stop", session=T_sid)
    return out


BASE = {"verbs-o": "capabilities-o"}

VARIANTS = {
    "verbs-o": vo_extras,
    "actions-0": lambda case: a0_extras(case, A0),
    "actions-0-placebo": lambda case: a0_extras(case, A0P, placebo=True),
    "actions-o": lambda case: ao_extras(case),
}


def make_format(variant):
    def fmt(case, rng=None):
        import formats
        state, q, keymap = formats.FORMATS[BASE.get(variant, SHIPPED)](case, rng=rng)
        extra, _ = VARIANTS[variant](case)
        return state, {**q, **scrub(extra)}, keymap
    return fmt


# ------------------------------------------------------------------ decisions

def checks(answers, mapping):
    """[(kind, card, session, p)] and globals {name: p}."""
    out, glob = [], {}
    for k, (kind, card, sid) in mapping.items():
        if k not in answers:
            continue
        p = answers[k]["noul"]
        if card is None and sid is None:
            glob[kind] = p
        else:
            out.append((kind, card, sid, p))
    return out, glob


def best_of(cs, kind):
    """{session: (p, card)} max per session for one kind."""
    out = {}
    for k, card, sid, p in cs:
        if k == kind and (sid not in out or p > out[sid][0]):
            out[sid] = (p, card)
    return out


def fires(per, bar, lead):
    """The session whose check fires (≥ bar, ahead of every other session's by `lead`), else None."""
    if not per:
        return None
    ranked = sorted(per.items(), key=lambda x: -x[1][0])
    sid, (p, card) = ranked[0]
    second = ranked[1][1][0] if len(ranked) > 1 else 0.0
    return (sid, p, card, p - second) if p >= bar and p - second >= lead else None


def overlay_a0(T, probs, cs, glob, gates, running):
    """→ {action, session, card, mode:{lenient, keep, literal}, ...}. action: stop / interrupt / ack / ask-mismatch / None."""
    T_sid = T[8:] if T and T.startswith("session:") else None
    stop = fires(best_of(cs, "stop"), 0.9, 0.4)
    ack = fires(best_of(cs, "ack"), 0.85, 0.4)
    gate_you = gates.get("gate_you", 0.0)
    out = {"stop_fire": stop and stop[0], "ack_fire": ack and ack[0], "gate_you": gate_you, "instead": glob.get("instead")}

    def act(sid_bound):
        """The action for target session sid_bound (None: no session target, the bound one is the firing one)."""
        if stop and gate_you < 0.5:
            if sid_bound is None or stop[0] == sid_bound:
                if running.get(stop[0]):
                    kind = "interrupt" if (glob.get("instead") or 0) >= 0.6 else "stop"
                    return {"action": kind, "session": stop[0]}
            else:
                return {"action": "ask-mismatch", "session": stop[0], "kind": "stop"}
        if ack:
            sid = ack[0]
            others = max([p for t, p in probs.items() if t.startswith("session:") and t[8:] != sid] or [0])
            if sid_bound is not None and sid != sid_bound:
                return {"action": "ask-mismatch", "session": sid, "card": ack[2], "kind": "ack"}
            if others < 0.5:
                return {"action": "ack", "session": sid, "card": ack[2]}
        return {"action": None}

    if T_sid is not None:
        r = act(T_sid)
        out.update(r, modes={"lenient": r, "keep": r, "literal": r})
    else:
        lenient = act(None)
        literal = lenient if lenient["action"] is None else {**lenient, "action": "ask-mismatch"}
        out.update(lenient, modes={"lenient": lenient, "keep": {"action": None}, "literal": literal})
    return out


def overlay_ao(T, probs, raw_top, cs, glob, running):
    BARS = {"ack": 0.8, "dismiss": 0.85, "stop": 0.9}
    T_sid = T[8:] if T and T.startswith("session:") else None

    def verb_for(sid):
        mine = [(k, card, p) for k, card, s, p in cs if s == sid and p >= BARS[k] and (k != "stop" or running.get(sid))]
        if not mine:
            return None
        k, card, p = max(mine, key=lambda x: x[2])
        return {"action": k, "session": sid, "card": card, "p": p}

    def standing_out():
        """A check ≥ .8 with every check on other targets ≤ .4."""
        for k, card, sid, p in sorted(cs, key=lambda x: -x[3]):
            if p >= 0.8 and all(q <= 0.4 for _, _, s, q in cs if s != sid):
                return sid
        return None

    stand = standing_out()
    pT = probs.get(T, 0.0) if T else 0.0
    route_unclear = raw_top == "unclear" or pT < 0.4
    target = T_sid
    override = False
    if stand and stand != T_sid and route_unclear:
        target, override = stand, True
    v = verb_for(target) if target else None
    if v is None and target and (glob.get("urgent") or 0) >= 0.9 and running.get(target):
        v = {"action": "interrupt", "session": target}
    out = {"action": None, **(v or {}), "override": override, "standing_out": stand, "globals": glob}
    out["second_call"] = ((glob.get("nothing_to_say") or 0) >= 0.5 or (glob.get("urgent") or 0) >= 0.5) and stand is None
    return out


# ------------------------------------------------------------------ system

def _system_class():
    from v2.run import episodes as E
    from v2.run import adapter, rules

    class ActionsSystem(E.RouterSystem):
        def __init__(self, variant, max_calls, repeat=False):
            # "<variant>+split": the route request unchanged (the base), the checks in a separate call on the same state.
            self.split = variant.endswith("+split")
            variant = variant.removesuffix("+split")
            self.base = BASE.get(variant, SHIPPED)
            super().__init__(self.base if self.split else variant, max_calls=max_calls)
            self.variant, self.repeat = variant, repeat
            self.shipped = E.RouterSystem(self.base, max_calls=max_calls)
            self.extra_calls = 0

        def _load(self):
            mods = super()._load()
            mods[0].FORMATS.update({v: make_format(v) for v in VARIANTS})
            return mods

        def _cached(self, digest):
            for cache in (self.cache_path, E.ROUTER / "cache"):
                p = cache / digest[:2] / f"{digest}.json"
                if p.exists():
                    return json.loads(p.read_text())
            raise RuntimeError("answer missing from cache")

        def _plain_ask(self, state, questions, sample=0):
            import jev
            raw = json.dumps({"model": "jev-latest", "state": state, "questions": questions}, sort_keys=False)
            d = hashlib.sha256((raw + f"#{sample}").encode()).hexdigest()
            if not any((c / d[:2] / f"{d}.json").exists() for c in (self.cache_path, E.ROUTER / "cache")):
                if self.extra_calls >= self.max_calls:
                    raise RuntimeError("new Jev call budget exhausted")
                self.extra_calls += 1
            old = jev.CACHE
            try:
                jev.CACHE = self.cache_path
                p = E.ROUTER / "cache" / d[:2] / f"{d}.json"
                if p.exists():
                    return json.loads(p.read_text())
                return jev.ask(state, questions, sample=sample)
            finally:
                jev.CACHE = old

        def _fused(self, fmt, case, answers):
            formats, _, legacy_run, _, lexical, fusion, final3 = self._load()
            _, _, keymap = formats.build(fmt, case)
            reading = legacy_run.reading({"id": case["id"], "keymap": keymap, "answers": answers})
            fusion._CASES = {case["id"]: case}
            fs = lexical.features(reading, case)
            probs = {}
            if fs:
                w, _ = final3.fitted()
                probs = fusion.probs(fs, w)
            route = answers.get("route", {}).get("probabilities", {})
            raw = {keymap.get(k, k): p for k, p in route.items()}
            raw_top = max(raw.items(), key=lambda x: x[1])[0] if raw else None
            st = {"sessions": case["board"]["sessions"]}
            canon = lambda t: adapter.canonical_target(t, st)
            return ({canon(k): v for k, v in probs.items()}, {canon(k): v for k, v in raw.items()},
                    canon(raw_top), reading["gates"])

        def decide(self, state, event):
            ship = self.shipped.decide(state, event)
            case = adapter.to_case(state, event)
            if "request_hash" in ship:
                _PRE[case["id"]] = self._fused(self.base, case, self._cached(ship["request_hash"])["answers"])[0]
            res = super().decide(state, event)
            if "request_hash" not in res:
                return {**res, "shipped": _brief(ship)}
            formats = self._load()[0]
            answers = self._cached(res["request_hash"])["answers"]
            probs, raw, raw_top, gates = self._fused(self.format_name, case, answers)
            if self.split:
                built, _, _ = formats.build(self.base, case)
                extra, _ = VARIANTS[self.variant](case)
                answers = {**answers, **self._plain_ask(built, scrub(extra))["answers"]}
            s_answers = self._cached(ship["request_hash"])["answers"]
            s_probs, s_raw, s_raw_top, _ = self._fused(self.base, case, s_answers)
            _, mapping = VARIANTS[self.variant](case)
            cs, glob = checks(answers, mapping)
            running = {s["id"]: bool(s.get("running")) for s in case["board"]["sessions"]}
            T = res.get("target") if res.get("decision") == "send" and (res.get("target") or "").startswith("session:") else res.get("top")
            info = {"T": T, "checks": [list(c) for c in cs], "globals": glob, "probs": _top(probs), "raw": _top(raw),
                    "raw_top": raw_top, "shipped": _brief(ship), "shipped_probs": _top(s_probs), "shipped_raw": _top(s_raw),
                    "shipped_raw_top": s_raw_top, "today": _brief(res)}
            if self.repeat:
                built, q, _ = formats.build(self.base, case)
                rep = self._plain_ask(built, q, sample=1)["answers"]
                r_probs, r_raw, r_raw_top, _ = self._fused(self.base, case, rep)
                info.update(repeat_probs=_top(r_probs), repeat_raw=_top(r_raw), repeat_raw_top=r_raw_top,
                            repeat_T=max(r_probs.items(), key=lambda x: x[1])[0] if r_probs else None)
            if self.variant == "verbs-o":
                verb = answers.get("verb", {}).get("probabilities", {})
                ov = overlay_vo(T, res.get("sureness"), cs, verb, running)
            elif self.variant.startswith("actions-0"):
                ov = overlay_a0(T, probs, cs, glob, gates, running)
            else:
                ov = overlay_ao(T, probs, raw_top, cs, glob, running)
                if ov["second_call"]:
                    full = {"cards": (glob.get("nothing_to_say") or 0) >= 0.5, "sessions": (glob.get("urgent") or 0) >= 0.5}
                    q2, m2 = ao_extras(case, full)
                    a2 = self._plain_ask({"message": case["message"]}, scrub(q2))["answers"] if q2 else {}
                    cs2, _ = checks(a2, m2)
                    ov2 = overlay_ao(T, probs, raw_top, cs2, glob, running)
                    ov = {**ov2, "second_call": True, "first": {k: ov.get(k) for k in ("action", "session", "card")},
                          "checks2": [list(c) for c in cs2]}
            info["overlay"] = ov
            act = ov.get("action")
            if act in ("stop", "interrupt", "ack", "dismiss"):
                return {**res, "decision": "send", "target": "change_fjord", "action": act, "action_session": ov["session"],
                        "action_card": ov.get("card"), "actions": info}
            if act in ("ask-mismatch", "ask-noverb"):
                return {**res, "decision": "ask", "target": None, "action": "ask-mismatch", "actions": info}
            return {**res, "action": None, "actions": info}

    return ActionsSystem


def _brief(d):
    return {k: d.get(k) for k in ("decision", "target", "top", "path", "reason", "request_hash")} | {
        "ranked": [r["target"] if isinstance(r, dict) else r for r in d.get("ranked", [])][:4]}


def _top(p, n=6):
    return dict(sorted(p.items(), key=lambda x: -x[1])[:n])


def _worker(args):
    set_name, variant, idx, max_calls, repeat = args
    from v2.run import episodes as E
    eps = E.load_episodes(EXP / f"{set_name}.jsonl")
    system = _system_class()(variant, max_calls, repeat)
    out = [E.play_episode(eps[i], system) for i in idx]
    for r in out:
        r.pop("final_state", None)
    return out, system.new_calls + system.shipped.new_calls + system.extra_calls


def run(set_name, variant, workers, max_calls, repeat):
    from v2.run import episodes as E
    n = len(E.load_episodes(EXP / f"{set_name}.jsonl"))
    chunks = [list(range(i, n, workers)) for i in range(workers)]
    with ProcessPoolExecutor(workers) as pool:
        parts = list(pool.map(_worker, [(set_name, variant, c, max_calls, repeat) for c in chunks]))
    results = sorted([r for p, _ in parts for r in p], key=lambda r: r["id"])
    calls = sum(c for _, c in parts)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{variant}.{set_name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    print(f"{variant} {set_name}: {len(results)} episodes, {calls} new calls")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["run", "report"])
    ap.add_argument("set", nargs="?")
    ap.add_argument("variant", nargs="?")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-calls", type=int, default=400)
    ap.add_argument("--repeat", action="store_true")
    a = ap.parse_args()
    if a.mode == "run":
        run(a.set, a.variant, a.workers, a.max_calls, a.repeat)
    else:
        from explore import actions0_report
        actions0_report.main()


if __name__ == "__main__":
    main()
