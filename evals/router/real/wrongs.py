"""Where a run's wrong sends went, by what decided them. python3 real/wrongs.py RUN [--cases ...] [--n 6]"""
import argparse
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import run  # noqa: E402
import score as sc  # noqa: E402

INTENTS = {"question", "compound", "change_lookout"}


def why(r, w):
    g = r.get("gates") or {}
    if w == "compound" and g.get("gate_compound", 0) >= 0.75:
        return "gate compound"
    if w == "change_lookout" and g.get("gate_setting", 0) >= 0.75:
        return "gate setting"
    reps = r.get("replies") or {}
    if reps and max(reps.values()) >= 0.5 and max(reps, key=reps.get) == w:
        return "card check"
    if w in INTENTS:
        return "route intent"
    if w.startswith("new:"):
        return "route new session"
    return "route other session"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--cases", default="real/data/real.jsonl")
    ap.add_argument("--n", type=int, default=6)
    a = ap.parse_args()
    cases = {c["id"]: c for c in run.load_cases(a.cases)}
    counts, ex = collections.Counter(), collections.defaultdict(list)
    for row in run.load(a.run):
        c = cases.get(row["id"])
        if not c:
            continue
        r = run.reading(row)
        k, w = sc.FINAL(r)
        if k == "send" and w not in c["gold"]["to"]:
            kind = why(r, w)
            counts[kind] += 1
            ex[kind].append((c["id"], c["message"][:90].replace("\n", " "), w, c["gold"]["to"],
                             round(r["dests"].get(w, 0), 2)))
    print(a.run, dict(counts))
    for k, v in ex.items():
        print("==", k)
        for e in v[:a.n]:
            print("   ", e)


if __name__ == "__main__":
    main()
