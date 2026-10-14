"""Tables for Stage 1 (explore/actions_d3.py): per action reach / wrong action / ask / traps acting / hit@4 on the
action gold, paired Δloss (group bootstrap) and McNemar against shipped with the placebo and Jev's own repeat noise
alongside, the bar grid (dev only), the mark-seen check on explicit requests vs bare acknowledgements, the dismiss
shortlist's recall with and without named cards, the 611 bench moments, failures and cost.

python3 -m explore.actions_d3_report [--split dev|calib] [--params JSON] [--grid]
Only gitignored data is read (v2/data/exp/out/actions_d3); messages printed are cut short."""
import argparse
import collections
import copy
import json
import math
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from explore import actions_d3 as D  # noqa: E402
from v2.run import action_score as A  # noqa: E402
from v2.run import compare as C  # noqa: E402

OUT = D.OUT
SETS = ["written_ack", "written_stop", "written_configure", "mined", "relabel_real"]
SYSTEMS = ["shipped", "shipped-repeat", "D3", "D3-placebo", "D3-same", "D3-w2", "D3-final"]
CANDS = ["D3", "D3-placebo", "D3-same", "D3-w2", "D3-final"]
ACTS = {"ack", "stop", "interrupt", "archive"}
EXPLICIT = re.compile(r"\b(mark|marque[rz]?)\b|\bclear (it|that card|the card)\b", re.I)
TRAP_FAMILIES = {"negation", "quoted", "to-session", "seen-then-do", "reply-needs-you", "stop-using", "stop-button",
                 "stop-button-bare", "dont-stop", "why-stopped", "dev-server", "dev-server-bare", "resume", "bare"}


def load(system, split, name):
    p = OUT / f"{system}.{split}.{name}.jsonl"
    return [{**json.loads(line), "_set": name} for line in open(p)] if p.exists() else None


def submits(eps):
    for e in eps:
        for ev in e["events"]:
            if ev.get("kind") == "submit":
                yield e, ev


def role(e, ev):
    """The submit's role in the per-action table."""
    g = ev["gold"]
    ia = g.get("intended_action") or ""
    v = A.verb(ia)
    fam = e.get("family", "")
    name = e.get("provenance", {}).get("set", "")
    if fam == "unmet" or fam.startswith("unmet") or fam.endswith("-unmet") or g.get("precondition") == "unmet":
        return "unmet"
    if fam in TRAP_FAMILIES:
        return "trap"
    if v == "ack":
        if ia == "ack:card:*":
            return "ack-all"
        return "ack-explicit" if EXPLICIT.search(ev["message"]) else "ack-bare"
    if v == "stop":
        return "stop" if g.get("ask") != "required" else "stop-ambiguous"
    if v in ("interrupt", "archive", "reopen"):
        return v
    if v in ("mute", "unmute"):
        return "mute"
    if "relabel" in name or e["id"].startswith("relabel") or e.get("_set") == "relabel_real":
        return "real"
    return (v or "other") + (" (mined)" if e.get("_set") == "mined" else "")


def owner_gold(e, ev):
    """The owner's reading: a bare acknowledgement may go to the card's session (say is acceptable too)."""
    if role(e, ev) != "ack-bare":
        return ev
    g = copy.deepcopy(ev["gold"])
    sid = A.target_session(g["intended_action"])
    g["acceptable_actions"] = list(g.get("acceptable_actions") or []) + [f"say:session:{sid}"]
    return {**ev, "gold": g}


