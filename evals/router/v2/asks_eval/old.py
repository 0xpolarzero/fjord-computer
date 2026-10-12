"""Asks eval, step 2: the OLD list, as the shipped app (RouterTriage.swift at HEAD fe1e147) makes it, and its triage.

    python3 v2/asks_eval/old.py [--workers 4]  →  v2/data/asks_eval/old.jsonl

The final message's sentences and list items (RouterTriage.sentences), those that look like asking (candidates, at most
24), Jev's one triage bundle with a yes/no per candidate "s<i>" (v2/build/triage.py `T.call`/`T.questions`; Jev cached by
evals/router/jev.py), kept when yes >= 0.6, then the lead-ins dropped (droppingLeadIns: an item ending in ":" unless last).
The bundle is T.questions with the state and waitingOn hints HEAD ships (triage.py still has round-1's): the s<i>
instruction is the same. The app's one-line summary isn't in the transcripts: not sent. The triage (state, work,
unverified) feeds the NEW call's context as the app's does."""
import argparse
import copy
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor

import common as C
import jev  # noqa: E402
import triage as T  # noqa: E402

HEAD_STATE_HINTS = {
    "done": "It completed the work it was asked for and reports it; some follow-through by the user may remain",
    "asks": "It needs the user's answer, decision, review, test or action now before it can go on: questions in prose, or something to choose or decide",
    "approval": "It asks permission before doing something consequential: pushing, publishing, deleting, driving the screen, spending money",
    "blocked": "It hit an error, lacks access or a permission, or can't proceed without help",
    "waiting": "Its work is blocked by a running process, an event or someone other than the user: CI or checks, tests running, a deploy, another session, someone else's review, a rate limit; nothing is needed from the user now",
    "progress": "It reports partial progress and isn't finished, without asking anything",
}
HEAD_REVIEW = "A review by someone other than the user"
S_INSTR = "Does sentence s{i} of the candidate sentences ask the user something, or need their decision or OK?"


def check_head():
    """The hints above and the s<i> instruction are HEAD's (fails loudly if HEAD moved on)."""
    src = subprocess.run(["git", "-C", str(C.REPO), "show", "fe1e147:Sources/FjordComputer/RouterTriage.swift"],
                         capture_output=True, text=True, check=True).stdout
    for hint in list(HEAD_STATE_HINTS.values()) + [HEAD_REVIEW, S_INSTR.replace("{i}", "\\(i)")]:
        assert hint in src, hint[:60]


def bundle(cands):
    q = T.questions(cands)
    q["state"] = T._choice(T.STATES, HEAD_STATE_HINTS, q["state"]["instructions"])
    q["waitingOn"] = copy.deepcopy(q["waitingOn"])
    q["waitingOn"]["criteria"]["review"] = HEAD_REVIEW
    for i in range(len(cands)):
        assert q[f"s{i}"]["instructions"] == S_INSTR.format(i=i)
    return q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    check_head()
    turns = C.jsonl(C.DATA / "turns.jsonl")
    calls = []
    for t in turns:
        st, _, cands = T.call(t["final"], t["title"], t["project"])
        calls.append((st, bundle(cands), cands))

    def one(c):
        try:
            return jev.ask(c[0], c[1])
        except Exception as e:  # noqa: BLE001
            return {"_error": str(e)[:200]}

    with ThreadPoolExecutor(a.workers) as pool:
        res = list(pool.map(one, calls))
    out, bad = [], 0
    for t, (st, q, cands), r in zip(turns, calls, res):
        ans = r.get("answers") if isinstance(r, dict) else None
        if ans is None:
            bad += 1
            out.append({"id": t["id"], "error": (r or {}).get("_error") or "no answers", "candidates": cands, "questions": [],
                        "triage": None})
            continue
        tri = T.parse(ans, cands)          # state, work, unverified, questions (yes >= 0.6) as the app parses them
        yes = [round((ans.get(f"s{i}") or {}).get("noul") or 0, 3) for i in range(len(cands))]
        out.append({"id": t["id"], "candidates": cands, "yes": yes, "kept": tri["questions"],
                    "questions": C.drop_lead_ins(tri["questions"]),
                    "triage": {"state": tri["state"], "work": tri["work"], "unverified": tri["unverified"],
                               "waitingOn": tri["waitingOn"], "kind": T.kind(tri)}})
    C.write_jsonl(C.DATA / "old.jsonl", out)
    import collections
    print("turns", len(out), "Jev failed", bad, "states", collections.Counter((o["triage"] or {}).get("state") for o in out))


if __name__ == "__main__":
    main()
