"""Is an LLM a better Router than Jev? Head-to-head on Stage 2's action gold (v2/ACTIONS.md, v2/run/action_score.py), the
same sets and scorer as explore/actions_d3.py, plus bench.py's 611 real moments for no-harm.

Systems (shipped and D3-all are read from explore/actions_d3's cached runs; nothing of theirs is re-asked):
  llm-haiku   claude-haiku-5-5 decides everything in ONE structured call: board (the sessions the Jev route sees, in
              Lookout's order, with project, state/now line, open cards with ids and kinds, what the user last told
              each, the latest finished sessions' last words) + message → {action, target, alternatives, confidence}.
              Act on `high`; else ask with [target + alternatives], filled up to four by recency.
  llm-sonnet  the same with claude-sonnet-5-5, on a subset (dev written + mined + ≥150 random relabel_real submits).
  hybrid      shipped Jev as today picks the target T (its send, else its fused top); Haiku decides only the action on
              T and whether to ask (same board, T marked).
The deterministic rules that run before Jev in Fjord (armed reply, pin, single @project pill; rules.plan) run first for
every system, as they are not Jev's. Jev's post-processing (rules.post_jev) is part of shipped only.

Calls go through the Claude Code CLI exactly as Fjord's RouterBrief.haiku does (`claude -p --model M --tools ""
--setting-sources "" --strict-mcp-config --no-session-persistence --output-format json --json-schema S --system-prompt
P`, the context on stdin); no API key is configured here. Every answer is cached on disk by a hash of (model, prompt,
context, schema, sample). Before any text reaches a model it goes through real.boards.redact (free text only, never
ids), as the Jev path does.

python3 -m explore.llm_router run SYSTEM SET [--split dev|calib] [--prompt v1|v2] [--subset] [--workers 6] [--max-calls N]
python3 -m explore.llm_router bench SYSTEM [--prompt v1|v2] [--max-calls N] [--limit N]
python3 -m explore.llm_router repeat SYSTEM [--prompt v1|v2] [--n 100]      re-ask 100 dev submits (sample 1)
python3 -m explore.llm_router probe                                          one call, prints the raw CLI answer
Only gitignored data is read or written (v2/data/actions, v2/data/exp/out/llm_router, v2/run/cache, cache)."""
import argparse
import hashlib
import json
import os
import pathlib
import random
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

os.environ["JEV_ORDERED"] = "1"
HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
ACTIONS = HERE / "v2" / "data" / "actions"
OUT = HERE / "v2" / "data" / "exp" / "out" / "llm_router"
CACHE = OUT / "cache"
D3OUT = HERE / "v2" / "data" / "exp" / "out" / "actions_d3"
MODELS = {"llm-haiku": "claude-haiku-5-5", "llm-sonnet": "claude-sonnet-5-5", "hybrid": "claude-haiku-5-5"}
SETS = ["written_ack", "written_stop", "written_configure", "mined", "relabel_real"]
ACTION_NAMES = ["say", "answer", "stop", "interrupt", "archive", "start", "configure", "ask_fjord", "unsure"]
HYBRID_NAMES = ["say", "answer", "stop", "interrupt", "archive", "not_this", "unsure"]

from real.boards import redact  # noqa: E402
import formats as F  # noqa: E402
from explore import recency as RC  # noqa: E402

KINDS = {"question": "a form question waiting for the user's answer (options listed)",
         "plan": "a plan waiting for the user's approval",
         "asks": "its turn ended asking the user something",
         "approval": "asks the user's OK",
         "stuck": "stuck, needs the user",
         "done": "worth-a-look: a finished turn the user may read and mark seen"}
NEEDS_YOU = {"question", "plan", "asks", "approval", "stuck"}

# ------------------------------------------------------------------ prompts

