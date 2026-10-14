"""Shared helpers for the action-labelled sets (v2/ACTIONS.md): action targets, their legacy projection, gold, splits."""
import hashlib
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
V2 = HERE.parent
OUT = V2 / "data" / "actions"
GROUPS = V2 / "data" / "episodes" / "groups.json"
CONTEXT = {"replyTo": None, "pinned": None, "pills": [], "notTo": None, "shown": None, "router_aside": False}

VERBS = {"say", "answer", "approve", "ack", "stop", "interrupt", "start", "configure", "ask_fjord",
         "archive", "reopen", "mute", "unmute"}
PROPOSALS = {"archive", "reopen", "mute", "unmute"}
NEEDS_YOU = {"question", "plan", "asks", "approval", "stuck"}
FORMS = {"question", "plan"}


def parse(action):
    """(verb, kind, id) of an action target; a target without a prefix is a `say`."""
    if action in ("configure", "ask_fjord", "compound"):
        return action, None, None
    head, _, rest = action.partition(":")
    if head in ("session", "new"):
        return ("say", "session", rest) if head == "session" else ("start", "new", rest)
    kind, _, ident = rest.partition(":")
    if head not in VERBS or not ident:
        raise ValueError(f"not an action target: {action!r}")
    return head, kind, ident


def card_session(card_id, state=None):
    for c in (state or {}).get("cards", []):
        if c["id"] == card_id:
            return c["session"]
    return card_id.split("#")[0]


def legacy(action, state=None):
    """The destination today's runner scores (BENCHMARK.md targets)."""
    verb, kind, ident = parse(action)
    if verb in ("say", "interrupt"):
        return "session:" + ident
    if verb in ("answer", "approve"):
        return "session:" + card_session(ident, state)
    if verb == "start":
        return "new:" + ident
    if verb == "ask_fjord":
        return "question"
    if verb == "compound":
        return "compound"
    return "change_fjord"            # ack, stop, configure and the proposal class


def gold(intended, acceptable, state, *, ask="allowed", clarify=(), consequential=False, evidence="",
         precondition="met", method="template", legacy_acceptable=None):
    """Gold with both the action fields and their legacy projection (v2/ACTIONS.md)."""
    acceptable = list(dict.fromkeys(acceptable))
    for a in [intended, *acceptable, *clarify]:
        parse(a)
    if any(parse(a)[0] in PROPOSALS for a in acceptable) and "configure" not in acceptable:
        acceptable.append("configure")
    if legacy_acceptable is None:
        # An interrupt projects to a plain send, which is the wrong thing when an interrupt was wanted.
        wrong_legacy = {legacy(a, state) for a in clarify}
        if parse(intended)[0] == "interrupt":
            wrong_legacy.add(legacy(intended, state))
        legacy_acceptable = [legacy(a, state) for a in acceptable if parse(a)[0] != "interrupt"]
        legacy_acceptable = [t for t in dict.fromkeys(legacy_acceptable) if t not in wrong_legacy]
    return {"intended": legacy(intended, state), "acceptable": legacy_acceptable,
            "clarify": list(dict.fromkeys(legacy(a, state) for a in clarify)), "ask": ask,
            "consequential": consequential, "evidence": evidence,
            "intended_action": intended, "acceptable_actions": acceptable, "clarify_actions": list(clarify),
            "precondition": precondition, "label_method": method}


def hash_split(group, calib_share=1 / 3, salt="actions-v1"):
    h = int(hashlib.sha256(f"{salt}:{group}".encode()).hexdigest(), 16) % 1000
    return "calib" if h < calib_share * 1000 else "dev"


def frozen():
    return json.loads(GROUPS.read_text()) if GROUPS.exists() else {}


def write(path, episodes):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.writelines(json.dumps(e, ensure_ascii=False) + "\n" for e in episodes)
