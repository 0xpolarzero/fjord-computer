"""Counts on recorded real submits: how often the last-told session is the target, checked, running.

python3 -m explore.v2_continuity.stats [RECORDS.pkl]"""
import collections
import pickle
import sys

from explore import recency as R
from explore.v2_continuity import told as T
from explore.v2_continuity.replay import OUT


def legacy(t):
    return t[8:] if t and t.startswith("session:") else t


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else OUT / "shipped.rec.pkl"
    recs = pickle.load(open(path, "rb"))
    c = collections.Counter()
    for r in recs:
        if r.get("source") not in (None, "real-moment"):
            continue
        case = r["case"]
        b = case["board"]
        gid = legacy(r["gold"]["intended"])
        t = T.last_told_id(b)
        by = {x["id"]: x for x in b["sessions"]}
        c["submits"] += 1
        c["has_lastTold"] += t is not None
        c["lastTold_is_target"] += t is not None and t == gid
        checked = [s["id"] for s in R.finished_by_recency(b)[:3]]
        if t:
            run = bool(by[t].get("running"))
            c["lastTold_running"] += run
            c["lastTold_running_and_target"] += run and t == gid
            c["lastTold_among_3_checked"] += t in checked
            ex = T.told_extra(case) is not None
            c["extra_check_asked"] += ex
            c["extra_check_and_target"] += ex and t == gid
        h = b["history"]
        if len(h) >= 2 and h[-1]["ago_min"] == h[-2]["ago_min"] and h[-1]["to"] != h[-2]["to"]:
            c["history_tie_at_top"] += 1
        c["target_running"] += bool(by.get(gid, {}).get("running"))
        tr = T.transition(case)
        for k in ("fresh", "backlog", "finx0"):
            c[f"{k}_any"] += any(v[k] for v in tr.values())
            c[f"{k}_target"] += bool(tr.get(gid, {}).get(k))
        c["short_msgs"] += len(case["message"].split()) <= T.SHORT_WORDS
    for k, v in c.items():
        print(f"{k:32s} {v}")
    # the extra check's answers (records of a told-format replay), and the shipped checks' for comparison
    pos, neg, spos, sneg = [], [], [], []
    for r in recs:
        if r.get("source") not in (None, "real-moment"):
            continue
        case, g = r["case"], r["reading"].get("gates") or {}
        gid = legacy(r["gold"]["intended"])
        extra = T.told_extra(case)
        if extra and f"gate_next_{extra[0]}" in g:
            (pos if extra[0] == gid else neg).append(g[f"gate_next_{extra[0]}"])
        for k, v in g.items():
            if k.startswith("gate_next_") and not (extra and k == f"gate_next_{extra[0]}"):
                (spos if k[10:] == gid else sneg).append(v)

    def auc(p, n):
        return sum((x > y) + 0.5 * (x == y) for x in p for y in n) / (len(p) * len(n)) if p and n else float("nan")

    def share(xs, bar=0.5):
        return f"{sum(x >= bar for x in xs)}/{len(xs)}"
    if pos or neg:
        print(f"extra check: target {len(pos)} (yes>=0.5 {share(pos)}), not {len(neg)} (yes>=0.5 {share(neg)}), "
              f"AUC {auc(pos, neg):.3f}")
    print(f"shipped checks: target {len(spos)} (yes>=0.5 {share(spos)}), not {len(sneg)} (yes>=0.5 {share(sneg)}), "
          f"AUC {auc(spos, sneg):.3f}")


if __name__ == "__main__":
    main()