SYSTEM_V1 = """You are the Router of Fjord, a Mac app that sits over the user's Claude Code sessions. The user typed one message into the Router's single composer. Decide what Fjord does with it: one action on one target.

Actions (target in brackets):
- say [session id]: deliver the words to that session as the user's next message (queued if it is running). The default for any instruction, question, reply or remark meant for a session, including questions to a session about its own work ("what does X mean?", "did you push?").
- answer [card id]: the words answer an open card that waits on the user (kinds question, plan, asks, approval, stuck): a reply to what it asks, a choice among its options, "yes", "go ahead", "no, do Y".
- stop [session id]: stop a RUNNING session's current turn; nothing else is sent. Only when the message asks for that and says nothing about what to do next ("stop the CI one", "kill it", "abort").
- interrupt [session id]: stop a RUNNING session's turn now AND send the words as its next message ("stop, use the other API instead", "wait, don't touch main, work on a branch").
- archive [card id]: remove a card from the board because the user will handle it themselves or doesn't need it ("I'll do the theme one myself", "drop the login card").
- start [new:<project>]: start a new session in that project with the words: the message asks for a new session, or is new work that no existing session is doing.
- configure [null, or the card/session/project it is about]: Fjord itself does something, no session involved: turn a setting or notifications on or off; change Triage's inbox categories, rules or groups; mark a worth-a-look card (or all of them) as seen/read ("seen the docs one", "got it, read the headlines", "mark everything seen"); reopen an archived card; mute or unmute a project.
- ask_fjord [null]: a read-only question to Fjord about the board ("which sessions are waiting on me?", "is the CI one done?"). A question to a session about its own work is say, not ask_fjord.
- unsure [null or your best guess]: you can't tell where it goes or what it means.

Traps (these are say/answer to a session, not Fjord actions):
- Words like stop, seen, archive, mute, reopen inside work for a session: "stop using lodash", "archive the old logs in the repo", "mute the warnings in the build", "reopen the issue and fix it", "stop the dev server" (a process the session runs), "why did you stop?", "don't stop", "keep going".
- A message addressed to a session ("tell X…", "X: …", "you…") or quoting text is for that session, even if it mentions seeing or stopping.
- "Seen it, now fix the tests" acknowledges and asks for more work: say to that session.
- Negations: "don't mark it seen yet", "no need to stop" are not those actions.
- stop/interrupt need a running session; an archive or a mark-seen needs that card on the board. If the message asks for one the board can't do (the named session isn't running, the card isn't there), answer unsure with that session as target.

The user's real messages are terse ("go", "commit it", "yes") and usually continue the conversation they were just having: the session with an open card waiting on them, the one that finished most recently, or the one they last wrote to. A bare reply to an open card is answer on that card.

Confidence: high only when the message and board leave one clear reading; medium when it is likely but another reading is plausible; low when guessing. A wrong send costs the user about 25 times what a question to them costs (Fjord asks with four options when you are not sure), and a wrong stop can't be undone. Give up to 3 alternatives (other plausible action+target pairs, most likely first) whenever confidence isn't high.

Use only ids that appear on the board. Answer with the JSON object only."""

# The one prompt-iteration round (dev only), from the v1 dev failures: every wrong v1 send on real moments was ask_fjord
# on a short question meant for a session, and 40 of 393 real asks missed the session on the card, mostly the one the
# user had just been talking to. Frozen after dev: Haiku v1 (v2 halved real wrong sends but lost more on asks, dev loss
# 1,027 vs 948), the hybrid v2, Sonnet v2 (subset loss 432 vs 467).
SYSTEM_V2_EXTRA = """

Two corrections:
- ask_fjord is only for a question about the board as a whole or about a session named in the third person ("which ones are waiting?", "is the CI one done?", "what is the docs session doing?"). A question with no session named, such as "what are you doing?", "anything new?", "anything left?", "where are we at?", "all good then?", "what should I do?", "what do we need to do?", is the user talking to the session they are in a conversation with: say to that session (low or medium confidence if you can't tell which), never ask_fjord.
- When you are not sure which session, your target and alternatives should be the sessions the user is most likely in a conversation with: the one they wrote to most recently (see "the user last told it" and how long ago), the ones that finished most recently, the one whose open card waits on them. A message with no name in it almost always goes to one of those."""

SCHEMA = {
    "type": "object",
    "properties": {
        "action": {"type": "string", "enum": ACTION_NAMES},
        "target": {"type": ["string", "null"]},
        "alternatives": {"type": "array", "maxItems": 3, "items": {
            "type": "object", "properties": {"action": {"type": "string", "enum": ACTION_NAMES},
                                             "target": {"type": ["string", "null"]}},
            "required": ["action", "target"], "additionalProperties": False}},
        "confidence": {"type": "string", "enum": ["low", "medium", "high"]},
    },
    "required": ["action", "target", "alternatives", "confidence"],
    "additionalProperties": False,
}

