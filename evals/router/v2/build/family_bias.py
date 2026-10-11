"""Does a writer's own model family label its episodes more kindly? (Claude and GPT label everything, own writing
included, because Gemini's quota can't cover the written set; label.independent_families.)

    python3 -m v2.build.family_bias sample [--labels v2/data/labels_full]   writes the Gemini audit keys
    python3 -m v2.build.family_bias report --labels v2/data/labels_full --claude v2/data/labels_full_claude \\
        [--gemini v2/data/labels_full_gem]

1. Free, on every written event: how often each labeller's `intended` matches the writer's own intended target, on its
   family's writing and on the other family's. The difference of differences cancels each labeller's general skill and
   leaves the own-family boost.
2. Gemini as a referee on a sample (75 Claude-written, 75 GPT-written, one event per episode, by mode; 50 real
   moments): how often each family agrees with Gemini on its own writing against the other's.
Prints aggregate rates with bootstrap CIs over episodes; no message text.
"""
import argparse
import collections
import json
import random
from pathlib import Path

V2 = Path(__file__).resolve().parents[1]
WRITERS = ("claude", "gpt")


def jsonl(path):
    path = Path(path)
    return [json.loads(line) for line in path.open() if line.strip()] if path.exists() else []


def labels(directory, family):
    out = {}
    for row in jsonl(Path(directory) / "raw.jsonl"):
        if row["family"] == family and row.get("role") == "independent" and row.get("status") == "ok":
            out[row["key"]] = row["label"]
    return out


def sample(manifest, seed=11, per_writer=75, real=50):
    rng = random.Random(seed)
    by_episode = collections.defaultdict(list)
    for record in manifest:
        by_episode[record["episode_id"]].append(record)
    firsts = [min(records, key=lambda r: r["event_id"]) for records in by_episode.values()]
    keys = []
    for writer in WRITERS:
        pool = [r for r in firsts if r.get("writer") == writer]
        by_mode = collections.defaultdict(list)
        for r in pool:
            by_mode[r["source"]].append(r)
        for mode, records in sorted(by_mode.items()):
            rng.shuffle(records)
            keys += [r["key"] for r in records[:round(per_writer * len(records) / len(pool))]]
    reals = [r for r in firsts if r["source"] == "real-moment"]
    rng.shuffle(reals)
    return keys + [r["key"] for r in reals[:real]]


def rate(pairs, rng, replicates=1000):
    """Share of True, with a bootstrap 95% CI over episodes (pairs: (episode, bool))."""
    if not pairs:
        return None
    by = collections.defaultdict(list)
    for episode, hit in pairs:
        by[episode].append(hit)
    episodes = list(by)
    point = sum(h for _, h in pairs) / len(pairs)
    draws = []
    for _ in range(replicates):
        chosen = [rng.choice(episodes) for _ in episodes]
        hits = [h for e in chosen for h in by[e]]
        draws.append(sum(hits) / len(hits))
    draws.sort()
    return {"rate": round(point, 3), "ci": [round(draws[25], 3), round(draws[974], 3)], "n": len(pairs)}


def report(manifest, gpt, claude, gemini, seed=7):
    rng = random.Random(seed)
    by_family = {"claude": claude, "gpt": gpt}
    out = {"writer_gold_match": {}, "gemini_agreement": {}}
    written = [r for r in manifest if r.get("writer") in WRITERS and r["original_gold"].get("intended")]
    for labeller, given in by_family.items():
        for writer in WRITERS:
            pairs = [(r["episode_id"], given[r["key"]]["intended"] == r["original_gold"]["intended"])
                     for r in written if r["writer"] == writer and r["key"] in given]
            out["writer_gold_match"][f"{labeller} labels {writer}-written"] = rate(pairs, rng)
    m = out["writer_gold_match"]
    if all(m.get(f"{a} labels {b}-written") for a in WRITERS for b in WRITERS):
        own = m["claude labels claude-written"]["rate"] + m["gpt labels gpt-written"]["rate"]
        cross = m["claude labels gpt-written"]["rate"] + m["gpt labels claude-written"]["rate"]
        out["own_family_boost"] = round((own - cross) / 2, 3)
    if gemini:
        for labeller, given in by_family.items():
            for source in ("claude-written", "gpt-written", "real-moment"):
                pairs = [(r["episode_id"], given[r["key"]]["intended"] == gemini[r["key"]]["intended"])
                         for r in manifest if r["key"] in gemini and r["key"] in given
                         and (r["source"] == "real-moment" if source == "real-moment" else r.get("writer") + "-written" == source)]
                out["gemini_agreement"][f"{labeller} vs gemini on {source}"] = rate(pairs, rng)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["sample", "report"])
    parser.add_argument("--labels", default=str(V2 / "data/labels_full"))
    parser.add_argument("--claude", default=str(V2 / "data/labels_full_claude"))
    parser.add_argument("--gemini", default=str(V2 / "data/labels_full_gem"))
    parser.add_argument("--out", default=str(V2 / "data/labels_full_gem_keys.txt"))
    args = parser.parse_args()
    manifest = jsonl(Path(args.labels) / "manifest.jsonl")
    if args.command == "sample":
        keys = sample(manifest)
        Path(args.out).write_text("\n".join(keys) + "\n")
        print(json.dumps({"keys": len(keys), "file": args.out}))
    else:
        print(json.dumps(report(manifest, labels(args.labels, "gpt"), labels(args.claude, "claude"),
                                labels(args.gemini, "gemini")), indent=1))


if __name__ == "__main__":
    main()
