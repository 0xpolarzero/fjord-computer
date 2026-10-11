"""What the measured policy decided, with its inputs, for Lookout's tests to check RouteFusion.decide against.

python3 parity.py  →  Tests/LookoutTests/Fixtures/router-fusion-parity.json (written cases only: synth and heldout;
real boards stay on this machine)."""
import json
import pathlib

import bench
import run
from explore import fuse2
from explore import fusion as Fu
from explore import recency as R

OUT = pathlib.Path(__file__).parent.parent.parent / "Tests" / "LookoutTests" / "Fixtures" / "router-fusion-parity.json"


def target(dest, board_ids):
    return f"session:{dest}" if dest in board_ids else dest


def main():
    Fu._patch_reading()
    pol = fuse2.guarded
    out = []
    for s in ("synth", "heldout"):
        cases = {c["id"]: c for c in bench.load_set(s)}
        for row in run.load(f"combo@{s}"):
            if row["order"] != 0:
                continue
            c = cases[row["id"]]
            b = c["board"]
            ids = {x["id"] for x in b["sessions"]}
            r = run.reading(row)
            k, w = pol(r, c)
            ordered = {x["id"] for x in __import__("formats").sessions_ordered(b)}
            hist = sorted(b.get("history", []), key=lambda h: h["ago_min"])
            g = r.get("gates") or {}
            out.append({
                "id": c["id"],
                "message": c["message"],
                "route": {target(d, ids): p for d, p in r["dests"].items()},
                "reply": r.get("replies") or {},
                "next": {k[len("gate_next_"):]: v for k, v in g.items() if k.startswith("gate_next_")},
                "gates": {k: v for k, v in g.items() if not k.startswith("gate_next_")},
                "latest": [x["id"] for x in R.finished_by_recency(b) if x["id"] in ordered],
                "running": [x["id"] for x in b["sessions"] if x.get("running") and x["id"] in ordered],
                "idle": {x["id"]: x.get("idle_min", 0) for x in b["sessions"] if x["id"] in ordered},
                "lastTold": hist[0]["to"] if hist and hist[0]["to"] in ids else None,
                "sure": k == "send",
                "top": target(w, ids) if k == "send" else None,
            })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0))
    print(len(out), "cases →", OUT)


if __name__ == "__main__":
    main()
