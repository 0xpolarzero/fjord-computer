"""Where a variant's outcomes differ from the shipped replay's (counts only, no message text).

python3 -m explore.v2_short.diag BASE_RECORDS.pkl CAND_RECORDS.pkl BASE.jsonl CAND.jsonl
Per real submit: Jev's own top-1 (route alone, by destination), the fused top-1, the outcome (right/wrong send, ask
hit/miss), and whether the target was offered to Jev in the candidate's request."""
import collections
import pickle
import sys

from explore.v2_continuity import metrics as M
from v2.run import adapter


def key(r):
    return (r["episode"], r["event"])


def jtop(reading):
    d = {k: v for k, v in reading["dests"].items() if k != "unclear"}
    return max(d, key=d.get) if d else None


def outcome(row):
    return "wrong" if row["wrong"] else "right" if row["right"] else "ask-hit" if row["askhit"] else "ask-miss"


def main():
    rb, rc, tb, tc = sys.argv[1:5]
    B = {key(r): r for r in pickle.load(open(rb, "rb")) if r.get("source") == "real-moment"}
    C = {key(r): r for r in pickle.load(open(rc, "rb")) if r.get("source") == "real-moment"}
    ob, oc = M.load(tb), M.load(tc)
    c = collections.Counter()
    trans = collections.Counter()
    for k in sorted(set(B) & set(C) & set(ob) & set(oc)):
        g = adapter.legacy_target(B[k]["gold"]["intended"])
        jb, jc = jtop(B[k]["reading"]), jtop(C[k]["reading"])
        off = set(C[k]["reading"].get("_off", []))
        offered = g not in off
        c["n"] += 1
        c["jev top-1 base"] += jb == g
        c["jev top-1 variant"] += jc == g
        c["target offered"] += offered
        if offered:
            c["offered: jev top-1 base"] += jb == g
            c["offered: jev top-1 variant"] += jc == g
            c["offered: n"] += 1
        else:
            c["left out: fused top-1 base"] += ob[k]["top1"]
            c["left out: fused top-1 variant"] += oc[k]["top1"]
        trans[(outcome(ob[k]), outcome(oc[k]), "offered" if offered else "left out")] += 1
    for name, v in c.items():
        print(f"{name:34s} {v}")
    print("outcome changes (base -> variant, target offered?):")
    for (a, b, o), v in sorted(trans.items()):
        if a != b:
            print(f"  {a:9s} -> {b:9s} {o:9s} {v}")


if __name__ == "__main__":
    main()
