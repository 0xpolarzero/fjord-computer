"""Stage 1 of the Router redesign: candidate D3, Router actions read from per-target yes/no checks, on the action gold
(v2/ACTIONS.md) with action-aware scoring (v2/run/action_score.py).

D3 = the shipped route request (`capabilities-x-archive-reopen`, unchanged, today's fusion and policy) + a second call
on the same state (split: Stage 0 showed the checks in the route's own call flip ~4% of real routes, the split none):
  markseen<i>  per worth-a-look card on the shortlist (≤8: 4 newest, then word overlap with the message, then newest)
  dismiss<i>   the same shortlist + open cards whose session title the message names (a candidate heuristic only)
  stop<i>      per running session not waiting on you (≤6, most recent first)
  urgent       global; instead: global (does the message also say what to do next)
No word rule decides anything: every action comes from a check over a bar. D3-placebo: the checks reworded and in
reverse order. D3-same: the checks in the route's own call. D3-w2: the one wording iteration (worse on dev). D3-final:
the frozen choice, D3 without markseen (it never reached an explicit "mark X seen" on dev), with PARAMS below.

Decision (`decide`, pure, re-run offline by the report for the bar grid): T = today's target (the send's session, else
the fused top). On T (a session): its best check over its bar (markseen/dismiss .85, stop .9; `t_lead` over the same
kind's checks on other sessions, 0 by default, as actions-o) acts. A running T is stopped when stop_T ≥ the stop bar or
urgent ≥ the urgent bar; with `instead` ≥ its bar that is an interrupt (stop + the words as the next message), and an
urgent-only reading without `instead` acts on nothing. When T is no session or the route is unclear (Jev's raw top
`unclear`, or T's fused p < .4) a check over its bar that stands out (leads every other session's checks of any kind
by `lead` .4) names the target. Unsure (a check between `ask_lo` .5 and its bar on T, or anywhere when the route is
unclear, or a standing-out check on another session than a clear T) → ask; the card's options are typed actions: the
unsure action(s) first, then today's target and card mapped to actions. Else today's outcome, mapped to the action the
live app takes (a send to a session holding a form answers it; else say).

D3-all: D3-final with no shortlist and no word logic: `dismiss<i>` on every open card on the board (any kind, board order;
the adapter's 60-card cap was never reached, max 25) and `stop<i>` on every running session not waiting on you (board
order, no cap), plus urgent and instead, in the same one second call. D3-all-split2: the same checks in two parallel
calls (dismiss; stop + urgent + instead). Same decide() and PARAMS. Each run records per checks call its size, input
tokens and latency (`checks_calls`).

python3 -m explore.actions_d3 run SYSTEM SET [--split dev|calib] [--workers 6] [--max-calls N]
   SYSTEM: shipped, shipped-repeat (the same request asked again, sample 1: Jev's own noise), D3, D3-placebo, D3-same,
           D3-w2, D3-final, D3-all, D3-all-split2
   SET: written_ack, written_stop, written_configure, mined, relabel_real
python3 -m explore.actions_d3 bench SYSTEM [--max-calls N]     D3's checks on bench.py's 611 real moments
Only gitignored data is read or written (v2/data/actions, v2/data/exp/out/actions_d3, v2/run/cache, cache)."""
import argparse
import hashlib
import json
import math
import os
import pathlib
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

os.environ["JEV_ORDERED"] = "1"
HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
ACTIONS = HERE / "v2" / "data" / "actions"
OUT = HERE / "v2" / "data" / "exp" / "out" / "actions_d3"
SHIPPED = "capabilities-x-archive-reopen"

from explore.actions0 import AO, A0, looks, named_cards, scrub, sessions_by_id, shortlist, working  # noqa: E402

WORDING = {
    "markseen": ("Does `message` ask Fjord to mark this card as seen, read or done (a request about the card itself), "
                 "rather than tell its session anything?"),
    "dismiss": AO["dismiss"],
    "stop": AO["stop"],
    "urgent": AO["urgent"],
    "instead": A0["instead"],
}
PLACEBO = {
    "markseen": ("Is `message` a request to Fjord to mark this card read, seen or done (about the card, not words for "
                 "its session)?"),
    "dismiss": ("Is `message` asking to drop or archive this card, since the user doesn't need it or will deal with it "
                "personally?"),
    "stop": "Is `message` asking that this session's current work be interrupted or halted now?",
    "urgent": "Is `message` asking a session to change or halt what it's doing right away, rather than once it is done?",
    "instead": "Apart from stopping something, does `message` tell what should happen next or in its place?",
}

