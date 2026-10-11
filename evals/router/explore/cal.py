"""Calibration in the same call (round 3).

combo-cc   contextual calibration (Zhao et al. 2021, "Calibrate Before Use"): the route asked again about a content-free
           field (`nothing`), on the same board; its answer is each option's pull with no message (first-option bias,
           a bait title, a long description), which the fusion can divide out (feature `lnull`).
combo-rev  the route asked twice, options in Lookout's order and reversed, averaged (permutation debiasing).
Run with JEV_ORDERED=1 so options reach Jev in the order built, as Lookout sends them."""
import math

import run
from explore import combo

NULL_INSTRUCTIONS = {"question": "Where does the user's `nothing` go?", "focus": "Decide about `nothing` alone."}


def combo_cc(case, rng=None):
    state, q, keymap = combo.combo(case, rng)
    state = {**state, "nothing": "(no message)"}
    q["route_null"] = {**q["route"], "instructions": NULL_INSTRUCTIONS}
    return state, q, keymap


def combo_rev(case, rng=None):
    state, q, keymap = combo.combo(case, rng)
    crit = q["route"]["criteria"]
    q["route_rev"] = {**q["route"], "criteria": dict(reversed(list(crit.items())))}
    return state, q, keymap


# combo-o: combo itself, saved under its own name, for runs made with JEV_ORDERED=1 (combo's own saved runs reached Jev
# in alphabetical order).
FORMATS = {"combo-cc": combo_cc, "combo-rev": combo_rev, "combo-o": combo.combo}


def _patch_reading():
    """run.reading plus r['null'] (the content-free route, per destination); combo-rev's two routes averaged into dests."""
    if getattr(run.reading, "_cal", False):
        return
    orig = run.reading

    def reading(row):
        r = dict(orig(row))
        a, km = row["answers"], row["keymap"]
        for key in ("route_null", "route_rev"):
            if key in a:
                d = {}
                for k, p in a[key].get("probabilities", {}).items():
                    dest = km.get(k, k)
                    d[dest] = d.get(dest, 0) + p
                if key == "route_null":
                    r["null"] = d
                else:
                    avg = {x: (r["dests"].get(x, 0) + d.get(x, 0)) / 2 for x in set(r["dests"]) | set(d)}
                    r["dests"] = avg
                    r["options"] = sorted(avg.items(), key=lambda x: -x[1])
        return r
    reading._cal = True
    reading._fusion = getattr(orig, "_fusion", False)
    run.reading = reading


def calibrated(r, floor=1e-3):
    """The route divided by its content-free pull, renormalised (Zhao et al.)."""
    null = r.get("null") or {}
    q = {d: p / max(null.get(d, floor), floor) for d, p in r["dests"].items()}
    z = sum(q.values()) or 1
    return {d: v / z for d, v in q.items()}
