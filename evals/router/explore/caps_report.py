"""Tables for the `capabilities-o` experiment: combo-o vs capabilities-o, both with the frozen shipped final3 weights.

python3 -m explore.caps_report bench  [--calls N]   realA / realB through bench.py's machinery (611 real moments)
python3 -m explore.caps_report episodes             v2.run.episodes traces in v2/data/exp/out (real_A, real_B, ack)
python3 -m explore.caps_report actions --base capabilities-o --new capabilities-x
                                                    the 42 archive / reopen / mute / stop cases and traps (ack_actions)
--base / --new name the two formats compared (default combo-o and capabilities-o).

Both read/write only gitignored data. `bench` asks Jev for the answers missing from the cache (JEV_ORDERED=1, at most
--calls new calls, 0 = cache only) and scores with explore.final3:best seeded with RouterRoute.swift's numbers, never
refitted. Loss per submit: wrong send 25; ask 1 (2 when the label says the destination was clear) if the gold is among
its four buttons, else 4; right send 0. Intervals: paired bootstrap over sessions/groups, 2000 replicates."""
import argparse
import hashlib
import json
import os
import pathlib
import random
import statistics
import sys

os.environ["JEV_ORDERED"] = "1"
HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
OUT = HERE / "v2" / "data" / "exp" / "out"
INTENTS = {"change_fjord", "question", "compound"}
FORMATS = ("combo-o", "capabilities-o")  # set from --base / --new


def kind_of(dest):
    if dest is None:
        return None
    dest = dest.replace("session:", "")
    if dest in INTENTS:
        return "router"
    if dest.startswith("new:"):
        return "new"
    return "session"


def record(rid, cluster, decision, target, ranked, gold, ask_policy, tokens, latency, path="jev", clear=False):
    """ranked: the ask's buttons (or the ranking); gold: acceptable destinations (canonical targets)."""
    gold = set(gold)
    send = decision != "ask"
    wrong = send and (ask_policy == "required" or target not in gold)
    hit4 = any(r in gold for r in ranked[:4])
    if wrong:
        loss = 25
    elif send:
        loss = 0
    else:
        loss = 4 if not hit4 else (2 if clear else 1)
    return dict(id=rid, cluster=cluster, send=int(send), wrong=int(wrong), loss=loss, hit4=int(hit4), ask=int(not send),
                tokens=tokens, latency=latency, path=path, target=target, gold_kind=kind_of(sorted(gold)[0]),
                sent_kind=kind_of(target) if send else "ask", clear=clear)


# ------------------------------------------------------------------ episodes

def episode_records(path):
    out = []
    for line in open(path):
        e = json.loads(line)
        for ev in e["events"]:
            if ev.get("kind") != "submit":
                continue
            g = ev["gold"]
            send = ev["decision"] != "ask"
            ranked = [r["target"] if isinstance(r, dict) else r for r in ev.get("ranked", [])]
            out.append(record(e["id"] + ":" + ev["id"], e["group"], "send" if send else "ask", ev.get("target"), ranked,
                              g.get("acceptable", []), g.get("ask", "allowed"), ev.get("tokens"), ev.get("latency"),
                              ev.get("path", "?")) | dict(cat=e.get("family"), message=ev["message"]))
    return out


# ------------------------------------------------------------------ bench