# The one wording iteration (dev): stop and dismiss phrased as requests to Fjord about the session/card, as markseen is.
WORDING2 = {
    **WORDING,
    "stop": ("Does `message` ask Fjord to stop this session now (halt, cancel, abort or interrupt its current run), "
             "rather than tell it something about the work?"),
    "dismiss": ("Does `message` ask Fjord to archive, drop or clear this card from the board (for instance because the "
                "user will handle it or doesn't need it), rather than tell its session anything?"),
}
# D3-final: the frozen choice after dev (D3's wording without markseen, which never reached an explicit request).
FINAL = {k: v for k, v in WORDING.items() if k != "markseen"}
WORDINGS = {"D3": (WORDING, False), "D3-same": (WORDING, False), "D3-placebo": (PLACEBO, True), "D3-w2": (WORDING2, False),
            "D3-final": (FINAL, False), "D3-all": (FINAL, False), "D3-all-split2": (FINAL, False)}

# Frozen on dev (explore/actions_d3_report.py --grid): the bars, t_lead .2 (T's check leads the same kind elsewhere),
# markseen off. The runs record every check, so the report re-decides any other setting offline.
PARAMS = {"bars": {"markseen": 0.85, "dismiss": 0.85, "stop": 0.9, "urgent": 0.85, "instead": 0.6},
          "lead": 0.4, "t_lead": 0.2, "ask_lo": 0.5, "unsure_ask": True, "named": True, "markseen": False}


def card_info(case, c):
    s = sessions_by_id(case)[c["session"]]
    return {"session": s["title"], "report": c.get("text", "")[:400]}


def session_info(s):
    return {"title": s["title"], "project": s.get("project", ""), "now": "working: " + (s.get("activity") or "")}


def all_cards(case):
    """Every open card on the board (any kind), in board order: no ranking, no words."""
    by = sessions_by_id(case)
    return [c for c in case["board"]["cards"] if c["session"] in by]


def stoppable(case, mode="short"):
    """Running sessions not waiting on you: ≤6 most recent (D3), or all of them in board order (D3-all)."""
    if mode == "all":
        return [s for s in case["board"]["sessions"] if s.get("running") and not s.get("waits_on_you")]
    return working(case, waiting_too=False)[:6]


def extras(case, wording=WORDING, placebo=False, mode="short", only=None):
    """→ (questions, mapping {key: (kind, card, session, named_only)}). mode "all": dismiss on every open card, stop on
    every running session. only: a set of kinds to ask (D3-all-split2's two calls)."""
    qs, m = [], {}
    if mode == "all":
        short, named = all_cards(case), []
    else:
        short = shortlist(case)
        named = [c for c in named_cards(case) if c not in short]
    for i, c in enumerate(short if "markseen" in wording else []):
        qs.append((f"markseen{i}", {"type": "noul", "instructions": {"question": wording["markseen"], "card": card_info(case, c)}}))
        m[f"markseen{i}"] = ("markseen", c["id"], c["session"], False)
    for i, c in enumerate(short + named):
        qs.append((f"dismiss{i}", {"type": "noul", "instructions": {"question": wording["dismiss"], "card": card_info(case, c)}}))
        m[f"dismiss{i}"] = ("dismiss", c["id"], c["session"], c in named)
    for i, s in enumerate(stoppable(case, mode)):
        qs.append((f"stop{i}", {"type": "noul", "instructions": {"question": wording["stop"], "session": session_info(s)}}))
        m[f"stop{i}"] = ("stop", None, s["id"], False)
    for k in ("urgent", "instead"):
        qs.append((k, {"type": "noul", "instructions": {"question": wording[k]}}))
        m[k] = (k, None, None, False)
    if only is not None:
        qs = [q for q in qs if m[q[0]][0] in only]
        m = {k: v for k, v in m.items() if v[0] in only}
    if placebo:
        qs = qs[::-1]
    return dict(qs), m


