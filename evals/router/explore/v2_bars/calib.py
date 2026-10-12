"""The round's one calib check: Lookout before round 4 (round-3 weights from git, the ranking's own card, the fused
pick at 0.9) against Lookout now, on the calib split. Prints aggregate deltas only.

    git show a4f8814:Sources/Lookout/RouterRoute.swift > /tmp/RouterRoute.round3.swift
    python3 -m explore.v2_bars.calib /tmp/RouterRoute.round3.swift
"""
import json, os, subprocess, sys, tempfile

from explore import final3
from v2.run import episodes as E

CALIB = "v2/data/episodes/calib/episodes.jsonl"


def replay(swift, card, bar, path):
    if swift:
        os.environ["ROUTER_SWIFT"] = swift
    else:
        os.environ.pop("ROUTER_SWIFT", None)
    final3.B2 = bar
    system = E.RouterSystem(card=card, max_calls=4000)
    results = [E.play_episode(ep, system) for ep in E.load_episodes(CALIB)]
    with open(path, "w") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in results)


def main():
    out = tempfile.mkdtemp(prefix="v2_calib_")
    before, now = f"{out}/round3.jsonl", f"{out}/round4.jsonl"
    replay(sys.argv[1], "policy", 0.9, before)
    replay(None, "top1,other,recent", 0.93, now)
    r = json.loads(subprocess.run([sys.executable, "-m", "v2.run.compare", before, now], capture_output=True, text=True).stdout)
    for mix in ("natural", "stress"):
        m = r[mix]
        print(mix, {k: (round(m["baseline"][k], 3), round(m["candidate"][k], 3), round(m["delta"][k], 3),
                        [round(m["ci95"][k]["low"], 3), round(m["ci95"][k]["high"], 3)])
                    for k in ("loss_per_submit", "wrong_all", "coverage", "hit_at_4", "ranking_hit_at_1")})
    real = [f"{out}/real_{n}" for n in ("round3.jsonl", "round4.jsonl")]
    for src, dst in zip((before, now), real):
        subprocess.run([sys.executable, "v2/data/realonly.py", src, dst], check=True)
    r = json.loads(subprocess.run([sys.executable, "-m", "v2.run.compare", *real], capture_output=True, text=True).stdout)
    m = r["natural"]
    print("real only", {k: (round(m["baseline"][k], 3), round(m["candidate"][k], 3), round(m["delta"][k], 3),
                            [round(m["ci95"][k]["low"], 3), round(m["ci95"][k]["high"], 3)])
                        for k in ("loss_per_submit", "wrong_all", "coverage", "hit_at_4", "ranking_hit_at_1")})
    print("traces (message text, outside the repo):", out)


if __name__ == "__main__":
    main()