def redecide(eps, params):
    """D3 traces decided again with other params (offline; later submits of an episode keep the recorded path)."""
    out = []
    for e in eps:
        e2 = {**e, "events": []}
        for ev in e["events"]:
            ev = dict(ev)
            if ev.get("kind") == "submit" and ev.get("d3"):
                d = D.decide(ev["d3"], params)
                r = ev["d3"]["routing"]
                if d["decision"] == "act":
                    inter = d["act"].startswith("interrupt")
                    ev.update(decision="send" if inter else "intent", act=d["act"], act_options=None,
                              target="session:" + d["act"].rsplit(":", 1)[1] if inter else "change_fjord")
                elif d["decision"] == "ask":
                    ev.update(decision="ask", act=None, act_options=d["options"], target=None)
                else:
                    kind = "ask" if r["decision"] == "ask" else ("start" if (r["target"] or "").startswith("new:") else
                                                                "intent" if r["target"] in ("change_fjord", "question", "compound") else "send")
                    ev.update(decision=kind, act=r["act"], target=r["target"],
                              act_options=r["options"] if kind == "ask" else None)
                ev["d3_decision"] = d
            e2["events"].append(ev)
        out.append(e2)
    return out


def scored(eps, owner=False):
    rows = []
    for e, ev in submits(eps):
        t = owner_gold(e, ev) if owner else ev
        s = A.event_score(t)
        act = t.get("act") if t["decision"] != "ask" else None
        rows.append({"id": e["id"] + ":" + ev["id"], "group": e["group"], "role": role(e, ev), "fam": e.get("family"),
                     "msg": ev["message"], "act": act, "verb": A.verb(act), "gold": t["gold"].get("intended_action"),
                     "options": t.get("act_options"), "decision": t["decision"], **s})
    return rows


def per_role(rows):
    out = collections.OrderedDict()
    for r in rows:
        c = out.setdefault(r["role"], collections.Counter())
        gv = A.verb(r["gold"])
        c["n"] += 1
        direct = r["right"] and not r["router_reach"] and r["verb"] == gv
        c["reach"] += direct
        c["via_router"] += r["router_reach"]
        c["right"] += r["right"]
        c["wrong"] += r["wrong"]
        c["wrong_verb"] += r["wrong_verb"]
        c["irrev_wrong"] += r["irreversible_wrong"]
        c["ask"] += r["ask"]
        c["hit4"] += r["hit_at_4"]
        c["hit_router"] += r["hit_router"]
        c["acting"] += r["verb"] in ACTS
        c["act_wrong"] += r["verb"] in ACTS and bool(r["wrong"])
        c["loss"] += r["loss"]
    return out


def upper95(k, n):
    """Exact (Clopper–Pearson) one-sided 95% upper bound of a rate k/n."""
    k = int(round(k))
    if n == 0:
        return None
    if k == n:
        return 1.0
    lo, hi = k / n, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        tail = sum(math.comb(n, i) * mid ** i * (1 - mid) ** (n - i) for i in range(k + 1))
        lo, hi = (mid, hi) if tail > 0.05 else (lo, mid)
    return hi


def fmt_role(c, role_name):
    n = c["n"]
    s = (f"n={n} reach {c['reach']}" + (f" (+{c['via_router']} via Router)" if c["via_router"] else "") +
         f", wrong {c['wrong']}" + (f" (verb {c['wrong_verb']}, irrev {c['irrev_wrong']})" if c["wrong"] else "") +
         f", ask {c['ask']} hit@4 {c['hit4']}" + (f" ({c['hit_router']} Router)" if c["hit_router"] else "") +
         f", acting {c['acting']} (wrong {c['act_wrong']}), loss {c['loss'] / max(n, 1):.2f}")
    return s


def paired(base, cand, owner=False, bootstrap=2000):
    """compare.compare with the action-aware episode score."""
    old = C.episode_score
    try:
        if owner:
            fix = lambda eps: [{**e, "events": [owner_gold(e, ev) if ev.get("kind") == "submit" else ev for ev in e["events"]]} for e in eps]
            base, cand = fix(base), fix(cand)
        C.episode_score = A.episode_score
        r = C.compare(base, cand, bootstrap=bootstrap, seed=7)
    finally:
        C.episode_score = old
    n = r["natural"]
    return {"d_loss_ps": n["delta"]["loss_per_submit"], "ci": (n["ci95"]["loss_per_submit"]["low"], n["ci95"]["loss_per_submit"]["high"]),
            "base_lps": n["baseline"]["loss_per_submit"], "cand_lps": n["candidate"]["loss_per_submit"],
            "wrong_base": n["baseline"]["wrong_all"], "wrong_cand": n["candidate"]["wrong_all"],
            "mcnemar": (r["mcnemar"]["baseline_only_wrong"], r["mcnemar"]["candidate_only_wrong"], r["mcnemar"]["p_value_exact_two_sided"])}


