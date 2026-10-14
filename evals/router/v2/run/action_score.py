"""Action-aware scoring of Router v2 traces (gold with `intended_action`, ACTIONS.md).

A submit whose gold has no `intended_action` is scored exactly as `score.event_score` does (legacy behaviour). With
action gold:

- an automatic outcome is the trace's `act` (an action target, ACTIONS.md) when the system wrote one, else the action
  its legacy destination maps to without the board (`session:<id>` → `say:session:<id>`, `new:<f>` → `start:new:<f>`,
  `change_fjord` → `configure`, `question` → `ask_fjord`, `compound` → `compound`);
- it is right when it is one of `acceptable_actions` (an `answer:card:<c>` also when `say:session:<c's session>` is
  acceptable: the live app passes words a form can't take on as text) and asking isn't required;
- `configure`/`compound` (a Router run) on gold that is a Fjord action (ack, stop, archive, reopen, mute, unmute,
  configure) is **reached Router**: not charged, counted apart (`router_reach`), since the run can't be executed
  offline and the redesign acts without it;
- anything else automatic is wrong: 25 (`wrong_cost`), 100 when the gold is consequential or the wrong action is a
  `stop` or `interrupt` (can't be undone). A wrong verb on the right target is wrong (`wrong_verb` counts it);
- an ask is charged as before (1 with the answer on the card, 2 if asking was forbidden, 4 without), the card being
  the trace's typed `act_options` (else its `ranked` mapped as above): a hit when the intended action or an acceptable
  one is among the first four, or `configure`/`compound` for Fjord-action gold (`hit_router` counts those apart).

Run from evals/router: python3 -m v2.run.action_score traces.jsonl
"""
from __future__ import annotations

import argparse
import json
import math
from typing import Any

from . import score

FJORD = {"ack", "stop", "archive", "reopen", "mute", "unmute", "configure"}
ROUTER_RUN = {"configure", "compound"}
IRREVERSIBLE = {"stop", "interrupt"}
_LEGACY = score.event_score  # captured before episode_score swaps the module function


def verb(action: str | None) -> str | None:
    if not action:
        return None
    head = action.split(":", 1)[0]
    return head if head in {"say", "answer", "approve", "ack", "stop", "interrupt", "start", "archive", "reopen", "mute",
                            "unmute", "configure", "ask_fjord", "compound"} else "say"


def target_session(action: str | None) -> str | None:
    """The session an action is about (`card:<sid>#…` → sid), else None."""
    if not action:
        return None
    parts = action.split(":", 2)
    if len(parts) == 2 and parts[0] == "session":
        return parts[1]
    if len(parts) == 3 and parts[1] == "session":
        return parts[2]
    if len(parts) == 3 and parts[1] == "card":
        return parts[2].split("#", 1)[0]
    return None


def legacy_action(target: str | None) -> str | None:
    """A legacy destination as the action it is without the board."""
    if not target:
        return None
    if target.startswith("session:"):
        return "say:" + target
    if target.startswith("new:"):
        return "start:" + target
    if target.startswith("answer:"):
        return "answer:card:" + target[7:]
    return {"change_fjord": "configure", "question": "ask_fjord", "compound": "compound"}.get(target, target)


def _options(trace: dict[str, Any]) -> list[str]:
    if "act_options" in trace:
        return list(trace["act_options"])[:4]
    return [legacy_action(t) for t in score._ranked_targets(trace)][:4]


def _right(action: str, acceptable: set[str]) -> bool:
    if action in acceptable:
        return True
    if action.startswith("answer:card:"):
        return "say:session:" + action[12:].split("#", 1)[0] in acceptable
    return False


def event_score(trace: dict[str, Any], wrong_cost: float = 25) -> dict[str, Any]:
    gold = trace.get("gold")
    if not isinstance(gold, dict) or "intended_action" not in gold:
        out = _LEGACY(trace, wrong_cost)
        return {**out, "router_reach": 0, "wrong_verb": 0, "hit_router": 0, "action_gold": 0, "irreversible_wrong": 0}
    views = gold.get("views")
    if not views:
        return _event_score(trace, gold, wrong_cost)
    scores = [_event_score(trace, view, wrong_cost) for view in views]
    return {key: sum(s[key] for s in scores) / len(scores) for key in scores[0]}


def _event_score(trace: dict[str, Any], gold: dict[str, Any], wrong_cost: float) -> dict[str, Any]:
    decision = trace.get("decision")
    if decision not in score.AUTOMATIC | {"ask"}:
        raise ValueError(f"unknown submit decision: {decision!r}")
    ask_policy = gold.get("ask", "allowed")
    intended = gold.get("intended_action")
    acceptable = set(gold.get("acceptable_actions") or [])
    fjord_gold = verb(intended) in FJORD
    automatic = decision in score.AUTOMATIC
    router_reach = wrong = wrong_verb = hit4 = hit_router = 0
    action = (trace.get("act") or legacy_action(trace.get("target"))) if automatic else None
    if automatic:
        if ask_policy == "required":
            wrong = 1
        elif _right(action, acceptable):
            router_reach = int(verb(action) in ROUTER_RUN)
        elif verb(action) in ROUTER_RUN and fjord_gold:
            router_reach = 1
        else:
            wrong = 1
        if wrong:
            costly = gold.get("consequential", False) or verb(action) in IRREVERSIBLE
            loss = 100 if costly else wrong_cost
            same = target_session(action) is not None and target_session(action) == target_session(intended)
            wrong_verb = int(same and verb(action) != verb(intended))
        else:
            loss = 0
    else:
        options = _options(trace)
        hit4 = int(intended in options or any(_right(o, acceptable) for o in options if o))
        if not hit4 and fjord_gold and any(verb(o) in ROUTER_RUN for o in options):
            hit4 = hit_router = 1
        loss = 4 if not hit4 else 2 if ask_policy == "forbidden" else 1
    recovery = trace.get("recovery_clicks", 0)
    if not isinstance(recovery, (int, float)) or not math.isfinite(recovery) or recovery < 0:
        raise ValueError("recovery_clicks must be a finite nonnegative number")
    return {"loss": loss + recovery, "wrong": wrong, "automatic": int(automatic), "ask": int(not automatic),
            "right": int(automatic and not wrong), "hit_at_1": 0, "hit_at_4": hit4,
            "needless_ask": int(not automatic and ask_policy == "forbidden"),
            "consequential_wrong": int(bool(wrong) and loss >= 100),
            "router_reach": router_reach, "wrong_verb": wrong_verb, "hit_router": hit_router, "action_gold": 1,
            "irreversible_wrong": int(bool(wrong) and verb(action) in IRREVERSIBLE)}


def episode_score(result: dict[str, Any], wrong_cost: float = 25) -> dict[str, Any]:
    """score.episode_score with the action-aware submit score."""
    original = score.event_score
    try:
        score.event_score = lambda trace, cost=25: event_score(trace, cost)
        return score.episode_score(result, wrong_cost)
    finally:
        score.event_score = original


def main() -> None:
    parser = argparse.ArgumentParser(description="Action-aware Router v2 scoring (falls back to legacy gold).")
    parser.add_argument("results")
    a = parser.parse_args()
    results = score.load_results(a.results)
    rows = [event_score(ev) for r in results for ev in r["events"] if ev.get("kind") == "submit"]
    keys = rows[0].keys() if rows else []
    print(json.dumps({k: sum(r[k] for r in rows) for k in keys} | {"submits": len(rows)}, indent=2))


if __name__ == "__main__":
    main()
