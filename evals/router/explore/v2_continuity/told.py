"""A5 continuity: the next-message check always asked for the last-told session, plus code-side transition features.

Format `combo-o-told`: the shipped `combo-o` call, plus one more "is `message` the user's next message in
`conversation`?" yes/no for the session your previous message went to (the last-told session) when the shipped call
doesn't already ask it (it asks only the 3 latest finished sessions). Its conversation is built exactly as combo's
(what you last told it, ≤ 300 characters; what it last said, ≤ 400), from the same redacted board text, scrubbed again
with `real.boards.redact`. Its answer lands under the same key family (`gate_next_<id>`), so the fusion's `nxt` and
the rules' next-message send read it as they read the others.

Transition features (session destinations only; definitions are the Swift port's):
- lastTold: the offered session your most recent message went to (Swift `Facts.lastTold`).
- prevAgo: minutes since your most recent message (any destination).
- told_fin   lastTold and not running (it finished since your previous message: delivery starts it).
- told_run   lastTold and running.
- finx0      the latest finished session other than lastTold.
- fresh      not lastTold, not running, finished after your previous message (idle < prevAgo).
- backlog    not lastTold, not running, waiting on you (a question/plan/asks/approval card), finished before your
             previous message (idle ≥ prevAgo): a card you had already left waiting.
- told_short lastTold × message of at most 5 words.
- nxt_t      the extra check's answer (0 when the shipped call already checks lastTold or there is none).
"""
import formats as F
from explore import combo
from explore import recency as R
from real.boards import redact

SHORT_WORDS = 5
TRANS = ["told_fin", "told_run", "finx0", "fresh", "backlog", "told_short", "nxt_t"]


def last_told_id(board):
    offered = {s["id"] for s in F.sessions_ordered(board)}
    for h in reversed(board.get("history", [])):   # the adapter keeps history oldest first; deliveries append
        if h.get("to") in offered:
            return h["to"]
    return None


def prev_ago(board):
    h = board.get("history", [])
    return h[-1].get("ago_min", 0) if h else None


def told_extra(case):
    """(session id, question) for the extra check, or None when the shipped call already covers lastTold."""
    board = case["board"]
    sid = last_told_id(board)
    if sid is None:
        return None
    checked = [s["id"] for s in R.finished_by_recency(board)[:3]]
    if sid in checked:
        return None
    s = F.session_by_id(board)[sid]
    conv = []
    h = R.last_told(board, s)
    if h:
        conv.append({"user": redact(h["you"][:300])})
    said = R.last_said(board, s)
    if said:
        conv.append({"session": redact(said[:400])})
    if not conv:
        return None
    return sid, {"type": "noul", "instructions": {"question": R.NEXT_QUESTIONS["next"], "conversation": conv}}


def combo_told(case, rng=None):
    state, q, keymap = combo.combo(case, rng)
    extra = told_extra(case)
    if extra:
        sid, question = extra
        q[f"gate_next_{sid}"] = question
    return state, q, keymap


FORMATS = {"combo-o-told": combo_told}


def transition(case):
    """{session id: {feature: value}} for the offered sessions (TRANS, without nxt_t)."""
    board = case["board"]
    sessions = F.sessions_ordered(board)
    told = last_told_id(board)
    ago = prev_ago(board)
    waits = {c["session"] for c in F.waiting_cards(board)}
    fin = sorted((s for s in sessions if not s.get("running") and s["id"] != told), key=lambda s: s.get("idle_min", 0))
    finx0 = fin[0]["id"] if fin else None
    short = len(case["message"].split()) <= SHORT_WORDS
    out = {}
    for s in sessions:
        sid, run, idle = s["id"], bool(s.get("running")), s.get("idle_min", 0)
        is_told = sid == told
        out[sid] = {
            "told_fin": int(is_told and not run),
            "told_run": int(is_told and run),
            "finx0": int(sid == finx0),
            "fresh": int(not is_told and not run and ago is not None and idle < ago),
            "backlog": int(not is_told and not run and sid in waits and ago is not None and idle >= ago),
            "told_short": int(is_told and short),
        }
    return out


def extend(base_features):
    """Wrap a features(r, case) function with the transition features and nxt_t."""
    def features(r, case):
        out = base_features(r, case)
        if not out:
            return out
        tr = transition(case)
        extra = told_extra(case)
        g = r.get("gates") or {}
        for d, f in out.items():
            if f.get("sess"):
                f.update(tr.get(d, {}))
                f["nxt_t"] = g.get(f"gate_next_{d}", 0) if extra and extra[0] == d else 0
        return out
    features._told = True
    return features
