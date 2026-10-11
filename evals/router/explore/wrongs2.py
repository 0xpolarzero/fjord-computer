"""Wrong sends of a needs_case policy on a set. python3 -m explore.wrongs2 FORMAT module:policy SET"""
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
    whole = {"realA": "real", "realB": "real"}.get(setname, setname)
    for row in run.load(f"{fmt}@{whole}"):
        c = cases.get(row["id"])
        if not c:
            continue
        r = run.reading(row)
        k, w = pol(r, c) if getattr(pol, "needs_case", False) else pol(r)
        if k == "send" and w not in c["gold"]["to"]:
            top = max(r["dests"].items(), key=lambda x: x[1])
            print(c["id"], repr(c["message"][:90]), "->", w, "gold", c["gold"]["to"], "jev top", top[0], round(top[1], 2))


if __name__ == "__main__":
    main()
