"""Real moments as routing cases: for each message you typed in a session, the board as Lookout would have shown it then
(the sessions active in the hours before, each as it stood at that moment), and where it went: that session, or, for a
session's first message, a new session in its project.

python3 real/boards.py [--per-project N] [--seed S]  →  real/data/real.jsonl"""
import argparse
import bisect
import json
import pathlib
import random
import re
from datetime import datetime

HERE = pathlib.Path(__file__).parent
KEEP = {"microsandbox-workspaces", "lookout", "lcu", "scratch", "msb-upstream", "amont", "sic", "vesper-ascent",
        "ai_academic_onboarding_claude"}
WINDOW_H = 8
MAX_SESSIONS = 25
QUESTION = re.compile(r"\?\s*(\*\*)?\s*$|\b(want me to|should i|shall i|do you want|which one|would you like)\b", re.I)


SECRET = re.compile(
    r"(sk-[A-Za-z0-9_-]{16,}|sk_(live|test)_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}"
    r"|(?i:(api[_-]?key|token|secret|password|passwd|bearer)\s*[:=]\s*\S{8,}))")


# Any long run of letters and digits (a key with no known prefix, like a z.ai `<32 hex>.<16>` key the first pattern
# missed and sent to TypeSafe; commit hashes go too, at little cost to routing).
LONG_TOKEN = re.compile(r"\b(?=[A-Za-z0-9._\-]*\d)(?=[A-Za-z0-9._\-]*[A-Za-z])[A-Za-z0-9._\-]{28,}\b")


# Account, card and routing numbers and IBANs (a pasted invoice put a bank account in a final message that stage A's
# triage sent to Jev before this). Long run ids go too.
NUMBERS = re.compile(r"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b|\b\d{9,}\b|\b\d{4}(?:[ -]\d{3,4}){2,4}\b")


def redact(text):
    """Keys, tokens and account numbers out of anything that may go to Jev: your transcripts can hold them."""
    return NUMBERS.sub("[redacted]", LONG_TOKEN.sub("[redacted]", SECRET.sub("[redacted]", text or "")))


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def last_paragraph(text, limit=300):
    paras = [p.strip() for p in re.split(r"\n\s*\n", text or "") if p.strip()]
    return (paras[-1] if paras else "")[:limit]


def load():
    sessions = []
    for line in open(HERE / "data" / "corpus.jsonl"):
        s = json.loads(line)
        if s["project"] not in KEEP:
            continue
        s["title"] = redact(s["title"])
        for t in s["turns"]:
            t["t0"], t["t1"] = ts(t["at"]), ts(t["end"])
            t["you"], t["said"] = redact(t["you"]), redact(t["said"])
        s["turns"].sort(key=lambda t: t["t0"])
        sessions.append(s)
    return sessions


def state_at(s, now):
    """The session as it stood at `now`: None when it hadn't started; else running, its last turn, your last message."""
    starts = [t["t0"] for t in s["turns"]]
    i = bisect.bisect_left(starts, now) - 1
    if i < 0:
        return None
    turn = s["turns"][i]
    running = turn["t1"] > now and turn["tools"] > 0
    done = s["turns"][i - 1] if running and i > 0 else (None if running else turn)
    return {"turn": turn, "running": running, "done": done, "last_you": turn, "last_at": turn["t1"] if not running else now}


def board_at(sessions, target, now, rng):
    projects, rows, cards = set(), [], []
    for s in sessions:
        st = state_at(s, now) if s is not target else state_at(s, now - 1e-3)
        if s is target and st is None:
            continue
        if st is None or now - (st["turn"]["t1"]) > WINDOW_H * 3600 and s is not target:
            continue
        rows.append((s, st))
    rows.sort(key=lambda x: -(x[1]["last_at"]))
    rows = rows[:MAX_SESSIONS]
    if target not in [r[0] for r in rows] and state_at(target, now - 1e-3):
        rows = rows[:MAX_SESSIONS - 1] + [(target, state_at(target, now - 1e-3))]
    out = []
    for s, st in rows:
        projects.add(s["project"])
        sid = s["id"][:8]
        entry = {"id": sid, "title": s["title"][:80], "project": s["project"], "running": st["running"],
                 "activity": "", "summary": "", "idle_min": round(max(0, now - st["last_at"]) / 60)}
        if st["running"]:
            entry["activity"] = "working on: " + st["turn"]["you"][:200].replace("\n", " ")
        elif st["done"]:
            said = last_paragraph(st["done"]["said"])
            if said:
                cards.append({"id": f"{sid}#c", "session": sid, "kind": "asks" if QUESTION.search(said) else "done", "text": said})
        out.append(entry)
    told = []
    for s, st in rows:
        if st and st["last_you"] and st["last_you"]["t0"] < now:
            told.append({"ago_min": round((now - st["last_you"]["t0"]) / 60), "you": st["last_you"]["you"][:200], "to": s["id"][:8]})
    told.sort(key=lambda h: -h["ago_min"])
    return {"projects": sorted(projects | {target["project"]}), "sessions": out, "cards": cards, "history": told}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-project", type=int, default=120)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    sessions = load()
    pool = []
    for s in sessions:
        for i, t in enumerate(s["turns"]):
            msg = t["you"].strip()
            if len(msg) > 1500 or len(msg) < 1:
                continue
            pool.append((s, i, t))
    rng.shuffle(pool)
    per, cases = {}, []
    for s, i, t in pool:
        if per.get(s["project"], 0) >= a.per_project:
            continue
        b = board_at(sessions, s, t["t0"], rng)
        if len(b["sessions"]) < 2 and i > 0:
            continue
        gold = s["id"][:8] if i > 0 else f"new:{s['project']}"
        if i == 0:
            b["sessions"] = [x for x in b["sessions"] if x["id"] != s["id"][:8]]
            b["cards"] = [c for c in b["cards"] if c["session"] != s["id"][:8]]
            b["history"] = [h for h in b["history"] if h["to"] != s["id"][:8]]
        per[s["project"]] = per.get(s["project"], 0) + 1
        cases.append({"id": f"re-{s['id'][:8]}-{i}", "tags": ["real", "first" if i == 0 else "follow-up", s["project"]],
                      "board": b, "message": t["you"].strip(), "gold": {"to": [gold], "ask_ok": None},
                      "at": t["at"]})
    with open(HERE / "data" / "real.jsonl", "w") as f:
        for c in cases:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")
    print(len(cases), "cases", per)


if __name__ == "__main__":
    main()
