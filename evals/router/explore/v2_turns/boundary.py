"""A8 check: where transcript turns and the board fallback cut a session's turns, on the frozen base moments (counts only).

Transcript (RouterLexical.turns, working): [..., (you_-2, said_-2), (you_-1, "")]
Board (RouterLexical.boardTurns / lexical.board_fields "turns"): [(told[:-1], summary + activity), (told[-1], cards)]

python3 -m explore.v2_turns.boundary
"""
import collections
import sys

sys.dont_write_bytecode = True

from explore.v2_turns import analyze as A


def main():
    mb = A.moments("base")
    c = collections.Counter()
    for x in mb.values():
        case = x.m["case"]
        cards = collections.Counter(cd["session"] for cd in case["board"]["cards"])
        told = collections.Counter(h["to"] for h in case["board"]["history"])
        for s in case["board"]["sessions"]:
            run = "running" if s.get("running") else "idle"
            turns = case["turns"].get(s["id"]) or []
            c[f"{run} sessions"] += 1
            c[f"{run}: no transcript turns (board fallback)"] += not turns
            c[f"{run}: open cards on the board"] += cards[s["id"]] > 0
            c[f"{run}: told by Lookout (history)"] += told[s["id"]] > 0
            c[f"{run}: activity line"] += bool(s.get("activity"))
            if turns:
                c[f"{run}: latest turn has no answer"] += not turns[-1][1]
                c[f"{run}: latest you == last told"] += bool(told[s["id"]]) and turns[-1][0].strip()[:80] == next(
                    h["you"] for h in sorted(case["board"]["history"], key=lambda h: h["ago_min"]) if h["to"] == s["id"]).strip()[:80]
                if s.get("running"):
                    c["running: open cards while working (board f_said would keep them, transcript blanks)"] += cards[s["id"]] > 0
    for k in sorted(c):
        print(f"{k}: {c[k]}")


if __name__ == "__main__":
    main()
