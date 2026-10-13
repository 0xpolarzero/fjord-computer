"""Deterministic Router dispatch, mirrored from the Swift desktop dispatcher.

The policy supplies confidence; this module never invents a probability threshold.
``plan`` mirrors RouterDispatcher.plan, followed by the carried live-chip path.
``post_jev`` mirrors classifyAndAct's ordered overrides and vetoes. Targets in
results use the v2 vocabulary: an ``answer:<card>`` becomes ``session:<id>``.

The v2 schema stores pill project names rather than character ranges. We recover
ranges only for literal, whole @names, and use the names to narrow projects. A
``shown`` target is the sure live chip displayed for these exact words; optional
``context.jev`` can carry its ranking, ``sure`` and ``assisted`` explicitly.
Cards default to open and visible, as in the schema. Optional hidden/closed/
addressedAt/shown flags and state.tasks represent Swift visibility when known.
Source: Sources/Fjord/{RouterDispatcher,RouterMCP,RouterPrepare}.swift.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

INTENTS = frozenset({"change_fjord", "question", "compound"})

# SessionStart.requestBoundary and startPhrase, kept literal so punctuation
# joined to "session" cannot turn a feature name into a start request.
REQUEST_BOUNDARY = (
    r"(?=[ \t]*(?:$|\n|[,:;.!?](?=\s|$))|[ \t]+(?:[\-–—](?=[ \t])|\()|"
    r"[ \t]+(?:(?:to|in|on|inside|for|about|and|then|that|at)\b|"
    r"(?:with|using|use|on)\s+(?:the\s+)?"
    r"(?:opus|sonnet|haiku|fable|low|medium|high|xhigh|max|effort)\b))"
)
START_PHRASE = (
    r"^(?:(?:please|pls|hey|can\s+you|could\s+you|i\s+want\s+you\s+to|"
    r"i'd\s+like\s+you\s+to)[,\s]+)?"
    r"(?:(?:start|open|create|launch|spin\s+up|kick\s+off|begin)\s+"
    r"(?:up\s+)?(?:an?\s+|the\s+|one\s+)?(?:new\s+|fresh\s+)?"
    r"(?:claude\s+)?(?:session|chat|conversation)|"
    r"(?:in\s+)?(?:an?\s+)?(?:new|fresh)\s+(?:claude\s+)?"
    r"(?:session|chat|conversation))" + REQUEST_BOUNDARY
)
GOES_ON = r"(?=[ \t]*(?:$|\n|[,:;.!?\-–—]|(?:to|and|then|with|using|at)\b))"
NEGATIONS = frozenset(
    "no not never none nothing nobody nowhere neither nor without dont don't "
    "cannot can't cant won't wont stop avoid".split()
)
NOT_ADDRESSEES = frozenset(
    "me us you it them him her we they i myself yourself ourselves themselves "
    "everyone everybody someone somebody anyone anybody all each nobody people "
    "folks guys team whoever note notes nb fyi ps pps todo also btw tldr tl;dr re "
    "edit update question answer reply q a idea reminder warning important context "
    "summary status reason why how what so and but then now here there this that "
    "yes no ok okay thanks hi hey hello please example e.g i.e result results error "
    "issue problem plan next done later first finally anyway well".split()
) | {"all of you", "no one", "to do"}
COMMON = frozenset(
    "the and for with this that these those from into onto you your please can "
    "could would should will what when where which who why how about then than "
    "them they have has had not are was were its our out all any some just also "
    "now new session project card does did but yes too there here let one get make "
    "use need want like ok okay thanks to in on it is of at an be do go me my no "
    "so up us we or if as by he hi am".split()
)


def _sessions(state: Mapping[str, Any]) -> list[dict[str, Any]]:
    return list(state.get("sessions", []))


def _cards(state: Mapping[str, Any]) -> list[dict[str, Any]]:
    return list(state.get("cards", []))


def _session_id(card: Mapping[str, Any]) -> str:
    return str(card.get("session", card.get("sessionID", "")))


def _basename(project: str) -> str:
    return project.rstrip("/").rsplit("/", 1)[-1]


def _project_name(state: Mapping[str, Any], project: str) -> str:
    return str(state.get("project_names", {}).get(project, _basename(project)))


def _card_project(state: Mapping[str, Any], card: Mapping[str, Any]) -> str:
    if "project" in card or "folder" in card:
        return str(card.get("project", card.get("folder", "")))
    return next((str(s.get("project", "")) for s in _sessions(state)
                 if s["id"] == _session_id(card)), "")


def _open(card: Mapping[str, Any]) -> bool:
    return not (card.get("closed") or card.get("addressed") or card.get("addressedAt"))


def _shown(state: Mapping[str, Any], card: Mapping[str, Any]) -> bool:
    if not _open(card) or card.get("hidden") or card.get("shown") is False:
        return False
    # RouterPage.shows hides done cards when that session's tasks still run.
    return not (card.get("kind") == "done"
                and state.get("tasks", {}).get(_session_id(card)))


def canonical_target(state: Mapping[str, Any], target: str | None) -> str | None:
    """Collapse card replies to their session, as required by the v2 schema."""
    if target and target.startswith("answer:"):
        card = next((c for c in _cards(state) if c["id"] == target[7:]), None)
        return "session:" + _session_id(card) if card else None
    return target


def eligible(state: Mapping[str, Any], target: str | None) -> bool:
    """RouterDispatcher.eligible: gate Jev/live sends and explicit ask picks."""
    if not target:
        return False
    if target.startswith("answer:"):
        return any(c["id"] == target[7:] and _shown(state, c) for c in _cards(state))
    if target.startswith("session:"):
        return any(s["id"] == target[8:] and not s.get("archived", False)
                   for s in _sessions(state))
    if target.startswith("new:"):
        return target[4:] in state.get("projects", [])
    # Swift's gate accepts every intent-shaped string; route rejects unknowns.
    return target in INTENTS


def pill_projects(state: Mapping[str, Any], context: Mapping[str, Any]) -> list[str]:
    """Resolve v2 pill names to known project keys, preserving composer order."""
    known = list(state.get("projects", []))
    names = context.get("projects", context.get("pills", []))
    result = []
    for name in names:
        if not isinstance(name, str):
            continue
        fits = [p for p in known if p == name or _project_name(state, p) == name
                or _basename(p) == name]
        project = name if name in known or len(fits) != 1 else fits[0]
        if project not in result:
            result.append(project)
    return result


def pill_ranges(message: str, pills: Sequence[str] = ()) -> list[tuple[int, int]]:
    """Swift tests' recorded-pill helper; names are data, never regex syntax."""
    names = sorted((n for n in pills if isinstance(n, str)), key=len, reverse=True)
    ranges = []
    for i, char in enumerate(message):
        if char != "@":
            continue
        for name in names:
            tag = "@" + name
            end = i + len(tag)
            if not message.startswith(tag, i):
                continue
            if end < len(message) and (message[end].isalnum() or message[end] in "./-_"):
                continue
            ranges.append((i, end))
            break
    return ranges


