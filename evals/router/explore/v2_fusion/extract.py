"""Replay dev episodes along the shipped final3 path (cache only, no Jev call) and freeze, per submit that reaches the
fusion, everything a fusion variant needs: the case, the reading, the raw Jev answer, the shipped features, the replay
state (for the ask card) and gold.

python3 -m explore.v2_fusion.extract [OUT.pkl]     (default /tmp/v2_fusion_moments.pkl, outside the repo: holds text)
"""
import copy
import json
import pickle
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from v2.run import adapter, episodes as E

DEV = Path(__file__).resolve().parents[2] / "v2" / "data" / "episodes" / "dev" / "provisional.jsonl"
OUT = Path("/tmp/v2_fusion_moments.pkl")


class Recorder(E.RouterSystem):
    def __init__(self, **kw):
        super().__init__(cache_only=True, **kw)
        self.moments = []
        self.episode = None

    def decide(self, state, event):
        before = copy.deepcopy(state)
        result = super().decide(state, event)
        if E.rules.plan(before, event["message"], event.get("context", {})) is not None:
            return result  # a deterministic rule decided before Jev: no fusion to study
        formats, _, legacy_run, policy, lexical, fusion, final3 = self._load()
        case = adapter.to_case(before, event)
        built_state, questions, keymap = formats.build(self.format_name, case, shuffle_seed=self.option_seed)
        answer, _, _ = self._ask(built_state, questions)
        row = {"id": case["id"], "keymap": keymap, "answers": answer["answers"]}
        reading = legacy_run.reading(row)
        fs = lexical.features(reading, case)
        from explore import combo
        rule_kind, rule_dest = combo.make_policy()(reading)
        self.moments.append(dict(
            episode=self.episode["id"], group=self.episode["group"], source=self.episode["provenance"]["source"],
            event=event["id"], case=case, state=before, reading=reading, answer=answer["answers"], keymap=keymap,
            fs=fs, gold=event["gold"], shipped=result, rule=(rule_kind, rule_dest)))
        return result


def main(out=OUT):
    eps = E.load_episodes([DEV])
    rec = Recorder()
    for ep in eps:
        rec.episode = ep
        E.play_episode(ep, rec)
    with open(out, "wb") as f:
        pickle.dump(rec.moments, f)
    import collections
    print(len(rec.moments), collections.Counter(m["source"] for m in rec.moments), "new calls", rec.new_calls)


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else OUT)
