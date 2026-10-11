"""What shipped (main 8bdd90c): the post-turn triage with `userStep` and `notable`, measured on the same 505 turns, labels
and behavioural truth as score.py.

    python3 v2/triage_eval/shipped.py [--no-call]  →  v2/data/triage_eval/jev_shipped.jsonl, stdout

Ported from main's Swift, verbatim:
- RouterTriage.questions: state hints done/asks/waiting reworded, waitingOn.review "by someone other than the user";
- RouterAttention.trivialExtra (unchanged) and RouterTriage.nextExtra (`userStep`, `notable`: noul with yes/no criteria,
  encoded by JevClient as criteria {"true": …, "false": …});
- RouterTriage.next: userStep ≥ stepSure (0.6) → you; nothing only when state == done, p(done) ≥ doneSure (0.7), userStep
  ≤ quiet (0.2), notable ≤ quiet, and not unverified; else note (nil when neither answered);
- RouterTriage.kind: done/progress/nil with next == you → finish (blocked/circles still stuck);
- RouterCard.tier: needsYou kinds → 1; waiting → 2 (a fresh turn has no `ready`); done: no triage → 3, unverified → 3,
  trivial and state == done → 4, next == nothing → 4, else 3.
The triage's choices go through `.choice` (a Swift dictionary, not JevClient.orderedObject), so their order is not the
app's own either way: sent with sorted keys as stage A did (JEV_ORDERED unset). Not ported: wait options, circles,
depends, the app's summary (`blocked` = false)."""
import argparse
import collections
import copy
import json
import pathlib
import random
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROUTER / "v2" / "build"), str(ROUTER)]
import jev  # noqa: E402
import triage as T  # noqa: E402
import score as SC  # noqa: E402

DATA = ROUTER / "v2" / "data" / "triage_eval"

STATE_HINTS = {
    "done": "It completed the work it was asked for and reports it; some follow-through by the user may remain",
    "asks": "It needs the user's answer, decision, review, test or action now before it can go on: questions in prose, or something to choose or decide",
    "approval": "It asks permission before doing something consequential: pushing, publishing, deleting, driving the screen, spending money",
    "blocked": "It hit an error, lacks access or a permission, or can't proceed without help",
    "waiting": "Its work is blocked by a running process, an event or someone other than the user: CI or checks, tests running, a deploy, another session, someone else's review, a rate limit; nothing is needed from the user now",
    "progress": "It reports partial progress and isn't finished, without asking anything",
}
REVIEW = "A review by someone other than the user"
TRIVIAL = "Is this turn trivial: a short reply, an acknowledgment or a small step, with nothing in it the user would want to look at?"


def noul(instructions, yes=None, no=None):
    crit = {}
    if yes:
        crit["true"] = yes
    if no:
        crit["false"] = no
    return {"type": "noul", "instructions": instructions, "criteria": crit or None}


def bundle(cands):
    q = T.questions(cands)
    q["state"] = T._choice(T.STATES, STATE_HINTS, q["state"]["instructions"])
    q["waitingOn"] = copy.deepcopy(q["waitingOn"])
    q["waitingOn"]["criteria"]["review"] = REVIEW
    q["trivial"] = noul(TRIVIAL)
    q["userStep"] = noul("Does the final message leave a concrete action the user needs to take now to complete, apply, verify or continue this work?",
                         "A required answer, decision, approval, merge, push, relaunch, command or manual test",
                         "No required user action now. Optional suggestions, offers of further work, and steps that wait on unfinished outside work don't count")
    q["notable"] = noul("Does the final message report a material caveat, risk, unverified success claim, consequential decision the session made on its own, or important finding?",
                        "It reports at least one such thing, whether or not the user also has something to do",
                        "It reports nothing like that: a routine completion or acknowledgement")
    return q


def yes(ans, k):
    a = (ans or {}).get(k)
    return None if not a or a.get("noul") is None else a["noul"]


