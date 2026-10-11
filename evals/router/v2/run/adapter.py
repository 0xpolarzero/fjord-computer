"""Adapt redacted v2 state to the existing format and fusion interfaces.

No gold, future events or transcript paths enter a case.  Installing this adapter
replaces lexical's private-corpus seam in memory; legacy source files stay intact.
An empty turns list means unknown in BENCHMARK.md, so board text is the fallback.
"""
import copy
import hashlib
import json
import sys

from . import rules

sys.dont_write_bytecode = True


def legacy_target(target):
    return target[8:] if isinstance(target, str) and target.startswith("session:") else target


def canonical_target(target, state):
    if target is None:
        return None
    if target.startswith("answer:"):
        card = next((c for c in state.get("cards", []) if c["id"] == target[7:]), None)
        return "session:" + card["session"] if card else target
    if target in {s["id"] for s in state.get("sessions", [])}:
        return "session:" + target
    return target


def to_case(state, event=None, *, message=None, context=None, case_id=None):
    """Deep-copy only Router-visible inputs; fingerprint mutable boards for BM25.

    Pills narrow before the shipped format's running/recent candidate cap, just
    like RouterTools.targets. Archived/hidden/addressed cards are not offered.
    Session turns remain available under both board.sessions and case.turns.
    """
    event = event or {}
    context = copy.deepcopy(context if context is not None else event.get("context", {}))
    message = message if message is not None else event.get("message", "")
    projects = list(state.get("projects", []))
    narrowed = rules.pill_projects(state, context)
    sessions = []
    for original in state.get("sessions", []):
        if original.get("archived", False) or (narrowed and original.get("project") not in narrowed):
            continue
        session = copy.deepcopy(original)
        for key, default in (("title", original["id"]), ("project", ""), ("running", False),
                             ("activity", ""), ("summary", ""), ("idle_min", 0), ("turns", [])):
            session.setdefault(key, default)
        sessions.append(session)
    ids = {s["id"] for s in sessions}
    cards = [copy.deepcopy(c) for c in state.get("cards", [])
             if c.get("session") in ids and rules.eligible(state, "answer:" + c["id"])][:60]
    for card in cards:
        card.setdefault("options", [])
        card.setdefault("text", "")
    history = copy.deepcopy(state.get("history", []))
    for row in history:
        row["to"] = legacy_target(canonical_target(row["to"], state))
        if row.get("corrected_from"):
            row["corrected_from"] = legacy_target(canonical_target(row["corrected_from"], state))
        row.setdefault("ago_min", 0)
    history.sort(key=lambda row: -row["ago_min"])
    board = {"projects": [p for p in projects if not narrowed or p in narrowed],
             "sessions": sessions, "cards": cards, "history": history}
    turns = {s["id"]: copy.deepcopy(s["turns"]) for s in sessions}
    visible = {"message": message, "board": board, "context": context, "turns": turns}
    digest = hashlib.sha256(json.dumps(visible, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:20]
    return {"id": f"{case_id or event.get('id', 'v2')}:{digest}", **visible}


def past_turns(case, sid):
    """Safe lexical seam: unknown turns fall back to the board, never disk."""
    if "turns" in case:
        turns = case["turns"].get(sid)
    else:
        session = next((s for s in case.get("board", {}).get("sessions", []) if s["id"] == sid), {})
        turns = session.get("turns")
    if not turns:
        return None
    return [(str(you), str(said)) for you, said in turns]


def _private_data_disabled(*args, **kwargs):
    raise RuntimeError("v2 uses redacted state turns; private corpus access is disabled")


def install_lexical():
    """Patch the confirmed past_turns seam, and fail closed on corpus-IDF calls."""
    from explore import lexical
    lexical.past_turns = past_turns
    lexical.corpus = _private_data_disabled
    lexical._turns = _private_data_disabled
    lexical._corpus_df = _private_data_disabled
    return lexical
