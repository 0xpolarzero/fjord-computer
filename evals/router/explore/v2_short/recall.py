"""A9 step 1 (0 Jev): shortlist recall on dev real moments, on the boards of the shipped replay.

python3 -m explore.v2_short.recall [RECORDS.pkl]     (default /tmp/v2_short/shipped.rec.pkl)
Recall = share of submits whose gold `intended` is offered to Jev: a new session or intent always is; a session only
when it is in the shortlist. Prints counts only."""
import collections
import pickle
import random
import statistics
import sys

from explore.v2_short import formats as SF
from v2.run import adapter

RULES = {
    "rr told,fin,bm,waits,run": (("told", 1), ("fin", 1), ("bm", 1), ("waits", 1), ("running", 1)),
    "rr fin,told,bm,waits,run": (("fin", 1), ("told", 1), ("bm", 1), ("waits", 1), ("running", 1)),
    "rr told,fin,waits,run (no bm)": (("told", 1), ("fin", 1), ("waits", 1), ("running", 1)),
    "rr told,fin2,bm,waits,run": (("told", 1), ("fin", 2), ("bm", 1), ("waits", 1), ("running", 1)),
    "rr told,fin,bm2,waits,run": (("told", 1), ("fin", 1), ("bm", 2), ("waits", 1), ("running", 1)),
    "rr run,waits,told,fin,bm": (("running", 1), ("waits", 1), ("told", 1), ("fin", 1), ("bm", 1)),
    "lookout order only": (),
    "rr order,told,bm": (("offered", 1), ("told", 1), ("bm", 1)),
    "rr order2,told,bm": (("offered", 2), ("told", 1), ("bm", 1)),
    "rr order3,told,bm": (("offered", 3), ("told", 1), ("bm", 1)),
    "rr order2,told,bm,waits": (("offered", 2), ("told", 1), ("bm", 1), ("waits", 1)),
    "rr order2,told": (("offered", 2), ("told", 1)),
    "rr order2,bm": (("offered", 2), ("bm", 1)),
    "rr order3,told": (("offered", 3), ("told", 1)),
}


def gold_session(rec):
    g = adapter.legacy_target(rec["gold"].get("intended"))
    sessions = {s["id"] for s in rec["case"]["board"]["sessions"]}
    return g if g in sessions else None, g


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/v2_short/shipped.rec.pkl"
    recs = [r for r in pickle.load(open(path, "rb")) if r.get("source") == "real-moment"]
    from explore import lexical as L  # installed by the replay's Variant; here only for lex()
    from v2.run import episodes as E
    E._legacy_modules("combo-o", "explore.final3:best")
    n = len(recs)
    kinds = collections.Counter()
    offered_sizes = []
    for r in recs:
        gs, g = gold_session(r)
        ls = SF._lists(r["case"])
        offered_sizes.append(len(ls["offered"]))
        kinds["session" if gs else ("new" if str(g).startswith("new:") else "other")] += 1
        if gs:
            kinds["session offered (ceiling)"] += gs in ls["offered"]
            kinds["session running"] += gs in ls["running"]
    print(f"{n} real submits; gold kinds {dict(kinds)}; sessions offered per call median "
          f"{statistics.median(offered_sizes)}, mean {statistics.mean(offered_sizes):.1f}, max {max(offered_sizes)}")
    groups = sorted({r["group"] for r in recs})
    ceiling = sum(1 for r in recs if (lambda gs, g: gs is None or gs in SF._lists(r["case"])["offered"])(*gold_session(r)))
    print(f"ceiling (full option list): {100 * ceiling / n:.1f}%")
    print("| rule | " + " | ".join(f"K={k}" for k in range(4, 13)) + " |")
    print("|---|" + "---:|" * 9)
    for name, rounds in RULES.items():
        cells = []
        for k in range(4, 13):
            hit = []
            for r in recs:
                gs, _ = gold_session(r)
                sl = SF.shortlist(r["case"], k, rounds=rounds)
                hit.append((r["group"], gs is None or gs in sl))
            rate = sum(h for _, h in hit) / n
            # group bootstrap lower bound
            byg = collections.defaultdict(list)
            for g, h in hit:
                byg[g].append(h)
            rng = random.Random(7)
            bs = []
            for _ in range(1000):
                pick = [groups[rng.randrange(len(groups))] for _ in groups]
                xs = [h for g in pick for h in byg[g]]
                bs.append(sum(xs) / len(xs))
            bs.sort()
            cells.append(f"{100 * rate:.1f} ({100 * bs[25]:.1f})")
        print(f"| {name} | " + " | ".join(cells) + " |")
    print("cells: recall % (2.5% group-bootstrap bound)")


if __name__ == "__main__":
    main()
