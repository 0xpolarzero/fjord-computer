"""Real moments on real boards (Router benchmark v2): every message you typed into one of your Claude Code sessions, with the
board exactly as Lookout would have shown it at that instant, in the v2 schema's `state` shape (BENCHMARK.md §Schema).

    python3 v2/build/states.py [--no-jev] [--limit N]  →  v2/data/states/moments.jsonl
    python3 v2/build/validate_states.py                 (counts, distributions, a sample, no keys)

Beyond the schema: a session row also has `waits_on_you` (stopped on a form), `background` (tasks it left running),
`finished_min`; a turn card has `triage` (state, urgency, work, waitingOn, questions), a question card `questions`.
Each record: id, group (session-day), at, project, message, went_to (short session id or new:<project>), flags
(transition same/switch/new and prev_to, recency_rank among the offered sessions not running by last finish,
running_target, queued, absorbed, after_interrupt, form_answer, first, target_offered, target_card, sent_at), state.

What it reconstructs from the transcripts (~/.claude/projects/*/*.jsonl), and how:
- sessions: the Claude app's sessions (entrypoint claude-desktop: Lookout reads the app's sessions, not the CLI's); a fork
  or resume owns only the records it added (records are deduplicated by uuid across files, oldest file first);
- titles as of the moment: the transcript's custom-title records in file order (timed by the record before them);
  before the first one, that first title (Claude names a session from its first prompt within seconds);
- turns: a turn starts at a prompt (your message, a peer/subagent hand-back, a task notification) and ends at its last
  assistant record with an end reason (end_turn, stop_sequence, refusal), or at an interrupt; a session is running in
  between, except while it is stopped on an AskUserQuestion or ExitPlanMode call (waiting on you, its turn still open);
- running moments: messages you typed while the session worked, from `queue-operation` enqueues (dequeued once the turn
  ended: the moment is the enqueue) and `queued_command` attachments (absorbed mid-turn), gold = that running session;
- cards (Router.swift): a finished turn makes a card (`<sid>#t<turns>`) once no background task it started is left,
  its kind from Lookout's triage (triage.py, Jev, cached), text the final message's last paragraph (the app's one-line
  summary isn't in the transcripts); an AskUserQuestion / ExitPlanMode call makes a `question` / `plan` card
  (`<sid>#w<ms>`, options from the tool input) until answered; cards are addressed by your next message to the session
  and superseded by a newer card of the same session;
- the window (RouterRoute.destinations + RouterMCP.candidates): working sessions plus the 20 most recent others across all
  projects, up to 80; open cards of sessions not offered come along (those made in the last 24 h); projects = every
  known folder (Store.knownFolders: the folders of the app's sessions so far; scratch chats have none);
- per session `turns`: the redacted turns before the moment as RouterLexical.turns reads them (your typed messages, the
  session's last text after each), at most the last 8, said empty while running;
- history: your messages to each offered session before the moment (the last 3 per session in 24 h).

Moments: messages in the projects of real/boards.py KEEP, typed by you (origin human), without agent-written first messages
(handoffs, compaction continuations), CI monitor events, slash commands, or probe sessions; plus answers you gave to
AskUserQuestion forms (flagged form_answer). Everything written is redacted (real/boards.py `redact`)."""
import argparse
import bisect
import collections
import glob
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path.insert(0, str(ROUTER / "real"))
sys.path.insert(0, str(HERE))
from boards import KEEP, redact  # noqa: E402
import triage as T  # noqa: E402

ROOT = os.path.expanduser("~/.claude/projects")
OUT = ROUTER / "v2" / "data" / "states"
TZ = ZoneInfo("Europe/Paris")

