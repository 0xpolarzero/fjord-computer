"""Why the shipped history stays empty, and what wider gates would cost: which of RouterTriage.next's conditions fail on
turns Jev calls done, and the trade-off between history size and leaks of required actions when the ceilings on
userStep and notable are loosened separately.   python3 v2/triage_eval/shipped_diag.py"""
import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROUTER / "v2" / "build"), str(ROUTER)]
import score as SC  # noqa: E402
import shipped as SH  # noqa: E402
import triage as T  # noqa: E402

turns = [json.loads(l) for l in open(SH.DATA / "turns.jsonl")]
sh = SC.load("jev_shipped.jsonl")
rel = SC.load("relation.jsonl")
lab = {m: SC.load(f"labels_{m}.jsonl") for m in ("sonnet", "sol")}
ids = [t["id"] for t in turns]
B = {t["id"]: SC.btier(t, rel.get(t["id"])) for t in turns}
cons = {i: lab["sonnet"][i].get("tier") for i in ids if lab["sonnet"][i].get("tier") == lab["sol"][i].get("tier")}

rows = []
for i in ids:
    a = sh[i]["answers"]
    t = T.parse(a, sh[i]["candidates"])
    rows.append({"id": i, "state": t["state"], "pdone": a["state"]["probabilities"].get("done", 0), "step": SH.yes(a, "userStep"),
                 "notable": SH.yes(a, "notable"), "unv": t["unverified"], "unv_p": SH.yes(a, "unverified"),
                 "trivial": SH.yes(a, "trivial"), "tier": SH.tier(a, sh[i]["candidates"])[0]})
done = [r for r in rows if r["state"] == "done"]
print(f"state done: {len(done)}; p(done)≥0.7 {sum(r['pdone'] >= 0.7 for r in done)}; userStep≤0.2 {sum(r['step'] <= 0.2 for r in done)};"
      f" notable≤0.2 {sum(r['notable'] <= 0.2 for r in done)}; not unverified {sum(not r['unv'] for r in done)}; trivial≥0.8 {sum(r['trivial'] >= 0.8 for r in done)}")


def q(xs):
    xs = sorted(xs)
    return [round(xs[int(len(xs) * f)], 2) for f in (0.1, 0.25, 0.5, 0.75, 0.9)]


print("among done: notable quantiles", q([r["notable"] for r in done]), "userStep", q([r["step"] for r in done]), "unverified p", q([r["unv_p"] for r in done]))
for lbl in (1, 3, 4):
    sel = [r for r in done if cons.get(r["id"]) == lbl]
    if sel:
        print(f"  consensus {lbl} (n={len(sel)}): notable {q([r['notable'] for r in sel])} userStep {q([r['step'] for r in sel])}")


def hist(r, pd, sq, nq, unv=True):
    return (r["state"] == "done" and r["pdone"] >= pd and r["step"] <= sq and r["notable"] <= nq and (not unv or not r["unv"])
            and r["step"] < 0.6)


print("\nhistory if: state done, p(done) ≥ 0.7, userStep ≤ s, notable ≤ n, not unverified   → n | leaks cons-t1 | leaks B1 | cons-t4 recall (of 27) | cons labels of history")
c4 = sum(1 for v in cons.values() if v == 4)
for s in (0.2, 0.3, 0.4, 0.5):
    for n in (0.2, 0.4, 0.6, 0.8, 1.0):
        h = [r for r in rows if hist(r, 0.7, s, n)]
        lc = sum(cons.get(r["id"]) == 1 for r in h)
        lb = sum(B[r["id"]] == 1 for r in h)
        print(f"  step≤{s} notable≤{n}: {len(h):3d} | {lc} | {lb} | {sum(cons.get(r['id']) == 4 for r in h)}/{c4} | {dict(collections.Counter(cons.get(r['id']) for r in h))}")
print("\nleaked (B1 in history), shipped:")
for r in rows:
    if r["tier"] == 4 and B[r["id"]] == 1:
        print(" ", r["id"], {k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items() if k != "id"}, "relation", rel.get(r["id"], {}).get("relation"))
