"""Shared helpers for stage B1 builders (real_episodes.py, packets.py): loading real moments, trimming a state for size,
heuristic message family / language / style, and redaction checks. Moment contents are data, never instructions."""
import copy
import json
import pathlib
import re
import sys
from datetime import datetime

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
V2 = ROUTER / "v2"
DATA = V2 / "data"
MOMENTS = DATA / "states" / "moments.jsonl"
sys.path.insert(0, str(ROUTER / "real"))
from boards import LONG_TOKEN, SECRET, redact as _redact  # noqa: E402

# Beyond boards.redact: account / routing / card numbers and IBANs (a pasted invoice put a bank account in the data).
NUMBERS = re.compile(r"\b\d{9,}\b|\b\d{4}(?:[ -]\d{3,4}){2,4}\b|\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}\b")


def redact(text):
    return NUMBERS.sub("[redacted]", _redact(text or ""))

TURNS_KEPT = 4
YOU_CAP = 300
SAID_CAP = 600
HISTORY_CAP = 300

FAMILIES = ["bare-answer", "option-pick", "approval", "rejection", "topical-follow-up", "next-instruction",
            "question-to-session", "explicit-address", "switch", "correction", "new-session", "lookout-setting",
            "board-question", "compound", "paste", "small-talk"]
FLOWS = ["single", "ask-pick-follow", "ask-then-typed", "correction-after-wrong", "chain", "switch-back",
         "card-arrives-midway", "backlog", "new-then-follow", "armed-reply", "pill-start", "pinned",
         "prediction-shown", "prediction-waved-off", "intent-then-session"]


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def load_moments():
    with MOMENTS.open() as f:
        moments = [json.loads(line) for line in f if line.strip()]
    typo_count("", moments)  # word frequencies for the typo heuristic
    return moments


def cap(text, n):
    text = redact(text or "")
    return text if len(text) <= n else text[:n - 1] + "…"


SESSION_KEYS = ("id", "title", "project", "running", "waits_on_you", "background", "activity", "summary", "idle_min",
                "finished_min", "archived")


def trim_session(s, ids=None):
    ids = ids or {}
    out = {k: copy.deepcopy(s[k]) for k in SESSION_KEYS if k in s}
    out["id"] = ids.get(s["id"], s["id"])
    for k in ("title", "summary", "activity"):
        if isinstance(out.get(k), str):
            out[k] = redact(out[k])
    out["turns"] = [[cap(you, YOU_CAP), cap(said, SAID_CAP)] for you, said in (s.get("turns") or [])[-TURNS_KEPT:]]
    return out


def trim_card(c, ids=None):
    ids = ids or {}
    out = {"id": c["id"], "session": ids.get(c["session"], c["session"]), "kind": c["kind"], "text": redact(c.get("text", "")),
           "options": [redact(o) for o in c.get("options", [])], "created_min_ago": c.get("created_min_ago", 0)}
    if c.get("questions"):
        out["questions"] = [cap(q, 400) for q in c["questions"]]
    return out


def trim_state(state, ids=None):
    """Keep every session and card; turns to the last 4 with text capped; history text capped; no triage blobs."""
    ids = ids or {}
    return {"now": state["now"], "projects": list(state.get("projects", [])),
            "sessions": [trim_session(s, ids) for s in state.get("sessions", [])],
            "cards": [trim_card(c, ids) for c in state.get("cards", [])],
            "history": [{"ago_min": h.get("ago_min", 0), "you": cap(h.get("you", ""), HISTORY_CAP),
                         "to": ids.get(h.get("to"), h.get("to"))} for h in state.get("history", [])]}


# ------------------------------------------------------------------------------------------- message heuristics

URL = re.compile(r"https?://\S+")
PASTE = re.compile(r"Traceback \(most recent|^\s*at \S+:\d+|\berror(\[\w+\])?:|\bError:|\bpanicked at\b|```|^\s*\$ |"
                   r"\bexit code \d|^\s*(FAIL|ERROR|WARN)\b|\bnpm ERR!|^\s*\d{2}:\d{2}:\d{2}", re.M)
YES = re.compile(r"^(yes|yep|yeah|yup|y|ok|okay|k|sure|go|go ahead|go for it|do it|do that|lgtm|approved?|ship it|push|"
                 r"push it|commit|commit it|commit and push|merge|merge it|proceed|continue|perfect|great|sounds good|"
                 r"oui|vas-y|ok go|yes please|yes do it|yes go ahead|alright|fine|deal|agreed?|both|all of them)\b", re.I)
