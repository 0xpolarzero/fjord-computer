"""Skipped-asks eval, step 4: per wording and gate, precision and recall of "skipped" per question, the false-flag rate on
questions the reply did respond to, split by single- and multi-question cards; Jev's latency and failures. Numbers only.

    python3 v2/skipped_eval/score.py [--wordings A,B]  →  stdout (markdown)

Reference: label.py's labels; `skipped` is positive, everything else (responded, moved_on, unclear) negative, so a flag on an
unclear question counts as a false flag. A failed call flags nothing (the app leaves the card cleared).
Rules: `plain` flags a question when Jev's "skipped" probability reaches the gate; `partly` also needs another question of
the same card read as responded (its "skipped" probability under 0.5), so a reply that moves on from all of them, and any
single-question card, flags nothing."""
import argparse
import collections
import pathlib
import statistics
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "asks_eval"))
import common as C  # noqa: E402
from jev_run import WORDINGS  # noqa: E402

OUT = C.ROUTER / "v2" / "data" / "skipped_eval"
GATES = [0.7, 0.8, 0.85, 0.9, 0.95]


def pct(a, b):
    return f"{100 * a / b:.0f}%" if b else "–"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wordings", default="A,B")
    a = ap.parse_args()
    labels = {r["id"]: r["labels"] for r in C.jsonl(OUT / "labels.jsonl")}
    counts = collections.Counter()
    for labs in labels.values():
        for lab in labs:
            counts[("multi" if len(labs) > 1 else "single", lab)] += 1
    print("## Labels (Opus)\n")
    print("| card | responded | moved_on | skipped | unclear |\n|---|---|---|---|---|")
    for split in ("single", "multi"):
        print(f"| {split} | " + " | ".join(str(counts[(split, k)]) for k in ("responded", "moved_on", "skipped", "unclear")) + " |")
    print(f"\ncases {len(labels)} (single {sum(len(v) == 1 for v in labels.values())}, multi {sum(len(v) > 1 for v in labels.values())}); "
          f"questions {sum(len(v) for v in labels.values())}\n")
    for name in a.wordings.split(","):
        rows = C.jsonl(OUT / f"jev_{name}.jsonl")
        yes_skipped = WORDINGS[name.split("_")[0]]["yes_means"] == "skipped"
        lat = sorted(r["latency"] for r in rows if r["latency"] is not None and not r["error"])
        fails = [r for r in rows if r["error"]]
        print(f"## Wording {name} ({'yes = skipped' if yes_skipped else 'yes = responded'})\n")
        print(f"calls {len(rows)}, failures {len(fails)}, latency median {statistics.median(lat):.2f} s, "
              f"p90 {lat[int(0.9 * (len(lat) - 1))]:.2f} s\n")
        print("| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |\n|---|---|---|---|---|---|---|---|")
        for rule in ("plain", "partly"):
            for gate in GATES:
                for split in ("all", "single", "multi"):
                    tp = fp = fn = neg = fm = 0
                    for r in rows:
                        labs = labels[r["id"]]
                        if split == "single" and len(labs) != 1 or split == "multi" and len(labs) < 2:
                            continue
                        ps = [None if p is None else (p if yes_skipped else 1 - p) for p in (r["p_yes"] or [None] * len(labs))]
                        for i, lab in enumerate(labs):
                            flag = ps[i] is not None and ps[i] >= gate
                            if rule == "partly":
                                flag = flag and any(p is not None and p < 0.5 for j, p in enumerate(ps) if j != i)
                            pos = lab == "skipped"
                            tp += flag and pos
                            fp += flag and not pos
                            fm += flag and lab == "moved_on"
                            fn += (not flag) and pos
                            neg += not pos
                    print(f"| {rule} | {gate} | {split} | {tp + fp} | {pct(tp, tp + fp)} ({tp}/{tp + fp}) | {pct(tp, tp + fn)} ({tp}/{tp + fn}) "
                          f"| {pct(fp, neg)} ({fp}/{neg}) | {fm} |")
        print()


if __name__ == "__main__":
    main()
