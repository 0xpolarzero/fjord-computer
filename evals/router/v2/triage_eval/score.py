"""Triage eval, steps 2 and 4b: behavioural ground truth, the tiers each Jev configuration gives, and how they compare.

    python3 v2/triage_eval/score.py [--detail]  →  stdout, and v2/data/triage_eval/scores.json

Behavioural tier (noisy; rules in REPORT.md):
  B2  something else spoke first: a task notification, a peer session's message or a CI event reached the session
      before your next message (or your message says the awaited thing finished), and your message didn't answer,
      approve or finish what the turn asked;
  B1  your next message there answered it, approved it, did or reported its last step, or told it to continue;
  B3  your next message reacted to its content (a correction, a comment, a question about a result or caveat);
  B4  your next message was a new task, or you never wrote there again.
Label tier: Sonnet's and Sol's blind tiers; "consensus" where they agree.
Jev tiers: today's kinds mapped (asks, approval, stuck → 1; waiting → 2; done → 4, or 3 when unverified), and the
planned bundles with each floor, fallback and trivial rule."""
import argparse
import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
sys.path[:0] = [str(ROUTER / "v2" / "build"), str(ROUTER)]
import triage as T  # noqa: E402

DATA = ROUTER / "v2" / "data" / "triage_eval"
POOL = {"asks": 658, "done": 558, "waiting": 153, "approval": 146, "stuck": 28}
TIERS = [1, 2, 3, 4]


def load(name):
    p = DATA / name
    return {r["id"]: r for r in map(json.loads, open(p))} if p.exists() else {}


def btier(t, rel):
    r = (rel or {}).get("relation")
    if r in ("answer", "approve", "finish", "continue"):
        return 1
    if t["agent_before_reply"] or (rel or {}).get("wait_resolved"):
        return 2
    if r == "react":
        return 3
    return 4


def yes(ans, key):
    return ((ans or {}).get(key) or {}).get("noul") or 0


def choice(ans, key):
    a = (ans or {}).get(key) or {}
    c = a.get("choice")
    return c, (a.get("probabilities") or {}).get(c) or 0


def old_tier(ans, cands, three=True):
    if ans is None:
        return 4
    t = T.parse(ans, cands)
    k = T.kind(t)
    if k in ("asks", "approval", "stuck"):
        return 1
    if k == "waiting":
        return 2
    return 3 if three and t["unverified"] else 4


def new_tier(ans, cands, shape, floor, fallback="note", trivial="note", unverified=True):
    """shape: C (choice `next`) or G (gates `step`, `worth`). fallback: what an unsure `next` becomes (note, nothing).
    trivial: which tiers a sure trivial turn drops to 4 from (note: 3 only; all: 1 and 3; off)."""
    if ans is None:
        return 4
    t = T.parse(ans, cands)
    k = T.kind(t)
    if k in ("asks", "approval", "stuck"):
        return 1
    if k == "waiting":
        return 2
    if shape == "C":
        c, p = choice(ans, "next")
        nxt = c if p >= floor else fallback
    else:
        s, w = yes(ans, "step"), yes(ans, "worth")
        if s >= floor:
            nxt = "you"
        elif w >= floor:
            nxt = "note"
        elif 1 - s >= floor and 1 - w >= floor:
            nxt = "nothing"
        else:
            nxt = fallback
    tier = {"you": 1, "note": 3, "nothing": 4}.get(nxt, 3)
    if unverified and tier == 4 and t["unverified"]:
        tier = 3
    if yes(ans, "trivial") >= 0.8 and ((trivial == "note" and tier == 3) or (trivial == "all" and tier in (1, 3))):
        tier = 4
    return tier


def kappa(pairs):
    pairs = [(a, b) for a, b in pairs if a is not None and b is not None]
    n = len(pairs)
    if not n:
        return float("nan")
    po = sum(a == b for a, b in pairs) / n
    ca, cb = collections.Counter(a for a, _ in pairs), collections.Counter(b for _, b in pairs)
    pe = sum(ca[k] * cb[k] for k in set(ca) | set(cb)) / n / n
    return (po - pe) / (1 - pe) if pe < 1 else float("nan")