def flips(a, b):
    """Submits whose (decision, target) differ between two runs of the same episodes (first submit of each episode
    only, where both saw the same state)."""
    ba = {e["id"]: e for e in b}
    n = k = 0
    for e in a:
        f = next((ev for ev in e["events"] if ev.get("kind") == "submit"), None)
        g = next((ev for ev in ba[e["id"]]["events"] if ev.get("kind") == "submit"), None)
        if f is None or g is None:
            continue
        ra = (f.get("routing") or {}).get("decision"), (f.get("routing") or {}).get("target")
        rb = (g.get("routing") or {}).get("decision"), (g.get("routing") or {}).get("target")
        n += 1
        k += ra != rb
    return k, n


def all_flips(a, b):
    ba = {e["id"]: e for e in b}
    n = k = 0
    for e in a:
        for f, g in zip([ev for ev in e["events"] if ev.get("kind") == "submit"],
                        [ev for ev in ba[e["id"]]["events"] if ev.get("kind") == "submit"]):
            n += 1
            k += ((f.get("routing") or {}).get("decision"), (f.get("routing") or {}).get("target")) != \
                 ((g.get("routing") or {}).get("decision"), (g.get("routing") or {}).get("target"))
    return k, n


def same_route_hash(d3, shipped):
    bs = {e["id"]: e for e in shipped}
    same = n = 0
    for e in d3:
        f = next((ev for ev in e["events"] if ev.get("kind") == "submit"), None)
        g = next((ev for ev in bs[e["id"]]["events"] if ev.get("kind") == "submit"), None)
        if f and g and f.get("request_hash") and g.get("request_hash"):
            n += 1
            same += f["request_hash"] == g["request_hash"]
    return same, n


def markseen_table(eps_by_set):
    """markseen check on written_ack (and every set): the gold card's value on explicit requests, and the max
    markseen per submit elsewhere."""
    out = collections.defaultdict(list)
    for name, eps in eps_by_set.items():
        for e, ev in submits(eps):
            info = ev.get("d3")
            if not info:
                out[(name, role(e, ev), "no-checks")].append(None)
                continue
            ms = [c for c in info["checks"] if c[0] == "markseen"]
            r = role(e, ev)
            if r in ("ack-explicit", "ack-bare"):
                card = ev["gold"]["intended_action"].split(":", 2)[2]
                v = max([c[3] for c in ms if c[1] == card] or [-1])
                out[(name, r, "gold")].append(v)
            out[(name, r, "max")].append(max([c[3] for c in ms] or [0]))
    return out


def recall(eps_by_set):
    """Is the gold card among the checked cards? markseen: shortlist; dismiss: shortlist, or only by naming."""
    rows = collections.Counter()
    for name, eps in eps_by_set.items():
        for e, ev in submits(eps):
            info = ev.get("d3")
            ia = ev["gold"].get("intended_action") or ""
            r = role(e, ev)
            if not info or A.verb(ia) not in ("ack", "archive") or ia.endswith("*"):
                continue
            card = ia.split(":", 2)[2]
            kind = "markseen" if A.verb(ia) == "ack" else "dismiss"
            hit = [c for c in info["checks"] if c[0] == kind and c[1] == card]
            rows[(r, "n")] += 1
            rows[(r, "short")] += any(not c[4] for c in hit)
            rows[(r, "named_only")] += any(c[4] for c in hit)
    return rows


