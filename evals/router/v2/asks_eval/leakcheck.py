"""Before committing v2/asks_eval/: no session text, no key-like strings, nothing under data/.

    python3 v2/asks_eval/leakcheck.py  →  exit 1 on any hit

Flags: (1) a run of 8 words found both in a file of v2/asks_eval/ and in any text under v2/data/asks_eval/ (messages,
lists, judge notes), unless that run is also in a tracked file elsewhere in the repo or in the judge's rubric (the app's
own prompt quoted by a session, or the rubric echoed in the judge's notes, is not a leak); (2) key and token patterns
(real/boards.py); (3) a staged or tracked path under data/."""
import pathlib
import re
import subprocess
import sys

import common as C
from boards import LONG_TOKEN, NUMBERS, SECRET  # noqa: E402

N = 8
WORD = re.compile(r"[\w'’-]+", re.U)


def shingles(text):
    w = [x.lower() for x in WORD.findall(text)]
    return {" ".join(w[i:i + N]) for i in range(len(w) - N + 1)}


def strings(o):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for v in o.values():
            yield from strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings(v)


def main():
    git = lambda *a: subprocess.run(["git", "-C", str(C.REPO), *a], capture_output=True, text=True).stdout
    data = set()
    for f in ("turns.jsonl", "old.jsonl", "new.jsonl", "judge.jsonl"):
        for rec in C.jsonl(C.DATA / f):
            for s in strings({k: v for k, v in rec.items() if k not in ("id", "session", "project", "title")}):
                data |= shingles(s)
    elsewhere = set()
    here = str(C.HERE.relative_to(C.REPO))
    for path in git("ls-files").splitlines():
        if path.startswith(here) or not path.endswith((".swift", ".md", ".py", ".json", ".txt")):
            continue
        p = C.REPO / path
        if p.is_file() and p.stat().st_size < 2_000_000:
            elsewhere |= shingles(p.read_text(errors="replace"))
    import judge                         # the judge's notes echo its own rubric: our words, not a session's
    elsewhere |= shingles(judge.SYSTEM)
    hits = 0
    for p in sorted(C.HERE.iterdir()):
        if p.is_dir() or p.suffix not in (".py", ".md", ".txt", ".json"):
            continue
        text = p.read_text()
        shared = (shingles(text) & data) - elsewhere
        for s in sorted(shared)[:5]:
            print(f"{p.name}: shares a run of {N} words with the data: {s[:40]}…")
        hits += len(shared)
        for pat in (SECRET, LONG_TOKEN, NUMBERS):
            for m in pat.finditer(text):
                print(f"{p.name}: key-like string {m.group(0)[:8]}…")
                hits += 1
    tracked = [l for l in (git("ls-files", "evals/router/v2/data") + git("diff", "--cached", "--name-only")).splitlines()
               if "/data/" in l]
    for t in tracked:
        print("tracked or staged under data/:", t)
    hits += len(tracked)
    print("leak check:", "clean" if not hits else f"{hits} hit(s)")
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
