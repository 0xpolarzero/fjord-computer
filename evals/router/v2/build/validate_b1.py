"""Checks stage B1's outputs: v2/data/episodes/raw/real.jsonl and v2/data/packets/*.jsonl.

    python3 v2/build/validate_b1.py   (run from evals/router; prints counts and problems, exits 1 on any problem)

real: the runner's own schema check (v2.run.episodes.validate_episode; a null gold.ask, left for the labellers, is
checked as "allowed"), unique ids, every target on the board when its submit plays (deltas applied as the runner
does), new:<project> among the projects. packets: unique ids, family/flow from BENCHMARK.md, three style examples,
targets and context ids on the board, the state accepted by the runner's check. Both: a redaction scan for key
patterns over every text value (ids skipped)."""
import collections
import copy
import json
import pathlib
import sys

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1]))
import episode_common as C  # noqa: E402
from v2.run import episodes as R  # noqa: E402

SKIP = {"id", "session", "to", "replyTo", "cards-", "anchors", "moment", "packet", "episode_id", "group", "groups",
        "anchor", "went_to", "intended", "acceptable", "clarify", "target", "target_hint", "pinned", "shown", "notTo"}


def texts(obj, key=None):
    if key in SKIP:
        return
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, list):
        for x in obj:
            yield from texts(x, key)
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from texts(v, k)


def scan(obj):
    return [hit for t in texts(obj) for hit in C.leaks(t)]


def check_real(path, problems):
    eps = [json.loads(line) for line in open(path)]
    ids = collections.Counter(e["id"] for e in eps)
    problems += [f"real: duplicate id {i}" for i, n in ids.items() if n > 1]
    stats = collections.Counter()
    for e in eps:
        x = copy.deepcopy(e)
        for ev in x["events"]:
            if ev["kind"] == "submit":
                if ev["gold"]["ask"] is not None:
                    problems.append(f"real {e['id']}: ask should be null for the labellers")
                ev["gold"]["ask"] = "allowed"
        try:
            R.validate_episode(x)
        except ValueError as err:
            problems.append(f"real {e['id']}: {err}")
        st = copy.deepcopy(e["state"])
        started = set()
        for ev in e["events"]:
            if ev["kind"] == "board":
                try:
                    R.apply_delta(st, ev["delta"])
                except ValueError as err:
                    problems.append(f"real {e['id']}: delta {err}")
            elif ev["kind"] == "submit":
                stats["submits"] += 1
                t = ev["gold"]["intended"]
                if t.startswith("new:"):
                    if t[4:] not in st["projects"]:
                        problems.append(f"real {e['id']}: {t} not a known project")
                    started.add("started-" + ev["id"])
                elif t[8:] not in started and t[8:] not in {s["id"] for s in st["sessions"]}:
                    problems.append(f"real {e['id']}: {t} not on the board at {ev['id']}")
        hits = scan(e)
        if hits:
            problems.append(f"real {e['id']}: key-like strings {hits[:3]}")
    multi = [e for e in eps if sum(ev["kind"] == "submit" for ev in e["events"]) > 1]
    return {"episodes": len(eps), "multi_submit": len(multi), "multi_share": round(len(multi) / len(eps), 3),
            "submits": stats["submits"], "bytes": path.stat().st_size,
            "groups": len({e["group"] for e in eps}),
            "groups_touched": len({g for e in eps for g in e["provenance"]["groups"]}),
            "source": dict(collections.Counter(e["provenance"]["source"] for e in eps)),
            "flow": dict(collections.Counter(e["tags"]["flow"] for e in eps).most_common()),
            "primary": dict(collections.Counter(e["tags"]["primary"] for e in eps).most_common()),
            "submit_family": dict(collections.Counter(ev["tags"]["family"] for e in eps for ev in e["events"]
                                                      if ev["kind"] == "submit").most_common()),
            "single_transition": dict(collections.Counter(
                next(s for s in e["tags"]["slices"] if s in {"same", "switch", "new"})
                for e in eps if e["tags"]["flow"] == "single")),
            "lang": dict(collections.Counter(e["tags"]["lang"] for e in eps))}


def check_packets(paths, problems):
    seen, eids = set(), set()
    out = {}
    allp = []
    for path in paths:
        rows = [json.loads(line) for line in open(path)]
        allp += rows
        for p in rows:
            for key, bag in (("packet", seen), ("episode_id", eids)):
                if p[key] in bag:
                    problems.append(f"packets: duplicate {key} {p[key]}")
                bag.add(p[key])
            if p["family"] not in C.FAMILIES or p["flow"] not in C.FLOWS:
                problems.append(f"{p['packet']}: unknown family/flow")
            if len(p["style"]["examples"]) != 3:
                problems.append(f"{p['packet']}: {len(p['style']['examples'])} style examples")
            if p["mode"] not in {"rewrite", "goal"} or (p["mode"] == "rewrite") != ("real" in p):
                problems.append(f"{p['packet']}: mode/task mismatch")
            st = p["state"]
            sids, cids = {s["id"] for s in st["sessions"]}, {c["id"] for c in st["cards"]}
            target = p["real"]["went_to"] if p["mode"] == "rewrite" else p["target_hint"]
            ok = (target in {"change_lookout", "question", "compound"} or
                  (target.startswith("new:") and target[4:] in st["projects"]) or
                  (target.startswith("session:") and target[8:] in sids))
            if not ok:
                problems.append(f"{p['packet']}: target {target} not on the board")
            ctx = p["contexts"]
            if ctx.get("replyTo") and ctx["replyTo"] not in cids:
                problems.append(f"{p['packet']}: replyTo absent")
            for k in ("pinned", "shown", "notTo"):
                if ctx.get(k) and ctx[k].startswith("session:") and ctx[k][8:] not in sids:
                    problems.append(f"{p['packet']}: {k} absent")
            if ctx.get("pills") and not all(x in st["projects"] for x in ctx["pills"]):
                problems.append(f"{p['packet']}: pill not a project")
            probe = {"schema": 2, "id": p["episode_id"], "group": p["anchor"]["group"], "state": st,
                     "events": [{"id": "e1", "kind": "submit", "message": "x",
                                 "gold": {"intended": target, "ask": "allowed"}}]}
            try:
                R.validate_episode(probe)
            except ValueError as err:
                problems.append(f"{p['packet']}: {err}")
            hits = scan(p)
            if hits:
                problems.append(f"{p['packet']}: key-like strings {hits[:3]}")
        out[path.stem] = {"packets": len(rows), "bytes": path.stat().st_size,
                          "modes": dict(collections.Counter(p["mode"] for p in rows))}
    out["total"] = {
        "packets": len(allp),
        "family": dict(sorted(collections.Counter(p["family"] for p in allp).items())),
        "flow": dict(sorted(collections.Counter(p["flow"] for p in allp).items())),
        "style": dict(collections.Counter(p["style"]["profile"] for p in allp).most_common()),
        "contexts": dict(collections.Counter(k for p in allp for k in p["contexts"]).most_common()),
        "groups": len({p["anchor"]["group"] for p in allp}),
        "moments": len({p["anchor"]["moment"] for p in allp})}
    return out


def main():
    problems = []
    report = {"real": check_real(C.DATA / "episodes" / "raw" / "real.jsonl", problems),
              "packets": check_packets(sorted((C.DATA / "packets").glob("*.jsonl")), problems)}
    report["problems"] = len(problems)
    print(json.dumps(report, indent=1, ensure_ascii=False))
    for p in problems[:40]:
        print("PROBLEM", p)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