# D3-all-split2: the dismiss checks in one call; the stop checks with urgent and instead in another, in parallel.
SPLIT2 = ({"dismiss"}, {"stop", "urgent", "instead"})


def check_calls(system, case):
    """→ [(questions, mapping)] for the second call(s) of a D3 system."""
    wording, placebo = WORDINGS[system]
    mode = "all" if system.startswith("D3-all") else "short"
    if system == "D3-all-split2":
        return [extras(case, wording, placebo, mode, only) for only in SPLIT2]
    return [extras(case, wording, placebo, mode)]


def read_checks(answers, mapping):
    cs, glob = [], {}
    for k, (kind, card, sid, named) in mapping.items():
        if k not in answers:
            continue
        p = answers[k]["noul"]
        if sid is None:
            glob[kind] = p
        else:
            cs.append([kind, card, sid, p, named])
    return cs, glob


# ------------------------------------------------------------------ actions

def act_of(kind, card, sid):
    return {"markseen": f"ack:card:{card}", "dismiss": f"archive:card:{card}", "stop": f"stop:session:{sid}",
            "interrupt": f"interrupt:session:{sid}"}[kind]


def live_action(target, cards):
    """A legacy destination as the live app acts on it. cards: [(id, session, kind)] open on the board."""
    if not target:
        return None
    if target.startswith("session:"):
        sid = target[8:]
        forms = [c for c in cards if c[1] == sid and c[2] in ("question", "plan")]
        return f"answer:card:{forms[0][0]}" if forms else "say:" + target
    if target.startswith("new:"):
        return "start:" + target
    if target.startswith("answer:"):
        return "answer:card:" + target[7:]
    return {"change_fjord": "configure", "question": "ask_fjord", "compound": "compound"}.get(target, target)


def decide(info, params=PARAMS):
    """→ {"decision": "act"|"ask"|"route", "act": action or None, "options": [typed actions] or None, "why": str}."""
    bars, lead, lo = params["bars"], params["lead"], params["ask_lo"]
    cs = [c for c in info["checks"] if (params["named"] or not c[4]) and (params["markseen"] or c[0] != "markseen")]
    glob = info["globals"]
    urgent, instead = glob.get("urgent") or 0.0, glob.get("instead") or 0.0
    running = set(info["stoppable"])
    T = info["T"]
    T_sid = T[8:] if T and T.startswith("session:") else None

    def other_max(c, any_kind=False):
        return max([d[3] for d in cs if d[2] != c[2] and (any_kind or d[0] == c[0])] or [0.0])

    def over(c):
        return c[3] >= bars[c[0]] and (c[0] != "stop" or c[2] in running)

    def act(c):
        kind = c[0]
        if kind == "stop" and instead >= bars["instead"]:
            kind = "interrupt"
        return act_of(kind, c[1], c[2])

    pT = info.get("pT") or 0.0
    unclear = info.get("raw_top") == "unclear" or pT < 0.4 or T_sid is None
    if T_sid:
        mine = sorted([c for c in cs if c[2] == T_sid and over(c) and c[3] - other_max(c) >= params["t_lead"]],
                      key=lambda c: -c[3])
        if mine:
            return {"decision": "act", "act": act(mine[0]), "options": None, "why": "T"}
        if T_sid in running and urgent >= bars["urgent"] and instead >= bars["instead"]:
            return {"decision": "act", "act": act_of("interrupt", None, T_sid), "options": None, "why": "urgent"}
    stand = sorted([c for c in cs if over(c) and c[3] - other_max(c, any_kind=True) >= lead], key=lambda c: -c[3])
    if stand and unclear:
        return {"decision": "act", "act": act(stand[0]), "options": None, "why": "standing-out"}
    if stand and stand[0][2] != T_sid:
        return _ask(info, [act(stand[0])], "elsewhere")
    if params["unsure_ask"]:
        near = sorted([c for c in cs if c[3] >= lo and (c[0] != "stop" or c[2] in running)
                       and (c[2] == T_sid or unclear)], key=lambda c: -c[3])
        if near:
            return _ask(info, [act(c) for c in near[:2]], "unsure")
    r = info["routing"]
    if r["decision"] == "ask":
        near = sorted([c for c in cs if c[3] >= lo and (c[0] != "stop" or c[2] in running)], key=lambda c: -c[3])
        return _ask(info, [act(c) for c in near[:2]], "route-ask")
    return {"decision": "route", "act": r["act"], "options": None, "why": "route"}


