"""Lookout's `evidenced` veto (RouterDispatcher.evidenced), ported: a send to a session or card needs the message to share
a meaningful word or a short name with it, or to follow your own message to it within 10 minutes with no other session
waiting on you. Wraps a policy: a vetoed send becomes an ask."""
import re

import formats

COMMON = set("the and for with this that these those from into onto you your please can could would should will what when "
             "where which who why how about then than them they have has had not are was were its our out all any some just "
             "also now new session project card does did but yes too there here let one get make use need want like ok okay "
             "thanks".split())
SHORT_COMMON = set("to in on it is of at an be do go me my no so up us we or if as by he hi am".split())


def tokens(text):
    return re.findall(r"[^\W_]+", text.lower())


def meaningful(text):
    return {w for w in tokens(text) if len(w) >= 3 and w not in COMMON}


def short_names(text):
    return {w for w in tokens(text) if 2 <= len(w) <= 3 and w not in COMMON and w not in SHORT_COMMON}


def evidenced(case, dest):
    board = case["board"]
    by = formats.session_by_id(board)
    if dest not in by:
        return True
    s = by[dest]
    names = [s["title"], s["project"]]
    about = [s.get("activity", ""), s.get("summary", "")]
    for c in board.get("cards", []):
        if c["session"] == dest:
            about += [c["text"]] + c.get("options", [])
    waiting = {c["session"] for c in formats.waiting_cards(board)}
    hist = board.get("history", [])
    if hist and hist[-1]["to"] == dest and hist[-1]["ago_min"] < 10 and not (waiting - {dest}):
        return True
    said = meaningful(case["message"])
    theirs = meaningful(" ".join(names + about))
    for w in said:
        for t in theirs:
            if w == t or (min(len(w), len(t)) >= 4 and (w.startswith(t) or t.startswith(w))):
                return True
    return bool(short_names(case["message"]) & short_names(" ".join(names)))


def wrap(policy, cases):
    by = {c["id"]: c for c in cases}

    def pol(r, case_id):
        kind, what = policy(r)
        if kind == "send" and not evidenced(by[case_id], what):
            return ("ask", [what])
        return kind, what
    return pol
