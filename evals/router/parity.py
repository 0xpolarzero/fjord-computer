"""What the measured policy decided, with its inputs, for Fjord's tests to check RouteFusion and RouterLexical against.

python3 parity.py  →  Tests/FjordTests/Fixtures/router-fusion-parity.json (written cases, synth and heldout, their boards
scrubbed of real text by `scrub`;
real boards stay on this machine). Policy: explore.final3 (round 3), format combo-o."""
import copy
import json
import pathlib
import re

import bench
import formats
import run
from explore import final3
from explore import fusion as Fu
from explore import lexical as L
from explore import recency as R

OUT = pathlib.Path(__file__).parent.parent.parent / "Tests" / "FjordTests" / "Fixtures" / "router-fusion-parity.json"


WORD = re.compile(r"[^\W_]+")


def scrub(case):
    """The case with its board's text replaced: the round-1 boards were copied from real sessions (titles, summaries,
    answers), and the fixture is committed. Every word not in the (written) message becomes a numbered placeholder,
    the same word the same placeholder within the case, so what overlaps the message, and what overlaps between
    sessions, still does for BM25; no real word is left, and numbering (not hashing) leaves nothing to look up."""
    keep = {w.lower() for w in WORD.findall(case["message"])}
    names = {}

    def text(value):
        if not isinstance(value, str):
            return value
        return WORD.sub(lambda m: m.group(0) if m.group(0).lower() in keep
                        else names.setdefault(m.group(0).lower(), f"w{len(names) + 1}"), value)

    case = copy.deepcopy(case)
    board = case["board"]
    for s in board["sessions"]:
        for key in ("title", "activity", "summary"):
            s[key] = text(s.get(key))
    for card in board.get("cards", []):
        card["text"] = text(card.get("text"))
    for h in board.get("history", []):
        h["you"] = text(h.get("you"))
    case.pop("why", None)
    return case


def target(dest, board_ids):
    return f"session:{dest}" if dest in board_ids else dest


def main():
    # The weights Fjord carries (RouteFusion's tables), so the fixture checks Swift computes as Python does with them.
    # final3.fitted's setup without its fit: the lexical fields as features, the tie-inclusive `agree`.
    from v2.run.episodes import _shipped_weights
    L.install()
    Fu.case_features = final3.case_features
    L.STATE["fields"] = True
    w, v = _shipped_weights()
    final3._FIT["combo-o"] = (w, v)
    pol = final3.make(w, v)
    out = []
    for s in ("synth", "heldout"):
        cases = {c["id"]: c for c in bench.load_set(s)}
        for row in run.load(f"combo-o@{s}"):
            if row["order"] != 0:
                continue
            c = scrub(cases[row["id"]])
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


CAPS_OUT = OUT.with_name("router-capabilities-parity.json")


def capabilities():
    """The two texts of format capabilities-o, as Fjord words them (the eval ran under the name Lookout)."""
    from explore import capabilities as C
    name = lambda t: t.replace("Lookout", "Fjord")
    CAPS_OUT.write_text(json.dumps({"change_fjord": name(C.change_fjord(C.ADOPTED_EXTRA)),
                                    "gate_setting": name(C.gate_setting(C.ADOPTED_EXTRA)["instructions"]["question"])},
                                   ensure_ascii=False, indent=1))
    print("capability texts →", CAPS_OUT)


if __name__ == "__main__":
    import sys
    capabilities() if sys.argv[1:] == ["capabilities"] else main()