HYBRID_SYSTEM = """You are part of the Router of Fjord, a Mac app over the user's Claude Code sessions. The user typed one message into the Router's composer. Another model already picked the session it is most likely about (the TARGET, marked on the board). Decide only what Fjord does to that target, and how sure you are.

Actions on the target:
- say: deliver the words to the target session as the user's next message (queued if it is running). The default for instructions, questions, replies and remarks for it, including questions about its own work.
- answer [card id of the target]: the words answer one of the target's open cards that waits on the user (question, plan, asks, approval, stuck).
- stop: stop the target's running turn; nothing else is sent. Only when the message asks for that and says nothing about what to do next. The target must be running.
- interrupt: stop the target's running turn now AND send the words as its next message. The target must be running.
- archive [card id of the target]: remove that card from the board because the user will handle it themselves or doesn't need it.
- not_this: the message is not for the target: it is for another session, for a new session, or for Fjord itself (a setting, marking cards seen, a question about the board).
- unsure: you can't tell.

Traps (these are say/answer, not stop/archive): words like stop, seen, archive, mute, reopen inside work for the session ("stop using lodash", "archive the old logs in the repo", "stop the dev server", "why did you stop?", "don't stop"); messages addressed to the session or quoting text; negations. A stop request when the target isn't running is unsure.

Confidence: high only when the reading is clear; medium when likely; low when guessing. A wrong action costs about 25 times a question to the user, and a wrong stop can't be undone. Answer with the JSON object only."""

HYBRID_SCHEMA = {
    "type": "object",
    "properties": {"action": {"type": "string", "enum": HYBRID_NAMES},
                   "card": {"type": ["string", "null"]},
                   "confidence": {"type": "string", "enum": ["low", "medium", "high"]}},
    "required": ["action", "card", "confidence"],
    "additionalProperties": False,
}

# The hybrid's one iteration round (dev only), from the v1 dev failures: 7 acknowledgements ("ok seen X") came back as
# archive (v1 had no mark-seen action), and 8 "hold on X, use Y instead" to a running target as say.
HYBRID_V2 = HYBRID_SYSTEM.replace(
    "- not_this:",
    "- mark_seen [card id of the target]: the user acknowledges one of the target's worth-a-look (done) cards and asks "
    "nothing more (\"seen\", \"ok vu\", \"read it, thanks\", \"mark it seen\"): Fjord marks it seen, nothing reaches the "
    "session. Not archive: archive is for cards the user will handle themselves or doesn't need.\n- not_this:").replace(
    "Traps (these",
    "If the target is RUNNING and the message changes what it is doing right now (\"hold on, …\", \"wait, do X first\", "
    "\"stop, use Y instead\", \"actually, … instead\"), that is interrupt, not say: say would only queue the words behind "
    "the running turn.\n\nTraps (these")
HYBRID_NAMES_V2 = HYBRID_NAMES[:5] + ["mark_seen"] + HYBRID_NAMES[5:]
HYBRID_SCHEMA_V2 = json.loads(json.dumps(HYBRID_SCHEMA))
HYBRID_SCHEMA_V2["properties"]["action"]["enum"] = HYBRID_NAMES_V2


def system_prompt(system, version):
    if system == "hybrid":
        return HYBRID_V2 if version == "v2" else HYBRID_SYSTEM
    return SYSTEM_V1 + (SYSTEM_V2_EXTRA if version == "v2" else "")


def schema_of(system, version):
    if system == "hybrid":
        return HYBRID_SCHEMA_V2 if version == "v2" else HYBRID_SCHEMA
    return SCHEMA


# ------------------------------------------------------------------ board

def _cut(text, n):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


