"""Send bars on dev real moments, by full replay (the bars change later boards): the fused pick's bar (final3.B2,
Swift RouteFusion.sure), the rules' send bar (C1, rulesSure), the short-message bar (TERSE_BAR, shortSure) and the
fewest words the fused pick alone sends (MIN_WORDS, fusedWords).

    python3 -m explore.v2_bars.sweep B2=0.8,0.85,0.9 C1=0.5,0.6 [TERSE_BAR=...] [MIN_WORDS=...]

Prints one line per combination: loss per submit, wrong sends, sends, needless asks, card misses (real moments only,
soft gold). Traces go to /tmp/v2_bars (they hold message text). NEVER reads calib or sealed.
"""
import itertools, json, pathlib, sys

from explore import final3
from v2.run import episodes as E
from v2.run.score import episode_score

DEV = "v2/data/episodes/dev/episodes.jsonl"
OUT = pathlib.Path("/tmp/v2_bars")


def run(params, episodes, system):
    for k, v in params.items():
        setattr(final3, k, v)
    results = [E.play_episode(ep, system) for ep in episodes]
    stats = [episode_score(r) for r in results]
    n = sum(s["submits"] for s in stats)
    tot = {k: sum(s[k] for s in stats) for k in ("loss", "wrong", "automatic", "needless_ask", "ask")}
    misses = sum(1 for r in results for ev in r["events"] if ev.get("kind") == "submit" and ev.get("decision") == "ask"
                 and not ev.get("duplicate_of_real") and ev["gold"]["intended"] not in
                 [x["target"] if isinstance(x, dict) else x for x in ev.get("ranked", [])][:4])
    name = ",".join(f"{k}={v}" for k, v in params.items())
    OUT.mkdir(exist_ok=True)
    with open(OUT / f"{name}.jsonl", "w") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in results)
    print(f"{name:42} loss {tot['loss'] / n:.3f} wrong {tot['wrong'] / n:.3f} sends {tot['automatic'] / n:.3f} "
          f"needless {tot['needless_ask'] / n:.3f} misses {misses}", flush=True)


def main():
    grid = {}
    for arg in sys.argv[1:]:
        key, values = arg.split("=")
        grid[key] = [float(x) if "." in x else int(x) for x in values.split(",")]
    episodes = [ep for ep in E.load_episodes(DEV) if (ep.get("provenance") or {}).get("source") == "real-moment"]
    system = E.RouterSystem(max_calls=3000)
    system._load()  # final3's module is loaded once; its bars are read at decision time
    for combo in itertools.product(*grid.values()):
        run(dict(zip(grid, combo)), episodes, system)


if __name__ == "__main__":
    main()