END_REASONS = {"end_turn", "stop_sequence", "refusal"}
NOT_TYPED = re.compile(r"^\s*(<(command-|local-command|system-reminder|bash-|task-notification|user-prompt-submit)|Caveat:|\[Request interrupted)")
INTERRUPT = re.compile(r"^\s*\[Request interrupted")
AGENT_FIRST = re.compile(r"^\s*(Background \(from the session that started this one\)|This session is being continued from a previous conversation)")
CI_EVENT = re.compile(r"^\s*<ci-monitor-event")
PROBE_FIRST = re.compile(r"^\s*(Bounded probe|Call the mcp__|Reply with exactly|Say exactly|Respond with exactly)", re.I)
BG_ID = re.compile(r"agentId: ([A-Za-z0-9]+)|running in background with ID: ([A-Za-z0-9]+)|moved to the background \(ID: ([A-Za-z0-9]+)\)")
TASK_ID = re.compile(r"<task-id>([A-Za-z0-9]+)</task-id>")
PEER_FROM = re.compile(r'<agent-message from="([A-Za-z0-9]+)"')
WINDOW_RECENT = 20
MAX_SESSIONS = 80
TURNS_KEPT = 8
OFFLIST_CARD_H = 24
HISTORY_PER_SESSION = 3
BG_MAX_H = 2


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")


def project_of(cwd):
    """The folder Lookout knows a session by (worktrees collapse onto the repository), by name; scratch chats have none."""
    if "Application Support/Claude/scratch-workspaces" in cwd:
        return "scratch"
    m = re.search(r"/\.claude/worktrees/", cwd)
    base = cwd[:m.start()] if m else cwd
    return os.path.basename(base.rstrip("/")) or base


def last_paragraph(text, limit=400):
    paras = [p.strip() for p in re.split(r"\n\s*\n", text or "") if p.strip()]
    return (paras[-1] if paras else "")[:limit]


def one_line(text, limit):
    s = " ".join((text or "").split())
    return s if len(s) <= limit else s[:limit - 1] + "…"


# ---------------------------------------------------------------- Claude.describe(tool:input:) (the working line)

def describe(name, inp):
    inp = inp or {}

    def file(key="file_path"):
        v = inp.get(key)
        return os.path.basename(v) if isinstance(v, str) and v else "a file"

    def short(s, n=48):
        line = (s or "").split("\n")[0]
        return line if len(line) <= n else line[:n - 1] + "…"

    if name == "Bash":
        d = inp.get("description")
        return short(d) if d else "Running " + short(inp.get("command") or "a command", 36)
    if name in ("Edit", "MultiEdit", "NotebookEdit"):
        return "Editing " + file("notebook_path" if name == "NotebookEdit" else "file_path")
    if name == "Write":
        return "Writing " + file()
    if name == "Read":
        return "Reading " + file()
    if name in ("Grep", "Glob"):
        return "Searching" + (" for " + short(inp["pattern"], 28) if isinstance(inp.get("pattern"), str) else "")
    if name in ("Agent", "Task"):
        return "Delegating" + (": " + short(inp["description"], 36) if isinstance(inp.get("description"), str) else "")
    if name == "WebSearch":
        return "Searching the web"
    if name == "WebFetch":
        m = re.match(r"https?://([^/]+)", inp.get("url") or "")
        return "Reading " + (m.group(1) if m else "a web page")
    if name == "TodoWrite":
        return "Planning"
    if name == "AskUserQuestion":
        qs = inp.get("questions") or []
        first = qs[0].get("question") if qs and isinstance(qs[0], dict) else None
        return short(first, 120) if first else "Asking you a question"
    if name == "ExitPlanMode":
        for line in (inp.get("plan") or "").split("\n"):
            t = line.strip("#* \t")
            if t:
                return "Approve the plan: " + short(t, 96)
        return "Waiting for you to approve a plan"
    if name == "Skill":
        return "Using " + (inp.get("skill") or "a skill")
    if name.startswith("mcp__"):
        parts = [p for p in name.split("_") if p]
        server = parts[1] if len(parts) > 1 else "a tool"
        return "Using " + ("a connector" if len(server) > 20 else server)
    return "Using " + name if name else "Working"


# ---------------------------------------------------------------- reading a transcript (compact events, file order)

