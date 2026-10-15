"""Tables for explore/llm_router.py: shipped (Jev), D3-all (Jev + checks), llm-haiku, hybrid, llm-sonnet (subset) on the
action gold with the action-aware scorer, as explore/actions_d3_report.py reads them; bench's 611 real moments for
no-harm; determinism, latency, tokens and cost.

python3 -m explore.llm_router_report [--split dev|calib] [--haiku v1] [--hybrid v1] [--sonnet v1] [--bootstrap 2000]
Only gitignored data is read; messages printed are cut short (60 chars written, 40 real) and were redacted at the
source."""
import argparse
import collections
import json
import math
import sys

from explore import actions_d3 as D
from explore import actions_d3_report as R
from explore import llm_router as L
from v2.run import action_score as A

OUT = L.OUT
ACTING = {"ack", "stop", "interrupt", "archive", "configure", "ask_fjord"}
# Haiku 5.5 / Sonnet 5.5 $/MTok (claude-api skill, cached 2026-10-06; Haiku ≤100K-token prompts). Cache writes 2× (1 h
# TTL, what the CLI used), reads 0.1×. Jev: $0.042/MTok input (explore/actions_d3 cost.py).
PRICE = {"claude-haiku-5-5": (0.10, 0.50), "claude-sonnet-5-5": (2.00, 10.00)}
JEV_PRICE = 0.042


def load_d3(system, split, name):
    p = D.OUT / f"{system}.{split}.{name}.jsonl"
    if not p.exists():
        return None
    eps = [{**json.loads(line), "_set": name} for line in open(p)]
    return R.redecide(eps, D.PARAMS) if system.startswith("D3") else eps


def load_llm(tag, split, name):
    p = OUT / f"{tag}.{split}.{name}.jsonl"
    return [{**json.loads(line), "_set": name.replace("-sub", "")} for line in open(p)] if p.exists() else None


def pct(xs, q):
    xs = sorted(x for x in xs if x is not None)
    return xs[min(len(xs) - 1, max(0, int(math.ceil(q * len(xs))) - 1))] if xs else float("nan")


def role_table(data, systems, names, title):
    print(f"### {title}\n")
    tabs = {s: R.per_role([r for n in names if data[s].get(n) for r in R.scored(data[s][n], True)]) for s in systems}
    roles = list(dict.fromkeys(r for t in tabs.values() for r in t))
    print("Cell: reach (+via Router) / wrong / asks hit@4 / loss per submit\n")
    print("| role | n | " + " | ".join(systems) + " |")
    print("|---|---|" + "---|" * len(systems))
    for ro in roles:
        n = next(t[ro]["n"] for t in tabs.values() if ro in t)
        cells = []
        for s in systems:
            c = tabs[s].get(ro)
            if not c:
                cells.append("-")
                continue
            via = f"+{c['via_router']}" if c["via_router"] else ""
            cells.append(f"{c['reach']:.0f}{via} / {c['wrong']:.0f} / {c['ask']:.0f} {c['hit4']:.0f} / {c['loss'] / c['n']:.2f}")
        print(f"| {ro} | {n} | " + " | ".join(cells) + " |")
    print()


def acting_on(data, s, names, roles):
    out = []
    for n in names:
        for r in R.scored(data[s][n], True) if data[s].get(n) else []:
            if r["role"] in roles and r["verb"] in ACTING:
                out.append(r)
    return out


def summary(rows):
    n = len(rows)
    return {"n": n, "loss": sum(r["loss"] for r in rows) / max(n, 1), "wrong": sum(r["wrong"] for r in rows),
            "sends": sum(r["automatic"] for r in rows), "asks": sum(r["ask"] for r in rows),
            "hit4": sum(r["hit_at_4"] for r in rows), "irrev": sum(r["irreversible_wrong"] for r in rows),
            "cons": sum(r["consequential_wrong"] for r in rows)}