def board_text(case, target=None):
    """The board the Jev route sees (formats.v2 + told), with ids and cards, as text. Free text redacted."""
    board = case["board"]
    ordered, names = F.session_options(board)
    latest = {s["id"] for s in RC.finished_by_recency(board)[:3]}
    lines = ["Projects (for start: new:<project>): " + ", ".join(board.get("projects", [])), "",
             "Sessions (running first, then most recent):"]
    for s in ordered:
        state = ("RUNNING" + (" (waiting on the user)" if s.get("waits_on_you") else "")) if s.get("running") else \
            f"idle, finished {F.ago(s.get('idle_min', 0))}"
        mark = "  <== TARGET" if target and s["id"] == target else ""
        lines.append(f"- session {s['id']}: \"{redact(_cut(names[s['id']], 90))}\" | project {s.get('project', '')} | "
                     f"{state}{mark}")
        lines.append(f"    now: {redact(_cut(F.session_status(board, s), 320))}")
        told = RC.last_told(board, s)
        if told:
            lines.append(f"    the user last told it ({F.ago(told.get('ago_min', 0))}): \"{redact(_cut(told['you'], 200))}\"")
        if s["id"] in latest:
            said = RC.last_said(board, s)
            if said:
                lines.append(f"    its last words: \"{redact(_cut(said, 400))}\"")
        for c in board.get("cards", []):
            if c["session"] != s["id"]:
                continue
            opts = (" Options: " + " / ".join(redact(_cut(o, 60)) for o in c["options"])) if c.get("options") else ""
            lines.append(f"    open card {c['id']} ({c['kind']}: {KINDS.get(c['kind'], c['kind'])}): "
                         f"\"{redact(_cut(c.get('text', ''), 260))}\"{opts}")
    return "\n".join(lines)


def context_text(case, target=None):
    return (board_text(case, target) + "\n\nThe user's message (verbatim, between the markers):\n<<<\n"
            + redact(case["message"]) + "\n>>>")


# ------------------------------------------------------------------ the CLI call (cached)

class Budget(Exception):
    pass


def ask_llm(model, system, context, schema, sample=0, budget=None):
    """→ (answer dict, meta, cached). meta: usage, wall, api ms, cost."""
    key = json.dumps({"model": model, "system": system, "context": context, "schema": schema, "sample": sample},
                     sort_keys=True, ensure_ascii=False)
    d = hashlib.sha256(key.encode()).hexdigest()
    p = CACHE / d[:2] / f"{d}.json"
    if p.exists():
        r = json.loads(p.read_text())
        return r["answer"], r["meta"], True
    if budget is not None:
        if budget["left"] <= 0:
            raise Budget("LLM call budget exhausted")
        budget["left"] -= 1
    home = OUT / "home"
    home.mkdir(parents=True, exist_ok=True)
    args = ["claude", "-p", "--model", model, "--tools", "", "--setting-sources", "", "--strict-mcp-config",
            "--no-session-persistence", "--output-format", "json", "--json-schema", json.dumps(schema),
            "--system-prompt", system]
    answer, meta = None, {}
    for attempt in range(3):
        t0 = time.time()
        proc = subprocess.run(args, input=context, capture_output=True, text=True, cwd=home, timeout=180)
        wall = time.time() - t0
        try:
            obj = json.loads(proc.stdout)
        except ValueError:
            obj = {"is_error": True, "result": proc.stdout[-400:] + proc.stderr[-400:]}
        so = obj.get("structured_output")
        if not obj.get("is_error") and isinstance(so, dict):
            answer = so
            meta = {"usage": obj.get("usage"), "wall": wall, "api_ms": obj.get("duration_api_ms"),
                    "cost_cli": obj.get("total_cost_usd"), "attempts": attempt + 1}
            break
        err = str(obj.get("result") or "")[:300]
        meta = {"error": err, "attempts": attempt + 1}
        if "limit" in err.lower() or "rate" in err.lower():
            time.sleep(30 * (attempt + 1))
        else:
            time.sleep(2)
    if answer is None:
        raise RuntimeError("LLM call failed: " + json.dumps(meta)[:400])
    p.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=p.parent, delete=False) as f:
        json.dump({"answer": answer, "meta": meta}, f)
    os.replace(f.name, p)
    return answer, meta, False


# ------------------------------------------------------------------ decisions

def _maps(case):
    sessions = {s["id"]: s for s in case["board"]["sessions"]}
    cards = {c["id"]: c for c in case["board"]["cards"]}
    return sessions, cards