def _text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def read_file(path):
    """Compact events of one transcript, in file order."""
    ev, cwd, entry, last_t = [], None, None, None
    for line in open(path, errors="replace"):
        if '"type":"attachment"' in line and "queued_command" not in line:
            continue
        if '"file-history' in line or '"type":"last-prompt"' in line or '"type":"atis-latch"' in line or '"agent-name"' in line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = r.get("type")
        cwd = cwd or r.get("cwd")
        entry = entry or r.get("entrypoint")
        if r.get("timestamp"):
            try:
                last_t = ts(r["timestamp"])
            except ValueError:
                pass
        if t == "custom-title" and r.get("customTitle"):
            ev.append({"e": "title", "t": last_t, "title": r["customTitle"]})
        elif t == "ai-title" and r.get("aiTitle"):
            ev.append({"e": "title", "t": last_t, "title": r["aiTitle"], "ai": True})
        elif t == "queue-operation":
            ev.append({"e": "qop", "t": last_t, "op": r.get("operation"), "content": r.get("content"), "reason": r.get("reason")})
        elif t == "attachment":
            a = r.get("attachment") or {}
            if a.get("type") == "queued_command" and not r.get("isSidechain"):
                ev.append({"e": "qc", "t": last_t, "uuid": r.get("uuid"), "origin": (a.get("origin") or {}).get("kind"),
                           "prompt": a.get("prompt") if isinstance(a.get("prompt"), str) else _text_of(a.get("prompt"))})
        elif t == "system":
            ev.append({"e": "sys", "t": last_t, "uuid": r.get("uuid"), "sub": r.get("subtype")})
        elif t in ("user", "assistant") and not r.get("isSidechain"):
            content = (r.get("message") or {}).get("content")
            if t == "user":
                results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"] if isinstance(content, list) else []
                e = {"e": "user", "t": last_t, "uuid": r.get("uuid"), "meta": bool(r.get("isMeta")),
                     "origin": (r.get("origin") or {}).get("kind"), "results": []}
                if results:
                    for b in results:
                        c = b.get("content")
                        c = c if isinstance(c, str) else _text_of(c)
                        e["results"].append({"id": b.get("tool_use_id"), "text": (c or "")[:4000], "is_error": bool(b.get("is_error"))})
                    tur = r.get("toolUseResult")
                    if isinstance(tur, dict) and "answers" in tur:
                        e["answers"] = tur.get("answers")
                else:
                    e["text"] = _text_of(content).strip()
                ev.append(e)
            else:
                msg = r.get("message") or {}
                blocks = content if isinstance(content, list) else []
                tools = []
                for b in blocks:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        name, inp = b.get("name", ""), b.get("input") or {}
                        keep = inp if name in ("AskUserQuestion", "ExitPlanMode") else None
                        tools.append({"id": b.get("id"), "name": name, "desc": describe(name, inp), "input": keep})
                ev.append({"e": "asst", "t": last_t, "uuid": r.get("uuid"), "text": _text_of(blocks).strip(), "tools": tools,
                           "stop": msg.get("stop_reason"), "thinking": any(isinstance(b, dict) and b.get("type") == "thinking" for b in blocks)})
    return {"id": pathlib.Path(path).stem, "cwd": cwd, "entry": entry, "events": ev}


def load_files():
    files = []
    for path in glob.glob(f"{ROOT}/*/*.jsonl"):
        f = read_file(path)
        times = [e["t"] for e in f["events"] if e.get("t") is not None]
        if not times or not f["cwd"]:
            continue
        f["t0"] = min(times)
        files.append(f)
    files.sort(key=lambda f: f["t0"])
    # A session moved to another folder (a worktree) is in two files under the same id: one session, in order.
    merged = {}
    for f in files:
        if f["id"] in merged:
            merged[f["id"]]["events"] += f["events"]
        else:
            merged[f["id"]] = f
    files = list(merged.values())
    owner, out = {}, []
    for f in files:
        own, copied = [], 0
        for e in f["events"]:
            u = e.get("uuid")
            if u and u in owner:
                copied += owner[u] != f["id"]
                continue
            if u:
                owner[u] = f["id"]
            own.append(e)
        f["events"], f["copied"] = own, copied
        out.append(f)
    return out


# ---------------------------------------------------------------- a session's timeline

