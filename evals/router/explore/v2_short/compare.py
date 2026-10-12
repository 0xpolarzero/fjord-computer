"""Paired comparison of variant traces against the shipped replay on dev real moments, with input tokens per call.

python3 -m explore.v2_short.compare BASE.jsonl CAND.jsonl [CAND2.jsonl ...]
Metrics and 95% CIs (resampling `group`) from explore.v2_continuity.metrics; tokens are Jev's usage.input_tokens of
each submit's call. Prints aggregates only."""
import json
import random
import statistics
import sys

from explore.v2_continuity import metrics as M

KEEP = ("top-1 of fused ranking", "top-1, same-session submits", "top-1, switch submits", "loss per submit",
        "sends / submit", "wrong sends / submit", "right sends / submit", "card hit@4 among asks",
        "asks missing target / submit", "AUROC sureness (top-1 right vs wrong)")


def tokens(path):
    out = {}
    for line in open(path):
        ep = json.loads(line)
        if (ep.get("provenance") or {}).get("source") != "real-moment":
            continue
        for ev in ep["events"]:
            if ev["kind"] == "submit" and ev.get("tokens") is not None:
                out[(ep["id"], ev["id"])] = (ep["group"], ev["tokens"])
    return out


def token_table(base_path, cand_path, reps=2000, seed=7):
    b, c = tokens(base_path), tokens(cand_path)
    keys = sorted(set(b) & set(c))
    tb, tc = [b[k][1] for k in keys], [c[k][1] for k in keys]
    groups = {}
    for k in keys:
        groups.setdefault(b[k][0], []).append(k)
    names = sorted(groups)
    rng = random.Random(seed)
    ratios = []
    for _ in range(reps):
        ks = [k for g in (names[rng.randrange(len(names))] for _ in names) for k in groups[g]]
        ratios.append(sum(c[k][1] for k in ks) / sum(b[k][1] for k in ks) - 1)
    ratios.sort()
    return (f"input tokens per call: base mean {statistics.mean(tb):.0f} (median {statistics.median(tb):.0f}), "
            f"variant mean {statistics.mean(tc):.0f} (median {statistics.median(tc):.0f}); change "
            f"{100 * (sum(tc) / sum(tb) - 1):+.1f}% (95% CI {100 * ratios[50]:+.1f} to {100 * ratios[-51]:+.1f}), "
            f"{len(keys)} calls")


def counts(path):
    rows = M.load(path)
    return {"wrong sends": sum(r["wrong"] for r in rows.values()), "sends": sum(r["send"] for r in rows.values()),
            "asks": sum(r["ask"] for r in rows.values()), "ask hits": sum(r["askhit"] for r in rows.values())}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    base = args[0]
    for cand in args[1:]:
        out, n, g, changed = M.paired(M.load(base), M.load(cand))
        print(f"{cand} vs {base}: {n} real submits, {g} groups, {changed} change outcome")
        print("| metric | base | variant | Δ | 95% CI |")
        print("|---|---:|---:|---:|---|")
        for m in KEEP:
            b, c, d, lo, hi = out[m]
            if m.startswith("loss") or m.startswith("AUROC"):
                print(f"| {m} | {b:.3f} | {c:.3f} | {d:+.3f} | {lo:+.3f} to {hi:+.3f} |")
            else:
                print(f"| {m} (%) | {100 * b:.1f} | {100 * c:.1f} | {100 * d:+.1f} | {100 * lo:+.1f} to {100 * hi:+.1f} |")
        print("counts base", counts(base), "variant", counts(cand))
        print(token_table(base, cand))
        print()


if __name__ == "__main__":
    main()