def resolve(case, action, target):
    """An LLM (action, target) → a typed action target (ACTIONS.md) the board can take, or None."""
    sessions, cards = _maps(case)
    t = (target or "").strip()
    for pre in ("session:", "card:"):
        if t.startswith(pre):
            t = t[len(pre):]
    sid = t if t in sessions else cards[t]["session"] if t in cards else None
    if action == "say":
        if not sid:
            return None
        # As the live app (actions_d3.live_action): words sent to a session holding a form answer that form.
        forms = [c for c in cards.values() if c["session"] == sid and c["kind"] in ("question", "plan")]
        return f"answer:card:{forms[0]['id']}" if forms else f"say:session:{sid}"
    if action == "answer":
        if t in cards and cards[t]["kind"] in NEEDS_YOU:
            return f"answer:card:{t}"
        if sid:
            forms = [c for c in cards.values() if c["session"] == sid and c["kind"] in NEEDS_YOU]
            return f"answer:card:{forms[-1]['id']}" if forms else f"say:session:{sid}"
        return None
    if action in ("stop", "interrupt"):
        if sid and sessions[sid].get("running") and not sessions[sid].get("waits_on_you"):
            return f"{action}:session:{sid}"
        return None
    if action == "archive":
        return f"archive:card:{t}" if t in cards else None
    if action == "start":
        f = t[4:] if t.startswith("new:") else t
        return f"start:new:{f}" if f in case["board"].get("projects", []) else None
    if action == "configure":
        return "configure"
    if action == "ask_fjord":
        return "ask_fjord"
    return None


def legacy_of(act, case):
    """A typed action → the legacy destination today's runner delivers (ACTIONS.md projection)."""
    if not act:
        return None
    head, _, rest = act.partition(":")
    if head in ("say", "stop", "interrupt") and rest.startswith("session:"):
        return "session:" + rest[8:] if head != "stop" else "change_fjord"
    if head in ("answer", "approve"):
        return "session:" + rest[5:].split("#", 1)[0]
    if head == "start":
        return rest
    if head in ("archive", "ack", "configure", "reopen", "mute", "unmute"):
        return "change_fjord"
    if head == "ask_fjord":
        return "question"
    return None


def recency_fill(case):
    ss = sorted(case["board"]["sessions"], key=lambda s: (s.get("idle_min", 0), s["id"]))
    return [f"say:session:{s['id']}" for s in ss]


def llm_decision(case, ans):
    """Act on high confidence; else ask with [target + alternatives], filled up to four by recency."""
    primary = resolve(case, ans.get("action"), ans.get("target")) if ans.get("action") != "unsure" else None
    if ans.get("action") == "unsure" and ans.get("target"):
        primary = resolve(case, "say", ans.get("target"))
    if ans.get("confidence") == "high" and ans.get("action") != "unsure" and primary:
        return {"decision": "act", "act": primary}
    opts = [primary] + [resolve(case, a.get("action"), a.get("target")) for a in ans.get("alternatives") or []
                        if a.get("action") != "unsure"]
    out = []
    for o in opts + recency_fill(case):
        if o and o not in out:
            out.append(o)
    return {"decision": "ask", "options": out[:4]}


def hybrid_decision(case, ans, T_sid, routing):
    """Jev's target, Haiku's action on it. routing: shipped's {decision, act, options}."""
    a, conf = ans.get("action"), ans.get("confidence")
    sessions, cards = _maps(case)
    if a in ("say", "answer"):
        act = resolve(case, a, ans.get("card") if a == "answer" and ans.get("card") in cards else T_sid)
    elif a in ("stop", "interrupt"):
        act = resolve(case, a, T_sid)
    elif a == "archive":
        card = ans.get("card")
        act = resolve(case, "archive", card) if card in cards and cards[card]["session"] == T_sid else None
    elif a == "mark_seen":
        card = ans.get("card")
        act = f"ack:card:{card}" if card in cards and cards[card]["session"] == T_sid and cards[card]["kind"] == "done" \
            else None
    else:
        act = None
    shipped_opts = list(routing.get("options") or [])
    t_act = routing.get("act") if routing["decision"] != "ask" else None

    def ask(first):
        out = []
        for o in first + ([t_act] if t_act else []) + shipped_opts + recency_fill(case):
            if o and o not in out:
                out.append(o)
        return {"decision": "ask", "options": out[:4]}

    if act and a in ("stop", "interrupt", "archive", "mark_seen"):
        return {"decision": "act", "act": act} if conf == "high" else ask([act])
    if act and a in ("say", "answer"):
        if routing["decision"] != "ask" and conf in ("high", "medium"):
            return {"decision": "act", "act": act}
        return ask([act])
    return ask([])


# ------------------------------------------------------------------ systems in the episode runner

def _rule_plan(state, event):
    from v2.run import rules
    return rules.plan(state, event["message"], event.get("context", {}))