class Session:
    def __init__(self, f):
        self.id, self.short, self.cwd, self.entry = f["id"], f["id"][:8], f["cwd"], f["entry"]
        self.project = project_of(f["cwd"])
        self.fork = f["copied"] > 0
        ev = [e for e in f["events"] if e.get("t") is not None]
        self.titles = [(e["t"], e["title"]) for e in f["events"] if e["e"] == "title" and e.get("t") is not None and not e.get("ai")]
        if not self.titles:
            self.titles = [(e["t"], e["title"]) for e in f["events"] if e["e"] == "title" and e.get("t") is not None]
        self.prompts, self.human, self.turns, self.forms, self.absorbed = [], [], [], [], []
        self._build(ev)
        starts = [p["t"] for p in self.prompts]
        self.start = min(starts) if starts else None

    # prompts: what starts a turn
    def _build(self, ev):
        enqueues = []          # (t, content) of enqueues, for the typed time of messages dequeued later
        segs, cur = [], None
        bg_launch, bg_done = {}, {}
        for i, e in enumerate(ev):
            k = e["e"]
            if k == "qop" and e["op"] == "enqueue" and isinstance(e.get("content"), str):
                enqueues.append((e["t"], e["content"]))
            if k == "qc":
                for m in TASK_ID.finditer(e.get("prompt") or ""):
                    bg_done.setdefault(m.group(1), e["t"])
                for m in PEER_FROM.finditer(e.get("prompt") or ""):
                    bg_done.setdefault(m.group(1), e["t"])
                if e.get("origin") == "human":
                    self.absorbed.append({"t": e["t"], "text": (e.get("prompt") or "").strip()})
                continue
            if k == "user" and not e["results"]:
                text = e.get("text") or ""
                origin = e.get("origin")
                for m in TASK_ID.finditer(text):
                    bg_done.setdefault(m.group(1), e["t"])
                for m in PEER_FROM.finditer(text):
                    bg_done.setdefault(m.group(1), e["t"])
                if INTERRUPT.match(text):
                    if cur is not None:
                        cur["interrupt"] = e["t"]
                    continue
                if origin == "human" or (origin is None and not e["meta"]):
                    if not text or (NOT_TYPED.match(text) and not text.lstrip().startswith("<task-notification")):
                        continue
                    kind = "agent" if text.lstrip().startswith("<task-notification") else "human"
                elif origin in ("peer", "task-notification", "plugin"):
                    kind = "agent"
                else:
                    continue
                p = {"t": e["t"], "kind": kind, "text": text, "i": i}
                if kind == "human":
                    # Typed while the session ran: its enqueue, well before the record, holds the moment you typed it.
                    typed = e["t"]
                    for qt, qc in reversed(enqueues):
                        if qt > e["t"]:
                            continue
                        if e["t"] - qt > 6 * 3600:
                            break
                        if qc.strip() == text or (len(qc) > 40 and text.startswith(qc.strip()[:40])):
                            typed = qt
                            break
                    p["typed"] = typed
                self.prompts.append(p)
                # Prompts delivered together (a hand-back and its task notification, two quick messages): one turn.
                if (cur is not None and not any(x["e"] == "asst" for x in cur["events"]) and cur.get("interrupt") is None
                        and e["t"] - cur["start"] < 60):
                    continue
                cur = {"prompt": len(self.prompts) - 1, "start": e["t"], "events": []}
                segs.append(cur)
                continue
            if cur is None:
                continue
            cur["events"].append(e)
            if k == "user":
                for r in e["results"]:
                    m = BG_ID.search(r["text"][:600])
                    if m:
                        bg_launch[next(g for g in m.groups() if g)] = e["t"]
        self.bg_launch, self.bg_done = bg_launch, bg_done
        pending_forms = {}
        for s in segs:
            evs = s["events"]
            ends = [e["t"] for e in evs if e["e"] == "asst" and e.get("stop") in END_REASONS]
            assts = [e["t"] for e in evs if e["e"] == "asst"]
            interrupted = s.get("interrupt") is not None and (not ends or s["interrupt"] > ends[-1])
            if interrupted:
                end = s["interrupt"]
            elif ends:
                end = ends[-1]
            elif assts:
                end = assts[-1]
            else:
                end = s["start"]
            end = max(end, s["start"])
            # The working line over time, and forms.
            acts = []
            for e in evs:
                if e["e"] == "asst":
                    if e["tools"]:
                        acts.append((e["t"], e["tools"][-1]["desc"]))
                        for tool in e["tools"]:
                            if tool["name"] in ("AskUserQuestion", "ExitPlanMode"):
                                pending_forms[tool["id"]] = {"ta": e["t"], "name": tool["name"], "input": tool["input"] or {},
                                                             "tool_id": tool["id"]}
                    elif e["text"]:
                        acts.append((e["t"], "Writing"))
                    else:
                        acts.append((e["t"], "Thinking"))
                elif e["e"] == "user":
                    acts.append((e["t"], "Thinking"))
                    for r in e["results"]:
                        if r["id"] in pending_forms:
                            fm = pending_forms.pop(r["id"])
                            fm["tb"] = e["t"]
                            fm["result"] = r["text"]
                            fm["answers"] = e.get("answers")
                            fm["error"] = (r["is_error"] or r["text"].startswith("Error")
                                           or "Tool permission request failed" in r["text"][:200])
                            self.forms.append(fm)
            # Lookout's final message (Claude.finalMessage): the texts after the turn's last step.
            texts = []
            for e in reversed(evs):
                if e["e"] == "user":
                    break
                if e["e"] != "asst":
                    continue
                if e["tools"]:
                    break
                if e["text"]:
                    texts.append(e["text"])
            final = "\n\n".join(reversed(texts)).strip()[-12000:] or None
            texts_t = [(e["t"], e["text"]) for e in evs if e["e"] == "asst" and e["text"]]
            launched = [k for k, t in self.bg_launch.items() if s["start"] <= t <= end]
            self.turns.append({"start": s["start"], "end": end, "prompt": s["prompt"], "final": final, "acts": acts,
                               "texts": texts_t, "launched": launched, "interrupted": interrupted})
        for fm in pending_forms.values():           # never answered (the session was left on it)
            fm["tb"] = float("inf")
            fm["result"], fm["answers"], fm["error"] = "", None, False
            self.forms.append(fm)
        self.forms.sort(key=lambda f: f["ta"])
        # Each turn's card: made once the turn ended with no background task it knows of still out.
        for k, turn in enumerate(self.turns):
            out = [b for b, t in self.bg_launch.items()
                   if t <= turn["end"] and self.bg_done.get(b, float("inf")) > turn["end"] and turn["end"] - t < BG_MAX_H * 3600]
            turn["carded"] = not out
            turn["n"] = k + 1                         # completedTurns once it ended
        self.turn_starts = [t["start"] for t in self.turns]
        self.turn_ends = sorted(t["end"] for t in self.turns)
        self.human = [p for p in self.prompts if p["kind"] == "human"]
        self.human_t = [p["t"] for p in self.human]
        # Queued: typed (enqueued) while a turn ran, delivered once it ended.
        for p in self.human:
            if p["typed"] < p["t"] - 0.5 and self.turn_at(p["typed"]) is not None:
                p["queued"] = True
            else:
                p["queued"], p["typed"] = False, min(p["typed"], p["t"])
        # What RouterLexical reads after each of your messages: the session's texts until your next one.
        self.human_texts = []
        for n, p in enumerate(self.human):
            nxt = self.human[n + 1]["t"] if n + 1 < len(self.human) else float("inf")
            self.human_texts.append([(t, text) for turn in self.turns if p["t"] - 1e-6 <= turn["start"] < nxt
                                     for t, text in turn["texts"] if t < nxt])

    # ---- as of a moment

    def title_at(self, now):
        best = None
        for t, title in self.titles:
            if t <= now:
                best = title
        if best is None and self.titles:
            best = self.titles[0][1]
        if best is None:
            best = (self.human[0]["text"] if self.human else (self.prompts[0]["text"] if self.prompts else "Untitled"))[:60]
        return best

    def turn_at(self, now):
        """The turn running at `now` (strictly inside), or None."""
        i = bisect.bisect_left(self.turn_starts, now) - 1
        if i >= 0 and self.turns[i]["end"] > now:
            return self.turns[i]
        return None

    def form_at(self, now):
        for f in self.forms:
            if f["ta"] < now < f["tb"]:
                return f
        return None

    def finished(self, now):
        """Turns ended before now, in order."""
        return [t for t in self.turns if t["end"] < now and t["start"] < now]

    def last_activity(self, now):
        cands = [t["end"] for t in self.turns if t["end"] < now]
        i = bisect.bisect_left(self.human_t, now) - 1
        if i >= 0:
            cands.append(self.human_t[i])
        j = bisect.bisect_left(self.turn_starts, now) - 1
        if j >= 0:
            cands.append(self.turn_starts[j])
        return max(cands) if cands else None

    def last_finish(self, now):
        i = bisect.bisect_left(self.turn_ends, now) - 1
        return self.turn_ends[i] if i >= 0 else None

    def lexical_turns(self, now, working):
        """RouterLexical.turns: per message you typed, the session's last text after it (before now)."""
        k = bisect.bisect_left(self.human_t, now)
        out = []
        for n in range(max(0, k - TURNS_KEPT), k):
            said = ""
            for t, text in self.human_texts[n]:
                if t < now:
                    said = text
            out.append([self.human[n]["text"], said])
        if working and out:
            out[-1][1] = ""
        return [[redact(you)[:400], redact(said)[:800]] for you, said in out]