def _code_mask(text: str) -> list[bool]:
    """Port Addressing.codeMask: fences, four-space/tab lines, inline backticks."""
    mask = [False] * len(text)
    start, fenced = 0, False
    for line_with_end in text.splitlines(keepends=True):
        line = line_with_end.rstrip("\r\n")
        fence_count = line.count("```")
        if fence_count % 2:
            fenced = not fenced
            mask[start:start + len(line)] = [True] * len(line)
        elif fenced or line.startswith(("    ", "\t")):
            mask[start:start + len(line)] = [True] * len(line)
        else:
            k = 0
            while k < len(line):
                if line[k] != "`":
                    k += 1
                    continue
                run = 1
                while k + run < len(line) and line[k + run] == "`":
                    run += 1
                j, close = k + run, None
                while j < len(line):
                    if line[j] != "`":
                        j += 1
                        continue
                    length = 1
                    while j + length < len(line) and line[j + length] == "`":
                        length += 1
                    if length == run:
                        close = j + length
                        break
                    j += length
                if close is None:
                    k += run
                else:
                    mask[start + k:start + close] = [True] * (close - k)
                    k = close
        start += len(line_with_end)
    return mask


def _quote_mask(text: str, code: Sequence[bool]) -> list[bool]:
    mask = [False] * len(text)
    k = 0
    while k < len(text):
        if code[k] or text[k] not in '\"“':
            k += 1
            continue
        close = '\"' if text[k] == '\"' else "”"
        j = k + 1
        while j < len(text) and text[j] not in "\r\n" and (code[j] or text[j] != close):
            j += 1
        if j == len(text) or text[j] in "\r\n":
            k += 1
        else:
            mask[k:j + 1] = [True] * (j + 1 - k)
            k = j + 1
    return mask


def _is_marker(text: str, i: int) -> bool:
    end = i + len("@router")
    if text[i:end].lower() != "@router":
        return False
    if i and text[i - 1].isalnum():
        return False
    if end < len(text):
        after = text[end]
        if after.isalnum() or after == "/":
            return False
        if after in ".-_@" and end + 1 < len(text) and text[end + 1].isalnum():
            return False
    return True