class LLMSystem:
    def __init__(self, system, version, budget, sample=0):
        self.system, self.version, self.budget, self.sample = system, version, budget, sample
        self.model = MODELS[system]
        self.new_calls = 0
        self._shipped = None

    @property
    def name(self):
        return f"{self.system}-{self.version}"

    def shipped(self):
        if self._shipped is None:
            from explore import actions_d3 as D
            self._shipped = D._system_class()("shipped", 4000)
        return self._shipped

    def call(self, case, target=None):
        system = system_prompt(self.system, self.version)
        schema = schema_of(self.system, self.version)
        ans, meta, cached = ask_llm(self.model, system, context_text(case, target), schema, self.sample, self.budget)
        self.new_calls += not cached
        return ans, meta

    def decide(self, state, event):
        from v2.run import adapter
        from explore.actions_d3 import live_action
        case = adapter.to_case(state, event)
        cards = [(c["id"], c["session"], c["kind"]) for c in case["board"]["cards"]]
        planned = _rule_plan(state, event)
        if planned is not None:
            act = live_action(planned.get("target"), cards) if planned["decision"] != "ask" else None
            return {**planned, "path": "rule", "act": act}
        if self.system == "hybrid":
            res = self.shipped().decide(state, event)
            routing = res["routing"]
            T = res.get("target") if res["decision"] == "send" and (res.get("target") or "").startswith("session:") \
                else res.get("top")
            if not (T or "").startswith("session:") or T[8:] not in {s["id"] for s in case["board"]["sessions"]}:
                return {**res, "llm": None, "path": "hybrid-jev"}
            ans, meta = self.call(case, T[8:])
            d = hybrid_decision(case, ans, T[8:], routing)
            extra = {"llm": ans, "llm_meta": meta, "routing": routing, "T": T, "jev_latency": res.get("latency"),
                     "jev_tokens": res.get("tokens")}
        else:
            ans, meta = self.call(case)
            d = llm_decision(case, ans)
            extra = {"llm": ans, "llm_meta": meta}
        if d["decision"] == "act":
            return {"decision": "send", "target": legacy_of(d["act"], case), "act": d["act"], "act_options": None,
                    "ranked": [], "path": "llm", **extra}
        ranked = [legacy_of(o, case) for o in d["options"]]
        ranked = [{"target": t, "score": 0} for t in dict.fromkeys(r for r in ranked if r)]
        return {"decision": "ask", "target": None, "act": None, "act_options": d["options"], "ranked": ranked,
                "path": "llm", **extra}


def set_path(split, name):
    if split not in ("dev", "calib"):
        raise SystemExit("only dev and calib")
    return ACTIONS / split / f"{name}.jsonl"


def subset_ids(eps, n_submits=150, seed=7):
    """Random relabel_real episodes until ≥ n_submits submits (Sonnet's subset)."""
    idx = list(range(len(eps)))
    random.Random(seed).shuffle(idx)
    out, k = [], 0
    for i in idx:
        if k >= n_submits:
            break
        out.append(i)
        k += sum(ev["kind"] == "submit" for ev in eps[i]["events"])
    return sorted(out)


def _worker(args):
    path, system, version, idx, max_calls = args
    from v2.run import episodes as E
    eps = E.load_episodes(path)
    sysm = LLMSystem(system, version, {"left": max_calls})
    out = []
    for i in idx:
        r = E.play_episode(eps[i], sysm)
        r.pop("final_state", None)
        out.append(r)
    return out, sysm.new_calls