# ---------------------------------------------------------------- cards (Router.swift RouterFeed, simplified)

def cards_of(s):
    """Every card the session ever made: (created, addressed, card) with addressed = your next message to it, its
    answer (forms), or a newer card of the session (superseded)."""
    out = []
    replies = [p["typed"] for p in s.human] + [a["t"] for a in s.absorbed]
    replies.sort()

    def next_reply(after):
        i = bisect.bisect_right(replies, after)
        return replies[i] if i < len(replies) else float("inf")

    for turn in s.turns:
        if not turn["carded"]:
            continue
        out.append({"created": turn["end"], "addressed": next_reply(turn["end"]), "turn": turn,
                    "id": f"{s.short}#t{turn['n']}", "kind": None})
    for fm in s.forms:
        kind = "question" if fm["name"] == "AskUserQuestion" else "plan"
        out.append({"created": fm["ta"], "addressed": min(fm["tb"], next_reply(fm["ta"])), "form": fm,
                    "id": f"{s.short}#w{int(fm['ta'] * 1000)}", "kind": kind})
    out.sort(key=lambda c: c["created"])
    for a, b in zip(out, out[1:]):
        a["addressed"] = min(a["addressed"], b["created"])
    return out


def form_options(fm):
    opts = []
    for q in (fm["input"].get("questions") or []):
        for o in (q.get("options") or []) if isinstance(q, dict) else []:
            label = o.get("label") if isinstance(o, dict) else o
            if label:
                opts.append(redact(one_line(str(label), 60)))
    return opts


