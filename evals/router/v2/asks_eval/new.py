"""Asks eval, step 3: the NEW list, one Haiku call per turn as the app makes it (RouterBriefer, RouterBriefContext).

    python3 v2/asks_eval/new.py [--workers 4]  →  v2/data/asks_eval/new.jsonl

The system prompt, schema, and the context's wording are read from Sources/Fjord/RouterBrief.swift at run time
(common.swift_prompt): edit the prompt there, rerun this, judge.py and score.py. Every turn is briefed as an "Asks you" card
under "needs you" that extracts its asks: the context has the title and project, what to explain (tierAsk .asks + the
extracting suffix), the old triage's sure lines (work label, unverified), the card's own text (the message's first two
sentences, 280 characters at most) and the message's last 6000 characters, all fenced. `claude -p --model
claude-haiku-5-5` with the app's flags, from an empty folder; the answer is checked as `RouterBriefContext.read` checks it:
anything it rejects is a failure (the card shows no list). Calls are cached on disk by everything that goes in."""
import argparse
import collections
from concurrent.futures import ThreadPoolExecutor

import common as C


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    p = C.swift_prompt()
    system = C.system_prompt(p)
    turns = C.jsonl(C.DATA / "turns.jsonl")
    old = {o["id"]: o for o in C.jsonl(C.DATA / "old.jsonl")}
    ctxs = [C.context(p, t["title"], t["project"], t["final"], (old.get(t["id"]) or {}).get("triage")) for t in turns]

    def one(ctx):
        return C.claude(C.HAIKU, system, ctx, p["schema"], "haiku")

    with ThreadPoolExecutor(min(a.workers, 4)) as pool:
        res = list(pool.map(one, ctxs))
    out, why = [], collections.Counter()
    for t, r in zip(turns, res):
        rec = {"id": t["id"], "elapsed": r.get("elapsed"), "slow": (r.get("elapsed") or 0) > C.APP_TIMEOUT}
        if r.get("error"):
            rec.update(failed=True, reason=r["error"], asks=[], brief=None)
        else:
            got, reason = C.read(C.typed_answer(r), p)
            if got is None:
                rec.update(failed=True, reason=reason, asks=[], brief=None)
            else:
                rec.update(failed=False, reason=None, asks=got["asks"], brief=got["brief"])
        why[rec["reason"]] += 1
        out.append(rec)
    C.write_jsonl(C.DATA / "new.jsonl", out)
    print("turns", len(out), "outcomes", dict(why), "slower than the app's 30 s", sum(o["slow"] for o in out),
          "non-empty lists", sum(bool(o["asks"]) for o in out))


if __name__ == "__main__":
    main()
