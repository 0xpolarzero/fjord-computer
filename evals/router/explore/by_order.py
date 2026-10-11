"""A saved multi-order run scored per order (order 0 = Lookout's own order: running, then latest finished).
python3 -m explore.by_order FORMAT module:policy SET"""
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
    cases = bench.load_set(setname)
    rows = run.load(f"{fmt}@{setname}")
    for o in sorted({r["order"] for r in rows}):
        sub = [r for r in rows if r["order"] == o]
        print(f"order {o}: " + bench.line(setname, bench.score(cases, sub, pol)))


if __name__ == "__main__":
    main()
