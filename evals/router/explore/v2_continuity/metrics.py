"""Paired metrics of variant traces against a base, real-moment submits only, 95% CIs by resampling `group`.

python3 -m explore.v2_continuity.metrics BASE.jsonl CAND.jsonl [CAND2.jsonl ...] [--md]

Per submit: top-1 of the fused ranking (trace `top` == gold.intended), the policy's outcome (send right / wrong, ask
with the target on the card's four or not), loss as v2.run.score charges it. Selective risk: all submits sorted by the
fused sureness, the top 30/40/50% taken as sends, the share whose fused top isn't the intended target; AUROC of
sureness between right and wrong fused tops."""
import json
import random
import sys

from v2.run.score import event_score

COVERAGES = (0.3, 0.4, 0.5)


def load(path):
    rows = {}
    for line in open(path):
        ep = json.loads(line)
        if (ep.get("provenance") or {}).get("source") != "real-moment":
            continue
        for ev in ep["events"]:
            if ev["kind"] != "submit" or ev.get("duplicate_of_real"):
                continue
            s = event_score(ev)
            slices = set((ev.get("tags") or {}).get("slices", []))
            rows[(ep["id"], ev["id"])] = {
                "group": ep["group"], "top1": int(ev.get("top") == ev["gold"]["intended"]),
                "sure": ev.get("sureness") if ev.get("sureness") is not None else 0.0,
                "loss": s["loss"], "send": s["automatic"], "wrong": s["wrong"], "right": s["right"],
                "ask": s["ask"], "askhit": s["ask"] * s["hit_at_4"], "askmiss": s["ask"] * (1 - s["hit_at_4"]),
                "same": int("same" in slices), "switch": int("switch" in slices)}
    return rows


def auroc(rows):
    pos = [r["sure"] for r in rows if r["top1"]]
    neg = [r["sure"] for r in rows if not r["top1"]]
    if not pos or not neg:
        return float("nan")
    allv = sorted([(v, 1) for v in pos] + [(v, 0) for v in neg])
    # rank-sum with ties averaged
    ranks, i = {}, 0
    rs = [0.0] * len(allv)
    while i < len(allv):
        j = i
        while j + 1 < len(allv) and allv[j + 1][0] == allv[i][0]:
            j += 1
        for k in range(i, j + 1):
            rs[k] = (i + j) / 2 + 1
        i = j + 1
    rp = sum(r for r, (_, y) in zip(rs, allv) if y)
    return (rp - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))


def risk_at(rows, cov):
    k = max(1, round(cov * len(rows)))
    top = sorted(rows, key=lambda r: -r["sure"])[:k]
    return 1 - sum(r["top1"] for r in top) / k


def summary(rows):
    n = len(rows)
    asks = sum(r["ask"] for r in rows)
    sends = sum(r["send"] for r in rows)
    out = {
        "top-1 of fused ranking": sum(r["top1"] for r in rows) / n,
        "top-1, same-session submits": _share(rows, "same", "top1"),
        "top-1, switch submits": _share(rows, "switch", "top1"),
        "loss per submit": sum(r["loss"] for r in rows) / n,
        "loss per submit, same-session": _share(rows, "same", "loss"),
        "loss per submit, switch": _share(rows, "switch", "loss"),
        "sends / submit": sends / n,
        "wrong sends / submit": sum(r["wrong"] for r in rows) / n,
        "right sends / submit": sum(r["right"] for r in rows) / n,
        "card hit@4 among asks": sum(r["askhit"] for r in rows) / asks if asks else float("nan"),
        "asks missing target / submit": sum(r["askmiss"] for r in rows) / n,
        "AUROC sureness (top-1 right vs wrong)": auroc(rows),
    }
    for c in COVERAGES:
        out[f"wrong rate @ {int(c * 100)}% coverage"] = risk_at(rows, c)
    return out


def _share(rows, cond, key):
    sub = [r for r in rows if r[cond]]
    return sum(r[key] for r in sub) / len(sub) if sub else float("nan")


def paired(base, cand, reps=2000, seed=7):
    keys = sorted(set(base) & set(cand))
    groups = {}
    for k in keys:
        groups.setdefault(base[k]["group"], []).append(k)
    names = sorted(groups)
    sb, sc = summary([base[k] for k in keys]), summary([cand[k] for k in keys])
    rng = random.Random(seed)
    deltas = {m: [] for m in sb}
    for _ in range(reps):
        pick = [names[rng.randrange(len(names))] for _ in names]
        ks = [k for g in pick for k in groups[g]]
        b, c = summary([base[k] for k in ks]), summary([cand[k] for k in ks])
        for m in sb:
            if b[m] == b[m] and c[m] == c[m]:
                deltas[m].append(c[m] - b[m])
    out = {}
    for m in sb:
        d = sorted(deltas[m])
        lo, hi = (d[int(0.025 * len(d))], d[int(0.975 * len(d)) - 1]) if d else (float("nan"),) * 2
        out[m] = (sb[m], sc[m], sc[m] - sb[m], lo, hi)
    changed = sum(1 for k in keys if (base[k]["top1"], base[k]["send"], base[k]["wrong"], base[k]["askhit"])
                  != (cand[k]["top1"], cand[k]["send"], cand[k]["wrong"], cand[k]["askhit"]))
    return out, len(keys), len(names), changed


def fmt(x, pct):
    if x != x:
        return "n/a"
    return f"{100 * x:+.1f}" if pct == "d" else f"{100 * x:.1f}" if pct else f"{x:.3f}"


def table(base_path, cand_path, md=False):
    out, n, g, changed = paired(load(base_path), load(cand_path))
    lines = [f"{cand_path} vs {base_path}: {n} real submits, {g} groups, {changed} submits change outcome",
             "| metric | base | variant | Δ | 95% CI |", "|---|---:|---:|---:|---|"]
    for m, (b, c, d, lo, hi) in out.items():
        pct = not (m.startswith("loss") or m.startswith("AUROC"))
        if pct:
            lines.append(f"| {m} (%) | {fmt(b, 1)} | {fmt(c, 1)} | {fmt(d, 'd')} | {fmt(lo, 'd')} to {fmt(hi, 'd')} |")
        else:
            lines.append(f"| {m} | {b:.3f} | {c:.3f} | {d:+.3f} | {lo:+.3f} to {hi:+.3f} |")
    return "\n".join(lines)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for cand in args[1:]:
        print(table(args[0], cand))
        print()


if __name__ == "__main__":
    main()
