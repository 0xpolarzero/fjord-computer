"""Where a variant's top-1 gains and losses come from, against shipped (counts only, no text).

python3 -m explore.v2_fusion.slices VARIANT [BASE]
"""
import collections
import sys

sys.dont_write_bytecode = True

from explore.v2_fusion import core as C
from explore.v2_fusion import experiments as X


def slice_of(x):
    if x.y is None:
        return "gold-not-offered"
    g = x.fs[x.dests[x.y]]
    if not g.get("sess"):
        return "gold-new" if g.get("new") else "gold-intent"
    tags = []
    tags.append("running" if g.get("run") else "finished")
    tags.append("told0" if g.get("told0") else "switch")
    return "gold-" + "/".join(tags)


def top_kind(x, top):
    f = x.fs[top]
    if not f.get("sess"):
        return "new" if f.get("new") else "intent"
    return ("run" if f.get("run") else "fin") + ("+told0" if f.get("told0") else "")


def main(var, base="shipped"):
    data = C.load()
    pa, _ = X.oof(data, base)
    pb, _ = X.oof(data, var)
    t = collections.defaultdict(collections.Counter)
    tops = collections.defaultdict(collections.Counter)
    for x, a, b in zip(data, pa, pb):
        s = slice_of(x)
        t[s]["n"] += 1
        t[s][base] += a["ok"]
        t[s][var] += b["ok"]
        t[s]["gain"] += b["ok"] and not a["ok"]
        t[s]["loss"] += a["ok"] and not b["ok"]
        for name, p in ((base, a), (var, b)):
            k = top_kind(x, p["top"])
            tops[name][k + ":n"] += 1
            tops[name][k + ":ok"] += p["ok"]
    print(f"| gold slice | n | {base} right | {var} right | gained | lost |\n|---|---|---|---|---|---|")
    for s in sorted(t):
        c = t[s]
        print(f"| {s} | {c['n']} | {c[base]} | {c[var]} | {c['gain']} | {c['loss']} |")
    kinds = sorted({k.split(':')[0] for v in tops.values() for k in v})
    print(f"\n| top-1 kind | {base} n (right) | {var} n (right) |\n|---|---|---|")
    for k in kinds:
        print(f"| {k} | {tops[base][k + ':n']} ({tops[base][k + ':ok']}) | {tops[var][k + ':n']} ({tops[var][k + ':ok']}) |")


if __name__ == "__main__":
    main(*sys.argv[1:])