def aside_ranges(text: str) -> list[tuple[int, int]]:
    """Only balanced brackets on one line or whole @router lines are asides."""
    code = _code_mask(text)
    quoted = _quote_mask(text, code)
    found: list[tuple[int, int]] = []
    start = 0
    for line_with_end in text.splitlines(keepends=True):
        line = line_with_end.rstrip("\r\n")
        end = start + len(line)
        first = start
        while first < end and text[first] == " " and first - start < 3:
            first += 1
        if first < end and not code[first] and _is_marker(text, first):
            stop = start + len(line_with_end)
            if stop > end:
                found.append((start, stop))
            elif found and found[-1][1] == start:
                found[-1] = (found[-1][0], end)
            else:
                found.append((start - 1 if start else 0, end))
            start += len(line_with_end)
            continue
        k = start
        while k < end:
            if code[k] or quoted[k] or text[k] not in "([":
                k += 1
                continue
            opening = text[k]
            closing = ")" if opening == "(" else "]"
            m = k + 1
            while m < end and text[m] in " \t":
                m += 1
            if m == end or code[m] or not _is_marker(text, m):
                k += 1
                continue
            depth, stop = 0, None
            for j in range(k, end):
                if not code[j] and text[j] == opening:
                    depth += 1
                elif not code[j] and text[j] == closing:
                    depth -= 1
                    if depth == 0:
                        stop = j + 1
                        break
            if stop is None:
                k += 1
                continue
            left = k
            while left > start and text[left - 1] in " \t":
                left -= 1
            if left == start:
                while stop < end and text[stop] in " \t":
                    stop += 1
            found.append((left, stop))
            k = stop
        start += len(line_with_end)
    return found


def without_leading_pills(message: str, pills: Sequence[str] = ()) -> str | None:
    code = _code_mask(message)
    ends = {a: b for a, b in pill_ranges(message, pills) if not code[a]}
    cut = 0
    while True:
        i = cut
        while i < len(message) and message[i] in " \t":
            i += 1
        end = ends.get(i)
        if end is None:
            break
        k = end
        if k < len(message) and not (message[k].isspace() or message[k] in ":,—–"):
            break
        while k < len(message) and message[k] in " \t":
            k += 1
        if k < len(message) and message[k] in ":,—–":
            k += 1
            while k < len(message) and message[k] in " \t":
                k += 1
            if k < len(message) and message[k] == "\r":
                k += 1
            if k < len(message) and message[k] == "\n":
                k += 1
        cut = k
    return message[cut:] if cut and message[cut:].strip() else None


def edit(message: str, pills: Sequence[str] = (), *, envelope: bool = True) -> str:
    """Addressing.edit's text; an empty return is Swift's NothingLeft error."""
    text = (without_leading_pills(message, pills) or message) if envelope else message
    for a, b in reversed(aside_ranges(text)):
        text = text[:a] + text[b:]
    return text.rstrip() if text != message else text


def for_router(message: str, context: Mapping[str, Any] | None = None) -> bool:
    # router_aside marks the presence of an aside, not whether all words are it.
    return bool(aside_ranges(message)) and not edit(message, (context or {}).get("pills", [])).strip()


def past_leading_tags(message: str, pills: Sequence[str] = ()) -> str:
    text = without_leading_pills(message, pills) or message
    return re.sub(r"^(?:\s*@[\w.\-/]+[\s,:;]*)*\s*", "", text)


def wants_new_session(message: str, pills: Sequence[str] = ()) -> bool:
    return re.search(START_PHRASE, past_leading_tags(message, pills), re.I) is not None


def start_request(message: str, pills: Sequence[str] = ()) -> dict[str, str | None] | None:
    pattern = START_PHRASE + (
        r"(?:\s+in\s+(?:the\s+)?([\w.\-]+)(?![\w./-])"
        r"(?:\s+(?:project|repo|repository|folder))?" + GOES_ON + r")?"
    )
    match = re.search(pattern, past_leading_tags(message, pills), re.I)
    if match is None:
        return None
    project = match.group(1).lower() if match.group(1) else None
    return {"project": None if project in NEGATIONS else project}


def spoken_addressee(message: str) -> str | None:
    polite = r"(?:(?:please|pls|hey|ok|okay|can\s+you|could\s+you|would\s+you)[,\s]+)?"
    patterns = (
        r"^\s*" + polite + r"(?:tell|ask)\s+(?:the\s+)?([^\n:]{1,80}?)"
        r"(?:\s+(?:session|chat))?(?:\s+to\s|\s*:)",
        r"^\s*" + polite + r"(?:for\s+)?(?:the\s+)?([^\n:]{1,80}?)"
        r"(?:\s+(?:session|chat))?\s*:\s",
    )
    for pattern in patterns:
        match = re.search(pattern, message, re.I)
        if match and match.group(1).strip():
            return match.group(1).strip().lower()
    return None


