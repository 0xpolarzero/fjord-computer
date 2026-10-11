"""Triage eval, step 4a: Jev's post-turn triage on the sampled turns, today's bundle and the planned one's variants.

    python3 v2/triage_eval/jev_variants.py [--only old,newC,...]  →  v2/data/triage_eval/jev_<variant>.jsonl

Every bundle is one call per turn, as the app makes it (cached by evals/router/jev.py; same key order as stage A):
- old:   today's questions (RouterTriage.questions, ported in v2/build/triage.py) + the `trivial` extra (RouterAttention).
- newC:  the planned change: reworded hints (state waiting / asks, waitingOn review) + `next` as a choice
         (you | note | nothing) whose criteria carry examples, + trivial.
- newC0: the same, `next`'s criteria without examples.
- newG:  reworded hints + two yes/no gates instead of `next`: `step` (leaves the user a step to do?) and `worth`
         (worth reading?), with examples; + trivial.
- newG0: the gates without examples.
- newCO, newGO: newC, newG with the asks hint saying an offer of optional further work ("Want me to also ...?") at the
         end of a finished turn is not asking (done).
Floors and fallbacks are applied afterwards (score.py) on the same answers: no call per floor.
The wait options (`waitTarget`) and the circles/depends extras aren't asked (the transcripts can't rebuild them)."""
import argparse
import copy
import json
import pathlib
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path.insert(0, str(ROUTER / "v2" / "build"))
sys.path.insert(0, str(ROUTER))
import jev  # noqa: E402
import triage as T  # noqa: E402

DATA = ROUTER / "v2" / "data" / "triage_eval"

TRIVIAL = T._noul("Is this turn trivial: a short reply, an acknowledgment or a small step, with nothing in it the user would want to look at?")

NEW_STATE_HINTS = {
    "done": "It finished what it was asked and reports it; nothing is asked of the user",
    "asks": "It asks the user one or more questions in prose, or wants them to choose or decide something, or says it waits on the user (their review, answer, test, action)",
    "approval": "It asks permission before doing something consequential: pushing, publishing, deleting, driving the screen, spending money",
    "blocked": "It hit an error, lacks access or a permission, or can't proceed without help",
    "waiting": "It waits on something outside it and outside the user: CI or checks, tests running, a deploy, another session, someone else's review, a rate limit; it will continue when that is done",
    "progress": "It reports partial progress and isn't finished, without asking anything",
}
NEW_REVIEW_HINT = "A review by someone other than the user"

NEXT_INSTR = "Once this turn is over, what does it leave the user? Judge by its final message."
NEXT_X = {
    "you": "A step for the user to do before the work is finished: merge, push, release, relaunch or try it, run a command, test by hand, add a setting or a key",
    "note": "Nothing to do, but something worth reading: a caveat, a risk, a decision it took alone, something untested or that \"should work\", a finding",
    "nothing": "Nothing to do and nothing notable: it did what was asked and says so",
}
NEXT_0 = {
    "you": "A step for the user to do",
    "note": "Nothing to do, but something worth reading",
    "nothing": "Nothing to do and nothing notable",
}
STEP_X = ("Does the turn leave the user a step to do before the work is finished, for instance merge, push, release, relaunch "
          "or try it, run a command, test by hand, add a setting or a key?")
STEP_0 = "Does the turn leave the user a step to do?"
WORTH_X = ("Even with nothing to do, is the message worth the user reading, for instance a caveat, a risk, a decision it took "
           "alone, something untested or that \"should work\", a finding?")
WORTH_0 = "Even with nothing to do, is the message worth the user reading?"


OFFER_ASKS = (NEW_STATE_HINTS["asks"] + ". An offer of optional further work at the end of a finished turn (\"Want me to "
              "also ...?\") is not asking: that is done")


def new_base(cands, offers=False):
    q = T.questions(cands)
    hints = dict(NEW_STATE_HINTS, asks=OFFER_ASKS) if offers else NEW_STATE_HINTS
    q["state"] = T._choice(T.STATES, hints, q["state"]["instructions"])
    q["waitingOn"] = copy.deepcopy(q["waitingOn"])
    q["waitingOn"]["criteria"]["review"] = NEW_REVIEW_HINT
    q["trivial"] = TRIVIAL
    return q


def bundle(variant, cands):
    if variant == "old":
        q = T.questions(cands)
        q["trivial"] = TRIVIAL
        return q
    q = new_base(cands, offers=variant.endswith("O"))
    variant = variant.rstrip("O")
    if variant == "newC":
        q["next"] = T._choice(["you", "note", "nothing"], NEXT_X, NEXT_INSTR)
    elif variant == "newC0":
        q["next"] = T._choice(["you", "note", "nothing"], NEXT_0, NEXT_INSTR)
    elif variant == "newG":
        q["step"], q["worth"] = T._noul(STEP_X), T._noul(WORTH_X)
    elif variant == "newG0":
        q["step"], q["worth"] = T._noul(STEP_0), T._noul(WORTH_0)
    else:
        raise ValueError(variant)
    return q


VARIANTS = ["old", "newC", "newC0", "newG", "newG0", "newCO", "newGO"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(VARIANTS))
    ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args()
    turns = [json.loads(l) for l in open(DATA / "turns.jsonl")]
    for variant in a.only.split(","):
        calls = []
        for t in turns:
            st, _, cands = T.call(t["final"], t["title"], t["project"])
            calls.append((st, bundle(variant, cands), cands))

        def one(c):
            try:
                return jev.ask(c[0], c[1])
            except Exception as e:  # noqa: BLE001
                return {"_error": str(e)[:200]}

        with ThreadPoolExecutor(a.workers) as pool:
            res = list(pool.map(one, calls))
        bad = 0
        with open(DATA / f"jev_{variant}.jsonl", "w") as out:
            for t, (st, q, cands), r in zip(turns, calls, res):
                ans = r.get("answers") if isinstance(r, dict) else None
                bad += ans is None
                out.write(json.dumps({"id": t["id"], "candidates": cands, "answers": ans,
                                      "error": None if ans is not None else r.get("_error")}, ensure_ascii=False) + "\n")
        print(variant, "calls", len(calls), "failed", bad, flush=True)


if __name__ == "__main__":
    main()
