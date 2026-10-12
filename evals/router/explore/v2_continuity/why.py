"""For submits whose outcome changes between shipped and a told-format trace: was the extra check asked, its answer, and
where the shipped send / pick and the target stand relative to lastTold (no message text).

python3 -m explore.v2_continuity.why BASE_STEM CAND_STEM   (stems in out/, records out/<stem>.rec.pkl)"""
import pickle
import sys

from explore import recency as R
from explore.v2_continuity import told as T
from explore.v2_continuity.diff import brief
from explore.v2_continuity.replay import OUT
from v2.run.score import event_score
import json


def traces(stem):
    out = {}
    for line in open(OUT / f"{stem}.jsonl"):
        ep = json.loads(line)
        for ev in ep["events"]:
            if ev["kind"] == "submit":
                out[(ep["id"], ev["id"])] = ev
    return out


def recs(stem):
    return {(r["episode"], r["event"]): r for r in pickle.load(open(OUT / f"{stem}.rec.pkl", "rb"))}


def leg(t):
    return t[8:] if t and t.startswith("session:") else t


def main():
    a, b = traces(sys.argv[1]), traces(sys.argv[2])
    rb = recs(sys.argv[2]) if (OUT / f"{sys.argv[2]}.rec.pkl").exists() else {}
    for k in sorted(set(a) & set(b)):
        if event_score(a[k])["loss"] == event_score(b[k])["loss"]:
            continue
        r = rb.get(k)
        info = ""
        if r:
            case, g = r["case"], r["reading"].get("gates") or {}
            t = T.last_told_id(case["board"])
            extra = T.told_extra(case)
            gold = leg(a[k]["gold"]["intended"])
            nx = {d[len("gate_next_"):]: round(v, 2) for d, v in g.items() if d.startswith("gate_next_")}
            info = (f"target=lastTold:{int(gold == t)} extra_asked:{int(bool(extra))} "
                    f"extra_yes:{nx.get(t) if extra else '-'} base_top=lastTold:{int(leg(a[k].get('top')) == t)} "
                    f"next_yes(target)={nx.get(gold, '-')} next_yes(base_top)={nx.get(leg(a[k].get('top')), '-')}")
        print(f"{brief(a[k])[:40]} -> {brief(b[k])[:40]} | {info}")


if __name__ == "__main__":
    main()
