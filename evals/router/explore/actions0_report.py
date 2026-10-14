"""Tables for Stage 0 (explore/actions0.py): reach, wrong actions and traps on the written action sets, false actions on
the real dev submits, route stability, calls. python3 -m explore.actions0 report"""
import collections
import json
import pathlib
import statistics
import sys

HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
OUT = HERE / "v2" / "data" / "exp" / "out" / "actions0"
VARIANTS = ["actions-0", "actions-0-placebo", "actions-o", "verbs-o", "actions-0+split", "actions-o+split", "verbs-o+split"]
BASES = {"shipped": "actions-0", "base-o": "verbs-o"}  # the base request on the same states, read from these traces
ACTS = {"ack", "stop", "interrupt", "dismiss"}
ROUTER = {"change_fjord", "compound", "question"}


def gold_targets():
    """{case id: target session id or None}: caps_ack's own picks, replayed (deterministic seeds)."""
    from explore import caps_ack as C
    picks = []
    orig = C.pick_for

    def rec(need, state, rng):
        r = orig(need, state, rng)
        if r is not None:
            picks.append(r)
        return r
    C.pick_for = rec
    try:
        acts = C.build_actions()
        a_picks = list(picks)
        picks.clear()
        ack, _ = C.build()
        k_picks = list(picks)
    finally:
        C.pick_for = orig
    out = {}
    for cases, ps, tmpl in ((acts, a_picks, C.ACTIONS), (ack, k_picks, C.CASES)):
        for e, (t, u, p) in zip(cases, ps):
            n = int(e["id"].split("-")[1])
            out[e["id"]] = {"t": t["id"] if t else None, "named": "{t}" in tmpl[n][3], "msg": e["events"][0]["message"]}
    return out


def load(variant, set_name):
    p = OUT / f"{variant}.{set_name}.jsonl"
    if not p.exists():
        return None
    return [json.loads(line) for line in open(p)]


def submits(eps):
    for e in eps:
        for ev in e["events"]:
            if ev["kind"] == "submit":
                yield e, ev


def outcome(ev, shipped=False):
    """(kind, session) kind: ack/stop/interrupt/dismiss, mismatch, router, session, new, ask."""
    if shipped:
        d = (ev.get("actions") or {}).get("shipped") or ev
        dec, tgt = d.get("decision"), d.get("target")
        if dec == "ask" or not tgt:
            return ("ask", None)
    else:
        if ev.get("action") in ACTS:
            return (ev["action"], ev.get("action_session"))
        if ev.get("action") == "ask-mismatch":
            return ("mismatch", None)
        dec, tgt = ev["decision"], ev.get("target")
        if dec == "ask" or not tgt:
            return ("ask", None)
    if tgt in ROUTER:
        return ("router", None)
    if tgt.startswith("new:"):
        return ("new", None)
    return ("session", tgt.replace("session:", ""))


def classify(case_id, fam, gold, g):
    """The case's role: ack-clear / ack-other / mixed / stop / other-action / trap."""
    if case_id.startswith("ack-"):
        if gold == "session":
            return "trap"
        if fam == "mixed":
            return "mixed"
        if fam in ("seen", "duplicate") and g["named"]:
            return "ack-clear"
        return "ack-other"
    if fam == "stop":
        return "stop"
    if fam.startswith("trap"):
        return "trap"
    return fam  # archive / reopen / mute


def judge(role, oc, t):
    """→ (reach, verb_reach, wrong_action, trap_acting)."""
    kind, sid = oc
    acted = kind in ACTS
    if role == "trap":
        return 0, 0, 0, int(acted)
    if role in ("ack-clear", "ack-other", "mixed"):
        verb = int(role == "ack-clear" and kind == "ack" and sid == t)
        reach = int(verb or kind == "router")
        return reach, verb, int(acted and not verb), 0
    if role == "stop":
        verb = int(kind in ("stop", "interrupt") and sid == t)
        return int(verb or kind == "router"), verb, int(acted and not verb), 0
    if role == "archive":
        verb = int(kind == "dismiss" and sid == t)
        return int(verb or kind == "router"), verb, int(acted and not verb), 0
    return int(kind == "router"), 0, int(acted), 0


