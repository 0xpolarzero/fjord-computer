"""Skipped-asks eval, step 1: real turns whose final message asks you something, each with the message you typed next, and the
card's asks as the app reads them (the Haiku asks call ported in asks_eval/common.py).

    python3 v2/skipped_eval/sample.py [--multi 230] [--single 110] [--seed 7] [--workers 4]
        →  v2/data/skipped_eval/cases.jsonl

Sessions: the Claude app's and the CLI's in the projects of real/boards.py KEEP, started by you (no handoffs, continuations,
probes). Turns: finished, not interrupted, a final message of 80+ characters with a question mark in its prose, followed by a
prompt of yours typed after the turn ended (not queued during it, not a slash command or meta line, not an agent's). Two
strata by a cheap count of the prose's question sentences: `multi` (2+) and `single` (1), at most 3 turns per session per
stratum. Every text is redacted (real/boards.py `redact`) before anything else reads it; nothing raw is written. Then one
Haiku asks call per turn (cached; the asks_eval cache is copied in first), and only turns with a non-empty list are kept."""
import argparse
import collections
import hashlib
import pathlib
import random
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "asks_eval"))
import common as C  # noqa: E402

OUT = C.ROUTER / "v2" / "data" / "skipped_eval"
ASKS_CACHE = C.CACHE
C.CACHE = OUT / "cache"

import states as S  # noqa: E402
from boards import KEEP, redact  # noqa: E402

INLINE = re.compile(r"`[^`\n]*`|\"[^\"\n]*\"|“[^”\n]*”|«[^»\n]*»")
QSENT = re.compile(r"[^.!?\n]*\?(?=\s|\*|$)")
MAX_REPLY = 6000


def prose(text):
    out, fenced = [], False
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            fenced = not fenced
            continue
        if not fenced and not s.startswith("#"):
            out.append(line)
    return INLINE.sub("", "\n".join(out))


def question_count(text):
    return len([m for m in QSENT.findall(prose(text)) if len(m.strip()) > 3])


def reply_after(s, turn):
    """Your next prompt after the turn ended, if the turn after it starts with it and you typed it after the turn ended."""
    nxt = next((p for p in s.prompts if p["t"] > turn["end"]), None)
    if nxt is None or nxt["kind"] != "human" or nxt.get("queued") or nxt["typed"] < turn["end"]:
        return None
    return nxt


def pool():
    files = S.load_files()
    out, seen = [], set()
    for f in files:
        if f["entry"] not in ("claude-desktop", "cli"):
            continue
        s = S.Session(f)
        if s.start is None or s.project not in KEEP or not s.prompts:
            continue
        first = s.prompts[0]
        if first["kind"] != "human" or S.AGENT_FIRST.match(first["text"]) or S.PROBE_FIRST.match(first["text"]) or S.automated(s):
            continue
        for turn in s.turns:
            if turn["interrupted"] or not turn["final"] or len(turn["final"]) < 80:
                continue
            nxt = reply_after(s, turn)
            if nxt is None:
                continue
            final = redact(turn["final"])
            n = question_count(final)
            if n == 0:
                continue
            h = hashlib.sha256(" ".join(final.split()).encode()).hexdigest()
            if h in seen:
                continue
            seen.add(h)
            out.append({"id": f"{s.short}#t{turn['n']}", "session": s.short, "project": s.project,
                        "title": redact(s.title_at(turn["end"])), "final": final, "reply": redact(nxt["text"])[:MAX_REPLY],
                        "nq": n, "gap_s": round(nxt["typed"] - turn["end"], 1)})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--multi", type=int, default=230)
    ap.add_argument("--single", type=int, default=110)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--keep-single", type=int, default=100, help="single-ask cards kept (every multi-ask card is kept)")
    a = ap.parse_args()
    if (ASKS_CACHE / "haiku").is_dir() and not (C.CACHE / "haiku").is_dir():
        shutil.copytree(ASKS_CACHE / "haiku", C.CACHE / "haiku")
    turns = pool()
    print("turns with a question and a reply after", len(turns), collections.Counter("multi" if t["nq"] >= 2 else "single" for t in turns))
    rng = random.Random(a.seed)
    picked = []
    for name, want, test in (("multi", a.multi, lambda t: t["nq"] >= 2), ("single", a.single, lambda t: t["nq"] == 1)):
        cands = [t for t in turns if test(t)]
        rng.shuffle(cands)
        per = collections.Counter()
        for t in cands:
            if sum(1 for p in picked if p["stratum"] == name) >= want:
                break
            if per[t["session"]] >= 3:
                continue
            per[t["session"]] += 1
            picked.append(dict(t, stratum=name))
    print("picked", collections.Counter(p["stratum"] for p in picked))
    p = C.swift_prompt()
    system = C.system_prompt(p)
    old = {o["id"]: o for o in C.jsonl(C.DATA / "old.jsonl")}

    def one(t):
        ctx = C.context(p, t["title"], t["project"], t["final"], (old.get(t["id"]) or {}).get("triage"))
        return C.claude(C.HAIKU, system, ctx, p["schema"], "haiku")

    with ThreadPoolExecutor(min(a.workers, 4)) as ex:
        res = list(ex.map(one, picked))
    out, why = [], collections.Counter()
    for t, r in zip(picked, res):
        if r.get("error"):
            why[r["error"][:40]] += 1
            continue
        got, reason = C.read(C.typed_answer(r), p)
        if got is None:
            why[reason] += 1
            continue
        if not got["asks"]:
            why["no asks"] += 1
            continue
        why["kept"] += 1
        out.append(dict(t, asks=got["asks"], brief=got["brief"]))
    singles = [o for o in out if len(o["asks"]) == 1]
    random.Random(a.seed).shuffle(singles)
    keep = {o["id"] for o in singles[:a.keep_single]}
    out = [o for o in out if len(o["asks"]) > 1 or o["id"] in keep]
    C.write_jsonl(OUT / "cases.jsonl", out)
    print("outcomes", dict(why))
    print("kept", len(out), "by asks count", sorted(collections.Counter(len(o["asks"]) for o in out).items()))


if __name__ == "__main__":
    main()
