"""Dev real moments relabelled with action gold, mechanically (v2/ACTIONS.md): a no-harm set, where the Router's new
actions must not turn your ordinary messages into acks, stops or settings.

    python3 v2/build/actions_relabel.py [--moments v2/data/states/moments.jsonl]  →  v2/data/actions/dev/relabel_real.jsonl

Per submit, on the board as it stood then (the episode's state with its board events applied), each legacy target maps:
- `session:X`: typed within a minute after interrupting X (the moment's `after_interrupt`) → `interrupt:session:X` only;
  your answer on X's form (`form_answer`) → `answer:card:<the form>` only; X has a card that needs you → `answer:card`
  (and `say:session:X`, same words delivered), the newest such card; else `say:session:X`.
- `new:<p>` → `start:new:<p>`; `change_fjord` → `configure`; `question` → `ask_fjord`; `compound` stays.
The legacy fields (and their labelled ask policy) are unchanged; soft-gold `views` get the same action fields. Only dev:
calib and sealed are never opened."""
import argparse
import collections
import copy
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import actions_common as A  # noqa: E402
from real_episodes import apply  # noqa: E402

DEV = A.V2 / "data" / "episodes" / "dev" / "episodes.jsonl"


def actions_for(target, state, flags):
    """The action targets one legacy target stands for on this board."""
    if target.startswith("new:"):
        return ["start:new:" + target[4:]]
    if target == "change_fjord":
        return ["configure"]
    if target == "question":
        return ["ask_fjord"]
    if target == "compound":
        return ["compound"]
    if not target.startswith("session:"):
        raise ValueError(target)
    sid = target[8:]
    if flags.get("after_interrupt"):
        return [f"interrupt:session:{sid}"]
    cards = sorted((c for c in state["cards"] if c["session"] == sid and c["kind"] in A.NEEDS_YOU),
                   key=lambda c: c.get("created_min_ago", 0))
    if flags.get("form_answer"):
        forms = [c for c in cards if c["kind"] in A.FORMS]
        if forms:
            return [f"answer:card:{forms[0]['id']}"]
    if cards:
        return [f"answer:card:{cards[0]['id']}", f"say:session:{sid}"]
    return [f"say:session:{sid}"]


def relabel(gold, state, went_to, flags):
    def mapped(target):
        return actions_for(target, state, flags if target == went_to else {})

    def fields(view):
        intended = mapped(view["intended"])[0] if view.get("intended") else None
        acceptable = [a for t in view.get("acceptable", []) for a in mapped(t)]
        clarify = [a for t in view.get("clarify", []) for a in mapped(t)]
        return {"intended_action": intended, "acceptable_actions": list(dict.fromkeys(acceptable)),
                "clarify_actions": list(dict.fromkeys(clarify))}

    out = {**gold, **fields(gold), "precondition": "met", "label_method": "mechanical"}
    if gold.get("views"):
        out["views"] = [{**v, **fields(v)} for v in gold["views"]]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--moments", default=str(A.V2 / "data" / "states" / "moments.jsonl"))
    args = ap.parse_args()
    eps = [json.loads(line) for line in open(DEV)]
    real = [e for e in eps if e["provenance"]["source"] == "real-moment"]
    wanted = {ev["tags"]["moment"] for e in real for ev in e["events"] if ev["kind"] == "submit"}
    flags = {}
    with open(args.moments) as f:
        for line in f:
            m = json.loads(line)
            if m["id"] in wanted:
                flags[m["id"]] = m["flags"]
    missing = len(wanted - set(flags))
    stats = collections.Counter()
    out = []
    for e in real:
        e = copy.deepcopy(e)
        state = copy.deepcopy(e["state"])
        for ev in e["events"]:
            if ev["kind"] == "board":
                apply(state, ev["delta"])
                continue
            if ev["kind"] != "submit":
                continue
            fl = flags.get(ev["tags"]["moment"], {})
            ev["gold"] = relabel(ev["gold"], state, ev["gold"]["intended"], fl)
            stats[ev["gold"]["intended_action"].split(":")[0]] += 1
            stats["submits"] += 1
            if len(ev["gold"]["acceptable_actions"]) > len(set(ev["gold"]["acceptable"])):
                stats["more than one action acceptable"] += 1
        e["provenance"] = {**e["provenance"], "set": "actions-relabel"}
        out.append(e)
    A.write(A.OUT / "dev" / "relabel_real.jsonl", out)
    print(json.dumps({"episodes": len(out), "groups": len({e["group"] for e in out}), "moments without flags": missing,
                      **stats}, indent=1))


if __name__ == "__main__":
    main()
