"""Run route formats over the cases and score them.

python3 run.py FORMAT [FORMAT...] [--orders N] [--cases GLOB] [--only PREFIX_OR_TAG] [--verbose]
Each case is asked N times with options in different orders (order 0 = Lookout's own order). Raw answers are kept in
runs/<format>.jsonl, so policies can be swept offline (analyze.py)."""
import argparse
import glob
import json
import pathlib
import statistics
import sys

import formats
import jev

HERE = pathlib.Path(__file__).parent
NOT_TARGETS = {"unclear"}


def load_cases(pattern="cases/*.jsonl"):
    cases = []
    for f in sorted(glob.glob(str(HERE / pattern))):
        for line in open(f):
            if line.strip():
                cases.append(json.loads(line))
    return cases


def run(fmt, cases, orders=1, transform=None):
    calls, meta = [], []
    for c in cases:
        if transform:
            c = transform(c)
        for o in range(orders):
            state, q, keymap = formats.build(fmt, c, shuffle_seed=None if o == 0 else o)
            calls.append((state, q))
            meta.append((c, o, keymap))
    answers = jev.ask_many(calls)
    rows = []
    for (c, o, keymap), a in zip(meta, answers):
        rows.append({"id": c["id"], "order": o, "keymap": keymap, "answers": a["answers"],
                     "latency": a.get("_latency"), "tokens": (a.get("usage") or {}).get("input_tokens")})
    return rows


def save(name, rows):
    out = HERE / "runs" / f"{name}.jsonl"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(json.dumps(r) for r in rows) + "\n")


def load(name):
    if name.startswith("_"):
        return json.load(open(HERE / "runs" / f"{name}.json"))
    return [json.loads(l) for l in open(HERE / "runs" / f"{name}.jsonl") if l.strip()]


# ---------------------------------------------------------------- readings: answers → destinations

def reading(row):
    """{'options': [(dest, p)] best first (per option, as Lookout ranks), 'dests': {dest: p} (summed per destination)}.
    For fan-out answers, also 'kind', 'yes' (per session) and 'project'."""
    if "_r" in row:
        return row["_r"]
    a, km = row["answers"], row["keymap"]
    if "route" in a:
        opts = sorted(((km.get(k, k), p) for k, p in a["route"].get("probabilities", {}).items()), key=lambda x: -x[1])
        dests = {}
        for d, p in opts:
            dests[d] = dests.get(d, 0) + p
        replies = {}
        for k, v in a.items():
            if k.startswith("answers"):
                replies[km[k]] = max(replies.get(km[k], 0), v["noul"])
        gates = {k: v["noul"] for k, v in a.items() if k.startswith("gate_")}
        return {"options": opts, "dests": dests, "replies": replies, "gates": gates}
    kind = a["kind"]["probabilities"]
    yes = {km[k]: v["noul"] for k, v in a.items() if k in km}
    project = a.get("project", {}).get("probabilities", {})
    total = sum(yes.values()) or 1
    dests = {sid: kind.get("session", 0) * y / total for sid, y in yes.items()}
    for p, pp in project.items():
        if p != "none":
            dests[f"new:{p}"] = kind.get("new_session", 0) * pp
    for k in ("change_lookout", "question", "compound", "unclear"):
        dests[k] = kind.get(k, 0)
    return {"options": sorted(dests.items(), key=lambda x: -x[1]), "dests": dests, "kind": kind, "yes": yes, "project": project}


# ---------------------------------------------------------------- policies: reading → ("send", dest) | ("ask", top3)

def ranked_targets(r):
    return [d for d, _ in sorted(r["dests"].items(), key=lambda x: -x[1]) if d not in NOT_TARGETS]


def policy_lead(p_min=0.75, lead=0.3, merged=False):
    """Lookout today (merged=False): the top option ≥ p_min, ahead of the runner-up by `lead`, and not unclear."""
    def pol(r):
        ranked = sorted(r["dests"].items(), key=lambda x: -x[1]) if merged else r["options"]
        top, p = ranked[0]
        second = ranked[1][1] if len(ranked) > 1 else 0
        if top in NOT_TARGETS or p < p_min or p - second < lead:
            return ("ask", ranked_targets(r)[:3])
        return ("send", top)
    return pol


