"""Sweep the intent bars (question, compound, setting) over saved runs. python3 real/intent_sweep.py FORMAT"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import analyze  # noqa: E402
import bench  # noqa: E402
import run  # noqa: E402


def main():
    fmt = sys.argv[1]
    sets = {s: (bench.load_set(s), run.load(f"{fmt}@{s}")) for s in ("synth", "heldout", "real")}
    for p_intent in (0.6, 0.8, 0.9, 0.95):
        for gc in (0.75, 0.9, 2):
            for gs in (0.75, 0.9):
                P = {**bench.FINAL, "p_intent": p_intent, "g_compound": gc, "g_setting": gs}
                pol = analyze.policy("gates", **P)
                out = []
                for s, (cases, rows) in sets.items():
                    t = bench.score(cases, rows, pol)
                    n = t["n"]
                    out.append(f"{s}: right {100 * t['right'] / n:4.1f} wrong {100 * t['wrong'] / n:4.1f}")
                print(f"p_intent={p_intent} g_compound={gc} g_setting={gs} | " + " | ".join(out))


if __name__ == "__main__":
    main()