def form_answer_text(fm):
    """What you answered on a form: the values you picked or typed."""
    ans = fm.get("answers")
    if isinstance(ans, dict) and ans:
        return "\n".join(str(v) for v in ans.values() if v)
    vals = re.findall(r'"[^"]*"="([^"]*)"', fm.get("result") or "")
    return "\n".join(vals)


# ---------------------------------------------------------------- moments

def moments_of(s):
    """Your typed messages in a session: (typed_at, text, flags)."""
    out = []
    for n, p in enumerate(s.human):
        text = p["text"]
        if CI_EVENT.match(text):
            continue
        first = s.prompts and s.prompts[0] is p
        if AGENT_FIRST.match(text):               # a handoff or a compaction's continuation: written by an agent
            continue
        out.append({"t": p["typed"], "sent": p["t"], "text": text, "first": bool(first), "queued": p["queued"],
                    "absorbed": False, "form_answer": False})
    for a in s.absorbed:
        if a["text"] and not NOT_TYPED.match(a["text"]):
            out.append({"t": a["t"], "sent": a["t"], "text": a["text"], "first": False, "queued": True, "absorbed": True,
                        "form_answer": False})
    for fm in s.forms:
        if fm["name"] != "AskUserQuestion" or fm["tb"] == float("inf") or fm["error"]:
            continue
        text = form_answer_text(fm)
        if text:
            out.append({"t": fm["tb"], "sent": fm["tb"], "text": text, "first": False, "queued": False, "absorbed": False,
                        "form_answer": True, "form": fm})
    out.sort(key=lambda m: m["t"])
    return out


def automated(s):
    """Probe or scripted sessions: their messages aren't yours to route."""
    if not s.human:
        return True
    first = s.human[0]["text"]
    return bool(PROBE_FIRST.match(first)) and len(s.human) <= 2


