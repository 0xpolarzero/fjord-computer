"""Two passes: a saved wide run (every destination) narrows to its top K; a second call chooses among those with more
detail on each. The second pass's answer replaces the route; the wide run's reply checks are kept.

python3 rerank.py WIDE_RUN [--k 4] [--variant full|lean] [--pad N]"""
import argparse
import json

import formats
import jev
import run

RERANK_INSTRUCTIONS = {
    "question": "Exactly one of these is where the user's `message` goes, or `none of these`. Which?",
    "focus": ("Read what each one is doing and what the user last told it. Decide about `message` alone; `earlier "
              "messages` only say what it refers to. A question about a session or about what is going on is "
              "`question`, not a message to the session."),
}


def candidate(board, dest, variant):
    by = formats.session_by_id(board)
    if dest in by:
        s = by[dest]
        crit = {"kind": "Claude Code session", "title": s["title"], "project": s["project"],
                "now": formats.session_status(board, s)}
        if variant == "full":
            told = [h for h in board.get("history", []) if h["to"] == dest]
            if told:
                crit["the user last told it"] = f"{told[-1]['you'][:200]} ({formats.ago(told[-1]['ago_min'])})"
            if s.get("summary") and s.get("summary") not in crit["now"]:
                crit["earlier"] = s["summary"][:300]
        return s["title"][:80], crit
    if dest.startswith("new:"):
        return f"new session in {dest[4:]}", {"kind": "new session", "project": dest[4:]}
    return dest, formats.INTENTS.get(dest, dest)


def build(case, dests, variant="full"):
    board = case["board"]
    names, crit, keymap = set(), {}, {}
    for d in dests:
        name, c = candidate(board, d, variant)
        while name in names:
            name += "'"
        names.add(name)
        crit[name] = c
        keymap[name] = d
    crit["none of these"] = formats.UNCLEAR_V2
    keymap["none of these"] = "unclear"
    _, names_all = formats.session_options(board)
    state = {"message": case["message"], **formats.history_state(board, names_all, "last10")}
    return state, {"route": {"type": "choice", "instructions": RERANK_INSTRUCTIONS, "criteria": crit}}, keymap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wide")
    ap.add_argument("--k", type=int, default=4)
    ap.add_argument("--variant", default="full")
    ap.add_argument("--pad", type=int)
    ap.add_argument("--cases", default="cases/*.jsonl")
    a = ap.parse_args()
    cases = {c["id"]: c for c in run.load_cases(a.cases)}
    if a.pad:
        import transforms
        cases = {i: transforms.pad(c, a.pad) for i, c in cases.items()}
    wide = run.load(a.wide)
    calls, meta = [], []
    for row in wide:
        r = run.reading(row)
        top = run.ranked_targets(r)[:a.k]
        state, q, keymap = build(cases[row["id"]], top, a.variant)
        calls.append((state, q))
        meta.append((row, keymap))
    answers = jev.ask_many(calls)
    out = []
    for (row, keymap), ans in zip(meta, answers):
        new = dict(row)
        new["answers"] = {**{k: v for k, v in row["answers"].items() if k.startswith("answers")}, "route": ans["answers"]["route"]}
        new["keymap"] = {**{k: v for k, v in row["keymap"].items() if k.startswith("answers")}, **keymap}
        new["latency"] = (row.get("latency") or 0) + (ans.get("_latency") or 0)
        out.append(new)
    name = f"{a.wide}+rr{a.k}{a.variant}"
    run.save(name, out)
    run.report(name, list(cases.values()), out)


if __name__ == "__main__":
    main()
