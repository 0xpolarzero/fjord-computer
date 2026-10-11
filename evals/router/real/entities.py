"""Identifier evidence: links, PR and issue numbers, paths, code identifiers, long numbers shared by the message and
each session's earlier turns (its transcript before the moment), weighted by rarity across the board's sessions.

python3 real/entities.py  →  how often the best-matching session is where the message went, and real/data/entities.json
(per real case: per session score), for policies to use."""
import collections
import json
import math
import pathlib
import re
from datetime import datetime

HERE = pathlib.Path(__file__).parent
ENTITY = re.compile(
    r"https?://[^\s)>\]]+"                        # links
    r"|\b[\w.-]+/[\w.-]+#\d+\b|#\d{2,6}\b"          # owner/repo#12, #123
    r"|(?:[\w.-]+/)+[\w.-]+\.\w{1,5}\b"             # paths with an extension
    r"|\b[\w-]+\.(?:swift|py|ts|tsx|js|rs|go|json|md|yml|yaml|toml|sh|plist|app)\b"   # file names
    r"|`[^`\n]{3,60}`"                            # code spans
    r"|\b[a-z]+(?:[A-Z][a-z0-9]+){1,}\b"           # camelCase
    r"|\b[a-z0-9]+(?:_[a-z0-9]+){1,}\b"            # snake_case
    r"|\b\d{4,}\b")                               # long numbers (runs, PRs, ports)


def entities(text):
    out = set()
    for m in ENTITY.finditer(text or ""):
        e = m.group(0).strip("`").rstrip(".,;:").lower()
        if len(e) >= 4:
            out.add(e)
            # a link counts by its path pieces too (a run URL names the repo and the run)
            if e.startswith("http"):
                out.update(p for p in re.split(r"[/?#=&]", e.split("://", 1)[-1]) if len(p) >= 4 and p not in {"github.com", "actions", "runs", "pull", "issues", "www"})
    return out


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def main():
    corpus = {}
    for line in open(HERE / "data" / "corpus.jsonl"):
        s = json.loads(line)
        corpus[s["id"][:8]] = s
    cases = [json.loads(l) for l in open(HERE / "data" / "real.jsonl")]
    stats = collections.Counter()
    scores = {}
    for c in cases:
        now = ts(c["at"])
        said = entities(c["message"])
        if not said:
            continue
        stats["with entities"] += 1
        per = {}
        for s in c["board"]["sessions"]:
            src = corpus.get(s["id"])
            if not src:
                continue
            text = " ".join(t["you"] + " " + t["said"] for t in src["turns"] if ts(t["at"]) < now)
            per[s["id"]] = entities(text + " " + s["title"])
        n = max(len(per), 1)
        idf = {e: math.log((n + 1) / (1 + sum(e in v for v in per.values()))) for e in said}
        sc = {sid: sum(idf[e] for e in said if e in v) for sid, v in per.items()}
        scores[c["id"]] = sc
        ranked = sorted(sc.items(), key=lambda x: -x[1])
        if ranked and ranked[0][1] > 0:
            stats["some match"] += 1
            unique = len(ranked) < 2 or ranked[0][1] > ranked[1][1]
            if unique:
                stats["unique best"] += 1
                stats["unique best right"] += ranked[0][0] in c["gold"]["to"]
    (HERE / "data" / "entities.json").write_text(json.dumps(scores))
    n = len(cases)
    print(f"{stats['with entities']} of {n} real messages hold an identifier; {stats['some match']} match a session's past; "
          f"a unique best match on {stats['unique best']}, right {stats['unique best right']} "
          f"({100 * stats['unique best right'] / max(stats['unique best'], 1):.0f}%)")


if __name__ == "__main__":
    main()
