"""Shared pieces of the asks eval: paths, the Swift prompt read at runtime, the app's Haiku call ported, a cached `claude -p`.

Nothing here prints session text. Everything under DATA is gitignored (evals/router/v2/.gitignore: data/)."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
REPO = ROUTER.parents[1]
DATA = ROUTER / "v2" / "data" / "asks_eval"
CACHE = DATA / "cache"
BRIEF_SWIFT = REPO / "Sources" / "FjordComputer" / "RouterBrief.swift"
sys.path.insert(0, str(ROUTER / "v2" / "build"))
sys.path.insert(0, str(ROUTER / "real"))
sys.path.insert(0, str(ROUTER))

FLAGS = ["--tools", "", "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence", "--output-format", "json"]
HAIKU = "claude-haiku-5-5"
OPUS = "claude-opus-5-5"
APP_TIMEOUT = 30          # RouterBriefer.timeout: a slower answer is a failure in the app
CALL_TIMEOUT = 120        # here: wait longer, record the latency, count > APP_TIMEOUT separately


def jsonl(path):
    return [json.loads(l) for l in open(path)] if pathlib.Path(path).exists() else []


def write_jsonl(path, recs):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w") as f:
        for r in recs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------- `claude -p`, cached on disk

def _version_key(v):
    return [int(x) for x in re.findall(r"\d+", v)]


def app_claude():
    """RouterStatus.findDefault: the highest version of the Claude app's own Claude Code
    (<root>/<version>/<hash>/claude.app/Contents/MacOS/claude), as the app runs it; `claude` on PATH if there is none."""
    root = pathlib.Path.home() / "Library" / "Application Support" / "Claude" / "claude-code"
    if root.is_dir():
        for v in sorted((d.name for d in root.iterdir() if d.name[:1].isdigit()), key=_version_key, reverse=True):
            for h in sorted(x.name for x in (root / v).iterdir() if not x.name.startswith(".")):
                path = root / v / h / "claude.app" / "Contents" / "MacOS" / "claude"
                if os.access(path, os.X_OK):
                    return str(path), v
    return "claude", "path"


BINARY, VERSION = app_claude()


def claude(model, system, context, schema, tag):
    """One isolated `claude -p` call, as RouterBriefer.haiku makes it (empty cwd, no tools, no settings, no MCP, no
    persistence). Cached by everything that goes in. Returns {"out": parsed stdout JSON or None, "raw": stdout text if not
    JSON, "error", "elapsed"}."""
    key = hashlib.sha256(json.dumps([model, system, context, schema, FLAGS, VERSION]).encode()).hexdigest()
    path = CACHE / tag / key[:2] / f"{key}.json"
    if path.exists():
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            pass
    args = [BINARY, "-p", "--model", model] + FLAGS + (["--json-schema", schema] if schema else []) + ["--system-prompt", system]
    for attempt in range(3):              # an API error (overload, 5xx) is tried again, and never cached
        t0 = time.time()
        res = {"out": None, "raw": None, "error": None, "version": VERSION}
        with tempfile.TemporaryDirectory(prefix="asks-eval-") as cwd:
            try:
                p = subprocess.run(args, input=context, capture_output=True, text=True, cwd=cwd, timeout=CALL_TIMEOUT)
                try:
                    res["out"] = json.loads(p.stdout)
                except json.JSONDecodeError:
                    res["raw"] = p.stdout[-2000:]
                    res["error"] = f"exit {p.returncode}: not JSON"
            except subprocess.TimeoutExpired:
                res["error"] = "timeout"
        res["elapsed"] = round(time.time() - t0, 2)
        api_error = isinstance(res["out"], dict) and res["out"].get("is_error") is True
        if not api_error and res["error"] in (None, "timeout"):
            break
        if api_error:
            res["error"] = "API error: " + str(res["out"].get("result"))[:200]
        time.sleep(5 * (attempt + 1))
    if res["error"] is None or res["error"] == "timeout":
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(res))
    return res


def typed_answer(res):
    """RouterBriefer.haiku: structured_output re-serialized when there, else the result text (which `read` checks)."""
    out = res.get("out")
    if not isinstance(out, dict):
        return res.get("raw") or ""
    if out.get("is_error") is not True and isinstance(out.get("structured_output"), dict):
        return json.dumps(out["structured_output"], ensure_ascii=False)
    return out.get("result") or ""


# ---------------------------------------------------------------- Swift string literals

def _unescape(body):
    """A Swift string literal's escapes (\\" \\\\ \\n \\t \\u{..}); interpolations are left as written."""
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n == "u" and body[i + 2:i + 3] == "{":
                j = body.index("}", i)
                out.append(chr(int(body[i + 3:j], 16)))
                i = j + 1
                continue
            out.append({"n": "\n", "t": "\t", "0": "\0", "r": "\r"}.get(n, n) if n != "(" else "\\(")
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _multiline(src, name):
    m = re.search(r'static let ' + name + r' = """\n(.*?)\n([ \t]*)"""', src, re.S)
    if not m:
        raise SystemExit(f"RouterBrief.swift: no multi-line literal `{name}`")
    indent = m.group(2)
    lines = [l[len(indent):] if l.startswith(indent) else l.lstrip() for l in m.group(1).split("\n")]
    text = ""
    for k, line in enumerate(lines):
        trail = len(line) - len(line.rstrip("\\"))
        if trail % 2 == 1:                       # a line continuation: no newline
            text += line[:-1]
        else:
            text += line + ("\n" if k < len(lines) - 1 else "")
    return _unescape(text)


