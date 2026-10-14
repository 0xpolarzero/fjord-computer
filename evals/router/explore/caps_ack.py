"""The acknowledgement set (40 cases) and the A/B split of the real dev episodes for the `capabilities-o` experiment.

Each case is a v2 episode (schema 2, one submit): the board is the starting state of a REAL dev episode (already
redacted, never committed), the message a template filled with a real session's title from that board. Gold:
  change     "seen the X", "mark X as seen", "got it, read the headlines": Lookout itself (change_fjord)
  session    instructions or replies for a session, however much they mention "seen"/"read": that session
  mixed      an acknowledgement plus a request for someone else: compound or change_fjord (a session drops half of it)
The templates are committed; the boards and filled messages go to v2/data/exp/ (gitignored).

python3 -m explore.caps_ack            (from evals/router) writes v2/data/exp/ack.jsonl, real_A.jsonl, real_B.jsonl"""
import hashlib
import json
import pathlib
import random

HERE = pathlib.Path(__file__).resolve().parents[1]
DEV = HERE / "v2" / "data" / "episodes" / "dev" / "episodes.jsonl"
OUT = HERE / "v2" / "data" / "exp"
CONTEXT = {"replyTo": None, "pinned": None, "pills": [], "notTo": None, "shown": None, "router_aside": False}

# (category, gold, need, template). need: board requirement; {t} the target session's title, {u} another session's
# title, {p} a project. gold "session" = that session; "change" = change_fjord; "mixed" = compound or change_fjord.
CASES = [
    ("seen", "change", "done", "seen {t}"),
    ("seen", "change", "done", "got it, read the headlines"),
    ("seen", "change", "done", "I've looked at {t}"),
    ("seen", "change", "done", "ok I read {t}, mark it as seen"),
    ("seen", "change", "done", "mark {t} as done"),
    ("seen", "change", "done", "seen the {t} one, thanks"),
    ("seen", "change", "done", "I saw {t}, you can clear that card"),
    ("seen", "change", "done", "read it all, mark everything as seen"),
    ("seen", "change", "done", "I've gone through the cards, mark them seen"),
    ("seen", "change", "done", "got it, seen the {t} summary"),
    ("seen", "change", "done", "done reading {t}"),
    ("seen", "change", "done", "seen {t}. all good"),
    ("negation", "session", "done", "haven't seen {t} yet, tell it to wait"),
    ("negation", "session", "done", "I haven't read {t} yet, tell it to hold on before pushing"),
    ("negation", "session", "done", "not seen {t} yet, ask it to wait for me"),
    ("negation", "session", "done", "haven't looked at {t} yet, tell that one to pause"),
    ("quoted", "session", "done", "in {t} it said \"seen the logs, nothing wrong\" but the tests still fail, tell it to look again"),
    ("quoted", "session", "done", "tell {t} that I wrote \"got it, read the headlines\" in the PR and it should reply"),
    ("quoted", "session", "done", "{t} printed \"seen 12 files\" but there are 40, ask it why"),
    ("to-session", "session", "done", "{t}: check it on mobile"),
    ("to-session", "session", "done", "tell {t} to check it on mobile"),
    ("to-session", "session", "done", "{t}, run the tests again"),
    ("to-session", "session", "done", "{t}: seen your summary, now push the branch"),
    ("to-session", "session", "done", "{t}: ok I read it, continue with the next step"),
    ("to-session", "session", "done", "tell {t} I've seen the draft and it can publish"),
    ("to-session", "session", "done", "ask {t} to double check the copy"),
    ("to-session", "session", "done", "{t}: ok got it, go on"),
    ("duplicate", "change", "dup", "seen {t}"),
    ("duplicate", "change", "dup", "I've looked at {t}"),
    ("duplicate", "change", "dup", "mark {t} as seen"),
    ("duplicate", "change", "dup", "got it, read {t}"),
    ("approval", "session", "approval", "yes approve it"),
    ("approval", "session", "approval", "go ahead, allow it"),
    ("approval", "session", "approval", "approved"),
    ("approval", "change", "approval", "I've seen the {t} approval request, mark it as seen for now"),
    ("approval", "change", "approval", "seen the approval from {t}, I'll deal with it later"),
    ("mixed", "mixed", "two", "seen {t}, and tell {u} to push the branch"),
    ("mixed", "mixed", "done", "mark {t} as seen and mute the notifications for a while"),
    ("mixed", "mixed", "done", "I read {t}, now tell it to merge"),
    ("mixed", "mixed", "project", "got it on {t}, and start a session in {p} to fix the typo"),
]
assert len(CASES) == 40