def policy_fanout(kind_min=0.6, yes_min=0.7, others_max=0.3, project_min=0.6):
    """Fan-out: the kind decides; a session needs a clear yes with every other session a clear no."""
    def pol(r):
        if "kind" not in r:
            return policy_lead(merged=True)(r)
        kind, kp = max(r["kind"].items(), key=lambda x: x[1])
        if kp < kind_min or kind == "unclear":
            return ("ask", ranked_targets(r)[:3])
        if kind == "session":
            ys = sorted(r["yes"].items(), key=lambda x: -x[1])
            if ys and ys[0][1] >= yes_min and (len(ys) < 2 or ys[1][1] <= others_max):
                return ("send", ys[0][0])
            return ("ask", ranked_targets(r)[:3])
        if kind == "new_session":
            p, pp = max(r["project"].items(), key=lambda x: x[1]) if r["project"] else ("none", 0)
            if p != "none" and pp >= project_min:
                return ("send", f"new:{p}")
            return ("ask", ranked_targets(r)[:3])
        return ("send", kind)
    return pol


def score(cases, rows, policy):
    by = {c["id"]: c for c in cases}
    tally = {"right": 0, "wrong": 0, "miss": 0, "good_ask": 0}
    wrongs, misses = [], []
    top1 = top3 = n_target = 0
    for row in rows:
        c = by[row["id"]]
        r = reading(row)
        gold = set(c["gold"]["to"])
        ask_ok = c["gold"].get("ask_ok", False) or not gold
        ranked = ranked_targets(r)
        if gold:
            n_target += 1
            top1 += bool(ranked[:1]) and ranked[0] in gold
            top3 += bool(gold & set(ranked[:3]))
        kind, what = policy(r)
        if kind == "send":
            if what in gold:
                tally["right"] += 1
            else:
                tally["wrong"] += 1
                wrongs.append((c["id"], row["order"], what, sorted(gold)))
        elif ask_ok:
            tally["good_ask"] += 1
        else:
            tally["miss"] += 1
            misses.append((c["id"], row["order"]))
    n = len(rows)
    return {"n": n, **{k: round(100 * v / n, 1) for k, v in tally.items()},
            "top1": round(100 * top1 / max(n_target, 1), 1), "top3": round(100 * top3 / max(n_target, 1), 1),
            "wrongs": wrongs, "misses": misses}


def order_flips(rows):
    tops = {}
    for row in rows:
        r = ranked_targets(reading(row)) or ["unclear"]
        tops.setdefault(row["id"], set()).add(r[0])
    return sum(len(v) > 1 for v in tops.values()), len(tops)


def report(fmt, cases, rows, verbose=False):
    pols = [("lookout", policy_lead()), ("lookout-merged", policy_lead(merged=True))]
    if "kind" in rows[0]["answers"]:
        pols = [("fanout", policy_fanout()), ("merged-lead", policy_lead(merged=True))]
    for name, pol in pols:
        s = score(cases, rows, pol)
        print(f"{fmt:10} {name:15} n={s['n']} right={s['right']}% wrong={s['wrong']}% miss={s['miss']}% "
              f"good_ask={s['good_ask']}% | top1={s['top1']}% top3={s['top3']}%")
        if verbose:
            print("   wrong:", s["wrongs"][:60])
    orders = len({r["order"] for r in rows})
    if orders > 1:
        f, t = order_flips(rows)
        print(f"{fmt:10} order flips: {f}/{t}")
    lat = [r["latency"] for r in rows if r["latency"]]
    tok = [r["tokens"] for r in rows if r["tokens"]]
    if lat:
        print(f"{fmt:10} latency median={statistics.median(lat):.2f}s p95={sorted(lat)[max(int(len(lat) * .95) - 1, 0)]:.2f}s "
              f"tokens median={statistics.median(tok) if tok else 0}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("formats", nargs="+")
    ap.add_argument("--orders", type=int, default=1)
    ap.add_argument("--cases", default="cases/*.jsonl")
    ap.add_argument("--only")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--pad", type=int, help="pad every board to this many sessions")
    ap.add_argument("--tag", default="", help="suffix for the saved run's name")
    a = ap.parse_args()
    cases = load_cases(a.cases)
    if a.only:
        cases = [c for c in cases if a.only in c.get("tags", []) or c["id"].startswith(a.only)]
    if a.pad:
        import transforms
        cases = [transforms.pad(c, a.pad) for c in cases]
    for fmt in a.formats:
        rows = run(fmt, cases, a.orders)
        save(fmt + a.tag, rows)
        report(fmt + a.tag, cases, rows, a.verbose)


if __name__ == "__main__":
    sys.exit(main())