def _literal(pattern, src, what):
    m = re.search(pattern, src, re.S)
    if not m:
        raise SystemExit(f"RouterBrief.swift: can't find {what}")
    return _unescape(m.group(1))


STR = r'"((?:[^"\\]|\\.)*)"'


def swift_prompt():
    """What the app's extracting brief call is made of, read from RouterBrief.swift as it is now."""
    src = BRIEF_SWIFT.read_text()
    p = {}
    p["rules"] = _multiline(src, "rules")
    p["asksRules"] = _multiline(src, "asksRules")
    p["defaultText"] = _literal(r'static let defaultText = ' + STR, src, "RouterStyle.defaultText")
    p["styleJoin"] = _literal(r'static func prompt\(_ rules: String, style: String\) -> String \{\s*rules \+ ' + STR + r' \+ style', src,
                              "RouterStyle.prompt")
    m = re.search(r'static let schema = #"(.*?)"#', src, re.S)
    if not m:
        raise SystemExit("RouterBrief.swift: can't find the schema")
    p["schema"] = m.group(1)
    json.loads(p["schema"])
    tier = src[src.index("private static func tierAsk"):]
    p["tierAskAsks"] = _literal(r'case \.asks: ' + STR, tier, "tierAsk .asks")
    ask = src[src.index("static func ask(_ subject: Subject)"):]
    p["extractSuffix"] = _literal(r'extracts\(subject\) \? ask \+ ' + STR, ask, "ask()'s extracting suffix")
    build = src[src.index("static func build(_ subject: Subject)"):]
    build = build[:build.index("static let maxAsks")]
    p["head"] = _literal(r'out\.append\(' + STR + r'\)\s*\n\s*out\.append\(fence\(UntrustedText', build, "build()'s first line")
    p["explain"] = _literal(r'out\.append\(' + STR + r' \+ ask\(subject\)\)', build, "build()'s What to explain")
    p["work"] = _literal(r'if let work = triage\.workLabel \{ out\.append\(' + STR, build, "build()'s work line")
    p["unverified"] = _literal(r'if triage\.unverified \{ out\.append\(' + STR, build, "build()'s unverified line")
    p["text"] = _literal(r'if !subject\.text\.isEmpty \{ out\.append\(' + STR + r' \+ fence', build, "build()'s card text line")
    m = re.search(r'out\.append\(' + STR + r' \+ \(message\.count > messageTail \? ' + STR + r' : ""\) \+ ' + STR, build)
    if not m:
        raise SystemExit("RouterBrief.swift: can't find build()'s final message line")
    p["final"], p["finalEnd"], p["finalColon"] = (_unescape(g) for g in m.groups())
    for name in ("messageTail", "maxAsks", "questionLimit", "optionLimit"):
        p[name] = int(_literal(r'static let ' + name + r' = (\d+)', src, name))
    for k in ("head", "explain", "work", "unverified", "text", "final"):
        if "\\(" in p[k] and k not in ("head", "work"):
            raise SystemExit(f"RouterBrief.swift: unexpected interpolation in {k}")
    return p


def system_prompt(p):
    """RouterBriefContext.system(style: default, extracting: true)."""
    return p["rules"] + "\n\n" + p["asksRules"] + p["styleJoin"] + p["defaultText"]


# ---------------------------------------------------------------- the context (RouterBriefContext.build), ported

WORK_LABEL = {"uncommitted": "not committed", "committed": "not pushed", "pushed": "pushed", "pr": "PR open"}


