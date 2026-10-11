"""Checks the sampled turns rebuild stage A's triage inputs byte for byte (its Jev answers are in the cache), and shows
one answer of the planned bundle.   python3 v2/triage_eval/parity.py"""
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROUTER / "v2" / "build"), str(ROUTER)]
import jev  # noqa: E402
import jev_variants as V  # noqa: E402
import triage as T  # noqa: E402

turns = [json.loads(l) for l in open(ROUTER / "v2" / "data" / "triage_eval" / "turns.jsonl")]
hits, same = 0, 0
for t in turns:
    st, q, c = T.call(t["final"], t["title"], t["project"])
    raw = json.dumps({"model": "jev-latest", "state": st, "questions": q}, sort_keys=True)
    d = hashlib.sha256((raw + "#0").encode()).hexdigest()
    p = jev.CACHE / d[:2] / f"{d}.json"
    if p.exists():
        hits += 1
        r = json.loads(p.read_text())
        tr = T.parse(r["answers"], c)
        same += T.kind(tr) == t["kind_today"]
print(f"stage A cache hits {hits}/{len(turns)}, same kind {same}/{hits}")
if len(sys.argv) > 1:
    t = turns[0]
    st, _, c = T.call(t["final"], t["title"], t["project"])
    r = jev.ask(st, V.bundle("newC", c))
    print({k: r["answers"].get(k) for k in ("state", "next", "trivial", "unverified", "urgency")})
    print({k: v for k, v in r.items() if k != "answers"})
