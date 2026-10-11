"""How often simple priors name where a real message went. python3 real/priors.py"""
import collections
import json
import pathlib

HERE = pathlib.Path(__file__).parent


def main():
    cases = [json.loads(l) for l in open(HERE / "data" / "real.jsonl")]
    hits = collections.Counter()
    n = 0
    for c in cases:
        if c["tags"][1] != "follow-up":
            continue
        n += 1
        b, gold = c["board"], c["gold"]["to"][0]
        idle = sorted((s for s in b["sessions"] if not s["running"]), key=lambda s: s["idle_min"])
        told = sorted(b["history"], key=lambda h: h["ago_min"])
        waiting = [k["session"] for k in b["cards"] if k["kind"] == "asks"]
        hits["last finished"] += bool(idle) and idle[0]["id"] == gold
        hits["last told"] += bool(told) and told[0]["to"] == gold
        hits["in 2 last finished"] += gold in [s["id"] for s in idle[:2]]
        hits["only one waiting & it"] += len(waiting) == 1 and waiting[0] == gold
        hits["gold is waiting (asks)"] += gold in waiting
        hits["gold finished ≤5 min ago"] += any(s["id"] == gold and s["idle_min"] <= 5 for s in idle)
        hits["gold is the only one ≤5 min"] += [s["id"] for s in idle if s["idle_min"] <= 5] == [gold]
    for k, v in hits.items():
        print(f"{k:32} {100 * v / n:5.1f}%  of {n} follow-ups")
    # Precision of "the one session that finished within m minutes", over every case (first messages included).
    for m in (1, 2, 5, 10):
        fired = right = 0
        for c in cases:
            recent = [s["id"] for s in c["board"]["sessions"] if not s["running"] and s["idle_min"] <= m]
            if len(recent) == 1:
                fired += 1
                right += recent[0] == c["gold"]["to"][0]
        print(f"only one finished ≤{m:>2} min: fires on {100 * fired / len(cases):5.1f}% of cases, right {100 * right / max(fired, 1):5.1f}%")


if __name__ == "__main__":
    main()