def tier(ans, cands, step_sure=0.6, done_sure=0.7, quiet=0.2, trivial_settles=True):
    """RouterTriage.parse + extras' apply + kind + RouterCard.tier. Also returns the parsed state and next."""
    if ans is None:
        return 3, None, None          # no triage: a done card with none is Worth a look
    t = T.parse(ans, cands)
    unverified, trivial = t["unverified"], (yes(ans, "trivial") or 0) >= 0.8
    step, notable = yes(ans, "userStep"), yes(ans, "notable")
    if step is None and notable is None:
        nxt = None
    elif (step or 0) >= step_sure:
        nxt = "you"
    else:
        p_done = ((ans.get("state") or {}).get("probabilities") or {}).get("done") or 0
        if (t["state"] == "done" and p_done >= done_sure and step is not None and step <= quiet
                and notable is not None and notable <= quiet and not unverified):
            nxt = "nothing"
        else:
            nxt = "note"
    s = t["state"]
    if s in ("asks", "approval", "blocked"):
        return 1, s, nxt
    if s == "waiting":
        return 2, s, nxt
    if nxt == "you":
        return 1, s, nxt              # finish
    if unverified:
        return 3, s, nxt
    if trivial_settles and trivial and s == "done":
        return 4, s, nxt
    return (4 if nxt == "nothing" else 3), s, nxt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-call", action="store_true")
    a = ap.parse_args()
    turns = [json.loads(l) for l in open(DATA / "turns.jsonl")]
    out_path = DATA / "jev_shipped.jsonl"
    if not a.no_call:
        calls = []
        for t in turns:
            st, _, cands = T.call(t["final"], t["title"], t["project"])
            calls.append((st, bundle(cands), cands))

        def one(c):
            try:
                return jev.ask(c[0], c[1])
            except Exception as e:  # noqa: BLE001
                return {"_error": str(e)[:200]}

        with ThreadPoolExecutor(8) as pool:
            res = list(pool.map(one, calls))
        with open(out_path, "w") as f:
            for t, c, r in zip(turns, calls, res):
                f.write(json.dumps({"id": t["id"], "candidates": c[2], "answers": r.get("answers")}) + "\n")
        print("failed", sum(r.get("answers") is None for r in res))
    sh = SC.load("jev_shipped.jsonl")
    old = SC.load("jev_old.jsonl")
    rel = SC.load("relation.jsonl")
    lab = {m: SC.load(f"labels_{m}.jsonl") for m in ("sonnet", "sol")}
    ids = [t["id"] for t in turns]
    B = [SC.btier(t, rel.get(t["id"])) for t in turns]
    L = {m: [lab[m][i].get("tier") for i in ids] for m in lab}
    cons = [x if x == y else None for x, y in zip(L["sonnet"], L["sol"])]
    n_kind = collections.Counter(t["kind_today"] for t in turns)
    w = [SC.POOL[t["kind_today"]] / n_kind[t["kind_today"]] for t in turns]

    def dist(pred):
        tot = sum(w)
        return "/".join(str(round(100 * sum(wi for p, wi in zip(pred, w) if p == k) / tot)) for k in SC.TIERS)

    def leaks(pred):
        c1 = [p for p, g in zip(pred, cons) if g == 1]
        b1 = [p for p, b in zip(pred, B) if b == 1]
        either = [p for p, g, b in zip(pred, cons, B) if g == 1 or b == 1]
        return (sum(p == 4 for p in c1), len(c1), sum(p == 4 for p in b1), len(b1), sum(p == 4 for p in either), len(either))

    def line(name, pred):
        l = leaks(pred)
        acc = sum(p == g for p, g in zip(pred, cons) if g) / sum(1 for g in cons if g)
        hist = sum(p == 4 for p in pred)
        # what reaches history, and what of it is required (either truth)
        print(f"{name:40s} leaks cons-t1 {l[0]}/{l[1]} ({100*l[0]/l[1]:.1f}%), B1 {l[2]}/{l[3]} ({100*l[2]/l[3]:.1f}%), either {l[4]}/{l[5]}"
              f" | history n={hist} ({dist(pred).split('/')[3]}% pool) | dist {dist(pred)} | acc {acc:.2f} κ {SC.kappa(zip(pred, cons)):.2f}")

    before = [SC.old_tier(old[i]["answers"], old[i]["candidates"], three=False) for i in ids]
    before3 = [SC.old_tier(old[i]["answers"], old[i]["candidates"]) for i in ids]
    res = {i: tier(sh[i]["answers"], sh[i]["candidates"]) for i in ids}
    pred = [res[i][0] for i in ids]
    print("PRIORITY: required actions sent to history (tier 4)")
    line("before (today, done → 4)", before)
    line("shipped", pred)

    print("\nper-tier P/R vs consensus labels | vs behaviour")
    for name, p_ in (("before", before3), ("shipped", pred)):
        print(f"  {name:8s}", " ".join(f"t{k} {SC.prf(p_, cons, k)[0]:.2f}/{SC.prf(p_, cons, k)[1]:.2f}" for k in SC.TIERS),
              "|", " ".join(f"t{k} {SC.prf(p_, B, k)[0]:.2f}/{SC.prf(p_, B, k)[1]:.2f}" for k in SC.TIERS))
    print("\nconfusion, rows = consensus label, cols = shipped tier")
    m = collections.Counter((g, p) for p, g in zip(pred, cons) if g)
    for g in SC.TIERS:
        print(f"  label {g}: " + "  ".join(f"{m[(g, p)]:4d}" for p in SC.TIERS))
    print("confusion, rows = behaviour, cols = shipped tier")
    m = collections.Counter((b, p) for p, b in zip(pred, B))
    for b in SC.TIERS:
        print(f"  B{b}:      " + "  ".join(f"{m[(b, p)]:4d}" for p in SC.TIERS))
    print("\nkinds before → shipped (state moves)")
    ks = collections.Counter()
    for i in ids:
        o = T.parse(old[i]["answers"], old[i]["candidates"])["state"]
        ks[f"{o}->{res[i][1]}"] += o != res[i][1]
    print(" ", dict(x for x in ks.most_common() if x[1]))
    print("  states before", dict(collections.Counter(T.parse(old[i]["answers"], old[i]["candidates"])["state"] for i in ids)))
    print("  states shipped", dict(collections.Counter(res[i][1] for i in ids)))
    print("  next shipped (done/progress/nil)", dict(collections.Counter(res[i][2] for i in ids if res[i][1] in ("done", "progress", None))))
    blk = collections.Counter()
    for i in ids:
        bl = lab["sonnet"][i].get("blocker")
        if bl and bl != "none" and bl == lab["sol"][i].get("blocker"):
            blk[(bl, T.parse(old[i]["answers"], old[i]["candidates"])["state"], res[i][1])] += 1
    print("  label blocker × state before × shipped:", {f"{k[0]}:{k[1]}->{k[2]}": v for k, v in sorted(blk.items(), key=lambda x: -x[1])})

    print("\nwhat reaches history, and why (shipped)")
    why = collections.Counter()
    for i in ids:
        if res[i][0] == 4:
            why["trivial" if res[i][2] != "nothing" else "nothing"] += 1
    print(" ", dict(why), "| history turns by consensus label",
          dict(collections.Counter(g for p, g in zip(pred, cons) if p == 4)), "by behaviour", dict(collections.Counter(b for p, b in zip(pred, B) if p == 4)))

    print("\nsweeps (one threshold at a time, others shipped)")
    for name, kw in ([("userStep", {"step_sure": v}) for v in (0.5, 0.6, 0.7)]
                     + [("p(done)", {"done_sure": v}) for v in (0.6, 0.7, 0.8)]
                     + [("ceilings", {"quiet": v}) for v in (0.1, 0.2, 0.3)]
                     + [("no trivial settle", {"trivial_settles": False})]):
        p_ = [tier(sh[i]["answers"], sh[i]["candidates"], **kw)[0] for i in ids]
        line(f"{name} {list(kw.values())[0]}", p_)
        print(f"{'':40s} t1 P/R cons {SC.prf(p_, cons, 1)[0]:.2f}/{SC.prf(p_, cons, 1)[1]:.2f}  t4 P/R cons {SC.prf(p_, cons, 4)[0]:.2f}/{SC.prf(p_, cons, 4)[1]:.2f}")
    print("\ngrid (step 0.6): p(done) × ceiling → history n, leaks cons-t1 / B1")
    for d in (0.6, 0.7, 0.8):
        row = []
        for qv in (0.1, 0.2, 0.3, 0.4):
            p_ = [tier(sh[i]["answers"], sh[i]["candidates"], done_sure=d, quiet=qv)[0] for i in ids]
            l = leaks(p_)
            row.append(f"q{qv}: {sum(x == 4 for x in p_):3d} ({l[0]}/{l[2]})")
        print(f"  done≥{d}: " + "  ".join(row))
    # leaked items detail (ids only, counts by today kind)
    lk = [i for i, p, g, b in zip(ids, pred, cons, B) if p == 4 and (g == 1 or b == 1)]
    print("\nleaked ids:", lk)
    rnd = random.Random(0)
    (DATA / "shipped_pred.json").write_text(json.dumps({i: res[i] for i in ids}))
    _ = rnd


if __name__ == "__main__":
    main()