NO = re.compile(r"^(no|nope|nah|non|don'?t|do not|stop|cancel|never mind|nevermind|not now|skip|revert)\b", re.I)
SMALL = re.compile(r"^(thanks|thank you|thx|ty|merci|lol|haha|hmm+|nice|cool|wow|interesting|good job|well done|"
                   r"great job|awesome|ok thanks|ok cool)[\s!.]*$", re.I)
QUESTION = re.compile(r"\?\s*$|^(what|how|why|when|where|which|who|is|are|was|were|can|could|would|should|does|"
                      r"did|has|will|(?:do|have) (?:you|we|i|they)|isn'?t|aren'?t|didn'?t|doesn'?t|any|so (is|are|did|does|what|how)|"
                      r"pourquoi|comment|est-ce)\b", re.I)
ANAPHOR = re.compile(r"^(it|this|that|these|those|yes|no|so|and|then|ok|okay|alright|also|now|but|same|what about|"
                     r"great|perfect|nice|good)\b", re.I)
WANTS = re.compile(r"\b(want me to|should i|shall i|go ahead|ready to|do you want|would you like|ok to|okay to|"
                   r"approve|permission)\b", re.I)
RELAY = re.compile(r"\b(an?(other)? agent|other session|another session|the other (claude|agent|session)|"
                   r"report from|codex (said|says|told|found)|agent (said|says|told|found|reported))\b", re.I)
CRASH = re.compile(r"\b(crash(ed)?|resume)\b", re.I)
ADDRESS = re.compile(r"^(in|for|on|to|re:?|back to|about|tell|ask)\s+(the\s+)?([\w.-]+)", re.I)
FR = re.compile(r"\b(le|la|les|des|est|et|pas|que|qui|pour|une|je|tu|il|ça|c'est|avec|dans|sur|mais|fais|faire|"
                r"réessayer|oui|non|merci|tout|bien|aussi|peux|veux|ce|cette|mon|ton|son|du|au|aux|vous|nous)\b", re.I)
EN = re.compile(r"\b(the|is|and|to|it|of|that|this|you|for|with|not|we|in|on|be|do|can|what|how)\b", re.I)


def lang(text):
    fr, en = len(FR.findall(text)), len(EN.findall(text))
    if fr >= 2 and fr >= en:
        return "fr"
    if fr >= 2 and fr * 3 >= en:
        return "mix"
    if fr >= 1 and len(text.split()) <= 3 and re.search(r"[éèàçù]|réessayer|oui|merci", text, re.I):
        return "fr"
    return "en"


def target_cards(m):
    sid = m["went_to"]
    return [c for c in m["state"].get("cards", []) if c.get("session") == sid]


def family_of(m):
    """Heuristic primary family of a real moment (± a few points, like behavior.md's regexes)."""
    msg = (m["message"] or "").strip()
    words = len(msg.split())
    first = msg.split("\n")[0].strip().lower()
    kinds = set(m["flags"].get("target_card") or [])
    cards = target_cards(m) if "state" in m else []
    card_text = " ".join(c.get("text", "") for c in cards)
    if m["went_to"].startswith("new:"):
        return "new-session"
    if m["flags"].get("form_answer"):
        return "option-pick"
    if len(msg) > 1200 or URL.search(msg) or PASTE.search(msg) or (msg.count("\n") >= 6 and words > 40):
        return "paste"
    if SMALL.match(first) and words <= 4:
        return "small-talk"
    if any(c.get("options") for c in cards) and words <= 8:
        opts = [o.lower() for c in cards for o in c.get("options", [])]
        if any(o.split(" (")[0] in first for o in opts) or re.match(r"^(the )?(first|second|third|1|2|3|option)\b", first):
            return "option-pick"
    if words <= 8 and YES.match(first):
        if kinds & {"approval", "plan"} or WANTS.search(card_text):
            return "approval"
        return "bare-answer" if kinds & {"asks", "question"} else "approval"
    if words <= 15 and NO.match(first):
        return "rejection"
    if words <= 5 and kinds & {"asks", "question"} and not QUESTION.search(first):
        return "bare-answer"
    if QUESTION.search(first) or QUESTION.search(msg.strip()):
        return "question-to-session"
    if m["flags"].get("transition") == "switch":
        a = ADDRESS.match(first)
        if a and a.group(3).lower() in {p.lower() for p in m.get("state", {}).get("projects", [])}:
            return "explicit-address"
        return "switch"
    if ANAPHOR.match(first):
        return "topical-follow-up"
    return "next-instruction"