def sid_of(episode):
    return episode["group"].split(":")[0]


def half(sid):
    """realA / realB exactly as bench.half (by the session id)."""
    return "A" if int(hashlib.sha256(sid.encode()).hexdigest(), 16) % 2 == 0 else "B"


def live(state):
    return [s for s in state["sessions"] if not s.get("archived")]


def titles(state):
    out = {}
    for s in live(state):
        out.setdefault(s["title"].strip().lower(), []).append(s)
    return out


def done_sessions(state, unique=True):
    t = titles(state)
    by = {s["id"]: s for s in live(state)}
    out = []
    for c in state["cards"]:
        s = by.get(c["session"])
        if (c["kind"] == "done" and s and not s.get("running") and 3 <= len(s["title"]) <= 45 and "<" not in s["title"]
                and (len(t[s["title"].strip().lower()]) == 1) == unique and s not in out):
            out.append(s)
    return out


def pick_for(need, state, rng):
    """(target session or None, other session or None, project or None) when the board suits, else None."""
    if len(live(state)) < 3:
        return None
    if need == "dup":
        c = done_sessions(state, unique=False)
        return (rng.choice(c), None, None) if c else None
    if need == "approval":
        approvals = [c for c in state["cards"] if c["kind"] == "approval"]
        by = {s["id"]: s for s in live(state)}
        if len(approvals) != 1 or approvals[0]["session"] not in by:
            return None
        return by[approvals[0]["session"]], None, None
    c = done_sessions(state)
    if not c:
        return None
    t = rng.choice(c)
    if need == "two":
        others = [s for s in c if s["id"] != t["id"]]
        return (t, rng.choice(others), None) if others else None
    if need == "project":
        return (t, None, rng.choice(state["projects"])) if state["projects"] else None
    return t, None, None


def build(seed=11):
    rng = random.Random(seed)
    eps = [json.loads(line) for line in open(DEV)]
    real = [e for e in eps if e["provenance"]["source"] == "real-moment"]
    order = list(range(len(real)))
    rng.shuffle(order)
    used, out = set(), []
    for n, (cat, gold, need, template) in enumerate(CASES):
        for i in order:
            e = real[i]
            if e["group"] in used:
                continue
            picked = pick_for(need, e["state"], rng)
            if picked is None:
                continue
            used.add(e["group"])
            t, u, p = picked
            has_t = "{t}" in template
            message = template.format(t=t["title"].strip() if t else "", u=u["title"].strip() if u else "", p=p or "")
            if gold == "session":
                intended, acceptable = "session:" + t["id"], ["session:" + t["id"]]
            elif gold == "change":
                intended, acceptable = "change_fjord", ["change_fjord"]
            else:
                intended, acceptable = "compound", ["compound", "change_fjord"]
            out.append({
                "schema": 2, "id": f"ack-{n:02d}-{cat}", "family": cat, "group": f"ack:{e['group']}",
                "provenance": {"source": "ack", "synthetic": ["message"], "board": e["id"]},
                "tags": {"primary": cat, "gold": gold}, "state": e["state"],
                "events": [{"id": "e1", "kind": "submit", "message": message, "context": CONTEXT,
                            "gold": {"intended": intended, "acceptable": acceptable, "clarify": [], "ask": "allowed",
                                     "consequential": False, "evidence": f"ack set: {cat}, {gold}"}}]})
            break
        else:
            raise SystemExit(f"no board for case {n} {template!r}")
    return out, real


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ack, real = build()
    (OUT / "ack.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in ack))
    for h in "AB":
        part = [e for e in real if half(sid_of(e)) == h]
        (OUT / f"real_{h}.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in part))
        print(f"real_{h}: {len(part)} episodes, {sum(ev['kind'] == 'submit' for e in part for ev in e['events'])} submits")
    print(f"ack: {len(ack)} cases")


if __name__ == "__main__":
    main()
