"""Replay dev real-moment episodes along the shipped final3 path with a turn-boundary variant (cache only unless
--calls N) and freeze every fusion moment (as explore.v2_fusion.extract does) plus the play results for score.evaluate.

python3 -m explore.v2_turns.extract MODE [--calls N]   ->  /tmp/v2_turns/MODE.pkl, /tmp/v2_turns/MODE.results.jsonl
(outside the repo: both hold message text)
"""
import argparse
import collections
import copy
import json
import pickle
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from explore.v2_turns import patch

OUT = Path("/tmp/v2_turns")
DEV = Path(__file__).resolve().parents[2] / "v2" / "data" / "episodes" / "dev" / "provisional.jsonl"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=patch.MODES)
    ap.add_argument("--calls", type=int, default=0, help="new Jev calls allowed on cache misses (0: cache only)")
    ap.add_argument("--all", action="store_true", help="every dev episode, not only real moments")
    a = ap.parse_args()
    patch.install(a.mode)
    from v2.run import adapter, episodes as E

    class Recorder(E.RouterSystem):
        def __init__(self, **kw):
            super().__init__(cache_only=a.calls == 0, max_calls=a.calls, **kw)
            self.moments, self.episode, self.misses = [], None, 0

        def _ask(self, state, questions):
            before = self.new_calls
            try:
                return super()._ask(state, questions)
            except RuntimeError:
                self.misses += 1
                raise
            finally:
                if self.new_calls > before:
                    self.misses += 1

        def decide(self, state, event):
            before = copy.deepcopy(state)
            result = super().decide(state, event)
            if E.rules.plan(before, event["message"], event.get("context", {})) is not None:
                return result
            formats, _, legacy_run, policy, lexical, fusion, final3 = self._load()
            case = adapter.to_case(before, event)
            built_state, questions, keymap = formats.build(self.format_name, case, shuffle_seed=self.option_seed)
            answer, _, _ = E.RouterSystem._ask(self, built_state, questions)
            row = {"id": case["id"], "keymap": keymap, "answers": answer["answers"]}
            reading = legacy_run.reading(row)
            fs = lexical.features(reading, case)
            from explore import combo
            self.moments.append(dict(
                episode=self.episode["id"], group=self.episode["group"], source=self.episode["provenance"]["source"],
                event=event["id"], case=case, state=before, reading=reading, answer=answer["answers"], keymap=keymap,
                fs=fs, gold=event["gold"], shipped=result, rule=combo.make_policy()(reading)))
            return result

    eps = E.load_episodes([DEV])
    if not a.all:
        eps = [e for e in eps if e["provenance"]["source"] == "real-moment"]
    rec = Recorder()
    results, failed = [], []
    for ep in eps:
        rec.episode = ep
        n = len(rec.moments)
        try:
            results.append(E.play_episode(ep, rec))
        except RuntimeError as err:
            del rec.moments[n:]
            failed.append((ep["id"], str(err)))
    OUT.mkdir(exist_ok=True)
    with open(OUT / f"{a.mode}.pkl", "wb") as f:
        pickle.dump(rec.moments, f)
    (OUT / f"{a.mode}.results.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))
    print(json.dumps({"mode": a.mode, "episodes": len(eps), "played": len(results), "failed": len(failed),
                      "moments": len(rec.moments), "sources": collections.Counter(m["source"] for m in rec.moments),
                      "new_calls": rec.new_calls, "cache_hits": rec.cache_hits, "misses": rec.misses}))
    for eid, err in failed[:20]:
        print("failed", eid, err)


if __name__ == "__main__":
    main()