def board(sessions, cards, now, exclude=None):
    """The state Lookout would have shown at `now` (sessions as of just before it)."""
    live = []
    for s in sessions:
        if s.start is None or s.start >= now or s is exclude:
            continue
        la = s.last_activity(now)
        if la is None:
            continue
        turn = s.turn_at(now)
        form = s.form_at(now) if turn else None
        live.append((s, la, turn, form))
    working = sorted([x for x in live if x[2] is not None], key=lambda x: -x[1])
    others = sorted([x for x in live if x[2] is None], key=lambda x: -x[1])[:WINDOW_RECENT]
    shown = (working + others)[:MAX_SESSIONS]
    offered = {x[0].short for x in shown}
    projects = sorted({s.project for s in sessions if s.start is not None and s.start < now and s.project != "scratch"})
    rows, open_cards, history, facts = [], [], [], {}
    for s, la, turn, form in shown:
        running = turn is not None and form is None
        title = redact(s.title_at(now))
        mine = [c for c in cards[s.id] if c["created"] < now < c["addressed"]]
        last_final = None
        for tr in reversed(s.turns[:bisect.bisect_left(s.turn_starts, now)]):
            if tr["end"] < now and tr["final"]:
                last_final = tr["final"]
                break
        summary = redact(last_paragraph(last_final, 300)) if last_final else ""
        if running:
            acts = [a for t, a in turn["acts"] if t < now]
            activity = acts[-1] if acts else "Thinking"
        elif form is not None:
            activity = describe(form["name"], form["input"])
        else:
            activity = ""
        lf = s.last_finish(now)
        background = sum(1 for b, t in s.bg_launch.items()
                         if t < now and s.bg_done.get(b, float("inf")) > now and now - t < BG_MAX_H * 3600)
        rows.append({"id": s.short, "title": one_line(title, 120), "project": s.project, "running": running,
                     "waits_on_you": form is not None, "background": background, "activity": redact(activity), "summary": summary,
                     "idle_min": round(max(0.0, now - la) / 60, 1),
                     "finished_min": None if lf is None else round((now - lf) / 60, 1),
                     "archived": False, "turns": s.lexical_turns(now, running)})
        facts[s.short] = {"running": running, "last_finish": lf, "la": la}
        open_cards += [(s, c) for c in mine]
        told = [p for p in s.human if p["typed"] < now and now - p["typed"] < 24 * 3600][-HISTORY_PER_SESSION:]
        history += [{"ago_min": round((now - p["typed"]) / 60, 1), "you": redact(p["text"])[:300], "to": s.short, "_t": p["typed"]}
                    for p in told]
    for s in sessions:
        if s.short in offered or s is exclude or s.start is None or s.start >= now:
            continue
        for c in cards[s.id]:
            if c["created"] < now < c["addressed"] and now - c["created"] < OFFLIST_CARD_H * 3600:
                open_cards.append((s, c))
    history.sort(key=lambda h: h["_t"])
    for h in history:
        del h["_t"]
    return {"now": iso(now), "projects": projects, "sessions": rows, "history": history}, open_cards, facts


