"""Your Claude Code sessions as a corpus: per session its folder, title and turns (your message, when, how the turn ended).

python3 real/extract.py  →  real/data/corpus.jsonl (gitignored: your own transcripts stay on this machine)."""
import glob
import json
import os
import pathlib
import re

ROOT = "/Users/polarzero/.claude/projects"
OUT = pathlib.Path(__file__).parent / "data"
SKIP_TEXT = re.compile(r"^\s*(<(command-|local-command|system-reminder|bash-|task-notification|user-prompt-submit)|Caveat:|\[Request interrupted)")


def user_text(rec):
    """What you typed: plain text of a user message, without tool results, commands or injected context."""
    if rec.get("isMeta") or rec.get("isSidechain"):
        return None
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    text = "\n".join(p for p in parts if p).strip()
    if not text or SKIP_TEXT.match(text):
        return None
    return text


def assistant_text(rec):
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text").strip()
    return ""


def session(path):
    sid = pathlib.Path(path).stem
    cwd, titles, turns = None, [], []
    current = None
    for line in open(path, errors="replace"):
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = r.get("type")
        cwd = cwd or r.get("cwd")
        if t == "custom-title" and r.get("customTitle"):
            titles.append(r["customTitle"])
        if t == "user":
            text = user_text(r)
            if text is not None:
                if current:
                    turns.append(current)
                current = {"at": r.get("timestamp"), "you": text, "end": r.get("timestamp"), "said": "", "tools": 0}
        elif t == "assistant" and current is not None and not r.get("isSidechain"):
            said = assistant_text(r)
            if said:
                current["said"] = said
            current["end"] = r.get("timestamp") or current["end"]
            content = (r.get("message") or {}).get("content")
            if isinstance(content, list):
                current["tools"] += sum(1 for b in content if isinstance(b, dict) and b.get("type") == "tool_use")
    if current:
        turns.append(current)
    if not turns or not cwd:
        return None
    return {"id": sid, "cwd": cwd, "project": project_of(cwd), "title": titles[-1] if titles else turns[0]["you"][:60],
            "titled": bool(titles), "turns": turns}


def project_of(cwd):
    m = re.search(r"/\.claude/worktrees/", cwd)
    base = cwd[:m.start()] if m else cwd
    if "/scratch/" in base or "Application Support/Claude" in base:
        return "scratch"
    return os.path.basename(base.rstrip("/"))


def main():
    OUT.mkdir(exist_ok=True)
    n = 0
    with open(OUT / "corpus.jsonl", "w") as out:
        for path in sorted(glob.glob(f"{ROOT}/*/*.jsonl")):
            s = session(path)
            if s:
                out.write(json.dumps(s, ensure_ascii=False) + "\n")
                n += 1
    print(n, "sessions")


if __name__ == "__main__":
    main()
