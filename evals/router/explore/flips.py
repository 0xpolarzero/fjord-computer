"""How often a policy's decision for one case changes with the options' order alone.
python3 -m explore.flips FORMAT module:policy SET"""
import collections
import importlib
import sys

import bench
import run
from explore import fusion as Fu


def main():
    fmt, spec, setname = sys.argv[1:4]
    Fu._patch_reading()
    mod, name = spec.split(":")
    pol = getattr(importlib.import_module(mod), name)
    cases = {c["id"]: c for c in bench.load_set(setname)}
    seen = collections.defaultdict(set)
    tops = collections.defaultdict(set)
    for row in run.load(f"{fmt}@{setname}"):
        c = cases[row["id"]]
        r = run.reading(row)
        k, w = pol(r, c) if getattr(pol, "needs_case", False) else pol(r)
        seen[row["id"]].add(w if k == "send" else "ask")
        t = run.ranked_targets(r)
        tops[row["id"]].add(t[0] if t else "-")
    n = len(seen)
    print(f"{setname}: decision changes with order in {sum(len(v) > 1 for v in seen.values())}/{n}, "
          f"Jev's top destination in {sum(len(v) > 1 for v in tops.values())}/{n}")


if __name__ == "__main__":
    main()