def grid():
    out = []
    for stop in (0.85, 0.9, 0.95):
        for card in (0.8, 0.85, 0.9):
            for urgent in (0.85, 0.9, 1.01):
                for t_lead in (0.0, 0.2):
                    p = copy.deepcopy(D.PARAMS)
                    p["bars"].update(stop=stop, dismiss=card, markseen=card, urgent=urgent)
                    p["t_lead"] = t_lead
                    out.append(p)
    return out


def ptag(p):
    b = p["bars"]
    extra = "".join(f" {k}=off" for k in ("unsure_ask", "named", "markseen") if not p[k])
    return (f"stop {b['stop']} card {b['dismiss']} urgent {b['urgent'] if b['urgent'] <= 1 else 'off'} "
            f"instead {b['instead']} t_lead {p['t_lead']}{extra}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="dev")
    ap.add_argument("--params", help="JSON overrides of D.PARAMS (bars merged)")
    ap.add_argument("--grid", action="store_true")
    ap.add_argument("--final", default="D3", help="the candidate the markseen, recall, grid and failure sections read")
    ap.add_argument("--bootstrap", type=int, default=2000)
    a = ap.parse_args()
    params = copy.deepcopy(D.PARAMS)
    if a.params:
        over = json.loads(a.params)
        params["bars"].update(over.pop("bars", {}))
        params.update(over)
    data = {s: {n: load(s, a.split, n) for n in SETS} for s in SYSTEMS}
    for s in CANDS:
        for n in SETS:
            if data[s][n] is not None:
                data[s][n] = redecide(data[s][n], params)
    print(f"# Stage 1 actions, split {a.split}; D3 params: {ptag(params)}\n")

    print("## Per action (strict gold / owner reading for bare acks)\n")
    for owner in (False, True):
        print(f"### {'owner reading: a bare ack may go to its session' if owner else 'strict gold'}")
        tabs = {}
        for s in SYSTEMS:
            rows = [r for n in SETS if data[s][n] for r in scored(data[s][n], owner)]
            tabs[s] = per_role(rows)
        roles = list(dict.fromkeys(r for t in tabs.values() for r in t))
        print("| role | " + " | ".join(SYSTEMS) + " |")
        print("|---|" + "---|" * len(SYSTEMS))
        for ro in roles:
            print(f"| {ro} | " + " | ".join(fmt_role(tabs[s][ro], ro) if ro in tabs[s] else "-" for s in SYSTEMS) + " |")
        print()
        for s in CANDS:
            for ro, c in tabs[s].items():
                if ro in ("ack-explicit", "stop", "interrupt", "archive", "trap", "real", "mute", "reopen", "unmet",
                          "answer", "say", "stop-ambiguous", "ack-bare"):
                    via = f" (+{c['via_router']} via Router)" if c["via_router"] else ""
                    print(f"  {s} {ro}: wrong-action {c['wrong']}/{c['n']} = {100 * c['wrong'] / c['n']:.1f}% "
                          f"(95% upper {100 * upper95(c['wrong'], c['n']):.1f}%), reach {100 * c['reach'] / c['n']:.0f}%"
                          f"{via}, acting {c['acting']} (of them wrong {c['act_wrong']}), asks {c['ask']} hit@4 {c['hit4']}")
        print()

    print("## Paired against shipped (loss per submit, Δ with group-bootstrap 95% CI; McNemar on groups with a wrong)\n")
    print("| set | system | shipped loss/submit | system | Δ [95% CI] | wrong all (shipped → system) | McNemar (shipped-only, system-only, p) |")
    print("|---|---|---|---|---|---|---|")
    groups = {"written (ack+stop+configure)": ["written_ack", "written_stop", "written_configure"], "mined": ["mined"],
              "relabel_real": ["relabel_real"]}
    for owner in (False, True):
        for gname, names in groups.items():
            if owner and gname != "written (ack+stop+configure)":
                continue
            base = [e for n in names if data["shipped"][n] for e in data["shipped"][n]]
            if not base:
                continue
            for s in SYSTEMS[1:]:
                cand = [e for n in names if data[s][n] for e in data[s][n]]
                if len(cand) != len(base):
                    continue
                r = paired(base, cand, owner, a.bootstrap)
                print(f"| {gname}{' (owner)' if owner else ''} | {s} | {r['base_lps']:.3f} | {r['cand_lps']:.3f} | "
                      f"{r['d_loss_ps']:+.3f} [{r['ci'][0]:+.3f}, {r['ci'][1]:+.3f}] | "
                      f"{100 * r['wrong_base']:.1f}% → {100 * r['wrong_cand']:.1f}% | {r['mcnemar'][0]}, {r['mcnemar'][1]}, p={r['mcnemar'][2]:.3f} |")
    print()

    print("## Route stability (routing decision + target; first submit of each episode, then all submits)\n")
    for n in SETS:
        sh = data["shipped"][n]
        if not sh:
            continue
        parts = []
        for s in SYSTEMS[1:]:
            if data[s][n]:
                k, m = flips(sh, data[s][n])
                k2, m2 = all_flips(sh, data[s][n])
                parts.append(f"{s} {k}/{m} ({k2}/{m2})")
        hs = same_route_hash(data[a.final][n], sh) if data[a.final][n] else (0, 0)
        print(f"- {n}: " + "; ".join(parts) + f"; D3 route request == shipped's: {hs[0]}/{hs[1]}")
    print()

    print("## Actions on real moments (relabel_real: every action is false; all submits)\n")
    for s in CANDS:
        eps = data[s]["relabel_real"]
        if not eps:
            continue
        fires = [(ev["message"][:50].replace("\n", " "), ev.get("act"), ev["d3_decision"]["why"]) for e, ev in submits(eps)
                 if ev.get("d3_decision") and ev["d3_decision"]["decision"] == "act"]
        asks = sum(1 for e, ev in submits(eps) if ev.get("d3_decision") and ev["d3_decision"]["decision"] == "ask"
                   and ev["d3_decision"]["why"] in ("unsure", "elsewhere") and ev["routing"]["decision"] != "ask")
        print(f"- {s}: actions {len(fires)} of {sum(1 for _ in submits(eps))}; sends turned into asks {asks}")
        for f in fires:
            print(f"    {f}")
    print()

    print("## markseen check (gold card's value on acks; max per submit by role)\n")
    ms = markseen_table({n: data[a.final][n] for n in SETS if data[a.final][n]})
    for k, v in sorted(ms.items()):
        vals = [x for x in v if x is not None]
        if vals:
            print(f"- {k}: n={len(v)} ≥.85: {sum(x >= .85 for x in vals)}, ≥.8: {sum(x >= .8 for x in vals)}, "
                  f"≥.5: {sum(x >= .5 for x in vals)}; top {[round(x, 2) for x in sorted(vals, reverse=True)[:12]]}")
    print()
    print("## Shortlist recall (gold card checked: on the shortlist / only as a named card)\n")
    rc = recall({n: data[a.final][n] for n in SETS if data[a.final][n]})
    for r in sorted({k[0] for k in rc}):
        print(f"- {r}: n={rc[(r, 'n')]}, shortlist {rc[(r, 'short')]}, named only {rc[(r, 'named_only')]}")
    print()

    if a.grid:
        print("## Grid (dev only; D3 re-decided offline): total loss over written+mined (owner reading) and relabel_real\n")
        print("| params | written+mined loss | traps acting | wrong irreversible | relabel_real loss | real actions |")
        print("|---|---|---|---|---|---|")
        for p in grid():
            tot = trap = irrev = 0
            for n in SETS[:-1]:
                rows = scored(redecide(data[a.final][n], p), owner=True)
                tot += sum(r["loss"] for r in rows)
                trap += sum(r["verb"] in ACTS for r in rows if r["role"] in ("trap", "unmet"))
                irrev += sum(r["irreversible_wrong"] for r in rows)
            rr = scored(redecide(data[a.final]["relabel_real"], p))
            print(f"| {ptag(p)} | {tot:.1f} | {trap} | {irrev} | {sum(r['loss'] for r in rr):.1f} | "
                  f"{sum(r['verb'] in ACTS for r in rr)} |")
        for extra in ({"unsure_ask": False}, {"named": False}, {"markseen": False}):
            p = {**copy.deepcopy(params), **extra}
            tot = sum(r["loss"] for n in SETS[:-1] for r in scored(redecide(data[a.final][n], p), owner=True))
            rr = scored(redecide(data[a.final]["relabel_real"], p))
            print(f"| {ptag(p)} | {tot:.1f} | | | {sum(r['loss'] for r in rr):.1f} | {sum(r['verb'] in ACTS for r in rr)} |")
        print()

    print("## Failures (D3; wrong actions, traps acting, clear cases not reached)\n")
    for n in SETS:
        eps = data[a.final][n]
        if not eps:
            continue
        for r in scored(eps, owner=True):
            clear = r["role"] in ("ack-explicit", "stop", "interrupt", "archive")
            if r["wrong"] or (r["verb"] in ACTS and r["role"] in ("trap", "unmet", "real")) or (clear and not r["right"]):
                msg = r["msg"][:60].replace("\n", " ") if n != "relabel_real" else r["msg"][:40].replace("\n", " ") + "…"
                print(f"- {n} {r['role']} | {msg} | gold {r['gold'][:28]} | {r['decision']} {(r['act'] or '')[:28]} "
                      f"{[o[:22] for o in (r['options'] or [])]} | loss {r['loss']}")
    print()

    print("## Cost\n")
    for s in SYSTEMS:
        tok = [ev.get("checks_tokens") for n in SETS if data[s][n] for e, ev in submits(data[s][n]) if ev.get("checks_tokens")]
        rt = [ev.get("tokens") for n in SETS if data[s][n] for e, ev in submits(data[s][n]) if ev.get("tokens")]
        if rt:
            print(f"- {s}: route call mean {sum(rt) / len(rt):.0f} input tokens ({len(rt)} calls)"
                  + (f"; checks call mean {sum(tok) / len(tok):.0f} ({len(tok)} calls)" if tok else ""))

    bp = OUT / "bench.D3.jsonl"
    if bp.exists():
        print("\n## bench.py 611 real moments (route request identical by construction; D3's checks added)\n")
        for s in ("D3", "D3-placebo", "D3-w2", "D3-final"):
            p = OUT / f"bench.{s}.jsonl"
            if not p.exists():
                continue
            rows = [json.loads(line) for line in open(p)]
            dec = [D.decide(r["d3"], params) for r in rows]
            acts = [(r["message"][:40].replace("\n", " ") + "…", d["act"], d["why"]) for r, d in zip(rows, dec) if d["decision"] == "act"]
            turned = sum(1 for r, d in zip(rows, dec) if d["decision"] == "ask" and r["d3"]["routing"]["decision"] == "send")
            turned_right = sum(1 for r, d in zip(rows, dec) if d["decision"] == "ask" and r["d3"]["routing"]["decision"] == "send"
                               and (r["d3"]["routing"]["target"] or "")[8:] in r["gold"]["to"])
            tok = [r["tokens"] for r in rows if r.get("tokens")]
            print(f"- {s}: n={len(rows)}; actions {len(acts)} (all false: every moment went to a session); sends turned "
                  f"into asks {turned} ({turned_right} of them right sends); checks call mean {sum(tok) / max(len(tok), 1):.0f} tokens")
            for x in acts:
                print(f"    {x}")


if __name__ == "__main__":
    main()
