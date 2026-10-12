"""How well do words predict the labellers' "consequential" (misdelivery could push, delete, approve, publish…)?
Dev only. python3 -m explore.v2_bars.conseq"""
import collections, json, re

CONSEQ = re.compile(r"\b(push|pushed|merge|merged|deploy|release|publish|ship|delete|remove|drop|rm|reset|revert|"
                    r"force|approve|approved|accept|go ahead|do it|proceed|send it|post|submit|close|archive|wipe|"
                    r"overwrite|rollback|tag|pr|commit|install|pay|buy|confirm|yes|yep|ok|lgtm)\b", re.I)

c = collections.Counter()
for line in open("v2/data/episodes/dev/episodes.jsonl"):
    ep = json.loads(line)
    real = (ep.get("provenance") or {}).get("source") == "real-moment"
    for ev in ep["events"]:
        if ev.get("kind") != "submit":
            continue
        g = ev["gold"]
        views = g.get("views") or [g]
        cons = sum(bool(v.get("consequential")) for v in views) / len(views)
        hit = bool(CONSEQ.search(ev["message"]))
        c[("real" if real else "other", "words", hit)] += 1
        c[("real" if real else "other", "conseq_mass", hit)] += cons
for src in ("real", "other"):
    tot = c[(src, "conseq_mass", True)] + c[(src, "conseq_mass", False)]
    n = c[(src, "words", True)] + c[(src, "words", False)]
    print(src, f"consequential share {tot / n:.3f}; words flag {c[(src, 'words', True)] / n:.3f} of messages, "
               f"recall {c[(src, 'conseq_mass', True)] / max(tot, 1e-9):.3f}, "
               f"precision {c[(src, 'conseq_mass', True)] / max(c[(src, 'words', True)], 1):.3f}")