def _ask(info, first, why):
    r = info["routing"]
    rest = ([info["T_act"]] if info.get("T_act") and r["decision"] != "ask" else []) + list(r["options"])
    out = []
    for a in first + rest:
        if a and a not in out:
            out.append(a)
    return {"decision": "ask", "act": None, "options": out[:4], "why": why}


# ------------------------------------------------------------------ system

def _system_class():
    from v2.run import episodes as E
    from v2.run import adapter

    class D3System(E.RouterSystem):
        def __init__(self, system, max_calls, params=PARAMS):
            self.system, self.params = system, params
            fmt = "D3-same" if system == "D3-same" else SHIPPED
            super().__init__(fmt, max_calls=max_calls)
            self.extra_calls = 0
            self.sample = 1 if system == "shipped-repeat" else 0

        @property
        def name(self):
            return self.system

        def _load(self):
            mods = super()._load()
            if "D3-same" not in mods[0].FORMATS:
                formats = mods[0]

                def same(case, rng=None):
                    state, q, keymap = formats.FORMATS[SHIPPED](case, rng=rng)
                    return state, {**q, **scrub(extras(case)[0])}, keymap
                formats.FORMATS["D3-same"] = same
            return mods

        def _ask(self, state, questions):
            if self.sample == 0:
                return super()._ask(state, questions)
            a = self._plain_ask(state, questions, self.sample)
            return a, "repeat", True

        def _plain_ask(self, state, questions, sample=0):
            import jev
            raw = json.dumps({"model": "jev-latest", "state": state, "questions": questions}, sort_keys=False)
            d = hashlib.sha256((raw + f"#{sample}").encode()).hexdigest()
            for c in (self.cache_path, E.ROUTER / "cache"):
                p = c / d[:2] / f"{d}.json"
                if p.exists():
                    return json.loads(p.read_text())
            if self.extra_calls + self.new_calls >= self.max_calls:
                raise RuntimeError("new Jev call budget exhausted")
            self.extra_calls += 1
            old = jev.CACHE
            try:
                jev.CACHE = self.cache_path
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
            return {canon(k): v for k, v in probs.items()}, canon(raw_top)

        def decide(self, state, event):
            res = super().decide(state, event)
            case = adapter.to_case(state, event)
            cards = [(c["id"], c["session"], c["kind"]) for c in case["board"]["cards"]]
            ranked = [r["target"] if isinstance(r, dict) else r for r in res.get("ranked", [])]
            options = [a for a in dict.fromkeys(live_action(t, cards) for t in ranked) if a][:4]
            act = live_action(res.get("target"), cards) if res["decision"] != "ask" else None
            routing = {"decision": "ask" if res["decision"] == "ask" else "send", "target": res.get("target"),
                       "act": act, "options": options, "reason": res.get("reason"), "path": res.get("path")}
            out = {**res, "act": act, "routing": routing}
            if res["decision"] == "ask":
                out["act_options"] = options
            if self.system in ("shipped", "shipped-repeat") or "request_hash" not in res:
                return out
            formats = self._load()[0]
            if self.system == "D3-same":
                q, mapping = extras(case)
                answers = self._cached(res["request_hash"])["answers"]
                cs, glob = read_checks(answers, mapping)
            else:
                built, _, _ = formats.build(SHIPPED, case)
                parts = [(q, mp) for q, mp in check_calls(self.system, case) if q]
                with ThreadPoolExecutor(max(len(parts), 1)) as pool:
                    fulls = list(pool.map(lambda x: self._plain_ask(built, scrub(x[0])), parts))
                cs, glob = [], {}
                for (q, mp), full in zip(parts, fulls):
                    c1, g1 = read_checks(full["answers"], mp)
                    cs += c1
                    glob.update(g1)
                out["checks_calls"] = [{"n": len(q), "tokens": (f.get("usage") or {}).get("input_tokens"),
                                        "latency": f.get("_latency")} for (q, _), f in zip(parts, fulls)]
                out["checks_tokens"] = sum(c["tokens"] or 0 for c in out["checks_calls"])
                out["n_board_cards"] = len(case["board"]["cards"])
            route_answers = self._cached(res["request_hash"])["answers"]
            probs, raw_top = self._fused(self.format_name, case, route_answers)
            T = res.get("target") if res["decision"] == "send" and (res.get("target") or "").startswith("session:") \
                else res.get("top")
            info = {"T": T, "pT": probs.get(T, 0.0) if T else 0.0, "raw_top": raw_top, "checks": cs, "globals": glob,
                    "stoppable": [s["id"] for s in stoppable(case, "all" if self.system.startswith("D3-all") else "short")],
                    "T_act": live_action(T, cards) if T else None, "routing": routing}
            d = decide(info, self.params)
            out["d3"] = info
            out["d3_decision"] = d
            if d["decision"] == "act":
                kind = d["act"].split(":", 1)[0]
                tgt = "session:" + d["act"].rsplit(":", 1)[1] if kind == "interrupt" else "change_fjord"
                return {**out, "decision": "send", "target": tgt, "act": d["act"], "act_options": None}
            if d["decision"] == "ask":
                return {**out, "decision": "ask", "target": None, "act": None, "act_options": d["options"]}
            return out

        def _cached(self, digest):
            for cache in (self.cache_path, E.ROUTER / "cache"):
                p = cache / digest[:2] / f"{digest}.json"
                if p.exists():
                    return json.loads(p.read_text())
            raise RuntimeError("answer missing from cache")

    return D3System


