"""A8 diagnosis (numbers only, no text): on submits whose target is running, does the variant raise the gold's f_said
and P; and the features behind every moment whose fused top changed.

python3 -m explore.v2_turns.why VARIANT
"""
import collections
import sys

sys.dont_write_bytecode = True

from explore.v2_turns import analyze as A

KEYS = ("f_said", "f_old", "f_you", "f_title", "run", "lp")


def feats(x, dest):
    f = x.fs.get(dest, {})
    return {k: round(f.get(k, 0), 2) for k in KEYS}


def main(variant):
    mb, mv = A.moments("base"), A.moments(variant)
    st = collections.Counter()
    for k in sorted(mb):
        xb, xv = mb[k], mv[k]
        g = xb.dests[xb.y] if xb.y is not None else None   # the gold as a fusion destination (legacy id)
        sl = A.slices(xb)
        pb, pv = A.per_moment(xb), A.per_moment(xv)
        if sl["target running"]:
            fb, fv = xb.fs.get(g, {}), xv.fs.get(g, {})
            st["n"] += 1
            st["gold not a fusion destination"] += g is None
            st["base right"] += pb["ok"]
            st["gold f_said up"] += fv.get("f_said", 0) > fb.get("f_said", 0) + 1e-9
            st["gold f_said down"] += fv.get("f_said", 0) < fb.get("f_said", 0) - 1e-9
            st["gold f_said>0 base"] += fb.get("f_said", 0) > 0
            st["gold f_said>0 variant"] += fv.get("f_said", 0) > 0
            st["gold f_old>0"] += fb.get("f_old", 0) > 0
            st["gold P up"] += pv["P"].get(g, 0) > pb["P"].get(g, 0) + 1e-9
            st["gold P down"] += pv["P"].get(g, 0) < pb["P"].get(g, 0) - 1e-9
            st["message shares no word with any session"] += max([f.get("bm", 0) for f in xb.fs.values()] + [0]) == 0
            st["base top is a running session"] += any(
                s["id"] == pb["top"] and s.get("running") for s in xb.m["state"]["sessions"])
        if pb["top"] != pv["top"]:
            run_top = any(s["id"] == pv["top"] and s.get("running") for s in xb.m["state"]["sessions"])
            print(f"{k[1]} target-running={sl['target running']} ok {pb['ok']}->{pv['ok']} | gold {feats(xb, g)} -> "
                  f"{feats(xv, g)} | new top (running={run_top}) {feats(xb, pv['top'])} -> {feats(xv, pv['top'])} | "
                  f"P gold {pb['P'].get(g, 0):.2f}->{pv['P'].get(g, 0):.2f}")
    for k, v in st.items():
        print(f"{k}: {v}")


if __name__ == "__main__":
    main(sys.argv[1])
