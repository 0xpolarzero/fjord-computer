"""Submits whose outcome changes between two traces (no message text): python3 -m explore.v2_continuity.diff A B"""
import json
import sys

from v2.run.score import event_score


def load(path):
    out = {}
    for line in open(path):
        ep = json.loads(line)
        if (ep.get("provenance") or {}).get("source") != "real-moment":
            continue
        for ev in ep["events"]:
            if ev["kind"] == "submit":
                out[(ep["id"], ev["id"])] = ev


def brief(ev):
    s = event_score(ev)
    kind = "wrong" if s["wrong"] else "right" if s["right"] else "ask-hit" if s["hit_at_4"] else "ask-miss"
    return f"{kind:8s} top1={int(ev.get('top') == ev['gold']['intended'])} sure={ev.get('sureness') or 0:.2f} " \
           f"reason={ev.get('reason')} loss={s['loss']}"


def main():
    a, b = {}, {}
    for path, d in ((sys.argv[1], a), (sys.argv[2], b)):
        for line in open(path):
            ep = json.loads(line)
            if (ep.get("provenance") or {}).get("source") != "real-moment":
                continue
            for ev in ep["events"]:
                if ev["kind"] == "submit":
                    d[(ep["id"], ev["id"])] = ev
    for k in sorted(set(a) & set(b)):
        x, y = brief(a[k]), brief(b[k])
        if x.split(" sure")[0] != y.split(" sure")[0] or event_score(a[k])["loss"] != event_score(b[k])["loss"]:
            tags = (a[k].get("tags") or {}).get("slices", [])
            same = "same" if "same" in tags else "switch" if "switch" in tags else "-"
            print(f"{k[0][-14:]}/{k[1]:4s} {same:6s} | {x} | {y}")


if __name__ == "__main__":
    main()
