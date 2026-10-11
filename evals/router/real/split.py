"""Labeling batches: real cases with the destination shown, as compact text a labeler reads.

python3 real/split.py N  →  real/data/label_in_{i}.txt (one block per case)."""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent


def block(c):
    b = c["board"]
    by = {s["id"]: s for s in b["sessions"]}
    lines = [f"### {c['id']}", f"MESSAGE: {c['message'][:1200]}", f"WENT TO: {c['gold']['to'][0]}"]
    for s in b["sessions"]:
        card = next((k for k in b["cards"] if k["session"] == s["id"]), None)
        state = ("running: " + s["activity"][:140]) if s["running"] else f"idle {s['idle_min']}m"
        if card:
            state += f" | {card['kind']} card: {card['text'][:200]}"
        told = next((h for h in reversed(b["history"]) if h["to"] == s["id"]), None)
        if told:
            state += f" | you last told it ({told['ago_min']}m ago): {told['you'][:120]}"
        lines.append(f"- {s['id']} [{s['project']}] {s['title']} :: {state}".replace("\n", " "))
    lines.append(f"projects: {', '.join(b['projects'])}")
    return "\n".join(lines)


def main():
    n = int(sys.argv[1])
    cases = [json.loads(l) for l in open(HERE / "data" / "real.jsonl")]
    for i in range(n):
        with open(HERE / "data" / f"label_in_{i}.txt", "w") as f:
            for c in cases[i::n]:
                f.write(block(c) + "\n\n")
    print(len(cases), "cases in", n, "batches")


if __name__ == "__main__":
    main()
