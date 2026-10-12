"""Free-running replay of dev real-moment episodes under the shortlist (A9) and two-wording (A12) formats.

python3 -m explore.v2_short.replay VARIANT [--max-calls N] [--cache-only] [--out DIR]
  VARIANT: shipped | short<K> | short<K>-mix | twoword
Traces to DIR/<variant>.jsonl (default /tmp/v2_short: they hold message text), records (case, reading, gold) to
DIR/<variant>.rec.pkl. Reuses explore.v2_continuity.replay.Variant (combo-o, the weights Swift ships); only
v2/data/episodes/dev/provisional.jsonl is read, real moments only."""
import argparse
import json
import pickle
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from explore.v2_continuity.replay import Variant, load  # noqa: E402
from explore.v2_short import formats as SF  # noqa: E402

OUT = Path("/tmp/v2_short")


def make(variant, cache_only=False, max_calls=0):
    v = Variant("combo-o", cache_only=cache_only, max_calls=max_calls)
    formats, _, run, *_ = v.mods
    formats.FORMATS.update(SF.FORMATS)
    SF.install_reading(run)
    if variant != "shipped":
        v.system.format_name = SF.format_name(variant)
    return v


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("variant")
    p.add_argument("--cache-only", action="store_true")
    p.add_argument("--max-calls", type=int, default=0)
    p.add_argument("--out", type=Path, default=OUT)
    p.add_argument("--route", choices=["avg", "first", "second"], default="avg",
                   help="twoword: which route answer the reading uses (same requests, so a cache-only check)")
    p.add_argument("--name", help="output name (default: the variant)")
    a = p.parse_args(argv)
    SF.MODE["route"] = a.route
    v = make(a.variant, a.cache_only, a.max_calls)
    eps = load(False)
    a.out.mkdir(parents=True, exist_ok=True)
    results = [v.play(e) for e in eps]
    name = a.name or a.variant
    (a.out / f"{name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    with open(a.out / f"{name}.rec.pkl", "wb") as f:
        pickle.dump(v.records, f)
    print(json.dumps({"variant": a.variant, "format": v.system.format_name, "episodes": len(eps),
                      "records": len(v.records), "new_calls": v.system.new_calls, "cache_hits": v.system.cache_hits}))


if __name__ == "__main__":
    main()
