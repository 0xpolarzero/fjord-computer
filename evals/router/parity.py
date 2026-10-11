"""What the measured policy decided, with its inputs, for Lookout's tests to check RouteFusion and RouterLexical against.

python3 parity.py  →  Tests/LookoutTests/Fixtures/router-fusion-parity.json (written cases only: synth and heldout;
real boards stay on this machine). Policy: explore.final3 (round 3), format combo-o."""
import json
import pathlib

import bench
import formats
import run
from explore import final3
from explore import fusion as Fu
from explore import lexical as L
from explore import recency as R

OUT = pathlib.Path(__file__).parent.parent.parent / "Tests" / "LookoutTests" / "Fixtures" / "router-fusion-parity.json"


def target(dest, board_ids):
    return f"session:{dest}" if dest in board_ids else dest


def main():
    w, v = final3.fitted()
    pol = final3.make(w, v)
    out = []
    for s in ("synth", "heldout"):
        cases = {c["id"]: c for c in bench.load_set(s)}
        for row in run.load(f"combo-o@{s}"):
            if row["order"] != 0:
                continue
            c = cases[row["id"]]
            b = c["board"]
            ids = {x["id"] for x in b["sessions"]}
            r = run.reading(row)
            k, dest = pol(r, c)
            ordered = {x["id"] for x in formats.sessions_ordered(b)}
            hist = sorted(b.get("history", []), key=lambda h: h["ago_min"])
            g = r.get("gates") or {}
            out.append({
                "id": c["id"],
                "message": c["message"],
                "route": {target(d, ids): p for d, p in r["dests"].items()},
                "reply": r.get("replies") or {},
                "next": {k[len("gate_next_"):]: x for k, x in g.items() if k.startswith("gate_next_")},
                "gates": {k: x for k, x in g.items() if not k.startswith("gate_next_")},
                "latest": [x["id"] for x in R.finished_by_recency(b) if x["id"] in ordered],
                "running": [x["id"] for x in b["sessions"] if x.get("running") and x["id"] in ordered],
                "idle": {x["id"]: x.get("idle_min", 0) for x in b["sessions"] if x["id"] in ordered},
                "lastTold": hist[0]["to"] if hist and hist[0]["to"] in ids else None,
                "leaves": [x["id"] for x in b["sessions"] if final3.terse_ok(c, x["id"])],
                "sessions": {x["id"]: {"title": x["title"],
                                       "turns": [list(t) for t in L.board_fields(c, x, "turns")]} for x in b["sessions"]},
                "lexical": {name: L.lex(c, cfg) for name, cfg in L.FIELDS.items()},
                "sure": k == "send",
                "top": target(dest, ids) if k == "send" else None,
            })
    # BM25 scores are normalised to the best session, as RouterLexical returns them.
    for case in out:
        for name, sc in case["lexical"].items():
            m = max(sc.values(), default=0)
            case["lexical"][name] = {d: (x / m if m else 0) for d, x in sc.items()}
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0))
    print(len(out), "cases →", OUT)


if __name__ == "__main__":
    main()