def run(system, set_name, split, version, workers, max_calls, subset):
    from v2.run import episodes as E
    path = set_path(split, set_name)
    eps = E.load_episodes(path)
    idx = subset_ids(eps) if subset and set_name == "relabel_real" else list(range(len(eps)))
    chunks = [idx[i::workers] for i in range(workers)]
    with ProcessPoolExecutor(workers) as pool:
        parts = list(pool.map(_worker, [(path, system, version, c, max_calls // workers + 1) for c in chunks]))
    results = sorted([r for p, _ in parts for r in p], key=lambda r: r["id"])
    calls = sum(c for _, c in parts)
    OUT.mkdir(parents=True, exist_ok=True)
    tag = "-sub" if subset and set_name == "relabel_real" else ""
    (OUT / f"{system}-{version}.{split}.{set_name}{tag}.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    print(f"{system}-{version} {split}/{set_name}{tag}: {len(results)} episodes, {calls} new LLM calls")


# ------------------------------------------------------------------ bench (611 real moments)

def bench(system, version, max_calls, workers, limit=None):
    """The LLM on bench.py's real moments. Every moment went to a session (gold `to`): any other action is false.
    The hybrid reads shipped's routing and target from explore/actions_d3's bench.D3-final run (same Jev answers)."""
    import bench as B
    cases = B.load_set("real")
    if limit:
        cases = random.Random(7).sample(cases, limit)
    ship = {}
    if system == "hybrid":
        for line in open(D3OUT / "bench.D3-final.jsonl"):
            r = json.loads(line)
            ship[r["id"]] = r["d3"]
    budget = {"left": max_calls}
    sysm = LLMSystem(system, version, budget)

    def one(c):
        if system == "hybrid":
            info = ship[c["id"]]
            T = info["T"]
            if not (T or "").startswith("session:"):
                return {"id": c["id"], "decision": "route", "routing": info["routing"]}
            ans, meta = sysm.call(c, T[8:])
            d = hybrid_decision(c, ans, T[8:], info["routing"])
            return {"id": c["id"], **d, "llm": ans, "llm_meta": meta, "routing": info["routing"], "T": T}
        ans, meta = sysm.call(c)
        return {"id": c["id"], **llm_decision(c, ans), "llm": ans, "llm_meta": meta}

    with ThreadPoolExecutor(workers) as pool:
        rows = list(pool.map(one, cases))
    by = {c["id"]: c for c in cases}
    for r in rows:
        c = by[r["id"]]
        r.update(message=c["message"], gold=c["gold"], half=B.half(c["id"]))
    OUT.mkdir(parents=True, exist_ok=True)
    tag = f"-n{limit}" if limit else ""
    (OUT / f"bench.{system}-{version}{tag}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"bench {system}-{version}{tag}: {len(rows)} moments, {max_calls - budget['left']} new LLM calls")


# ------------------------------------------------------------------ determinism

def repeat(system, version, n, workers):
    """Re-ask n dev submits (first submit of random episodes, all sets) with sample 1: the decision changes?"""
    from v2.run import episodes as E, adapter
    pool_ = []
    for name in SETS:
        for e in E.load_episodes(set_path("dev", name)):
            ev = next((x for x in e["events"] if x["kind"] == "submit"), None)
            if ev and _rule_plan(e["state"], ev) is None:
                pool_.append((name, e, ev))
    pick = random.Random(11).sample(pool_, n)
    budget = {"left": 2 * n + 10}
    a, b = LLMSystem(system, version, budget, 0), LLMSystem(system, version, budget, 1)

    def one(x):
        name, e, ev = x
        st = json.loads(json.dumps(e["state"]))
        da, db = a.decide(st, ev), b.decide(json.loads(json.dumps(e["state"])), ev)
        key = lambda d: (d["decision"], d.get("act"), tuple(d.get("act_options") or []))
        return {"set": name, "id": e["id"], "message": ev["message"][:60], "a": key(da), "b": key(db),
                "llm_a": da.get("llm"), "llm_b": db.get("llm")}

    with ThreadPoolExecutor(workers) as pool:
        rows = list(pool.map(one, pick))
    (OUT / f"repeat.{system}-{version}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"repeat {system}-{version}: {len(rows)} submits, {2 * n + 10 - budget['left']} new calls")


def probe():
    ans, meta, cached = ask_llm("claude-haiku-5-5", SYSTEM_V1,
                                "Projects: demo\n\nSessions:\n- session abc123: \"CI fix\" | project demo | RUNNING\n\n"
                                "The user's message:\n<<<\nstop the CI one\n>>>", SCHEMA)
    print(json.dumps({"answer": ans, "meta": meta, "cached": cached}, indent=1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["run", "bench", "repeat", "probe"])
    ap.add_argument("system", nargs="?", choices=list(MODELS))
    ap.add_argument("set", nargs="?")
    ap.add_argument("--split", default="dev")
    ap.add_argument("--prompt", default="v1", choices=["v1", "v2"])
    ap.add_argument("--subset", action="store_true")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-calls", type=int, default=800)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--n", type=int, default=100)
    a = ap.parse_args()
    if a.mode == "probe":
        probe()
    elif a.mode == "run":
        run(a.system, a.set, a.split, a.prompt, a.workers, a.max_calls, a.subset)
    elif a.mode == "bench":
        bench(a.system, a.prompt, a.max_calls, a.workers, a.limit)
    else:
        repeat(a.system, a.prompt, a.n, a.workers)


if __name__ == "__main__":
    main()
