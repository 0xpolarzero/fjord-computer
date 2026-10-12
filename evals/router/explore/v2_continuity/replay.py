"""Free-running replay of dev episodes under a format/weights variant, recording each submit's case and Jev reading.

python3 -m explore.v2_continuity.replay VARIANT [--all-sources] [--max-calls N] [--cache-only]
  VARIANT: shipped (combo-o, Swift weights)      told (combo-o-told, Swift weights)
Traces go to explore/v2_continuity/out/<variant>.jsonl, records (case, reading, gold) to out/<variant>.rec.pkl.
Only v2/data/episodes/dev/provisional.jsonl is read; calib and sealed are never opened."""
import argparse
import json
import pickle
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from v2.run import episodes as E

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
DEV = E.ROUTER / "v2" / "data" / "episodes" / "dev" / "provisional.jsonl"


def load(all_sources=False):
    eps = E.load_episodes([DEV])
    if not all_sources:
        eps = [e for e in eps if (e.get("provenance") or {}).get("source") == "real-moment"]
    return eps


class Variant:
    """A RouterSystem whose format, features and weights can be swapped per episode."""

    def __init__(self, fmt="combo-o", trans=False, cache_only=False, max_calls=0):
        self.system = E.RouterSystem(fmt, cache_only=cache_only, max_calls=max_calls)
        formats, jev, run, policy, lexical, fusion, final3 = self.system._load()
        from explore.v2_continuity import told
        formats.FORMATS.update(told.FORMATS)
        self.base_features = lexical.features if not getattr(lexical.features, "_told", False) else None
        if trans:
            lexical.features = told.extend(lexical.features)
        self.mods = [formats, jev, run, policy, lexical, fusion, final3]
        self.records = []
        self.shipped = E._shipped_weights()
        self.set_weights(*self.shipped)

    def set_weights(self, w, v):
        formats, jev, run, _, lexical, fusion, final3 = self.mods
        final3._FIT["combo-o"] = (dict(w), dict(v))
        inner = final3.make(dict(w), dict(v))
        records = self.records

        def pol(r, case):
            records.append({"case": case, "reading": r})
            return inner(r, case)
        pol.needs_case = True
        self.system._modules = (formats, jev, run, pol, lexical, fusion, final3)

    def play(self, episode):
        start = len(self.records)
        res = E.play_episode(episode, self.system)
        # tie each record to its trace event (decide is called once per submit that reaches Jev)
        subs = [ev for ev in res["events"] if ev["kind"] == "submit" and ev.get("request_hash")]
        recs = self.records[start:]
        assert len(subs) == len(recs), (episode["id"], len(subs), len(recs))
        for rec, ev in zip(recs, subs):
            rec.update(episode=episode["id"], group=episode["group"], event=ev["id"], gold=ev["gold"],
                       source=(episode.get("provenance") or {}).get("source"))
        return res


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("variant", choices=["shipped", "told", "shipped-trans", "told-trans"])
    p.add_argument("--all-sources", action="store_true")
    p.add_argument("--cache-only", action="store_true")
    p.add_argument("--max-calls", type=int, default=0)
    a = p.parse_args(argv)
    fmt = "combo-o-told" if a.variant.startswith("told") else "combo-o"
    v = Variant(fmt, trans=a.variant.endswith("trans"), cache_only=a.cache_only, max_calls=a.max_calls)
    eps = load(a.all_sources)
    OUT.mkdir(exist_ok=True)
    suffix = "_all" if a.all_sources else ""
    results = [v.play(e) for e in eps]
    (OUT / f"{a.variant}{suffix}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    with open(OUT / f"{a.variant}{suffix}.rec.pkl", "wb") as f:
        pickle.dump(v.records, f)
    print(json.dumps({"episodes": len(eps), "records": len(v.records), "new_calls": v.system.new_calls,
                      "cache_hits": v.system.cache_hits}))


if __name__ == "__main__":
    main()