def first_sentences(text, count=1, limit=200):
    """RouterLive.firstSentences."""
    if text is None:
        return None
    for mark in ["```", "**", "__", "`", "#"]:
        text = text.replace(mark, "")
    paras = text.split("\n\n")
    para = next((x for x in paras if x.strip()), text)
    text = " ".join(para.split())
    if not text:
        return None
    seen, end = 0, len(text)
    for i, ch in enumerate(text):
        if ch in ".!?" and (i + 1 == len(text) or text[i + 1] == " "):
            seen += 1
            if seen == count:
                end = i + 1
                break
    text = text[:end]
    if len(text) > limit:
        text = text[:limit - 1].strip(" ") + "…"
    if text.endswith(":"):
        text = text[:-1]
    return text


def interp(s, *values):
    """A literal's interpolations (`\\(...)`, nested parentheses allowed) replaced by the values, in order."""
    out, i, k = [], 0, 0
    while True:
        j = s.find("\\(", i)
        if j < 0:
            break
        depth, e = 0, j + 1
        while True:
            depth += {"(": 1, ")": -1}.get(s[e], 0)
            if depth == 0:
                break
            e += 1
        out.append(s[i:j] + values[k])
        k, i = k + 1, e + 1
    if k != len(values):
        raise SystemExit(f"RouterBrief.swift: {k} interpolations where {len(values)} were expected")
    return "".join(out) + s[i:]


def context(p, title, project, message, triage):
    """RouterBriefContext.build for an Asks you card under Needs you that extracts its asks (no form, no plan, asks unread)."""
    import triage as T
    out = [interp(p["head"], "Asks you", "needs you")]
    out.append(T.fence(T.clean(title, 200) + "\n" + T.clean(project, 120)))
    out.append(p["explain"] + p["tierAskAsks"] + p["extractSuffix"])
    if triage:
        work = WORK_LABEL.get(triage.get("work"))
        if work:
            out.append(interp(p["work"], work))
        if triage.get("unverified"):
            out.append(p["unverified"])
    text = first_sentences(message, count=2, limit=280) or ""
    if text:
        out.append(p["text"] + T.fence(text))
    tail = p["messageTail"]
    clipped = "…" + message[-tail:] if len(message) > tail else message
    out.append(p["final"] + (p["finalEnd"] if len(message) > tail else "") + p["finalColon"] + T.fence(clipped))
    return "\n".join(out)


# ---------------------------------------------------------------- the answer (RouterBriefContext.read), ported

def read(answer, p):
    """(brief, asks) or (None, reason) when the app would drop the answer (the card then shows no list)."""
    text = answer.strip()
    if not text.startswith("{") and "{" in text and "}" in text and text.index("{") < text.rindex("}"):
        text = text[text.index("{"):text.rindex("}") + 1]
    try:
        obj = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        return None, "not JSON"
    if not isinstance(obj, dict) or not isinstance(obj.get("brief"), str) or not isinstance(obj.get("asks"), list):
        return None, "not {brief, asks}"
    if len(obj["asks"]) > p["maxAsks"]:
        return None, f"more than {p['maxAsks']} asks"
    flat = lambda s: " ".join(s.split())
    asks = []
    for item in obj["asks"]:
        if not isinstance(item, dict) or not isinstance(item.get("question"), str):
            return None, "an ask without a question"
        raw = item.get("options", [])
        if not isinstance(raw, list) or len(raw) > p["maxAsks"]:
            return None, "options not a short list"
        options = []
        for o in raw:
            if not isinstance(o, str):
                return None, "an option not a string"
            f = flat(o)
            if f and f not in options:
                options.append(f)
        q = flat(item["question"])
        if len(q) > p["questionLimit"] or any(len(o) > p["optionLimit"] for o in options):
            return None, "a question or option too long"
        if not q or any(a["question"].lower() == q.lower() for a in asks):
            continue
        asks.append({"question": q, "options": options})
    brief = obj["brief"]
    for mark in ["**", "__", "`", "#"]:
        brief = brief.replace(mark, "")
    brief = " ".join(brief.split())
    if not brief:
        return None, "empty brief"
    n = 1 if asks else 2
    return {"brief": first_sentences(brief, count=n, limit=10 ** 9), "asks": asks}, None


# ---------------------------------------------------------------- the old list (RouterTriage at HEAD), ported

def drop_lead_ins(questions):
    """RouterTriage.droppingLeadIns."""
    return [q for i, q in enumerate(questions) if i == len(questions) - 1 or not q.strip(" *_").endswith(":")]