def episodes_section(data, systems, names, split, bootstrap, label):
    print(f"## {label}: split {split}, sets {', '.join(names)}\n")
    role_table(data, systems, names, "Per action (owner reading for bare acks)")
    print("### Totals per set group (loss/submit; wrong; sends; asks hit@4; irreversible wrong)\n")
    groups = {"written": [n for n in names if n.startswith("written")], "mined": [n for n in names if n == "mined"],
              "relabel_real": [n for n in names if n.startswith("relabel")]}
    print("| group | " + " | ".join(systems) + " |")
    print("|---|" + "---|" * len(systems))
    for g, gn in groups.items():
        if not gn:
            continue
        cells = []
        for s in systems:
            rows = [r for n in gn if data[s].get(n) for r in R.scored(data[s][n], g == "written")]
            m = summary(rows)
            cells.append(f"{m['loss']:.2f}; w{m['wrong']:.0f}/{m['n']}; s{m['sends']:.0f}; a{m['asks']:.0f} h{m['hit4']:.0f}; i{m['irrev']:.0f}")
        print(f"| {g} | " + " | ".join(cells) + " |")
    print()
    print("### Paired Δloss/submit vs shipped and D3-all (group bootstrap 95% CI; McNemar base-only, sys-only, p)\n")
    print("| group | base | system | base | system | Δ [95% CI] | wrong | McNemar |")
    print("|---|---|---|---|---|---|---|---|")
    for g, gn in groups.items():
        if not gn:
            continue
        for b in ("shipped", "D3-all"):
            base = [e for n in gn if data[b].get(n) for e in data[b][n]]
            for s in systems:
                if s in ("shipped", "D3-all", b):
                    continue
                cand = [e for n in gn if data[s].get(n) for e in data[s][n]]
                if not base or len(cand) != len(base):
                    continue
                r = R.paired(base, cand, g == "written", bootstrap)
                print(f"| {g} | {b} | {s} | {r['base_lps']:.3f} | {r['cand_lps']:.3f} | {r['d_loss_ps']:+.3f} "
                      f"[{r['ci'][0]:+.3f}, {r['ci'][1]:+.3f}] | {100 * r['wrong_base']:.1f}% → {100 * r['wrong_cand']:.1f}% | "
                      f"{r['mcnemar'][0]}, {r['mcnemar'][1]}, p={r['mcnemar'][2]:.3f} |")
    print()
    print("### Fjord actions on traps / unmet / real moments (each is false)\n")
    for s in systems:
        t = acting_on(data, s, names, {"trap", "unmet"})
        rr = acting_on(data, s, names, {"real"})
        print(f"- {s}: traps/unmet acting {len(t)}; relabel_real acting {len(rr)}")
        for r in (t + rr)[:6]:
            cut = 40 if r["role"] == "real" else 60
            print(f"    {r['role']} | {r['msg'][:cut].replace(chr(10), ' ')} | {r['act']} | gold {r['gold']}")
    print()


def bench_rows(system):
    """→ [(id, decision, act, options, gold, meta)] for bench's 611 moments."""
    out = []
    if system in ("shipped", "D3-all"):
        f = "bench.D3-final.jsonl" if system == "shipped" else "bench.D3-all.jsonl"
        p = D.OUT / f
        if not p.exists():
            return None
        for line in open(p):
            r = json.loads(line)
            if system == "shipped":
                rt = r["d3"]["routing"]
                d = {"decision": "act" if rt["decision"] == "send" else "ask", "act": rt.get("act"), "options": rt.get("options")}
            else:
                d = D.decide(r["d3"], D.PARAMS)
                if d["decision"] == "route":
                    rt = r["d3"]["routing"]
                    d = {"decision": "act" if rt["decision"] == "send" else "ask", "act": rt.get("act"), "options": rt.get("options")}
            lat = [c.get("latency") for c in (r.get("checks_calls") or [])]
            out.append({"id": r["id"], **d, "gold": r["gold"], "message": r["message"],
                        "tokens": (r.get("route_tokens") or 0) + (r.get("tokens") if system == "D3-all" else 0) or 0})
        return out
    p = OUT / f"bench.{system}.jsonl"
    if not p.exists():
        return None
    for line in open(p):
        r = json.loads(line)
        if r["decision"] == "route":
            rt = r["routing"]
            r = {**r, "decision": "act" if rt["decision"] == "send" else "ask", "act": rt.get("act"), "options": rt.get("options")}
        out.append(r)
    return out