def prf(pred, gold, tier):
    tp = sum(1 for p, g in zip(pred, gold) if g is not None and p == tier and g == tier)
    fp = sum(1 for p, g in zip(pred, gold) if g is not None and p == tier and g != tier)
    fn = sum(1 for p, g in zip(pred, gold) if g is not None and p != tier and g == tier)
    P = tp / (tp + fp) if tp + fp else float("nan")
    R = tp / (tp + fn) if tp + fn else float("nan")
    return P, R


def confusion(pred, gold):
    m = collections.Counter((g, p) for p, g in zip(pred, gold) if g is not None)
    return {f"{g}->{p}": m[(g, p)] for g in TIERS for p in TIERS if m[(g, p)]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--detail", action="store_true")
    a = ap.parse_args()
    turns = [json.loads(l) for l in open(DATA / "turns.jsonl")]
    rel = load("relation.jsonl")
    lab = {m: load(f"labels_{m}.jsonl") for m in ("sonnet", "sol")}
    jv = {v: load(f"jev_{v}.jsonl") for v in ("old", "newC", "newC0", "newG", "newG0", "newCO", "newGO")}
    ids = [t["id"] for t in turns]
    sample_n = collections.Counter(t["kind_today"] for t in turns)
    w = [POOL[t["kind_today"]] / sample_n[t["kind_today"]] for t in turns]

    B = [btier(t, rel.get(t["id"])) for t in turns]
    L = {m: [lab[m].get(i, {}).get("tier") for i in ids] for m in lab}
    cons = [a if a == b else None for a, b in zip(L["sonnet"], L["sol"])]
    out = {"n": len(turns), "behaviour": dict(collections.Counter(B))}

    print(f"turns {len(turns)}; today's kinds {dict(sample_n)}")
    print("behaviour tiers", dict(sorted(collections.Counter(B).items())))
    rels = collections.Counter((rel.get(i) or {}).get("relation") for i in ids)
    print("reply relations", dict(rels))
    gaps = [t["reply_gap_min"] for t in turns]
    print("replied ≤10 min", sum(g is not None and g <= 10 for g in gaps), "≤60", sum(g is not None and g <= 60 for g in gaps),
          "later", sum(g is not None and g > 60 for g in gaps), "never", sum(g is None for g in gaps))
    for m in L:
        print(f"labels {m}", dict(sorted(collections.Counter(L[m]).items(), key=lambda x: str(x[0]))))
    print("label agreement sonnet~sol: raw %.2f kappa %.2f; consensus on %d" % (
        sum(a == b for a, b in zip(L["sonnet"], L["sol"]) if a) / sum(1 for a, b in zip(L["sonnet"], L["sol"]) if a and b),
        kappa(zip(L["sonnet"], L["sol"])), sum(c is not None for c in cons)))
    def c3(x):
        return None if x is None else min(x, 3)
    for m in L:
        print(f"  {m} vs behaviour: kappa4 %.2f, kappa(1/2/3+4) %.2f, tier1 P/R %.2f/%.2f" % (
            kappa(zip(L[m], B)), kappa((c3(a), c3(b)) for a, b in zip(L[m], B)), *prf(L[m], B, 1)))
    print("  consensus vs behaviour: kappa(1/2/3+4) %.2f, tier1 P/R %.2f/%.2f" % (
        kappa((c3(a), c3(b)) for a, b in zip(cons, B) if a), *prf(cons, B, 1)))
    for flag in ("finish_up", "worth_a_look", "offer_only"):
        print(f"  {flag}: sonnet {sum(bool(lab['sonnet'].get(i, {}).get(flag)) for i in ids)}, "
              f"sol {sum(bool(lab['sol'].get(i, {}).get(flag)) for i in ids)}, both "
              f"{sum(bool(lab['sonnet'].get(i, {}).get(flag)) and bool(lab['sol'].get(i, {}).get(flag)) for i in ids)}")
    offers = [i for i in ids if lab["sonnet"].get(i, {}).get("offer_only") and lab["sol"].get(i, {}).get("offer_only")]
    bo = collections.Counter(B[ids.index(i)] for i in offers)
    print(f"  offer-only turns (both): behaviour {dict(bo)}; labels sonnet {dict(collections.Counter(lab['sonnet'][i]['tier'] for i in offers))}"
          f" sol {dict(collections.Counter(lab['sol'][i]['tier'] for i in offers))}")

    tot = sum(w)
    for name, lt in (("sonnet", L["sonnet"]), ("sol", L["sol"]), ("consensus", cons)):
        tw = sum(wi for x, wi in zip(lt, w) if x)
        print(f"  {name} labels, pool-weighted %:", {k: round(100 * sum(wi for x, wi in zip(lt, w) if x == k) / tw) for k in TIERS})
    cands = {i: (jv["old"].get(i) or {}).get("candidates") or [] for i in ids}
    configs = {"today (no tier 3)": lambda i: old_tier(jv["old"][i]["answers"], cands[i], three=False),
               "today + unverified→3": lambda i: old_tier(jv["old"][i]["answers"], cands[i])}
    for v, shape in (("newC", "C"), ("newC0", "C"), ("newG", "G"), ("newG0", "G"), ("newCO", "C"), ("newGO", "G")):
        if not jv[v]:
            continue
        for floor in (0.5, 0.6, 0.7, 0.8):
            for fb in ("note", "nothing"):
                configs[f"{v} f{floor} unsure→{fb}"] = (lambda v, shape, floor, fb: lambda i: new_tier(
                    jv[v][i]["answers"], cands[i], shape, floor, fb))(v, shape, floor, fb)
        configs[f"{v} f0.6 unsure→note trivial→all"] = (lambda v, shape: lambda i: new_tier(
            jv[v][i]["answers"], cands[i], shape, 0.6, "note", "all"))(v, shape)
        configs[f"{v} f0.6 unsure→note no-unverified"] = (lambda v, shape: lambda i: new_tier(
            jv[v][i]["answers"], cands[i], shape, 0.6, "note", "note", False))(v, shape)
    for v in ("newG", "newGO"):
        configs[f"{v} step≥0.6 worth≥0.7 →nothing (rec.)"] = (lambda v: lambda i: gate_tier(
            jv[v][i]["answers"], cands[i], 0.6, 0.7, "nothing"))(v)
    if not jv["old"]:
        return
    print("\nconfig | dist(pool-weighted %) | vs consensus: acc, kappa, P/R t1, t2, t3, t4 | vs behaviour: t1 P/R, t2 P/R, kappa(1/2/3+4)")
    res = {}
    for name, f in configs.items():
        pred = [f(i) for i in ids]
        tot = sum(w)
        dist = {k: round(100 * sum(wi for p, wi in zip(pred, w) if p == k) / tot) for k in TIERS}
        acc = sum(p == g for p, g in zip(pred, cons) if g) / sum(1 for g in cons if g)
        pr = {k: prf(pred, cons, k) for k in TIERS}
        prb = {k: prf(pred, B, k) for k in (1, 2)}
        kb = kappa((c3(p), c3(b)) for p, b in zip(pred, B))
        res[name] = {"dist": dist, "acc": acc, "kappa": kappa(zip(pred, cons)), "pr": pr, "prb": prb, "kb": kb,
                     "conf": confusion(pred, cons), "confb": confusion(pred, B)}
        print(f"{name:42s} | {dist[1]:2d}/{dist[2]:2d}/{dist[3]:2d}/{dist[4]:2d} | {acc:.2f} {res[name]['kappa']:.2f} "
              + " ".join(f"{pr[k][0]:.2f}/{pr[k][1]:.2f}" for k in TIERS)
              + f" | {prb[1][0]:.2f}/{prb[1][1]:.2f} {prb[2][0]:.2f}/{prb[2][1]:.2f} {kb:.2f}")
        res[name]["by_tier"] = {k: {"n": sum(p == k for p in pred),
                                    "B1": sum(p == k and b == 1 for p, b in zip(pred, B)),
                                    "reply10": sum(p == k and t["reply_gap_min"] is not None and t["reply_gap_min"] <= 10
                                                   for p, t in zip(pred, turns)),
                                    "offers": sum(p == k and i in offers for p, i in zip(pred, ids))} for k in TIERS}
        if a.detail:
            print("   per tier: n, B1, replied≤10, offer-only", res[name]["by_tier"])
            print("   label->jev", res[name]["conf"])
            print("   behav->jev", res[name]["confb"])
    # Waiting vs asks under the new hints: the turns the labels say wait on the user, and those that wait on others.
    print("\nwaits: label blocker (both agree) × Jev state, old vs newC")
    for v in ("old", "newC"):
        m = collections.Counter()
        for i in ids:
            bl = lab["sonnet"].get(i, {}).get("blocker")
            if bl is None or bl != lab["sol"].get(i, {}).get("blocker") or bl == "none":
                continue
            st = T.parse(jv[v][i]["answers"], cands[i])["state"] if jv[v].get(i) and jv[v][i]["answers"] else None
            m[(bl, st)] += 1
        print(" ", v, dict(sorted(m.items(), key=lambda x: (x[0][0], str(x[0][1])))))
    # The state shift old → new, and `next`'s answers within done/progress/nil.
    for v in ("newC", "newG"):
        if not jv[v]:
            continue
        sh = collections.Counter()
        for i in ids:
            o = T.parse(jv["old"][i]["answers"], cands[i])["state"] if jv["old"][i]["answers"] else None
            n = T.parse(jv[v][i]["answers"], cands[i])["state"] if jv[v][i]["answers"] else None
            if o != n:
                sh[f"{o}->{n}"] += 1
        print(f"state changes old→{v}:", dict(sh.most_common()))
    nx = collections.Counter()
    probs = []
    for i in ids:
        ans = jv["newC"][i]["answers"]
        if ans and T.parse(ans, cands[i])["state"] in ("done", "progress", None):
            c, p = choice(ans, "next")
            nx[c] += 1
            probs.append(p)
    probs.sort()
    print("newC next within done/progress/nil:", dict(nx), "p quartiles", [round(probs[int(len(probs) * q)], 2) for q in (0.1, 0.25, 0.5, 0.75)],
          "below 0.6:", sum(p < 0.6 for p in probs), "below 0.8:", sum(p < 0.8 for p in probs))
    (DATA / "scores.json").write_text(json.dumps({"summary": out, "configs": res}, default=str, indent=1))


def scope_report():
    """Within the turns `next` applies to (Jev's state done, progress or unsure): what `next` and the gates say against
    the labels and against what you did, by confidence."""
    turns = [json.loads(l) for l in open(DATA / "turns.jsonl")]
    rel = load("relation.jsonl")
    lab = {m: load(f"labels_{m}.jsonl") for m in ("sonnet", "sol")}
    jv = {v: load(f"jev_{v}.jsonl") for v in ("newC", "newC0", "newG", "newG0", "newCO", "newGO")}

    def fmt(c):
        return dict(sorted(collections.Counter(c).items(), key=lambda x: str(x[0])))

    for v in jv:
        rows = []
        for t in turns:
            i = t["id"]
            ans = jv[v][i]["answers"]
            if not ans or T.parse(ans, jv[v][i]["candidates"])["state"] not in ("done", "progress", None):
                continue
            ls, lo = lab["sonnet"][i].get("tier"), lab["sol"][i].get("tier")
            rows.append({"ans": ans, "label": ls if ls == lo else None, "b": btier(t, rel.get(i)),
                         "trivial": yes(ans, "trivial"), "unverified": yes(ans, "unverified")})
        print(f"\n{v}: {len(rows)} turns in scope; consensus labels there {fmt(r['label'] for r in rows)};"
              f" behaviour {fmt(r['b'] for r in rows)}; trivial≥0.8: {sum(r['trivial'] >= 0.8 for r in rows)};"
              f" unverified≥0.7: {sum(r['unverified'] >= 0.7 for r in rows)}")
        if v.startswith("newC"):
            for c in ("you", "note", "nothing"):
                for lo_, hi in ((0, 0.6), (0.6, 0.8), (0.8, 1.01)):
                    sel = [r for r in rows if choice(r["ans"], "next")[0] == c and lo_ <= choice(r["ans"], "next")[1] < hi]
                    if sel:
                        print(f"  next={c:7s} p∈[{lo_},{hi}) n={len(sel):3d} label {fmt(r['label'] for r in sel)} behaviour {fmt(r['b'] for r in sel)}")
        else:
            for key in ("step", "worth"):
                for lo_, hi in ((0, 0.2), (0.2, 0.5), (0.5, 0.6), (0.6, 0.8), (0.8, 1.01)):
                    sel = [r for r in rows if lo_ <= yes(r["ans"], key) < hi]
                    if sel:
                        print(f"  {key:5s} p∈[{lo_},{hi}) n={len(sel):3d} label {fmt(r['label'] for r in sel)} behaviour {fmt(r['b'] for r in sel)}")


def gate_tier(ans, cands, step_floor, worth_floor, fallback):
    """The gates with a floor each: step sure → 1; else worth sure → 3; else both surely no → 4; else the fallback."""
    t = T.parse(ans, cands)
    k = T.kind(t)
    if k in ("asks", "approval", "stuck"):
        return 1
    if k == "waiting":
        return 2
    s, w = yes(ans, "step"), yes(ans, "worth")
    if s >= step_floor:
        tier = 1
    elif w >= worth_floor:
        tier = 3
    elif 1 - w >= worth_floor:
        tier = 4
    else:
        tier = {"note": 3, "nothing": 4}[fallback]
    if tier == 4 and t["unverified"]:
        tier = 3
    if tier == 3 and yes(ans, "trivial") >= 0.8:
        tier = 4
    return tier


def sweep():
    """Separate floors for the two gates, and the planned choice for reference, on the turns where they differ (Jev's
    state done, progress or unsure), against the consensus labels, with a bootstrap interval on accuracy."""
    import random
    turns = [json.loads(l) for l in open(DATA / "turns.jsonl")]
    lab = {m: load(f"labels_{m}.jsonl") for m in ("sonnet", "sol")}
    jv = {v: load(f"jev_{v}.jsonl") for v in ("newC", "newG", "newG0")}
    rel = load("relation.jsonl")
    ids = [t["id"] for t in turns]
    cons = {i: lab["sonnet"][i].get("tier") for i in ids if lab["sonnet"][i].get("tier") == lab["sol"][i].get("tier")}
    B = {t["id"]: btier(t, rel.get(t["id"])) for t in turns}
    scope = [i for i in ids if i in cons and T.parse(jv["newC"][i]["answers"], jv["newC"][i]["candidates"])["state"] in ("done", "progress", None)]
    rng = random.Random(1)
    boots = [[rng.choice(scope) for _ in scope] for _ in range(1000)]

    ref = {i: new_tier(jv["newC"][i]["answers"], jv["newC"][i]["candidates"], "C", 0.6, "note") for i in scope}

    def report(name, f):
        pred = {i: f(i) for i in scope}
        acc = sum(pred[i] == cons[i] for i in scope) / len(scope)
        accs = sorted(sum(pred[i] == cons[i] for i in b) / len(b) for b in boots)
        diffs = sorted(sum((pred[i] == cons[i]) - (ref[i] == cons[i]) for i in b) / len(b) for b in boots)
        name = f"{name} Δ vs planned [{diffs[25]:+.2f},{diffs[975]:+.2f}]"
        pr = {k: prf([pred[i] for i in scope], [cons[i] for i in scope], k) for k in (1, 3, 4)}
        d = collections.Counter(pred.values())
        b3 = [B[i] for i in scope if pred[i] == 3]
        b4 = [B[i] for i in scope if pred[i] == 4]
        print(f"{name:62s} acc {acc:.2f} [{accs[25]:.2f}-{accs[975]:.2f}] " + " ".join(f"t{k} {pr[k][0]:.2f}/{pr[k][1]:.2f}" for k in (1, 3, 4))
              + f" | n 1/3/4 {d[1]}/{d[3]}/{d[4]} | reacted (B3) in t3 {sum(x == 3 for x in b3)}/{len(b3)}, in t4 {sum(x == 3 for x in b4)}/{len(b4)}")

    print(f"\nin scope with consensus labels: {len(scope)}; labels {dict(collections.Counter(cons[i] for i in scope))}")
    for floor in (0.5, 0.6, 0.7, 0.8):
        for fb in ("note", "nothing"):
            report(f"choice f{floor} unsure→{fb}", lambda i, floor=floor, fb=fb: new_tier(
                jv["newC"][i]["answers"], jv["newC"][i]["candidates"], "C", floor, fb))
    for v in ("newG", "newG0"):
        for sf in (0.5, 0.6, 0.7, 0.8):
            for wf in (0.6, 0.7, 0.8):
                for fb in ("note", "nothing"):
                    report(f"{v} step≥{sf} worth≥{wf} unsure→{fb}", lambda i, v=v, sf=sf, wf=wf, fb=fb: gate_tier(
                        jv[v][i]["answers"], jv[v][i]["candidates"], sf, wf, fb))


if __name__ == "__main__":
    main()
    scope_report()
    sweep()
