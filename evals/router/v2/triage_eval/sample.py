"""Triage eval, step 1: ~500 real finished turns, stratified by today's card kind, with what you did next.

    python3 v2/triage_eval/sample.py [--n 500] [--seed 7]  →  v2/data/triage_eval/turns.jsonl

The pool: every turn card on the boards of v2/data/states/moments.jsonl (its kind is today's triage, stage A, cached).
Each turn is rebuilt from the transcripts with v2/build/states.py's own reader (the same final message Lookout reads,
`Claude.finalMessage`), so the old triage's inputs are byte-identical to stage A's. Per turn: the final message, title
and project (redacted, `real/boards.py` `redact`), and what came next in that session: the next prompt (yours, a peer's,
a task notification, a CI monitor event), when, and your next typed message (redacted, cut to 1500 chars).
Nothing raw is written."""
import argparse
import collections
import json
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path.insert(0, str(ROUTER / "v2" / "build"))
sys.path.insert(0, str(ROUTER / "real"))
import states as S  # noqa: E402
from boards import KEEP, redact  # noqa: E402

OUT = ROUTER / "v2" / "data" / "triage_eval"
QUOTAS = {"done": 215, "asks": 150, "waiting": 85, "approval": 55, "stuck": 28}
CI_EVENT = re.compile(r"^\s*<ci-monitor-event")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    pool = {}
    for line in open(ROUTER / "v2" / "data" / "states" / "moments.jsonl"):
        for c in json.loads(line)["state"]["cards"]:
            if "#t" in c["id"] and c.get("triage") is not None:
                pool[c["id"]] = c
    print("pool", len(pool), collections.Counter(c["kind"] for c in pool.values()))

    files = S.load_files()
    sessions = {s.short: s for s in (S.Session(f) for f in files if f["entry"] == "claude-desktop") if s.start is not None}
    rng = random.Random(a.seed)
    by_kind = collections.defaultdict(list)
    for cid in sorted(pool):
        by_kind[pool[cid]["kind"]].append(cid)
    picked = []
    for kind, n in QUOTAS.items():
        ids = by_kind[kind][:]
        rng.shuffle(ids)
        picked += ids[:n]

    OUT.mkdir(parents=True, exist_ok=True)
    n_out = 0
    with open(OUT / "turns.jsonl", "w") as out:
        for cid in picked:
            short, n = cid.split("#t")
            s = sessions.get(short)
            if s is None or s.project not in KEEP:
                continue
            turn = s.turns[int(n) - 1]
            if not turn["final"]:
                continue
            end = turn["end"]
            # What came next in the session: the first prompt after the turn ended (yours by when you typed it).
            nxt = sorted((p for p in s.prompts if (p.get("typed", p["t"]) if p["kind"] == "human" else p["t"]) > end),
                         key=lambda p: p.get("typed", p["t"]) if p["kind"] == "human" else p["t"])
            first = nxt[0] if nxt else None
            human = next((p for p in nxt if p["kind"] == "human" and not CI_EVENT.match(p["text"])), None)
            agent_before = [p for p in nxt if (p["kind"] == "agent" or CI_EVENT.match(p["text"]))
                            and (human is None or p["t"] < human["typed"])]
            # A form answered later in the same session (an AskUserQuestion of the next turn) is not this turn's.
            rec = {
                "id": cid, "kind_today": pool[cid]["kind"], "triage_today": pool[cid]["triage"], "project": s.project,
                "title": redact(s.title_at(end)), "final": redact(turn["final"]), "end": S.iso(end),
                "interrupted": turn["interrupted"],
                "next_kind": None if first is None else ("ci" if CI_EVENT.match(first["text"]) else first["kind"]),
                "next_gap_min": None if first is None else round(((first.get("typed", first["t"]) if first["kind"] == "human" else first["t"]) - end) / 60, 1),
                "reply_gap_min": None if human is None else round((human["typed"] - end) / 60, 1),
                "reply": None if human is None else redact(human["text"])[:1500],
                "agent_before_reply": [("ci" if CI_EVENT.match(p["text"]) else "agent", round((p["t"] - end) / 60, 1),
                                        redact(p["text"])[:200]) for p in agent_before[:3]],
                "later_turns": len(s.turns) - int(n),
            }
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            n_out += 1
    print("wrote", n_out)


if __name__ == "__main__":
    main()
