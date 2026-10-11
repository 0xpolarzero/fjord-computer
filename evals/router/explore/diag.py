"""Wrong sends of a format+policy on a set, with what decided them and the board facts around the destination.
python3 -m explore.diag FORMAT module:policy SET [N]"""
import collections
import importlib
import sys

import bench
import run
from explore import recency as R


def facts(case, dest):
    b = case["board"]
    fin = [s["id"] for s in R.finished_by_recency(b)]
    s = next((x for x in b["sessions"] if x["id"] == dest), None)
    if not s:
        return "not a session"
    rank = fin.index(dest) if dest in fin else None
    card = next((k["kind"] for k in b["cards"] if k["session"] == dest), "-")
    return f"recency={rank} running={s['running']} idle={s['idle_min']}m card={card}"


def main():
    fmt, pol_spec, setname = sys.argv[1:4]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 20
    mod, name = pol_spec.split(":")
    pol = getattr(importlib.import_module(mod), name)
    cases = {c["id"]: c for c in bench.load_set(setname)}
    rows = run.load(f"{fmt}@{setname}")
    cnt = collections.Counter()
    out = []
    for row in rows:
        c = cases[row["id"]]
        r = run.reading(row)
        k, w = pol(r)
        if k != "send" or w in c["gold"]["to"]:
            continue
        ns = R.nexts(r)
        reps = r.get("replies") or {}
        top, p = max(r["dests"].items(), key=lambda x: x[1])
        why = ("next-check" if ns and ns[0][0] == w and ns[0][1] >= 0.5 else
               "card-check" if reps and max(reps, key=reps.get) == w and max(reps.values()) >= 0.5 and top != w else
               "route")
        cnt[why] += 1
        out.append((why, c["id"], c["gold"].get("label"), round(r["dests"].get(w, 0), 2), facts(c, w),
                    "gold:" + facts(c, c["gold"]["to"][0]) if c["gold"]["to"] else "", c["message"][:80].replace("\n", " ")))
    print(cnt)
    for o in out[:n]:
        print(o)


if __name__ == "__main__":
    main()