def addressed_session(state: Mapping[str, Any], message: str) -> str | None:
    name = spoken_addressee(message)
    if name is None or name in NOT_ADDRESSEES:
        return None
    sessions = [s for s in _sessions(state) if not s.get("archived", False)]
    projects = set(state.get("projects", [])) | {s.get("project", "") for s in sessions}
    projects = {p for p in projects if p and name in
                {_project_name(state, p).lower(), _basename(p).lower()}}
    if len(projects) != 1:
        return None
    fits = [s for s in sessions if s.get("project", "") in projects]
    return str(fits[0]["id"]) if len(fits) == 1 else None


def short_names(message: str) -> set[str]:
    return {word for word in re.findall(r"[^\W_]+", message.lower())
            if 2 <= len(word) <= 3 and word not in COMMON}


def addressed(state: Mapping[str, Any], message: str, session: str) -> bool:
    """Only unique projects and their unique live sessions can clear approval."""
    own = next((s for s in _sessions(state) if s["id"] == session), None)
    if own is None:
        return False
    if addressed_session(state, message) == session:
        return True
    said = short_names(message)

    def named(project: str) -> bool:
        return bool(project and said & short_names(_project_name(state, project) + " " + _basename(project)))

    if not named(str(own.get("project", ""))):
        return False
    sessions = [s for s in _sessions(state) if not s.get("archived", False)]
    projects = set(state.get("projects", [])) | {s.get("project", "") for s in sessions}
    projects = {p for p in projects if named(p)}
    return projects == {own.get("project", "")} and [s["id"] for s in sessions
            if s.get("project", "") == own.get("project", "")] == [session]


def offered_targets(state: Mapping[str, Any], context: Mapping[str, Any]) -> list[str]:
    """RouterTools.targets limits, needed before trusting a spoken destination."""
    narrowed = set(pill_projects(state, context))
    cards = [c for c in _cards(state) if _shown(state, c)
             and (not narrowed or _card_project(state, c) in narrowed)][:60]
    live = [s for s in _sessions(state) if not s.get("archived", False)
            and (not narrowed or s.get("project", "") in narrowed)]
    live.sort(key=lambda s: float(s.get("idle_min", 0)))
    working = [s for s in live if s.get("running", False)]
    recent = [s for s in live if not s.get("running", False)][:20]
    projects = [p for p in state.get("projects", []) if p and (not narrowed or p in narrowed)][:60]
    return (["answer:" + str(c["id"]) for c in cards]
            + ["session:" + str(s["id"]) for s in (working + recent)[:80]]
            + ["new:" + p for p in projects] + ["unclear"])


def destination(state: Mapping[str, Any], message: str,
                context: Mapping[str, Any] | None = None) -> str | None:
    context = context or {}
    targets = offered_targets(state, context)
    start = start_request(message, context.get("pills", []))
    if start is not None:
        name = start["project"]
        if name is None:
            return None
        fits = [t for t in targets if t.startswith("new:") and name in
                {_project_name(state, t[4:]).lower(), _basename(t[4:]).lower()}]
        return fits[0] if len(fits) == 1 else None
    session = addressed_session(state, message)
    target = "session:" + session if session else None
    return target if target in targets else None


def _action(state: Mapping[str, Any], target: str, reason: str,
            ranked: Sequence[Any] = (), **extra: Any) -> dict[str, Any]:
    canonical = canonical_target(state, target)
    kind = "send" if target.startswith(("session:", "answer:")) else "start" if target.startswith("new:") else "intent"
    return {"decision": kind, "target": canonical, "top": canonical,
            "ranked": list(ranked) or [canonical], "reason": reason, **extra}


def _target(row: Any) -> str | None:
    if isinstance(row, str):
        return row
    if isinstance(row, Mapping):
        return row.get("target")
    if isinstance(row, (tuple, list)) and row:
        return row[0]
    return None


def _ranked(state: Mapping[str, Any], rows: Sequence[Any]) -> list[Any]:
    """Canonical, unique, renderable ask-card buttons, best first (at most four)."""
    result, seen = [], set()
    for row in rows:
        raw = _target(row)
        target = canonical_target(state, raw)
        if not target or target == "unclear" or target in seen:
            continue
        if raw.startswith("answer:") and not eligible(state, raw):
            continue
        if target.startswith("session:") and not any(s["id"] == target[8:] for s in _sessions(state)):
            continue
        if not target.startswith(("session:", "new:")) and target not in INTENTS:
            continue
        result.append({**row, "target": target} if isinstance(row, Mapping) else target)
        seen.add(target)
        if len(result) == 4:
            break
    return result