def bench_score(rows):
    """Every moment went to a session in gold `to`: a say/answer there is right; anything else automatic is wrong
    (25, 100 for stop/interrupt); an ask costs 1 with a right option among four, else 4."""
    c = collections.Counter()
    fires = []
    for r in rows:
        to = set(r["gold"]["to"])
        c["n"] += 1
        if r["decision"] == "act":
            c["sends"] += 1
            v = A.verb(r["act"])
            ok = v in ("say", "answer") and A.target_session(r["act"]) in to
            if not ok:
                c["wrong"] += 1
                c["loss"] += 100 if v in ("stop", "interrupt") else 25
                if v not in ("say", "answer"):
                    c["fires"] += 1
                    fires.append((r["message"][:40].replace("\n", " ") + "…", r["act"]))
        else:
            c["asks"] += 1
            hit = any(A.verb(o) in ("say", "answer") and A.target_session(o) in to for o in (r.get("options") or [])[:4])
            c["hit4"] += hit
            c["loss"] += 1 if hit else 4
    return c, fires


def bench_delta(base, cand, n=2000, seed=7):
    """Paired Δ loss per moment (cand − base), bootstrap over the moments both have."""
    import random

    def per(rows):
        return {r["id"] + ":" + r["message"][:20]: bench_score([r])[0]["loss"] for r in rows}
    a, b = per(base), per(cand)
    d = [b[k] - a[k] for k in a if k in b]
    rng = random.Random(seed)
    boots = sorted(sum(d[rng.randrange(len(d))] for _ in d) / len(d) for _ in range(n))
    return boots[int(0.025 * n)], sum(d) / len(d), boots[int(0.975 * n)]


def cost_of(metas, model):
    pin, pout = PRICE[model]
    tin = [((m.get("usage") or {}).get("input_tokens") or 0) + ((m.get("usage") or {}).get("cache_creation_input_tokens") or 0)
           + ((m.get("usage") or {}).get("cache_read_input_tokens") or 0) for m in metas]
    tout = [(m.get("usage") or {}).get("output_tokens") or 0 for m in metas]
    cli = [(m.get("usage") or {}) for m in metas]
    as_cli = sum(((u.get("input_tokens") or 0) + 2 * (u.get("cache_creation_input_tokens") or 0)
                  + 0.1 * (u.get("cache_read_input_tokens") or 0)) * pin + (u.get("output_tokens") or 0) * pout for u in cli) / 1e6
    api = sum(i * pin + o * pout for i, o in zip(tin, tout)) / 1e6
    n = max(len(metas), 1)
    return {"calls": len(metas), "in_mean": sum(tin) / n, "in_p95": pct(tin, .95), "out_mean": sum(tout) / n,
            "out_p95": pct(tout, .95), "usd_msg_api": api / n, "usd_msg_cli": as_cli / n}


