"""Asks eval, step 5: OLD vs NEW error counts from the judge, overall, per stratum, and on the cards that list asks.

    python3 v2/asks_eval/score.py              →  tables on stdout (counts only), v2/data/asks_eval/score.json
    python3 v2/asks_eval/score.py --mistakes   →  also writes v2/data/asks_eval/mistakes_new.jsonl (redacted text: stays there)

Per side: fake items (lead-in, narration, duplicate, fragment), distorted items, missed asks, option errors (dropped or
split; invented options counted apart), messages with any error, messages the judge says ask nothing that got a
non-empty list, and messages that ask something that got an empty one. "Cards" = turns Jev's (old) triage put in asks or
approval: the cards that would list asks in the app."""
import argparse
import collections
import json

import common as C

FAKE = ["lead_in", "narration", "duplicate", "fragment"]
STRATA = ["leadin", "numbered", "options", "buried", "nothing"]


def side(j, key):
    g = j[key]
    v = collections.Counter(i["verdict"] for i in g["items"])
    issues = collections.Counter(i["issue"] for i in g["items"] if i["verdict"] == "distorted")
    opt = collections.Counter(e["kind"] for e in g["option_errors"])
    n_items = j["n_" + key]
    r = {"items": n_items, "graded": len(g["items"]), "fake": sum(v[k] for k in FAKE), **{k: v[k] for k in FAKE},
         "distorted": v["distorted"], **{"dist_" + k: n for k, n in issues.items()}, "real": v["real_ask"],
         "missed": len(g["missed"]), "opt": opt["dropped"] + opt["split"], "opt_dropped": opt["dropped"],
         "opt_split": opt["split"], "opt_invented": opt["invented"]}
    r["any"] = int(r["fake"] + r["distorted"] + r["missed"] + r["opt"] + r["opt_invented"] > 0)
    r["nothing_listed"] = int(not j["message_asks_user"] and n_items > 0)
    r["something_empty"] = int(j["message_asks_user"] and n_items == 0)
    return r


def table(rows, title):
    keys = ["turns", "fake", "lead_in", "narration", "duplicate", "fragment", "distorted", "missed", "opt", "opt_dropped",
            "opt_split", "opt_invented", "any", "nothing_listed", "something_empty", "items", "failed"]
    names = {"turns": "turns", "fake": "fake items", "lead_in": "  lead-in", "narration": "  narration",
             "duplicate": "  duplicate", "fragment": "  fragment", "distorted": "distorted items", "missed": "missed asks",
             "opt": "option errors", "opt_dropped": "  choices dropped", "opt_split": "  choices split",
             "opt_invented": "invented options", "any": "messages with any error",
             "nothing_listed": "asks-nothing msgs given a list", "something_empty": "asking msgs given no list",
             "items": "items listed", "failed": "NEW call failures"}
    cols = list(rows)
    out = [f"\n### {title}\n", "| | " + " | ".join(cols) + " |", "|---|" + "---|" * len(cols)]
    for k in keys:
        out.append(f"| {names[k]} | " + " | ".join(str(rows[c].get(k, "")) for c in cols) + " |")
    return "\n".join(out)


def agg(recs, keyside):
    tot = collections.Counter()
    for r in recs:
        tot.update(r[keyside])
    tot["turns"] = len(recs)
    if keyside == "new":
        tot["failed"] = sum(r["failed"] for r in recs)
    return dict(tot)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mistakes", action="store_true")
    a = ap.parse_args()
    turns = {t["id"]: t for t in C.jsonl(C.DATA / "turns.jsonl")}
    old = {o["id"]: o for o in C.jsonl(C.DATA / "old.jsonl")}
    new = {n["id"]: n for n in C.jsonl(C.DATA / "new.jsonl")}
    recs, skipped, mismatch = [], 0, 0
    for j in C.jsonl(C.DATA / "judge.jsonl"):
        if "error" in j:
            skipped += 1
            continue
        o, n = side(j, "old"), side(j, "new")
        mismatch += (o["graded"] != o["items"]) + (n["graded"] != n["items"])
        state = (old[j["id"]].get("triage") or {}).get("state")
        recs.append({"id": j["id"], "stratum": turns[j["id"]]["stratum"], "card": state in ("asks", "approval"),
                     "asks_user": j["message_asks_user"], "old": o, "new": n, "failed": new[j["id"]]["failed"]})
    print(f"judged turns {len(recs)} (judge failed {skipped}); lists whose graded count differs from their length: {mismatch}")
    print("Jev (old triage) states:", dict(collections.Counter((o.get("triage") or {}).get("state") for o in old.values())))
    print("cards that would list asks (state asks/approval):", sum(r["card"] for r in recs),
          "| judge: message asks the user something:", sum(r["asks_user"] for r in recs))
    subsets = [("All turns", recs), ("Cards (Jev state asks or approval)", [r for r in recs if r["card"]])]
    subsets += [(f"Stratum {s}", [r for r in recs if r["stratum"] == s]) for s in STRATA]
    report = {}
    for title, rs in subsets:
        rows = {"OLD": agg(rs, "old"), "NEW": agg(rs, "new")}
        report[title] = rows
        print(table(rows, title))
    dist = collections.Counter()
    for r in recs:
        for k, v in r["new"].items():
            if k.startswith("dist_"):
                dist[k[5:]] += v
    print("\nNEW distorted items by issue:", dict(dist))
    dist_o = collections.Counter()
    for r in recs:
        for k, v in r["old"].items():
            if k.startswith("dist_"):
                dist_o[k[5:]] += v
    print("OLD distorted items by issue:", dict(dist_o))
    (C.DATA / "score.json").write_text(json.dumps(report, indent=1))
    if a.mistakes:
        out = []
        for j in C.jsonl(C.DATA / "judge.jsonl"):
            if "error" in j:
                continue
            asks = new[j["id"]]["asks"]
            for it in j["new"]["items"]:
                if it["verdict"] != "real_ask":
                    k = it["n"] - 1
                    out.append({"id": j["id"], "kind": it["verdict"], "issue": it["issue"], "why": it["why"],
                                "entry": asks[k] if 0 <= k < len(asks) else None})
            for m in j["new"]["missed"]:
                out.append({"id": j["id"], "kind": "missed", "why": m})
            for e in j["new"]["option_errors"]:
                out.append({"id": j["id"], "kind": "option_" + e["kind"], "why": e["ask"] + ": " + e["why"]})
        C.write_jsonl(C.DATA / "mistakes_new.jsonl", out)
        print("NEW mistakes:", dict(collections.Counter(m["kind"] for m in out)), "→", C.DATA / "mistakes_new.jsonl")


if __name__ == "__main__":
    main()