def _same(state: Mapping[str, Any], left: str | None, right: str | None) -> bool:
    return bool(left and right and canonical_target(state, left) == canonical_target(state, right))


def plan(state: Mapping[str, Any], message: str,
         context: Mapping[str, Any] | None = None) -> dict[str, Any] | None:
    """Return a deterministic action, or None when Jev must classify the draft.

    Swift does not eligibility-veto armed replies or pins: they are the user's
    choices. Missing reply cards fall through; Jev/live sends are checked later.
    """
    context = context or {}
    if not for_router(message, context):
        reply = context.get("replyTo")
        card = next((c for c in _cards(state) if c["id"] == reply), None)
        if card is not None:
            return _action(state, "answer:" + str(card["id"]), "armed-reply", card=card["id"], sure=True)
        pin = context.get("pinned", context.get("target"))
        if pin:
            return _action(state, pin, "pinned", sure=True)
        projects = pill_projects(state, context)
        if len(projects) == 1:
            project = projects[0]
            other = any(_open(c) and _card_project(state, c) == project for c in _cards(state)) or any(
                not s.get("archived", False) and s.get("project", "") == project for s in _sessions(state))
            if wants_new_session(message, context.get("pills", [])) or not other:
                return _action(state, "new:" + project, "pill-start", sure=True)
    # Swift's .classify path reuses a carried live reading even for @router-only
    # messages. Their normal reply/pin/pill plan is skipped, but shown is not.
    shown = context.get("shown")
    if shown:
        carried = context.get("jev")
        if carried is not None:
            rows = carried.get("ranked", [])
            top = carried.get("top", _target(rows[0]) if rows else carried.get("target"))
            if not (carried.get("sure") and carried.get("assisted", True) and _same(state, top, shown)):
                return None
            found = dict(carried, target=top, decision="send")
        else:
            found = {"decision": "send", "target": shown, "top": shown,
                     "ranked": [shown], "sure": True, "assisted": True}
        found = post_jev(state, message, context, found)
        if found.get("reason") == "jev":
            found["reason"] = "live-shown"
        return found
    return None


def post_jev(state: Mapping[str, Any], message: str, context: Mapping[str, Any] | None,
             decision: Mapping[str, Any], ranked: Sequence[Any] | None = None) -> dict[str, Any]:
    """Apply classifyAndAct's overrides to a format+policy result, in Swift order.

    On an ask, ``top`` retains the policy's best fused target while ``target`` is
    None. Ranked entries accept strings, {target, p, ...}, or (target, score).
    The result retains policy diagnostics (including sureness).
    """
    context = context or {}
    rows = list(ranked if ranked is not None else decision.get("ranked", []))
    top = decision.get("top") or (_target(rows[0]) if rows else decision.get("target"))
    sure = bool(decision.get("sure", decision.get("decision") != "ask" and top is not None))
    assisted = bool(decision.get("assisted", True))
    live = assisted and sure and _same(state, top, context.get("shown"))
    reason = "jev"
    veto = context.get("notTo")
    if _same(state, top, veto):
        sure, reason = False, "notTo"
    router_only = for_router(message, context)
    named = None if router_only else destination(state, message, context)
    canonical_rows = _ranked(state, rows)
    if named and not _same(state, named, top) and not _same(state, named, veto) and eligible(state, named):
        return {**decision, **_action(state, named, "named-destination", canonical_rows),
                "sure": True, "live": False}
    if router_only:
        intents = [row for row in rows if _target(row) in INTENTS]
        first = _target(intents[0]) if intents else None
        if first != top:
            sure, reason = False, "router-only"
        rows = intents or ["question", "change_fjord"]
        top = _target(rows[0])
        canonical_rows = _ranked(state, rows)
    session = canonical_target(state, top)
    session = session[8:] if session and session.startswith("session:") else None
    if sure and not live and session and any(
            _session_id(c) == session and c.get("kind") == "approval" and _shown(state, c)
            for c in _cards(state)) and not addressed(state, message, session):
        sure, reason = False, "approval-veto"
    if sure and not eligible(state, top):
        sure, reason = False, "ineligible"
    extra = {**decision, "top": canonical_target(state, top), "ranked": canonical_rows,
             "sure": sure, "live": live, "reason": reason}
    if sure and top:
        return {**extra, **_action(state, top, reason, canonical_rows), "sure": True, "live": live}
    return {**extra, "decision": "ask", "target": None}