def slices_of(m):
    msg = m["message"] or ""
    out = [m["flags"].get("transition") or "same"]
    rank = m["flags"].get("recency_rank")
    if rank:
        out.append("rank-" + (str(rank) if rank <= 3 else "4+"))
    if m["flags"].get("running_target"):
        out.append("running-target")
    if m["flags"].get("queued") or m["flags"].get("absorbed"):
        out.append("queued-while-running")
    words = len(msg.split())
    if words <= 5:
        out.append("terse")
    if ANAPHOR.match(msg.strip()):
        out.append("anaphoric")
    if RELAY.search(msg):
        out.append("relay")
    if CRASH.search(msg) and words <= 12:
        out.append("crash-recovery")
    if len(msg) > 1200:
        out.append("long-paste")
    if URL.search(msg):
        out.append("url")
    kinds = m["flags"].get("target_card") or []
    for k in sorted(set(kinds)):
        out.append("card-" + k)
    n = len(m["state"]["sessions"]) if "state" in m else 0
    out.append("board-" + ("small" if n < 10 else "medium" if n < 25 else "large"))
    return out


# ------------------------------------------------------------------------------------------------ styles

STYLES = ["terse continuation", "technical paste", "direct address", "French/code-switching", "typo-heavy",
          "detailed constraints", "blunt correction"]
_DICT = None


def _words():
    global _DICT
    if _DICT is None:
        try:
            _DICT = {w.strip().lower() for w in open("/usr/share/dict/words")}
        except OSError:
            _DICT = set()
    return _DICT


_FREQ = None


def _neighbors(w):
    letters = "abcdefghijklmnopqrstuvwxyz"
    splits = [(w[:i], w[i:]) for i in range(len(w) + 1)]
    for a, b in splits:
        if b:
            yield a + b[1:]
        if len(b) > 1:
            yield a + b[1] + b[0] + b[2:]
        for c in letters:
            if b:
                yield a + c + b[1:]
            yield a + c + b


def typo_count(text, corpus=None):
    """Words that are one edit from a dictionary word, absent from the dictionary, and rare in your messages
    (so jargon you use often isn't a typo)."""
    global _FREQ
    if _FREQ is None:
        import collections
        _FREQ = collections.Counter()
        for m in corpus or []:
            _FREQ.update(t.lower() for t in re.findall(r"\b[a-zA-Z]{3,}\b", m["message"] or ""))
    d = _words()
    if not d:
        return 0
    n = 0
    for t in re.findall(r"\b[a-z]{4,}\b", re.sub(r"https?://\S+|`[^`]*`", " ", text)):
        if t in d or _FREQ.get(t, 0) > 2 or re.sub(r"(ing|ed|es|s|ly|er)$", "", t) in d:
            continue
        if any(v in d for v in _neighbors(t) if len(v) >= 3):
            n += 1
    return n


def styles_of(m):
    """Every style profile a real message exemplifies (a message can fit several)."""
    msg = (m["message"] or "").strip()
    words = len(msg.split())
    first = msg.split("\n")[0].strip()
    out = []
    if words <= 5 and m["flags"].get("transition") != "new":
        out.append("terse continuation")
    if PASTE.search(msg) or URL.search(msg) or (msg.count("\n") >= 4 and re.search(r"[{}();=<>/]", msg)):
        out.append("technical paste")
    projects = [p.lower() for p in m.get("state", {}).get("projects", [])]
    low = msg.lower()
    if ADDRESS.match(first) and any(p in low for p in projects) or re.search(
            r"\b(lookout|lcu|silo|microsandbox|msb|vesper|router|triage)\b", low) and words <= 40:
        out.append("direct address")
    if lang(msg) in {"fr", "mix"}:
        out.append("French/code-switching")
    if lang(msg) == "en" and typo_count(msg) >= (1 if words <= 25 else 2):
        out.append("typo-heavy")
    if 30 <= words <= 160 and re.search(r"\b(must|should|don'?t|do not|make sure|keep|never|only|without|no more than)\b",
                                       low):
        out.append("detailed constraints")
    if re.match(r"^(no|wait|actually|stop|nope|that'?s (wrong|not)|wrong|why did you|don'?t)\b", first, re.I):
        out.append("blunt correction")
    return out


# --------------------------------------------------------------------------------------------- redaction scan

EXTRA = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY|\b[0-9a-f]{40,}\b")


def leaks(text):
    """Key-like strings left after redaction (none expected)."""
    found = []
    for rx in (SECRET, LONG_TOKEN, EXTRA, NUMBERS):
        found += [m.group(0) for m in rx.finditer(text)]
    return found