def written(gold):
    rows = {}
    fails = []
    for set_name in ("ack", "ack_actions"):
        for v in list(BASES) + VARIANTS:
            eps = load(BASES.get(v, v), set_name)
            if eps is None:
                continue
            for e, ev in submits(eps):
                g = gold[e["id"]]
                role = classify(e["id"], e["family"], e["tags"]["gold"], g)
                oc = outcome(ev, shipped=v in BASES)
                r, vr, w, tr = judge(role, oc, g["t"])
                key = (v, role)
                acc = rows.setdefault(key, collections.Counter())
                acc.update(n=1, reach=r, verb=vr, wrong=w, trap=tr, **{"to_" + oc[0]: 1})
                if v not in BASES and (w or tr or (role in ("ack-clear", "stop") and not vr)):
                    ov = (ev.get("actions") or {}).get("overlay", {})
                    ck = (ev.get("actions") or {}).get("checks", [])
                    tval = max([c[3] for c in ck if c[2] == g["t"] and c[0] in ("ack", "stop")] or [None], key=lambda x: x or 0)
                    fails.append((v, role, e["id"], g["msg"][:70], oc[0], oc[1] == g["t"] if oc[1] else None, tval,
                                  (ev.get("actions") or {}).get("T"), ov.get("action")))
    return rows, fails


def table(rows):
    roles = ["ack-clear", "ack-other", "mixed", "stop", "archive", "reopen", "mute", "trap"]
    vs = list(BASES) + VARIANTS
    print("\n| role (n) | " + " | ".join(vs) + " |")
    print("|---|" + "---|" * len(vs))
    for role in roles:
        n = rows.get(("shipped", role), {}).get("n", 0)
        if not n:
            continue
        cells = []
        for v in vs:
            c = rows.get((v, role))
            if not c:
                cells.append("-")
                continue
            if role == "trap":
                cells.append(f"acting {c['trap']}; router {c['to_router']}, ask {c['to_ask'] + c['to_mismatch']}")
            else:
                cells.append(f"reach {c['reach']} (verb {c['verb']}), wrong act {c['wrong']}; router {c['to_router']}, "
                             f"session {c['to_session']}, ask {c['to_ask']}, mismatch {c['to_mismatch']}")
        print(f"| {role} ({n}) | " + " | ".join(cells) + " |")


def shortlist_recall(gold):
    eps = load("actions-o", "ack") or []
    eps2 = load("actions-o", "ack_actions") or []
    hit = tot = 0
    for e, ev in list(submits(eps)) + list(submits(eps2)):
        g = gold[e["id"]]
        role = classify(e["id"], e["family"], e["tags"]["gold"], g)
        if role not in ("ack-clear", "archive") or not ev.get("actions"):
            continue
        tot += 1
        ck = ev["actions"]["checks"]
        kind = "ack" if role == "ack-clear" else "dismiss"
        hit += any(c[0] == kind and c[2] == g["t"] for c in ck)
    return hit, tot


def real(v):
    out = collections.Counter()
    fires = []
    near = []
    for s in ("real_A", "real_B"):
        eps = load(v, s)
        if eps is None:
            return None, None, None
        for e, ev in submits(eps):
            out["n"] += 1
            a = ev.get("actions")
            if not a:
                continue
            out["jev"] += 1
            ov = a["overlay"]
            sh = a.get("shipped") or {}
            if ev.get("action") and sh.get("decision") != "ask" and sh.get("target") in ev["gold"].get("acceptable", []):
                out["lost_right_sends"] += 1
            if ev.get("action") in ACTS:
                out[ev["action"]] += 1
                fires.append((v, ev["message"][:70], ev["action"], ev.get("action_session"), a.get("T")))
            if ev.get("action") == "ask-mismatch":
                out["mismatch"] += 1
                fires.append((v, ev["message"][:70], "ask-mismatch", ov.get("session"), a.get("T")))
            if ov.get("second_call"):
                out["second_call"] += 1
            if v.startswith("actions-0"):
                for mode in ("keep", "literal"):
                    m = ov.get("modes", {}).get(mode, {})
                    if m.get("action") in ACTS:
                        out[mode + "_fires"] += 1
            for kind in ("ack", "stop", "dismiss"):
                ps = [c[3] for c in a["checks"] if c[0] == kind]
                if ps:
                    near.append((kind, max(ps)))
            if ev.get("tokens"):
                out["tokens"] += ev["tokens"]
    return out, fires, near


def stability(v):
    rows = []
    for s in ("real_A", "real_B"):
        for e, ev in submits(load(v, s) or []):
            a = ev.get("actions")
            if a:
                rows.append(a)
    if not rows:
        return None
    n = len(rows)
    raw_flip = sum(a["raw_top"] != a["shipped_raw_top"] for a in rows)
    T = lambda p: max(p.items(), key=lambda x: x[1])[0] if p else None
    fused_flip = sum(T(a["probs"]) != T(a["shipped_probs"]) for a in rows)
    dec = sum((a["today"]["decision"], a["today"]["target"]) != (a["shipped"]["decision"], a["shipped"]["target"]) for a in rows)
    dp = [abs(a["raw"].get(a["shipped_raw_top"], 0) - a["shipped_raw"].get(a["shipped_raw_top"], 0)) for a in rows]
    dfp = [abs(a["probs"].get(T(a["shipped_probs"]), 0) - a["shipped_probs"].get(T(a["shipped_probs"]), 0)) for a in rows]
    out = dict(n=n, raw_flip=raw_flip, fused_flip=fused_flip, decision_change=dec, dp_mean=statistics.mean(dp),
               dp_p95=sorted(dp)[int(.95 * (n - 1))], dfp_mean=statistics.mean(dfp))
    rep = [a for a in rows if "repeat_raw_top" in a]
    if rep:
        out.update(rep_n=len(rep), rep_raw_flip=sum(a["repeat_raw_top"] != a["shipped_raw_top"] for a in rep),
                   rep_fused_flip=sum(a["repeat_T"] != T(a["shipped_probs"]) for a in rep),
                   rep_dp_mean=statistics.mean(abs(a["repeat_raw"].get(a["shipped_raw_top"], 0)
                                                   - a["shipped_raw"].get(a["shipped_raw_top"], 0)) for a in rep))
    return out