def metas_of(data, s, names):
    out = []
    for n in names:
        for e in data[s].get(n) or []:
            for ev in e["events"]:
                if ev.get("kind") == "submit" and ev.get("llm_meta") and ev["llm_meta"].get("usage"):
                    out.append(ev)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="dev")
    ap.add_argument("--haiku", default="v1")
    ap.add_argument("--hybrid", default="v1")
    ap.add_argument("--sonnet", default="v1")
    ap.add_argument("--bootstrap", type=int, default=2000)
    a = ap.parse_args()
    split = a.split
    names = [n for n in L.SETS if split == "dev" or n != "relabel_real"]
    H, Y, S = f"llm-haiku-{a.haiku}", f"hybrid-{a.hybrid}", f"llm-sonnet-{a.sonnet}"
    data = {"shipped": {n: load_d3("shipped", split, n) for n in names},
            "D3-all": {n: load_d3("D3-all", split, n) for n in names},
            H: {n: load_llm(H, split, n) for n in names}, Y: {n: load_llm(Y, split, n) for n in names}}
    systems = [s for s in ["shipped", "D3-all", H, Y] if all(data[s][n] for n in names)]
    episodes_section(data, systems, names, split, a.bootstrap, "Full sets")

    # Sonnet subset: written + mined + the relabel_real-sub episodes; everyone else restricted to the same episodes.
    sub = load_llm(S, split, "relabel_real-sub") if split == "dev" else None
    if any(load_llm(S, split, n) for n in names if n != "relabel_real"):
        subnames = [n for n in names if n != "relabel_real"] + (["relabel_real"] if sub else [])
        ids = {e["id"] for e in sub} if sub else set()
        d2 = {}
        for s in systems + [S]:
            d2[s] = {}
            for n in subnames:
                src = (load_llm(S, split, "relabel_real-sub") if n == "relabel_real" else load_llm(S, split, n)) \
                    if s == S else data[s][n]
                if src is not None and n == "relabel_real":
                    src = [e for e in src if e["id"] in ids]
                d2[s][n] = src
        sys2 = [s for s in systems + [S] if all(d2[s].get(n) for n in subnames)]
        episodes_section(d2, sys2, subnames, split, a.bootstrap, f"Sonnet subset ({len(ids)} relabel_real episodes)")
        data[S] = d2[S]

    print("## bench.py 611 real moments (no-harm: each went to a session; Fjord actions are false)\n")
    print("| system | n | sends | wrong sends | non-say fires | asks | hit@4 | loss/moment |")
    print("|---|---|---|---|---|---|---|---|")
    bench_cache = {}
    for s in ["shipped", "D3-all", H, Y, S + "-n200"]:
        rows = bench_rows(s)
        if not rows:
            continue
        bench_cache[s] = rows
        c, fires = bench_score(rows)
        print(f"| {s} | {c['n']} | {c['sends']} | {c['wrong']} ({100 * c['wrong'] / c['n']:.1f}%) | {c['fires']} | "
              f"{c['asks']} | {c['hit4']} | {c['loss'] / c['n']:.2f} |")
    for s, rows in bench_cache.items():
        if s.startswith("llm") or s.startswith("hybrid"):
            ids = {r["id"] for r in rows}
            if len(ids) < len({r["id"] for r in bench_cache["shipped"]}):
                for b in ("shipped", "D3-all"):
                    c, _ = bench_score([r for r in bench_cache[b] if r["id"] in ids])
                    print(f"| {b} on {s}'s {len(ids)} | {c['n']} | {c['sends']} | {c['wrong']} | {c['fires']} | {c['asks']} | {c['hit4']} | {c['loss'] / c['n']:.2f} |")
    print()
    for s, rows in bench_cache.items():
        if s in ("shipped", "D3-all"):
            continue
        for b in ("shipped", "D3-all"):
            lo, mid, hi = bench_delta(bench_cache[b], rows)
            print(f"- {s} − {b}: Δloss/moment {mid:+.3f} [{lo:+.3f}, {hi:+.3f}] (paired moment bootstrap)")
    for s, rows in bench_cache.items():
        _, fires = bench_score(rows)
        if fires and s not in ("shipped", "D3-all"):
            print(f"- {s} fires: " + "; ".join(f"{m} → {act}" for m, act in fires[:5]))
    print()

    print("## Jev's own noise on relabel_real (shipped vs shipped-repeat, same requests asked again)\n")
    if split == "dev":
        rep = load_d3("shipped-repeat", split, "relabel_real")
        if rep:
            k, n = R.all_flips(data["shipped"]["relabel_real"], rep)
            r = R.paired(data["shipped"]["relabel_real"], rep, False, a.bootstrap)
            print(f"- decisions changed {k}/{n}; loss/submit {r['base_lps']:.3f} vs {r['cand_lps']:.3f} "
                  f"(Δ {r['d_loss_ps']:+.3f} [{r['ci'][0]:+.3f}, {r['ci'][1]:+.3f}]); wrong {100 * r['wrong_base']:.1f}% vs "
                  f"{100 * r['wrong_cand']:.1f}%\n")

    print("## Determinism (100 dev submits asked twice; decision = act/ask + action + card options)\n")
    for s in (H, Y, S):
        p = OUT / f"repeat.{s}.jsonl"
        if not p.exists():
            continue
        rows = [json.loads(line) for line in open(p)]
        kind = sum(r["a"][0] != r["b"][0] for r in rows)
        act = sum(r["a"][:2] != r["b"][:2] for r in rows)
        full = sum(r["a"] != r["b"] for r in rows)
        conf = sum((r["llm_a"] or {}).get("confidence") != (r["llm_b"] or {}).get("confidence") for r in rows)
        print(f"- {s}: n={len(rows)}; send/ask flips {kind}; decision (incl. action/target) changed {act}; card options "
              f"changed too {full}; confidence label changed {conf}")
    print()

    print("## Latency per message and tokens/cost\n")
    for s in ["shipped", "D3-all"]:
        evs = [ev for n in names if data[s].get(n) for e in data[s][n] for ev in e["events"] if ev.get("kind") == "submit"]
        lat = [ev.get("latency") for ev in evs if ev.get("latency")]
        if s == "D3-all":
            lat = [(ev.get("latency") or 0) + max([c.get("latency") or 0 for c in ev.get("checks_calls") or []] or [0])
                   for ev in evs if ev.get("latency")]
        tok = [(ev.get("tokens") or 0) + (ev.get("checks_tokens") or 0 if s == "D3-all" else 0) for ev in evs if ev.get("tokens")]
        if lat and tok:
            usd = sum(tok) / len(tok) * JEV_PRICE / 1e6
            print(f"- {s}: latency p50 {pct(lat, .5):.2f}s p95 {pct(lat, .95):.2f}s ({len(lat)} timed, Jev answers as "
                  f"cached at first ask); input tokens/msg mean {sum(tok) / len(tok):.0f}; ${usd:.6f}/msg; "
                  f"100 msgs/day → ${usd * 3000:.3f}/month (send-time only)")
    for s, model in ((H, "claude-haiku-5-5"), (Y, "claude-haiku-5-5"), (S, "claude-sonnet-5-5")):
        if s not in data:
            continue
        evs = metas_of(data, s, list(data[s]))
        if not evs:
            continue
        metas = [ev["llm_meta"] for ev in evs]
        wall = [m.get("wall") for m in metas]
        api = [(m.get("api_ms") or 0) / 1000 for m in metas]
        if s == Y:
            wall = [(ev.get("jev_latency") or 0.25) + ev["llm_meta"]["wall"] for ev in evs]
        c = cost_of(metas, model)
        print(f"- {s} ({model}): latency/msg wall p50 {pct(wall, .5):.2f}s p95 {pct(wall, .95):.2f}s (CLI; API time p50 "
              f"{pct(api, .5):.2f}s p95 {pct(api, .95):.2f}s); tokens in mean {c['in_mean']:.0f} (p95 {c['in_p95']:.0f}) "
              f"out mean {c['out_mean']:.0f} (p95 {c['out_p95']:.0f}); $/msg {c['usd_msg_api']:.5f} uncached API, "
              f"{c['usd_msg_cli']:.5f} as the CLI billed it (1 h cache writes); 100 msgs/day → "
              f"${c['usd_msg_api'] * 3000:.2f}–{c['usd_msg_cli'] * 3000:.2f}/month (send-time only); {c['calls']} calls")
    print()

    print("## Failures (wrong automatic outcomes and traps acting; cut short)\n")
    for s in [H, Y, S]:
        if s not in data:
            continue
        k = 0
        for n in data[s]:
            for r in R.scored(data[s][n], True) if data[s][n] else []:
                if r["wrong"] or (r["role"] in ("trap", "unmet") and r["verb"] in ACTING):
                    cut = 40 if r["role"] == "real" else 60
                    print(f"- {s} {n} {r['role']} | {r['msg'][:cut].replace(chr(10), ' ')} | gold {r['gold'][:30]} | "
                          f"{r['decision']} {(r['act'] or '')[:30]} | loss {r['loss']}")
                    k += 1
        print()


if __name__ == "__main__":
    sys.exit(main())
