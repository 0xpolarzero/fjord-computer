"""The explorers' findings in one call: intents worded by who a question is for (intents.py), the tight compound and
second-person gates (intents.py), a "next message in this conversation?" yes/no for the latest sessions (recency.py).
One Jev call, all questions answered in parallel."""
import analyze
import formats as F
import run
from explore import intents as I
from explore import recency as R

GATES = {**F.GATES, "gate_compound2": I.G_COMPOUND_TIGHT, "gate_you": I.G_YOU}


def combo(case, rng=None, nxt=3, nxt_q="next", gates=GATES, crit=I.CRIT_WORDED):
    state, q, keymap = I.make(crit, gates)(case, rng)
    board = case["board"]
    for s in R.finished_by_recency(board)[:nxt]:
        conv = []
        h = R.last_told(board, s)
        if h:
            conv.append({"user": h["you"][:300]})
        said = R.last_said(board, s)
        if said:
            conv.append({"session": said[:400]})
        if conv:
            q[f"gate_next_{s['id']}"] = {"type": "noul", "instructions": {"question": R.NEXT_QUESTIONS[nxt_q],
                                                                          "conversation": conv}}
    return state, q, keymap


FORMATS = {
    "combo": combo,
    "combo-addressed": lambda c, rng=None: combo(c, rng, nxt_q="addressed"),
}


def make_policy(a=0.5, m=0.3, agree=0.4, gc2=0.5, veto=0.5, base=None):
    """1. one latest session stands out on "next message?" (≥ a, ahead by m) and the route agrees, says unclear or is
    under `agree`: send there; 2. else the shipped policy with intents checked by gates (intents.gated_policy)."""
    inner = I.gated_policy(gc2=gc2, veto=veto, veto_gate="gate_you", base=base)

    def pol(r):
        ns = R.nexts(r)
        if ns:
            best, y = ns[0]
            y2 = ns[1][1] if len(ns) > 1 else 0
            top, p = max(r["dests"].items(), key=lambda x: x[1])
            if y >= a and y - y2 >= m and (top in (best, "unclear") or p < agree):
                return ("send", best)
        return inner(r)
    return pol


policy = make_policy()


def recency_ranks(case):
    """Each session's place among the board's latest: finished sessions by how recently (0 = the last to finish);
    running ones count as latest."""
    b = case["board"]
    ranks = {s["id"]: i for i, s in enumerate(R.finished_by_recency(b))}
    for s in b["sessions"]:
        if s.get("running"):
            ranks[s["id"]] = 0
    return ranks


def make_recent_policy(near=3, far_bar=0.9, card_near=2, new_bar_recent=0.8, recent_min=5, **kw):
    """make_policy, knowing the board's recency:
    - a session send outside the `near` latest needs the route at least `far_bar` sure (by route or card check);
    - a card's answer check counts only for the `card_near` latest sessions;
    - a new session needs `new_bar_recent` while a session finished in the last `recent_min` minutes."""
    base = make_policy(**kw)

    def pol(r, case):
        ranks = recency_ranks(case)
        reps = {s: p for s, p in (r.get("replies") or {}).items() if ranks.get(s, 99) < card_near}
        r = {**r, "replies": reps}
        k, w = base(r)
        if k != "send":
            return k, w
        if w in ranks and ranks[w] >= near and r["dests"].get(w, 0) < far_bar:
            return ("ask", run.ranked_targets(r)[:3])
        if w.startswith("new:") and r["dests"].get(w, 0) < new_bar_recent:
            if any(not s.get("running") and s.get("idle_min", 99) <= recent_min for s in case["board"]["sessions"]):
                return ("ask", run.ranked_targets(r)[:3])
        return k, w
    pol.needs_case = True
    return pol


recent = make_recent_policy()