def gold_values(gold):
    """The check's value on the gold target, per role, for actions-0 and actions-o (a bar sweep's raw material)."""
    out = collections.defaultdict(list)
    for v in VARIANTS:
        for s in ("ack", "ack_actions"):
            for e, ev in submits(load(v, s) or []):
                a = ev.get("actions")
                if not a:
                    continue
                g = gold[e["id"]]
                role = classify(e["id"], e["family"], e["tags"]["gold"], g)
                kind = {"ack-clear": "ack", "stop": "stop", "archive": "dismiss"}.get(role)
                if kind:
                    out[(v, role)].append(max([c[3] for c in a["checks"] if c[0] == kind and c[2] == g["t"]] or [0]))
                if role == "trap":
                    out[(v, "trap-max")].append(max([c[3] for c in a["checks"]] or [0]))
    return out


def verbs_extra(gold):
    """verbs-o's own keep checks: argmax ack<i> on the right card (ack cases with a named card), and any check ≥ .5 on
    the 34 traps (16 action traps + 18 session-gold acks); the same numbers for the other variants."""
    for v in VARIANTS:
        right = tot = 0
        hot = []
        for s in ("ack", "ack_actions"):
            for e, ev in submits(load(v, s) or []):
                a = ev.get("actions")
                g = gold[e["id"]]
                role = classify(e["id"], e["family"], e["tags"]["gold"], g)
                if not a:
                    continue
                acks = [c for c in a["checks"] if c[0] == "ack"]
                if role == "ack-clear" and acks:
                    tot += 1
                    right += max(acks, key=lambda c: c[3])[2] == g["t"]
                if role == "trap":
                    m = max([c[3] for c in a["checks"]] or [0])
                    if m >= 0.5:
                        hot.append((e["id"], g["msg"][:50], round(m, 2)))
        print(f"{v}: argmax ack = right card {right}/{tot}; traps with any check ≥ .5: {len(hot)} {hot}")


def main():
    gold = gold_targets()
    rows, fails = written(gold)
    print("## Written sets (ack 40 + ack_actions 42)")
    table(rows)
    h, t = shortlist_recall(gold)
    print(f"\nactions-o shortlist recall (gold card among the checked cards; clear acks + archive asks): {h}/{t}")
    print("\n## Gold target's own check value (sorted)")
    for k, vals in sorted(gold_values(gold).items()):
        print(k, [round(x, 2) for x in sorted(vals, reverse=True)])
    print("\n## argmax and trap checks")
    verbs_extra(gold)
    print("\n## Real dev submits (393, no Router moments: every action is false)")
    allfires = []
    for v in VARIANTS:
        c, fires, near = real(v)
        if c is None:
            print(v, "not run")
            continue
        allfires += fires
        acts = sum(c[k] for k in ACTS)
        print(f"{v}: n={c['n']} jev={c['jev']} actions={acts} ({100 * acts / c['n']:.2f}%) "
              + " ".join(f"{k}={c[k]}" for k in ("ack", "stop", "interrupt", "dismiss", "mismatch", "lost_right_sends", "second_call",
                                                  "keep_fires", "literal_fires")) + f" tokens={c['tokens']}")
        for kind in ("ack", "stop", "dismiss"):
            ps = sorted([p for k, p in near if k == kind], reverse=True)
            if ps:
                print(f"   max {kind} per submit, top 8: {[round(p, 2) for p in ps[:8]]}; ≥.7: {sum(p >= .7 for p in ps)}, "
                      f"≥.8: {sum(p >= .8 for p in ps)}, ≥.85: {sum(p >= .85 for p in ps)}, ≥.9: {sum(p >= .9 for p in ps)}")
    print("\n## Route stability (same state, with vs without the extra checks)")
    for v in VARIANTS:
        print(v, stability(v))
    print("\n## Failures on the written sets")
    for f in fails:
        print(f)
    print("\n## Real actions / mismatches")
    for f in allfires:
        print(f)


if __name__ == "__main__":
    main()