def bench_records(fmt, set_name, max_calls):
    import bench
    import jev
    import run
    from explore import final3, fusion
    from explore import lexical as L
    from v2.run import episodes
    import formats as F
    from explore import cal, capabilities, combo
    for m in (combo, cal, capabilities):  # not formats._explorations(): some explorer modules' FORMATS aren't dicts
        F.FORMATS.update(m.FORMATS)
    jev.ordered = True
    L.install()
    fusion.case_features = final3.case_features
    L.STATE["fields"] = True
    final3._FIT["combo-o"] = episodes._shipped_weights()
    pol = final3.best
    cases = bench.load_set(set_name)
    # Count the calls Jev has not answered yet, refuse to exceed the budget.
    import formats
    import hashlib as H
    todo = 0
    for c in cases:
        state, q, _ = formats.build(fmt, c)
        raw = json.dumps({"model": "jev-latest", "state": state, "questions": q}, sort_keys=False)
        d = H.sha256((raw + "#0").encode()).hexdigest()
        if not (jev.CACHE / d[:2] / f"{d}.json").exists():
            todo += 1
    print(f"[{fmt} {set_name}] {len(cases)} cases, {todo} uncached calls (budget {max_calls})", file=sys.stderr)
    if todo > max_calls:
        raise SystemExit(f"{todo} new calls exceed the budget {max_calls}")
    rows = run.run(fmt, cases, 1)
    by = {c["id"]: c for c in cases}
    recs = []
    for row in rows:
        c = by[row["id"]]
        r = run.reading(row)
        k, w = pol(r, c)
        gold = c["gold"]["to"]
        sid = c["id"].split("-")[1] if c["id"].startswith("re-") else c["id"]
        recs.append(record(c["id"], sid, k, w if k == "send" else None, [] if k == "send" else list(w), gold, "allowed",
                           row.get("tokens"), row.get("latency"), clear=c["gold"].get("label") == "clear"))
    return recs, todo


# ------------------------------------------------------------------ metrics

