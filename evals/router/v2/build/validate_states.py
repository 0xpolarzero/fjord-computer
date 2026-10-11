"""Checks v2/data/states/moments.jsonl: counts, distributions against research/behavior.md, a compact sample, no keys.

    python3 v2/build/validate_states.py [--sample 5] [--seed 3]"""
import argparse
import collections
import json
import pathlib
import random
import re
import statistics
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "real"))
from boards import SECRET, LONG_TOKEN  # noqa: E402

PATH = HERE.parents[1] / "v2" / "data" / "states" / "moments.jsonl"


def pct(c, total):
    return {k: f"{v} ({100 * v / total:.0f}%)" for k, v in sorted(c.items(), key=lambda x: -x[1])} if total else {}


def q(xs, ps=(25, 50, 75, 90)):
    xs = sorted(xs)
    return {p: xs[min(len(xs) - 1, int(len(xs) * p / 100))] for p in ps} if xs else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=5)
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    raw = PATH.read_text()
    recs = [json.loads(line) for line in raw.splitlines()]
    n = len(recs)
    print(f"{n} moments, {len({r['group'] for r in recs})} groups, {len({r['went_to'] for r in recs if not r['went_to'].startswith('new:')})} target sessions")

    kinds = collections.Counter()
    for r in recs:
        f = r["flags"]
        kinds["first (new session)"] += f["first"]
        kinds["queued (typed while running)"] += f["queued"]
        kinds["  of which absorbed mid-turn"] += f["absorbed"]
        kinds["after interrupt"] += f["after_interrupt"]
        kinds["running target"] += f["running_target"]
        kinds["form answer"] += f["form_answer"]
        kinds["target not offered"] += not f["target_offered"]
    print("kinds:", dict(kinds))
    print("projects:", dict(collections.Counter(r["project"] for r in recs).most_common()))

    # Transitions as research/behavior.md counted them: your typed messages (no queued, no form answers) one after another.
    typed = [r for r in recs if not r["flags"]["form_answer"]]
    plain = [r for r in typed if not r["flags"]["queued"]]
    for name, rows in (("typed, queued excluded", plain), ("all typed", typed)):
        prev, c = None, collections.Counter()
        for r in rows:
            to = r["went_to"]
            if prev is not None:
                c["new" if r["flags"]["first"] else ("same" if to == prev else "switch")] += 1
            prev = r["went_to"] if not to.startswith("new:") else r["id"].split("-")[1]
        print(f"transitions ({name}; behavior.md 51/40/9):", pct(c, sum(c.values())))
    sw = [r for r in plain if r["flags"]["transition"] == "switch" and not r["flags"]["running_target"]]
    ranks = collections.Counter(r["flags"]["recency_rank"] for r in sw)
    bucket = collections.Counter({"1": ranks[1], "2": ranks[2], "3": ranks[3],
                                  "4-6": sum(ranks[k] for k in (4, 5, 6)),
                                  "7+": sum(v for k, v in ranks.items() if isinstance(k, int) and k >= 7),
                                  "none": ranks[None]})
    print("recency rank on switches (behavior.md 36/32/18/13):", pct(bucket, len(sw)))
    same = [r for r in plain if r["flags"]["transition"] == "same" and not r["flags"]["running_target"]]
    print("recency rank on same:", pct(collections.Counter(r["flags"]["recency_rank"] if (r["flags"]["recency_rank"] or 99) <= 3 else "4+" for r in same), len(same)))

    st = [r["state"] for r in recs]
    print("sessions on board:", q([len(s["sessions"]) for s in st]))
    print("running on board (others):", q([sum(x["running"] for x in s["sessions"]) for s in st]),
          "share with >=1 running:", f"{100 * sum(any(x['running'] for x in s['sessions']) for s in st) / n:.0f}%")
    print("active in last 2 h:", q([sum((x["running"] or x["idle_min"] <= 120) for x in s["sessions"]) for s in st]))
    print("projects known:", q([len(s["projects"]) for s in st]))
    print("open cards:", q([len(s["cards"]) for s in st]))
    ck = collections.Counter(c["kind"] for s in st for c in s["cards"])
    print("card kinds (card-moments):", pct(ck, sum(ck.values())))
    uniq = {}
    for s in st:
        for c in s["cards"]:
            uniq[c["id"]] = c["kind"]
    print("card kinds (distinct cards):", pct(collections.Counter(uniq.values()), len(uniq)))
    print("target's open card kind:", pct(collections.Counter((r["flags"]["target_card"] or ["none"])[-1] for r in recs if not r["flags"]["first"]),
                                          sum(not r["flags"]["first"] for r in recs)))
    print("turns per offered session:", q([len(x["turns"]) for s in st for x in s["sessions"]]))
    print("message words:", q([len(r["message"].split()) for r in recs], (10, 25, 50, 75, 90)),
          "<=5 words:", f"{100 * sum(len(r['message'].split()) <= 5 for r in recs) / n:.0f}%")

    # Keys: none of the redaction's patterns may match anything written.
    def strings(x):
        if isinstance(x, str):
            yield x
        elif isinstance(x, dict):
            for v in x.values():
                yield from strings(v)
        elif isinstance(x, list):
            for v in x:
                yield from strings(v)

    leaks = [m.group(0)[:10] + "…" for r in recs for s in strings(r) for pat in (SECRET, LONG_TOKEN) for m in pat.finditer(s)]
    print("key patterns left (decoded strings):", len(leaks), leaks[:5])

    rng = random.Random(a.seed)
    for r in rng.sample(recs, a.sample):
        s = r["state"]
        print("\n---", r["id"], r["at"], r["project"], "→", r["went_to"], {k: v for k, v in r["flags"].items() if v not in (False, None, [])})
        print("  message:", json.dumps(r["message"][:160], ensure_ascii=False))
        for x in s["sessions"][:8]:
            mark = "*" if x["id"] == r["went_to"] else " "
            st_ = "RUN " + x["activity"][:40] if x["running"] else (f"WAIT {x['activity'][:40]}" if x.get("waits_on_you") else f"idle {x['idle_min']}m")
            print(f"  {mark} {x['id']} [{x['project'][:12]}] {x['title'][:50]!r} {st_} turns={len(x['turns'])}")
        if len(s["sessions"]) > 8:
            print(f"    … {len(s['sessions']) - 8} more sessions")
        for c in s["cards"][:6]:
            print(f"  card {c['session']} {c['kind']} {c['created_min_ago']}m {c['text'][:70]!r} {c['options'][:3] if c['options'] else ''}")
        print(f"  history {len(s['history'])}, projects {len(s['projects'])}")


if __name__ == "__main__":
    main()
