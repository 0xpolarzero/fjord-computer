"""Asks eval, step 1: ~200 real finished turns of your own sessions, in five strata picked by cheap heuristics (sampling only).

    python3 v2/asks_eval/sample.py [--per 40] [--seed 11]  →  v2/data/asks_eval/turns.jsonl

Sessions: the Claude app's and the CLI's (states.py's reader; each turn's `final` is the app's final message), in the
projects of real/boards.py KEEP, started by you: not by another agent (a handoff or continuation, AGENT_FIRST), a peer, or a
probe (states.automated). Turns: finished (not interrupted), with a final message of 80+ characters, deduplicated by text.
Every text is redacted (real/boards.py `redact`) first; the heuristics read the redacted text; nothing raw is written.

Strata (a turn may match several; it is drawn into one, the rarest first, at most 2 turns per session per stratum):
  leadin    a line ending in ":" right before a list, with a question mark somewhere
  numbered  2+ list items that are questions
  options   a question followed by 2+ list items without "?" (choices), or (a)/(b), "Option A/B"
  buried    a "?" sentence in a paragraph other than the last, the last paragraph with no "?"
  nothing   none of the above, and no question to you: `plain` (no "?" at all, no asking phrase) or `qmark` ("?" only
            in code, inline code, quotes or headings, no asking phrase, or a question answered on its own line: "Why? Because ...")"""
import argparse
import collections
import hashlib
import random
import re

import common as C
import states as S  # noqa: E402
import triage as T  # noqa: E402
from boards import KEEP, redact  # noqa: E402

LIST = re.compile(r"^\s*(?:[-*+•]\s+|\d{1,3}[.)]\s+|\(?[a-hA-H]\)\s+|\*\*(?:Option\s+)?[A-H][.):]?\*\*|Option\s+[A-H]\b|\*\*\d{1,2}[.)]?\*\*)")
CHOICE = re.compile(r"\([a-c]\).{0,200}\([b-d]\)|\bOption\s+[A-C]\b.{0,400}\bOption\s+[B-D]\b", re.S)
ASKY = re.compile(r"\b(should i|shall i|do you want|want me to|let me know|would you like|your call|which (?:one|do you)|prefer|up to you|go ahead\?)\b", re.I)
RHETORIC = re.compile(r"\?\**:?\s+(Because|Parce que|Short answer|Answer|Yes|No|Not|Mostly|Partly)\b")
INLINE = re.compile(r"`[^`\n]*`|\"[^\"\n]*\"|“[^”\n]*”|«[^»\n]*»")


def prose_lines(text):
    out, fenced = [], False
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            fenced = not fenced
            continue
        if not fenced:
            out.append(line)
    return out


def ends_q(line):
    return line.rstrip().rstrip("*_").rstrip().endswith("?")


def strata(text):
    lines = prose_lines(text)
    nonempty = [l for l in lines if l.strip()]
    prose = "\n".join(lines)
    bare = INLINE.sub("", prose)
    has_q = "?" in bare
    found = set()
    for k, line in enumerate(nonempty[:-1]):
        nxt = nonempty[k + 1]
        if line.strip().rstrip(" *_").endswith(":") and not LIST.match(line) and LIST.match(nxt) and has_q:
            found.add("leadin")
        if ends_q(line) or (line.strip().rstrip(" *_").endswith(":") and "?" in line):
            items = []
            for l in nonempty[k + 1:k + 6]:
                if not LIST.match(l):
                    break
                items.append(l)
            if len(items) >= 2 and not any("?" in l for l in items):
                found.add("options")
    if sum(1 for l in nonempty if LIST.match(l) and "?" in INLINE.sub("", l)) >= 2:
        found.add("numbered")
    if CHOICE.search(bare) and has_q:
        found.add("options")
    paras = [p for p in re.split(r"\n\s*\n", prose) if p.strip()]
    if len(paras) >= 2 and "?" not in INLINE.sub("", paras[-1]):
        if any(T.ask_score(s) == 2 for p in paras[:-1] for s in T.sentences(INLINE.sub("", p))):
            found.add("buried")
    sub = None
    if not found and not ASKY.search(bare):
        qlines = [l for l in nonempty if "?" in INLINE.sub("", l)]
        if "?" not in text:
            sub = "plain"
        elif all(l.lstrip().startswith("#") or RHETORIC.search(l) for l in qlines):
            sub = "qmark"
    return found, sub


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per", type=int, default=40)
    ap.add_argument("--seed", type=int, default=11)
    a = ap.parse_args()
    files = S.load_files()
    pool, seen = [], set()
    skipped = collections.Counter()
    for f in files:
        if f["entry"] not in ("claude-desktop", "cli"):
            continue
        s = S.Session(f)
        if s.start is None or s.project not in KEEP:
            continue
        first = s.prompts[0]
        if first["kind"] != "human" or S.AGENT_FIRST.match(first["text"]) or S.PROBE_FIRST.match(first["text"]) or S.automated(s):
            skipped["agent/probe session"] += 1
            continue
        for turn in s.turns:
            if turn["interrupted"] or not turn["final"] or len(turn["final"]) < 80:
                continue
            final = redact(turn["final"])
            h = hashlib.sha256(" ".join(final.split()).encode()).hexdigest()
            if h in seen:
                skipped["duplicate text"] += 1
                continue
            seen.add(h)
            found, sub = strata(final)
            pool.append({"id": f"{s.short}#t{turn['n']}", "session": s.short, "project": s.project,
                         "title": redact(s.title_at(turn["end"])), "final": final, "matches": sorted(found), "sub": sub})
    print("turns in the pool", len(pool), dict(skipped))
    by = collections.defaultdict(list)
    for r in pool:
        for m in r["matches"]:
            by[m].append(r)
        if r["sub"]:
            by["nothing"].append(r)
    print("matches", {k: len(v) for k, v in by.items()}, "nothing by kind", collections.Counter(r["sub"] for r in by["nothing"]))
    rng = random.Random(a.seed)
    picked, taken = [], set()
    for name in sorted(["leadin", "numbered", "options", "buried"], key=lambda k: len(by[k])) + ["nothing"]:
        cands = by[name][:]
        rng.shuffle(cands)
        if name == "nothing":       # half plain reports, half with question marks that ask nothing (as many as there are)
            q = [r for r in cands if r["sub"] == "qmark"][:a.per // 2]
            cands = q + [r for r in cands if r["sub"] == "plain"]
        per_session = collections.Counter()
        n = 0
        for r in cands:
            if n >= a.per:
                break
            if r["id"] in taken or per_session[r["session"]] >= 2:
                continue
            per_session[r["session"]] += 1
            taken.add(r["id"])
            picked.append(dict(r, stratum=name))
            n += 1
        print(f"{name:9s} picked {n}")
    C.write_jsonl(C.DATA / "turns.jsonl", picked)
    print("wrote", len(picked), "turns to", C.DATA / "turns.jsonl")


if __name__ == "__main__":
    main()