def card_json(s, c, now, triaged):
    out = {"id": c["id"], "session": s.short, "kind": c["kind"], "text": "", "options": [],
           "created_min_ago": round((now - c["created"]) / 60, 1)}
    if "form" in c:
        fm = c["form"]
        out["text"] = redact(describe(fm["name"], fm["input"]))
        if fm["name"] == "AskUserQuestion":
            qs = [q.get("question", "") for q in (fm["input"].get("questions") or []) if isinstance(q, dict)]
            out["questions"] = [redact(one_line(q, 300)) for q in qs]
        out["options"] = form_options(fm)
    else:
        turn = c["turn"]
        out["text"] = redact(last_paragraph(turn["final"])) if turn["final"] else "Finished its turn"
        t = triaged.get(c["id"])
        out["kind"] = t["kind"] if t else "done"
        out["triage"] = None if not t else {"state": t["state"], "urgency": t["urgency"], "work": t["work"],
                                            "waitingOn": t["waitingOn"], "questions": [redact(q)[:300] for q in t["questions"][:4]]}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-jev", action="store_true", help="skip the triage calls (turn cards stay `done`)")
    ap.add_argument("--limit", type=int, default=0, help="only the first N moments (debugging)")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    files = load_files()
    sessions = [Session(f) for f in files if f["entry"] == "claude-desktop"]
    sessions = [s for s in sessions if s.start is not None]
    shorts = collections.Counter(s.short for s in sessions)
    assert max(shorts.values()) == 1, "short ids collide"
    cards = {s.id: cards_of(s) for s in sessions}
    by_id = {s.short: s for s in sessions}
    print(len(files), "transcripts,", len(sessions), "app sessions,", sum(len(s.turns) for s in sessions), "turns")

    # The moments, in time order.
    raw = []
    dropped = collections.Counter()
    for s in sessions:
        if s.project not in KEEP:
            continue
        if automated(s):
            dropped["automated session"] += len(s.human)
            continue
        for m in moments_of(s):
            if s.fork and m["first"]:
                dropped["fork's first message"] += 1
                continue
            raw.append((m["t"], s, m))
    raw.sort(key=lambda x: x[0])
    if a.limit:
        raw = raw[:a.limit]
    print(len(raw), "moments; dropped", dict(dropped))

    # Boards (without the turn cards' kinds), and the turn cards they show.
    built, need = [], {}
    for t, s, m in raw:
        # The board just before the message (the card it answers is still open). Typed within a minute of interrupting
        # the same session: you decided while it worked, so the board is the one just before the interrupt.
        now = t - 1e-3
        m["after_interrupt"] = False
        if not m["first"] and not m["queued"]:
            prev_turn = next((tr for tr in reversed(s.turns) if tr["end"] < t and tr["start"] < t), None)
            if prev_turn is not None and prev_turn["interrupted"] and t - prev_turn["end"] < 60:
                m["after_interrupt"] = True
                now = prev_turn["end"] - 1e-3
        m["board_t"] = now
        exclude = s if m["first"] else None
        st, open_cards, facts = board(sessions, cards, now, exclude=exclude)
        for sess, c in open_cards:
            if "turn" in c and c["turn"]["final"]:
                need[c["id"]] = (sess, c)
        built.append((t, s, m, st, open_cards, facts))

    triaged = {}
    if not a.no_jev and need:
        ids = sorted(need)
        items = []
        for cid in ids:
            sess, c = need[cid]
            items.append((redact(c["turn"]["final"]), redact(sess.title_at(c["created"])), sess.project))
        print("triage:", len(items), "turn cards")
        res = T.triage_many(items)
        failed = 0
        for cid, r in zip(ids, res):
            if r is None:
                failed += 1
            else:
                triaged[cid] = r
        print("triage failed:", failed)

    # Write.
    stats = collections.Counter()
    prev = None
    n_by_session = collections.Counter()
    with open(OUT / "moments.jsonl", "w") as out:
        for t, s, m, st, open_cards, facts in built:
            now = m["board_t"]
            st["cards"] = [card_json(sess, c, now, triaged) for sess, c in sorted(open_cards, key=lambda x: x[1]["created"])]
            went_to = f"new:{s.project}" if m["first"] else s.short
            running_target = (not m["first"]) and facts.get(s.short, {}).get("running", False)
            # Recency rank: among the offered sessions not running, by when each last finished (1 = most recent).
            idle = sorted([k for k, f in facts.items() if not f["running"] and f["last_finish"] is not None],
                          key=lambda k: -facts[k]["last_finish"])
            rank = idle.index(s.short) + 1 if (not m["first"] and s.short in idle) else None
            # A new session is offered per known folder (scratch chats have none); a session when listed or carded.
            offered = (s.project in st["projects"]) if m["first"] else (
                s.short in facts or any(c["session"] == s.short for c in st["cards"]))
            transition = "new" if m["first"] else ("same" if prev == s.short else ("switch" if prev else None))
            local = datetime.fromtimestamp(t, TZ)
            n_by_session[s.short] += 1
            rec = {"id": f"rm-{s.short}-{n_by_session[s.short]}", "group": f"{s.short}:{local.date().isoformat()}",
                   "at": iso(t), "project": s.project, "message": redact(m["text"]).strip(), "went_to": went_to,
                   "flags": {"transition": transition, "prev_to": prev, "recency_rank": rank,
                             "running_target": bool(running_target), "queued": m["queued"], "absorbed": m["absorbed"],
                             "after_interrupt": m["after_interrupt"], "form_answer": m["form_answer"], "first": m["first"],
                             "target_offered": bool(offered),
                             "target_card": [c["kind"] for c in st["cards"] if c["session"] == s.short],
                             "sent_at": iso(m["sent"])},
                   "state": st}
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            prev = s.short
    print("wrote", len(built), "moments to", OUT / "moments.jsonl")


if __name__ == "__main__":
    main()