def set_path(split, name):
    if split not in ("dev", "calib"):
        raise SystemExit("only dev and calib")
    return ACTIONS / split / f"{name}.jsonl"


def _worker(args):
    path, system, idx, max_calls = args
    from v2.run import episodes as E
    eps = E.load_episodes(path)
    sysm = _system_class()(system, max_calls)
    out = [E.play_episode(eps[i], sysm) for i in idx]
    for r in out:
        r.pop("final_state", None)
    return out, sysm.new_calls + sysm.extra_calls


def run(system, set_name, split, workers, max_calls):
    from v2.run import episodes as E
    path = set_path(split, set_name)
    n = len(E.load_episodes(path))
    chunks = [list(range(i, n, workers)) for i in range(workers)]
    with ProcessPoolExecutor(workers) as pool:
        parts = list(pool.map(_worker, [(path, system, c, max_calls // workers + 1) for c in chunks]))
    results = sorted([r for p, _ in parts for r in p], key=lambda r: r["id"])
    calls = sum(c for _, c in parts)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{system}.{split}.{set_name}.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    print(f"{system} {split}/{set_name}: {len(results)} episodes, {calls} new calls")


# ------------------------------------------------------------------ bench (611 real moments)

def bench(system, max_calls):
    """D3's route on bench.py's real moments is the shipped request itself (split call): the same hash, so the same
    answer. Asks D3's checks on each, decides with the shipped fused T, records every check and outcome."""
    import bench as B
    import formats as F
    import jev
    import run as R
    from explore import cal, capabilities, combo, final3, fusion
    from explore import lexical as L
    from v2.run import episodes as E
    for m in (combo, cal, capabilities):
        F.FORMATS.update(m.FORMATS)
    jev.ordered = True
    L.install()
    fusion.case_features = final3.case_features
    L.STATE["fields"] = True
    final3._FIT["combo-o"] = E._shipped_weights()
    cases = B.load_set("real")
    calls, out, spans = [], [], []
    for c in cases:
        state, q, keymap = F.build(SHIPPED, c)
        start = len(calls)
        calls.append((state, q))
        parts = [(xq, mp) for xq, mp in check_calls(system, c) if xq]
        for xq, _ in parts:
            calls.append((state, scrub(xq)))
        spans.append((start, parts))
    route_idx = {s for s, _ in spans}
    todo = route_todo = 0
    for i, (st, q) in enumerate(calls):
        raw = json.dumps({"model": "jev-latest", "state": st, "questions": q}, sort_keys=False)
        d = hashlib.sha256((raw + "#0").encode()).hexdigest()
        miss = not (jev.CACHE / d[:2] / f"{d}.json").exists()
        todo += miss
        route_todo += miss and i in route_idx
    # The route request is the shipped one: answered already by the shipped bench run (route_todo 0) = the same answer.
    print(f"[bench {system}] {len(cases)} cases, {todo} uncached calls, of which {route_todo} route requests",
          file=sys.stderr)
    if todo > max_calls:
        raise SystemExit(f"{todo} new calls exceed the budget {max_calls}")
    answers = jev.ask_many(calls)
    for i, c in enumerate(cases):
        state, q, keymap = F.build(SHIPPED, c)
        start, parts = spans[i]
        route, checks_l = answers[start], answers[start + 1:start + 1 + len(parts)]
        row = {"id": c["id"], "keymap": keymap, "answers": route["answers"]}
        r = R.reading(row)
        fusion._CASES = {c["id"]: c}
        k, w = final3.best(r, c)
        fs = L.features(r, c)
        probs = fusion.probs(fs, final3.fitted()[0]) if fs else {}
        probs = {("session:" + t if t in {s["id"] for s in c["board"]["sessions"]} else t): p for t, p in probs.items()}
        top = max(probs.items(), key=lambda x: x[1])[0] if probs else None
        rt = {keymap.get(kk, kk): p for kk, p in route["answers"].get("route", {}).get("probabilities", {}).items()}
        raw_top = max(rt.items(), key=lambda x: x[1])[0] if rt else None
        raw_top = "session:" + raw_top if raw_top in {s["id"] for s in c["board"]["sessions"]} else raw_top
        cs, glob = [], {}
        for (xq, mp), ch in zip(parts, checks_l):
            c1, g1 = read_checks(ch["answers"], mp)
            cs += c1
            glob.update(g1)
        sent = "session:" + w if k == "send" and w in {s["id"] for s in c["board"]["sessions"]} else (w if k == "send" else None)
        T = sent if sent and sent.startswith("session:") else top
        cards = [(cd["id"], cd["session"], cd["kind"]) for cd in c["board"]["cards"]]
        routing = {"decision": "send" if k == "send" else "ask", "target": sent, "act": live_action(sent, cards),
                   "options": [live_action("session:" + t if t in {s["id"] for s in c["board"]["sessions"]} else t, cards)
                               for t in (w if k != "send" else [])][:4]}
        info = {"T": T, "pT": probs.get(T, 0.0) if T else 0.0, "raw_top": raw_top, "checks": cs, "globals": glob,
                "stoppable": [s["id"] for s in stoppable(c, "all" if system.startswith("D3-all") else "short")],
                "T_act": live_action(T, cards) if T else None, "routing": routing}
        out.append({"id": c["id"], "message": c["message"], "gold": c["gold"], "label": c["gold"].get("label"),
                    "half": B.half(c["id"]), "route_hash": hashlib.sha256(json.dumps(
                        {"model": "jev-latest", "state": state, "questions": q}, sort_keys=False).encode()).hexdigest(),
                    "d3": info, "d3_decision": decide(info),
                    "tokens": sum((ch.get("usage") or {}).get("input_tokens") or 0 for ch in checks_l),
                    "checks_calls": [{"n": len(xq), "tokens": (ch.get("usage") or {}).get("input_tokens"),
                                      "latency": ch.get("_latency")} for (xq, _), ch in zip(parts, checks_l)],
                    "n_board_cards": len(c["board"]["cards"]),
                    "route_tokens": (route.get("usage") or {}).get("input_tokens")})
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"bench.{system}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in out))
    print(f"bench {system}: {len(out)} moments, {todo} new calls")


# ------------------------------------------------------------------ parity fixture for the Swift port

PARITY = HERE.parents[1] / "Tests" / "FjordTests" / "Fixtures" / "router-actions-parity.json"


def _walk(o):
    if isinstance(o, dict):
        if "d3_decision" in o:
            yield o
        for v in o.values():
            yield from _walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from _walk(v)


def synthetic_cases(n=300, seed=7):
    """Made-up boards (three sessions with a card each, two stoppable) with checks drawn from values at, under and over
    every bar, so that the branches the recorded traces rarely reach (archive, an unclear T, a lead too small, urgent
    without instead) are compared too."""
    import random
    rng = random.Random(seed)
    values = [0.05, 0.3, 0.49, 0.5, 0.55, 0.6, 0.65, 0.84, 0.85, 0.88, 0.9, 0.95, 0.99]
    sessions = ["s1", "s2", "s3"]
    out = []
    for i in range(n):
        checks = [["dismiss", f"{s}#c", s, rng.choice(values), False] for s in sessions]
        stop_for = rng.sample(sessions, rng.choice([0, 1, 2]))
        checks += [["stop", None, s, rng.choice(values), False] for s in stop_for]
        T = rng.choice(["session:s1", "session:s2", "session:s3", "new:lookout", "change_fjord", "question", None])
        sid = T[8:] if T and T.startswith("session:") else None
        cards = [(f"{s}#c", s, rng.choice(["done", "question"])) for s in sessions]
        routing_ask = rng.random() < 0.4
        ranked = rng.sample(["session:s1", "session:s2", "session:s3", "new:lookout", "change_fjord"], 4)
        options = [a for a in dict.fromkeys(live_action(t, cards) for t in ranked) if a][:4]
        act = None if routing_ask else live_action(T, cards)
        info = {"T": T, "pT": rng.choice([0.0, 0.2, 0.39, 0.4, 0.7, 0.95]) if T else 0.0,
                "raw_top": rng.choice(["unclear", T or "unclear", "session:s2", "change_fjord"]), "checks": checks,
                "globals": {"urgent": rng.choice(values), "instead": rng.choice(values)}, "stoppable": stop_for,
                "T_act": live_action(T, cards) if T else None,
                "routing": {"decision": "ask" if routing_ask else "send", "target": T, "act": act, "options": options}}
        out.append({"name": f"synthetic:{i}", "info": info, "expected": decide(info)})
    return out


def export_parity(per_class=45):
    """Recorded check/route answers of the cached D3-all dev traces (runs and bench) with `decide`'s answer on each, for
    RouterActionsParityTests: every case where a check decided (act, unsure, elsewhere), and an even spread of the route-ask
    and route outcomes. Deterministic. Only probabilities, ids of the eval boards and actions are written (no message text)."""
    import glob
    rows = []
    for f in sorted(glob.glob(str(OUT / "D3-all.*.jsonl"))) + [str(OUT / "bench.D3-all.jsonl")]:
        if not os.path.exists(f):
            continue
        for line in open(f):
            for n, x in enumerate(_walk(json.loads(line))):
                info = x["d3"]
                d = decide(info)
                assert d == x["d3_decision"], (f, n)
                rows.append((os.path.basename(f), x.get("id"), n, info, d))
    strata = {}
    for r in rows:
        strata.setdefault((r[4]["decision"], r[4]["why"]), []).append(r)
    cases = []
    for key in sorted(strata):
        rs = sorted(strata[key], key=lambda r: (r[0], str(r[1]), r[2]))
        if key in (("route", "route"), ("ask", "route-ask")):
            step = max(1, len(rs) // per_class)
            rs = rs[::step][:per_class]
        for r in rs:
            cases.append({"name": f"{r[0]}:{r[1]}:{r[2]}", "info": r[3], "expected": r[4]})
    cases += synthetic_cases()
    PARITY.parent.mkdir(parents=True, exist_ok=True)
    PARITY.write_text(json.dumps({"params": PARAMS, "cases": cases}, sort_keys=True, separators=(",", ":")) + "\n")
    print(f"{len(cases)} cases -> {PARITY}", {f"{k[0]}/{k[1]}": len(v) for k, v in sorted(strata.items())})


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "export-parity":
        return export_parity()
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["run", "bench"])
    ap.add_argument("system", choices=["shipped", "shipped-repeat", "D3", "D3-placebo", "D3-same", "D3-w2", "D3-final",
                                       "D3-all", "D3-all-split2"])
    ap.add_argument("set", nargs="?")
    ap.add_argument("--split", default="dev")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-calls", type=int, default=1200)
    a = ap.parse_args()
    if a.mode == "run":
        run(a.system, a.set, a.split, a.workers, a.max_calls)
    else:
        bench(a.system, a.max_calls)


if __name__ == "__main__":
    main()