def pct(values, p):
    if not values:
        return None
    v = sorted(values)
    pos = p * (len(v) - 1)
    lo, hi = int(pos), min(int(pos) + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (pos - lo)


def metrics(recs):
    n = len(recs)
    sends = sum(r["send"] for r in recs)
    asks = n - sends
    lat = [r["latency"] for r in recs if r["latency"]]
    tok = [r["tokens"] for r in recs if r["tokens"]]
    s2r = sum(1 for r in recs if r["send"] and r["gold_kind"] == "session" and r["sent_kind"] == "router")
    r2s = sum(1 for r in recs if r["send"] and r["gold_kind"] == "router" and r["sent_kind"] in ("session", "new"))
    return dict(n=n, wrong_all=sum(r["wrong"] for r in recs) / n, wrong_sends=sum(r["wrong"] for r in recs) / sends if sends else 0,
                send_rate=sends / n, loss=sum(r["loss"] for r in recs) / n, s2r=s2r, r2s=r2s,
                hit4=sum(r["hit4"] for r in recs if r["ask"]) / asks if asks else 0,
                tokens=statistics.mean(tok) if tok else None, p50=pct(lat, .5), p95=pct(lat, .95), nlat=len(lat))


def paired(base, new, key, reps=2000, seed=7):
    """Bootstrap of mean(new[key]) - mean(base[key]) over clusters (sessions/groups), same ids in both."""
    b = {r["id"]: r for r in base}
    pairs = [(b[r["id"]], r) for r in new if r["id"] in b]
    groups = {}
    for x, y in pairs:
        groups.setdefault(x["cluster"], []).append((x, y))
    cl = list(groups.values())
    rng = random.Random(seed)
    diffs = []
    for _ in range(reps):
        sample = [p for _ in cl for p in rng.choice(cl)]
        diffs.append(sum(y[key] - x[key] for x, y in sample) / len(sample))
    diffs.sort()
    point = sum(y[key] - x[key] for x, y in pairs) / len(pairs)
    return point, diffs[int(.025 * reps)], diffs[int(.975 * reps)]


def show(title, base, new):
    m0, m1 = metrics(base), metrics(new)
    names = FORMATS
    print(f"\n### {title}  (n={m0['n']}, paired on {len({r['id'] for r in base} & {r['id'] for r in new})})")
    print(f"| metric | {names[0]} | {names[1]} | delta [95% paired] |")
    print("|---|---|---|---|")
    rows = [("wrong / all", "wrong_all", "wrong"), ("wrong / sends", "wrong_sends", None), ("send rate", "send_rate", "send"),
            ("loss / submit (wrong 25)", "loss", "loss"), ("ask hit@4", "hit4", None)]
    for label, k, pk in rows:
        a, b = m0[k], m1[k]
        f = (lambda v: f"{v:.3f}") if k == "loss" else (lambda v: f"{100 * v:.1f}%")
        d = ""
        if pk:
            pt, lo, hi = paired(base, new, pk)
            d = (f"{pt:+.3f} [{lo:+.3f}, {hi:+.3f}]" if k == "loss" else f"{100 * pt:+.1f} [{100 * lo:+.1f}, {100 * hi:+.1f}] pts")
        print(f"| {label} | {f(a)} | {f(b)} | {d} |")
    print(f"| session->Router sends (gold session) | {m0['s2r']} | {m1['s2r']} | |")
    print(f"| Router->session sends (gold Router) | {m0['r2s']} | {m1['r2s']} | |")
    print(f"| input tokens (mean) | {m0['tokens'] and round(m0['tokens'])} | {m1['tokens'] and round(m1['tokens'])} | |")
    f = lambda v: "-" if v is None else f"{v:.2f}s"
    print(f"| latency p50 / p95 | {f(m0['p50'])} / {f(m0['p95'])} (n={m0['nlat']}) | {f(m1['p50'])} / {f(m1['p95'])} (n={m1['nlat']}) | |")


def ack_table(base, new):
    print("\n### acknowledgement set: where each category went (sessions / Router / new / ask) for gold Router vs gold session")
    for fmt, recs in ((FORMATS[0], base), (FORMATS[1], new)):
        print(f"\n{fmt}")
        print("| category | gold | n | right | to session | to Router | to new | ask | wrong |")
        print("|---|---|---|---|---|---|---|---|---|")
        cats = []
        for r in recs:
            key = (r["cat"], r["gold_kind"])
            if key not in cats:
                cats.append(key)
        for tag, filt in [(c, lambda r, c=c: (r["cat"], r["gold_kind"]) == c) for c in cats] + [(("ALL", "router"), lambda r: r["gold_kind"] == "router"), (("ALL", "session"), lambda r: r["gold_kind"] == "session")]:
            sel = [r for r in recs if filt(r)]
            if not sel:
                continue
            cnt = lambda k: sum(1 for r in sel if r["sent_kind"] == k)
            print(f"| {tag[0]} | {tag[1]} | {len(sel)} | {sum(r['send'] - r['wrong'] for r in sel)} | {cnt('session')} | {cnt('router')} | {cnt('new')} | {cnt('ask')} | {sum(r['wrong'] for r in sel)} |")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["bench", "episodes", "actions"])
    ap.add_argument("--base", default="combo-o")
    ap.add_argument("--new", default="capabilities-o")
    ap.add_argument("--calls", type=int, default=0)
    ap.add_argument("--sets", default="realA,realB")
    a = ap.parse_args()
    global FORMATS
    FORMATS = (a.base, a.new)
    if a.mode == "actions":
        base, new = (episode_records(OUT / f"{f}.ack_actions.jsonl") for f in FORMATS)
        ack_table(base, new)
        print("\nmessages that reached the Router, by case")
        for b, n in zip(base, new):
            print(f"{b['id']:28} {b['message'][:56]:56} {b['sent_kind']:7} -> {n['sent_kind']:7} (gold {n['gold_kind']})")
    elif a.mode == "bench":
        total = 0
        for s in a.sets.split(","):
            recs = {}
            for fmt in FORMATS:
                recs[fmt], todo = bench_records(fmt, s, a.calls)
                total += todo
                json.dump(recs[fmt], open(OUT / f"bench.{fmt}.{s}.json", "w"))
            show(f"bench {s} (final3:best, shipped weights)", recs[FORMATS[0]], recs[FORMATS[1]])
        print(f"\nnew calls this run: {total}")
    else:
        for s in ("real_B", "real_A"):
            show(f"episodes dev {s}", *(episode_records(OUT / f"{f}.{s}.jsonl") for f in FORMATS))
        base, new = (episode_records(OUT / f"{f}.ack.jsonl") for f in FORMATS)
        show("episodes ack set (40)", base, new)
        ack_table(base, new)


if __name__ == "__main__":
    main()
