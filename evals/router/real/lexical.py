"""BM25 between the message and each board session's recent turns (its transcript before the moment).

python3 real/lexical.py [--turns N]  →  accuracy of the best match alone, precision when it stands out, and
real/data/lexical.json (per real case: per session score, normalised to the best)."""
import argparse
import collections
import json
import math
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import veto  # noqa: E402  (its stop words)
from real.entities import ts  # noqa: E402

HERE = pathlib.Path(__file__).parent


def words(text):
    return [w for w in re.findall(r"[^\W_]{3,}", (text or "").lower()) if w not in veto.COMMON]


def bm25(query, docs, k1=1.2, b=0.75):
    n = len(docs)
    avg = sum(len(d) for d in docs.values()) / max(n, 1)
    df = collections.Counter(w for d in docs.values() for w in set(d))
    out = {}
    for sid, d in docs.items():
        tf = collections.Counter(d)
        s = 0.0
        for w in set(query):
            if tf[w]:
                idf = math.log(1 + (n - df[w] + 0.5) / (df[w] + 0.5))
                s += idf * tf[w] * (k1 + 1) / (tf[w] + k1 * (1 - b + b * len(d) / max(avg, 1)))
        out[sid] = s
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--turns", type=int, default=6)
    a = ap.parse_args()
    corpus = {}
    for line in open(HERE / "data" / "corpus.jsonl"):
        s = json.loads(line)
        corpus[s["id"][:8]] = s
    cases = [json.loads(l) for l in open(HERE / "data" / "real.jsonl")]
    st = collections.Counter()
    out = {}
    for c in cases:
        now = ts(c["at"])
        q = words(c["message"])
        if not q:
            continue
        docs = {}
        for s in c["board"]["sessions"]:
            src = corpus.get(s["id"])
            past = [t for t in (src["turns"] if src else []) if ts(t["at"]) < now][-a.turns:]
            docs[s["id"]] = words(s["title"] + " " + " ".join(t["you"] + " " + t["said"] for t in past))
        sc = bm25(q, docs)
        top = max(sc.values()) if sc else 0
        out[c["id"]] = {k: (v / top if top else 0) for k, v in sc.items()}
        if c["tags"][1] != "follow-up" or not top:
            continue
        ranked = sorted(sc.items(), key=lambda x: -x[1])
        st["n"] += 1
        st["top1"] += ranked[0][0] in c["gold"]["to"]
        ratio = ranked[0][1] / max(ranked[1][1], 1e-9) if len(ranked) > 1 else 99
        for r in (1.5, 2, 3):
            if ratio >= r:
                st[f"r{r}"] += 1
                st[f"r{r}ok"] += ranked[0][0] in c["gold"]["to"]
    (HERE / "data" / "lexical.json").write_text(json.dumps(out))
    print(f"turns={a.turns}: follow-ups with words {st['n']}, BM25 top1 {100 * st['top1'] / st['n']:.1f}%")
    for r in (1.5, 2, 3):
        print(f"  best ≥ {r}× the next: fires {100 * st[f'r{r}'] / st['n']:.0f}%, right {100 * st[f'r{r}ok'] / max(st[f'r{r}'], 1):.0f}%")


if __name__ == "__main__":
    main()
