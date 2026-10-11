"""Sweep decision policies over saved runs (no Jev calls).

python3 analyze.py RUN [RUN...] [--max-wrong 1.0]
For each run: the best policy of each family at each wrong-send budget, by how often it acts rightly."""
import argparse
import itertools

import run

FAMILIES = {
    # top destination's probability and its lead over the runner-up (per destination, card and session merged)
    "lead": [dict(p_min=p, lead=l) for p in (0.3, 0.4, 0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9) for l in (0, 0.1, 0.2, 0.3, 0.4, 0.5)],
    # top-to-second ratio
    "ratio": [dict(p_min=p, ratio=r) for p in (0.2, 0.3, 0.4, 0.5, 0.6, 0.7) for r in (1.5, 2, 3, 4, 6, 10)],
    # a card's "answers it" yes first (when one card stands out), else the lead rule
    "reply": [dict(p_min=p, lead=l, reply=y, reply_other=o) for p in (0.4, 0.5, 0.6, 0.7, 0.8) for l in (0, 0.2, 0.4)
              for y in (0.5, 0.6, 0.7, 0.8, 0.9) for o in (0.2, 0.4)],
    "guard": [dict(p_min=p, lead=l, reply=y, reply_other=0.4, p_new=n, p_intent=i, conflict=k) for p in (0.5, 0.6, 0.7, 0.8)
              for l in (0, 0.2) for y in (0.5, 0.6) for n in (0.5, 0.6, 0.7) for i in (0.4, 0.5, 0.6) for k in (0.5, 0.7)],
    # by risk: a session send keeps a high bar; a new session and Lookout's own intents get theirs
    "risk": [dict(p_min=p, lead=0, reply=y, reply_other=0.4, p_new=n, p_intent=i) for p in (0.6, 0.7, 0.8)
             for y in (0.5, 0.7) for n in (0.5, 0.6, 0.7) for i in (0.4, 0.5, 0.6)],
}


LOW_RISK = {"question", "compound", "change_lookout"}


def policy(family, p_min=0.75, lead=0.3, ratio=2.0, reply=None, reply_other=0.3, p_new=None, p_intent=None, conflict=None):
    """p_new / p_intent: the bar for a new session, and for Lookout's own intents (answered, or a change you can revert).
    conflict: when one card's answer check stands out but the route's top is another session at least this sure, ask."""
    def pol(r):
        ranked = sorted(r["dests"].items(), key=lambda x: -x[1])
        top, p = ranked[0]
        if conflict is not None and reply is not None and r.get("replies"):
            ys = sorted(r["replies"].items(), key=lambda x: -x[1])
            if ys[0][1] >= reply and (len(ys) < 2 or ys[1][1] <= reply_other):
                if top != ys[0][0] and top not in run.NOT_TARGETS and not top.startswith("new:") and top not in LOW_RISK and p >= conflict:
                    return ("ask", run.ranked_targets(r)[:3])
                return ("send", ys[0][0])
        if p_intent is not None and top in LOW_RISK and p >= p_intent:
            return ("send", top)
        if p_new is not None and top.startswith("new:") and p >= p_new:
            return ("send", top)
        if reply is not None and r.get("replies"):
            ys = sorted(r["replies"].items(), key=lambda x: -x[1])
            if ys[0][1] >= reply and (len(ys) < 2 or ys[1][1] <= reply_other):
                return ("send", ys[0][0])
        ranked = sorted(r["dests"].items(), key=lambda x: -x[1])
        top, p = ranked[0]
        second = ranked[1][1] if len(ranked) > 1 else 0
        ok = p >= p_min and (p - second >= lead if family != "ratio" else p >= ratio * max(second, 1e-9))
        if top in run.NOT_TARGETS or not ok:
            return ("ask", run.ranked_targets(r)[:3])
        return ("send", top)
    return pol


def sweep(cases, rows, budgets):
    out = {}
    for fam, grid in FAMILIES.items():
        scored = []
        for params in grid:
            s = run.score(cases, rows, policy(fam, **params))
            scored.append((s, params))
        for b in budgets:
            ok = [x for x in scored if x[0]["wrong"] <= b]
            if ok:
                out[(fam, b)] = max(ok, key=lambda x: (x[0]["right"], -x[0]["wrong"]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--budgets", default="0.5,1,2,3")
    ap.add_argument("--cases", default="cases/*.jsonl")
    a = ap.parse_args()
    cases = run.load_cases(a.cases)
    ids = {c["id"] for c in cases}
    budgets = [float(x) for x in a.budgets.split(",")]
    for name in a.runs:
        rows = [r for r in run.load(name) if r["id"] in ids]
        res = sweep(cases, rows, budgets)
        for (fam, b), (s, params) in sorted(res.items()):
            print(f"{name:10} {fam:6} wrong≤{b:<4} right={s['right']:5}% wrong={s['wrong']:4}% miss={s['miss']:5}% "
                  f"good_ask={s['good_ask']:5}%  {params}")


if __name__ == "__main__":
    main()
