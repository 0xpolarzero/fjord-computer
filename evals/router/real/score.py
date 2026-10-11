"""Real cases scored strictly: right = where you actually typed it, wrong = anywhere else, ask = asked.

python3 real/score.py RUN [RUN...] [--cases real/data/real.jsonl] [--by tag|len|waiting]"""
import argparse
import collections
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import analyze  # noqa: E402
import run  # noqa: E402

FINAL = analyze.policy("gates", p_min=0.7, lead=0, reply=0.5, reply_other=0.4, p_new=0.6, p_intent=0.6, conflict=0.5,
                       g_compound=0.75, g_setting=0.75, g_question=2)


def bucket(c, by):
    if by == "tag":
        return c["tags"][1]
    if by == "len":
        n = len(c["message"].split())
        return "1-3 words" if n <= 3 else "4-15" if n <= 15 else "16-60" if n <= 60 else "60+"
    if by == "waiting":
        return f"{sum(1 for k in c['board']['cards'] if k['kind'] == 'asks')} asks"
    if by == "label":
        return (c["gold"].get("label") or "unlabeled")
    return "all"


def score(cases, rows, pol=FINAL, by="all"):
    byid = {c["id"]: c for c in cases}
    t = collections.defaultdict(collections.Counter)
    for row in rows:
        c = byid.get(row["id"])
        if not c:
            continue
        r = run.reading(row)
        k, w = pol(r)
        gold = set(c["gold"]["to"])
        ranked = run.ranked_targets(r)
        b = bucket(c, by)
        t[b]["n"] += 1
        t[b]["top1"] += bool(ranked[:1]) and ranked[0] in gold
        t[b]["top3"] += bool(gold & set(ranked[:3]))
        t[b]["right" if k == "send" and w in gold else "wrong" if k == "send" else "ask"] += 1
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--cases", default="real/data/real.jsonl")
    ap.add_argument("--by", default="all")
    a = ap.parse_args()
    cases = run.load_cases(a.cases)
    for name in a.runs:
        t = score(cases, run.load(name), by=a.by)
        for b, v in sorted(t.items()):
            n = v["n"]
            print(f"{name:16} {b:12} n={n:4} right={100 * v['right'] / n:5.1f}% wrong={100 * v['wrong'] / n:4.1f}% "
                  f"ask={100 * v['ask'] / n:5.1f}% | top1={100 * v['top1'] / n:5.1f}% top3={100 * v['top3'] / n:5.1f}%")


if __name__ == "__main__":
    main()
