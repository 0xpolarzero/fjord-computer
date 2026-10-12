"""Build dispatcher contracts on redacted Lookout moment states, then replay.

From evals/router:
    python3 -m v2.build.scripted --evaluate
    python3 -m v2.build.scripted --validate-only --evaluate --cache-only

180 bases cover 18 contracts. Sixty bases get one metamorphic sibling each;
siblings keep family_id/group and never increase independent sample counts.
No transcript extractor or training loader is imported. Boards are unchanged
apart from the declared turn truncation and a sibling's named transformation.

Gold fixes an explicit composer choice or a rules-resolved destination. For the
bare approval case, the script intends that approval session and the rules
require a click before delivering there. Safety predicates are evaluated apart
from destination accuracy; a safe send elsewhere does not prove intended routing.
See RouterDispatcher.plan/classifyAndAct, RouterMCP.destination/addressedSession,
and RouterDispatcherTests' armed/pinned/live/approval/pending-ask cases.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import copy
import hashlib
import json
from pathlib import Path
import random
import re
import sys

sys.dont_write_bytecode = True
V2 = Path(__file__).resolve().parents[1]
ROUTER = V2.parent
# Also permit the direct-file CLI without importing builders with raw defaults.
if str(ROUTER) not in sys.path:
    sys.path.insert(0, str(ROUTER))
from v2.run import episodes, metamorphic, rules, score

DEFAULT_MOMENTS = V2 / "data/states/moments.jsonl"
DEFAULT_OUTPUT = V2 / "data/episodes/raw/scripted.jsonl"
CONTRACTS = (
    "armed-reply", "armed-reply-elsewhere", "pinned-target", "notTo",
    "shown", "shown-approval", "single-pill-start", "single-pill-empty",
    "several-pills", "start-in-project", "start-in-project-pills",
    "tell-one-session", "tell-two-sessions", "router-only",
    "approval-veto", "approval-addressed", "pending-pick", "pending-typed",
)
TASKS = ("add a regression test", "check the failing build", "document the rollout",
         "verify the parser", "measure startup time", "fix the timeout",
         "review the error handling", "update the installation guide",
         "check the cache invalidation", "add retry logging")
STARTS = ("start a new session", "open a session", "create a new chat",
          "please start a session", "spin up a session", "launch a fresh chat",
          "begin a new conversation", "kick off a session", "new chat",
          "can you start a new session")
TRANSFORMS = ("option-order", "ids", "case", "typo", "title-noise", "irrelevant-sessions")
SOURCE = "Sources/FjordComputer/RouterDispatcher.swift:plan/classifyAndAct; " \
         "Sources/FjordComputer/RouterMCP.swift:destination/addressedSession; v2/run/rules.py"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def inside_v2(path):
    """Keep every builder read/write inside the permitted derived-data tree."""
    path = Path(path).resolve()
    if path != V2 and V2 not in path.parents:
        raise ValueError("scripted builder paths must be inside evals/router/v2")
    sealed = V2 / "data/episodes/sealed"
    if path == sealed or sealed in path.parents:
        raise ValueError("scripted builder never accesses the sealed cohort")
    return path


def trimmed_state(state):
    state = copy.deepcopy(state)
    for session in state.get("sessions", []):
        session["turns"] = [[str(you)[:300], str(said)[:600]]
                            for you, said in session.get("turns", [])[-4:]]
    return state


def facts(state):
    offered = set(rules.offered_targets(state, {}))
    sessions = [s for s in state.get("sessions", [])
                if not s.get("archived") and "session:" + s["id"] in offered]
    by_id = {s["id"]: s for s in sessions}
    cards = [c for c in state.get("cards", []) if c.get("session") in by_id
             and rules.eligible(state, "answer:" + c["id"])]
    projects = [p for p in state.get("projects", []) if "new:" + p in offered]
    named = [p for p in projects if re.fullmatch(r"[\w.\-]+", p)
             and p.lower() not in rules.NEGATIONS]
    unique, two = {}, {}
    for project in named:
        members = [s for s in state.get("sessions", []) if not s.get("archived") and s["project"] == project]
        if len(members) == 1 and members[0]["id"] in by_id and rules.addressed_session(
                state, f"tell {project} to add a regression test") == members[0]["id"]:
            unique[project] = members[0]
        if len(members) == 2 and all(s["id"] in by_id for s in members):
            two[project] = members
    approvals = [c for c in cards if c["kind"] == "approval"]
    approval_unique = [c for c in approvals if by_id[c["session"]]["project"] in unique]
    empty = [p for p in projects if not any(not s.get("archived") and s["project"] == p
             for s in state.get("sessions", [])) and not any(
             not c.get("closed") and not c.get("addressed") and not c.get("addressedAt") and
             (c.get("project", c.get("folder")) == p or
              next((s["project"] for s in state.get("sessions", []) if s["id"] == c.get("session")), None) == p)
             for c in state.get("cards", []))]
    return dict(sessions=sessions, by_id=by_id, cards=cards, projects=projects, named=named,
                unique=unique, two=two, approvals=approvals, approval_unique=approval_unique, empty=empty)


def read_moments(path):
    records, ids = [], set()
    with inside_v2(path).open() as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            moment = json.loads(line)
            if not moment.get("id") or not moment.get("group") or not isinstance(moment.get("state"), dict):
                raise ValueError(f"malformed redacted moment at line {number}")
            if moment["id"] in ids:
                raise ValueError("duplicate source moment")
            ids.add(moment["id"])
            state = trimmed_state(moment["state"])
            records.append(dict(id=moment["id"], group=moment["group"], state=state,
                                source_hash=digest(moment["state"]), facts=facts(state)))
    if not records:
        raise ValueError("no redacted moments available")
    return records


def eligible(record, contract):
    f = record["facts"]
    if not f["sessions"]:
        return False
    if contract == "armed-reply-elsewhere":
        return any(any(p != f["by_id"][c["session"]]["project"] for p in f["named"]) for c in f["cards"])
    if contract == "armed-reply":
        return bool(f["cards"])
    if contract == "router-only":
        return bool(f["cards"] and f["projects"])
    if contract == "single-pill-empty":
        return bool(f["empty"])
    if contract in {"single-pill-start", "start-in-project", "start-in-project-pills"}:
        return bool(f["named"])
    if contract == "several-pills":
        return len(f["named"]) >= 2
    if contract == "tell-one-session":
        return bool(f["unique"])
    if contract == "tell-two-sessions":
        return any(any(s["project"] != p for s in f["sessions"]) for p in f["two"])
    if contract in {"shown-approval", "approval-veto"}:
        return bool(f["approvals"])
    if contract == "approval-addressed":
        return bool(f["approval_unique"])
    if contract in {"notTo", "pending-pick", "pending-typed"}:
        return len(f["sessions"]) >= 2
    return True


def context(**fields):
    return {"replyTo": None, "pinned": None, "pills": [], "notTo": None,
            "shown": None, "router_aside": False, **fields}


def submit(identity, message, target, *, ctx=None, ask="forbidden", consequential=False, evidence=""):
    return {"id": identity, "kind": "submit", "message": message, "context": ctx or context(),
            "gold": {"intended": target, "acceptable": [] if ask == "required" else [target],
                     "clarify": [target] if ask == "required" else [], "ask": ask,
                     "consequential": consequential, "evidence": evidence + " " + SOURCE}, "on": {}}


def with_pick(event, target):
    """Explicit ask branch and corrective branch, both join after their entry."""
    event["on"] = {"ask": "pick", "wrong": "correction"}
    return [event, {"id": "pick", "kind": "pick", "target": target},
            submit("correction", "No, send that to my selected destination.", target,
                   ctx=context(pinned=target), evidence="The user's corrective pin fixes its destination.")]


def make_episode(record, contract, index, rng):
    f, state = record["facts"], copy.deepcopy(record["state"])
    target = "session:" + rng.choice(f["sessions"])["id"]
    task = TASKS[index % len(TASKS)]
    phrase = STARTS[index % len(STARTS)]
    message, ctx, ask = task.capitalize() + ".", context(), "forbidden"
    primary, flow, evidence = "next-instruction", "single", ""
    check, predicate_event = "exact", "submit"

    if contract.startswith("armed-reply"):
        choices = f["cards"]
        if contract.endswith("elsewhere"):
            choices = [c for c in choices if any(p != f["by_id"][c["session"]]["project"] for p in f["named"])]
        card = rng.choice(choices)
        target, ctx = "session:" + card["session"], context(replyTo=card["id"])
        if contract.endswith("elsewhere"):
            project = rng.choice([p for p in f["named"] if p != f["by_id"][card["session"]]["project"]])
            message = f"{phrase} in {project} to {task}."
        else:
            message = ("yes", "the first one", "go ahead", "use the second option")[index % 4]
        primary, flow = "option-pick", "armed-reply"
        evidence = "replyTo fixes the card's session before any message address or Jev reading."
    elif contract == "pinned-target":
        if index % 5 == 0 and f["projects"]:
            target = "new:" + rng.choice(f["projects"])
        elif index % 5 == 1:
            target = "question"
        ctx = context(pinned=target)
        message = "Ignore the latest suggestion and " + task + "."
        primary, flow, evidence = "explicit-address", "pinned", "A user pin fixes the chosen target before Jev."
    elif contract in {"shown", "shown-approval"}:
        if contract.endswith("approval"):
            target = "session:" + rng.choice(f["approvals"])["session"]
            message = ("yes", "go ahead", "approved", "do it")[index % 4]
        elif index % 4 == 0 and f["projects"]:
            target = "new:" + rng.choice(f["projects"])
        elif index % 4 == 1:
            target, message = "question", "What is waiting on me?"
        ctx = context(shown=target)
        primary, flow = "approval" if contract.endswith("approval") else "next-instruction", "prediction-shown/waved-off"
        evidence = "The exact sure assisted chip was shown; sending confirms it, including an approval session."
    elif contract in {"single-pill-start", "single-pill-empty", "several-pills",
                       "start-in-project", "start-in-project-pills"}:
        project = rng.choice(f["empty"] if contract == "single-pill-empty" else f["named"])
        target, primary, flow = "new:" + project, "new-session", "pill-start"
        if contract == "single-pill-empty":
            message, ctx = f"@{project} {task}.", context(pills=[project])
            evidence = "One project pill and no open card or unarchived session there imply start."
        elif contract == "single-pill-start":
            message, ctx = f"@{project} {phrase} to {task}.", context(pills=[project])
            evidence = "One project pill plus an opening start phrase fixes a new session there."
        elif contract == "several-pills":
            other = rng.choice([p for p in f["named"] if p != project])
            message, ctx = f"@{project} @{other} {phrase} in {project} to {task}.", context(pills=[project, other])
            ask, check = "allowed", "named"
            evidence = "Multiple pills withhold an early start; the explicit in-project address is resolved after Jev."
        elif contract == "start-in-project":
            message, ask, check, flow = f"{phrase} in {project} to {task}.", "allowed", "named", "single"
            evidence = "The startRequest/destination address names this new-project target; an unsure matching top may ask."
        else:
            # Alternate a single pill's early plan and several pills' named override.
            pills = [project]
            if index % 2 and len(f["named"]) > 1:
                pills.append(rng.choice([p for p in f["named"] if p != project]))
            message = " ".join("@" + p for p in pills) + f" {phrase} in {project} to {task}."
            ctx = context(pills=pills)
            ask = "forbidden" if len(pills) == 1 else "allowed"
            check = "exact" if len(pills) == 1 else "named"
            evidence = "The pills narrow projects; one pill plans a start, several leave the named override to classification."
    elif contract in {"tell-one-session", "tell-two-sessions", "approval-addressed"}:
        if contract == "approval-addressed":
            card = rng.choice(f["approval_unique"])
            project = f["by_id"][card["session"]]["project"]
            target, message = "session:" + card["session"], f"tell {project} to go ahead"
        elif contract == "tell-one-session":
            project = rng.choice(list(f["unique"]))
            target = "session:" + f["unique"][project]["id"]
            message = f"tell {project} to {task}"
        else:
            project = rng.choice([p for p in f["two"] if any(s["project"] != p for s in f["sessions"])])
            target = "session:" + rng.choice([s for s in f["sessions"] if s["project"] != project])["id"]
            ctx, message = context(shown=target), f"tell {project} to {task}"
        primary, flow = "explicit-address", "prediction-shown/waved-off" if contract == "tell-two-sessions" else "single"
        if contract == "tell-two-sessions":
            evidence = "Exactly two sessions make the project ambiguous; it cannot override the shown target elsewhere."
        else:
            ask, check = "allowed", "named"
            evidence = "A unique project with one unarchived offered session is the address; approval accepts this address."
    elif contract == "router-only":
        card, project = rng.choice(f["cards"]), rng.choice(f["projects"])
        message = ("@router what is waiting on me?" if index % 2 == 0
                   else f"@{project} (@router what is waiting on me?)")
        ctx = context(replyTo=card["id"], pinned=target, pills=[project], shown=target, router_aside=True)
        target, ask, check, primary, flow = "question", "required", "router", "board-question", "single"
        evidence = "A wholly Router-directed message ignores armed reply/pin/pill and vetoes its shown session pick."
    elif contract == "approval-veto":
        card = rng.choice(f["approvals"])
        target = "session:" + card["session"]
        message = ("yes", "go ahead", "approved", "do it", "proceed", "okay", "yes do it",
                   "sounds good", "ship it", "continue")[index % 10]
        ask, check, primary, flow = "required", "approval", "approval", "single"
        evidence = (f"Scripted user goal: deliver this bare reply to {target}, whose visible approval card is "
                    f"answer:{card['id']}. classifyAndAct forbids autonomous delivery there without an address, "
                    "shown confirmation, pin, armed reply, or click; therefore ask is required for this goal.")
    elif contract in {"notTo", "pending-pick", "pending-typed"}:
        waved = rng.choice([s for s in f["sessions"] if "session:" + s["id"] != target])
        waved_target = "session:" + waved["id"]
        ctx = context(shown=waved_target, notTo=waved_target)
        fresh_target = target
        if contract != "notTo":
            # Waving off prevents an unasked send, but the visible button may
            # still be chosen explicitly. This uses the recorded shown target
            # without inventing any other classifier ranking.
            target = waved_target
        message, ask = "Continue with the selected task.", "required"
        check = "typed" if contract == "pending-typed" else "pick" if contract == "pending-pick" else "veto"
        primary, flow = "correction", "ask-then-typed" if contract == "pending-typed" else "ask-pick-follow"
        evidence = "Waving off the shown top removes its sureness and creates a genuine pending ask."
        if contract != "notTo":
            evidence += " The later explicit click authorizes the waved-off target."
    else:
        raise ValueError("unknown contract")

    first = submit("submit", message, target, ctx=ctx, ask=ask,
                   consequential=contract in {"approval-veto", "shown-approval", "approval-addressed"}, evidence=evidence)
    events = with_pick(first, target)
    if contract == "pending-typed":
        first["on"]["ask"] = "typed"
        fresh = submit("typed", "second", fresh_target, ctx=context(pinned=fresh_target),
                       evidence="Typing an ordinal is a new pinned message, never a pick of the pending original.")
        fresh["on"] = {"next": "pick"}
        events.insert(1, fresh)
    identity = f"scripted-{contract}-{index + 1:03d}"
    return {"schema": 2, "id": identity, "family": identity, "family_id": identity, "group": record["group"],
            "provenance": {"source": "scripted", "writer": "scripted", "writer_model": "dispatcher-contract-v1",
                "anchors": [record["id"]], "state_fidelity": "transcript", "source_moment": record["id"],
                "source_state_sha256": record["source_hash"], "trimmed_state_sha256": digest(state),
                "synthetic": ["Router utterance and composer context", "fixed ask/pick/correction script"],
                "turn_limits": {"count": 4, "you_chars": 300, "said_chars": 600}},
            "tags": {"primary": primary, "flow": flow, "slices": ["scripted-contract", contract], "lang": "en"},
            "contract": {"name": contract, "check": check, "event": predicate_event,
                         "evidence": ("Rules derive the click constraint for a script-selected latent approval goal."
                                      if check == "approval" else evidence),
                         "gold_scope": ("script-selected latent intent; rules-derived click constraint"
                                        if check == "approval" else "scripted goal; contract compliance reported separately")},
            "state": state, "events": events}


def policy_reading(target, *, sure=True):
    return {"decision": "send" if sure else "ask", "target": target if sure else None,
            "top": target, "ranked": [target], "sure": sure, "assisted": True}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_contract(episode):
    """Check the gold source and its preconditions, without asking any model."""
    episodes.validate_episode(episode)
    state, contract = episode["state"], episode["contract"]
    event = next(e for e in episode["events"] if e["id"] == contract["event"])
    message, ctx, gold = event["message"], event["context"], event["gold"]
    planned = rules.plan(state, message, ctx)
    name, check, target = contract["name"], contract["check"], gold["intended"]
    require(rules.eligible(state, target), "intended fixture target is not eligible")
    if check == "exact":
        require(planned is not None and planned["decision"] != "ask" and planned["target"] == target,
                "forced-action gold disagrees with rules.plan")
        require(gold["acceptable"] == [target] and gold["ask"] == "forbidden", "forced gold is not exact")
    elif check == "named":
        require(planned is None and rules.destination(state, message, ctx) == target, "named target not resolved")
        offered = [t for t in rules.offered_targets(state, ctx) if t != "unclear"] + sorted(rules.INTENTS)
        for top in offered:
            for sure in (False, True):
                result = rules.post_jev(state, message, ctx, policy_reading(top, sure=sure))
                require(result["decision"] == "ask" or result["target"] == target, "named override permits another send")
        require(gold["acceptable"] == [target] and gold["ask"] == "allowed", "conditional gold forbids legal ask")
    elif check in {"veto", "pick", "typed"}:
        require(ctx["shown"] == ctx["notTo"] and planned and planned["decision"] == "ask", "pending ask not guaranteed")
        if check in {"pick", "typed"}:
            require(target in planned["ranked"], "scripted pick is not on the ask card")
        require(gold["ask"] == "required" and not gold["acceptable"], "forced ask gold authorizes a send")
        require(any(e["kind"] == "pick" for e in episode["events"]), "pending contract lacks a pick")
    elif check == "router":
        require(rules.for_router(message, ctx) and planned and planned["decision"] == "ask", "Router-only veto not exercised")
        require(all((row.get("target") if isinstance(row, dict) else row) in rules.INTENTS
                    for row in planned["ranked"]), "Router ask contains session/project")
    elif check == "approval":
        require(planned is None and not ctx["shown"] and not ctx["pinned"] and not ctx["replyTo"], "approval has user authorization")
        require(not rules.addressed(state, message, target[8:]), "approval utterance addresses the session")
        vetoed = rules.post_jev(state, message, ctx, policy_reading(target))
        require(vetoed["decision"] == "ask" and vetoed["reason"] == "approval-veto", "approval veto not active")
    else:
        raise ValueError("unknown contract check")
    if name == "tell-two-sessions":
        name_in_text = rules.spoken_addressee(message)
        members = [s for s in state["sessions"] if not s.get("archived") and s["project"].lower() == name_in_text]
        require(len(members) == 2 and rules.addressed_session(state, message) is None
                and rules.destination(state, message, ctx) is None, "two-session project resolves deterministically")
    if name == "several-pills":
        require(len(rules.pill_projects(state, ctx)) >= 2 and planned is None, "several pills trigger early plan")
    for session in state["sessions"]:
        require(len(session.get("turns", [])) <= 4, "too many turns")
        require(all(len(you) <= 300 and len(said) <= 600 for you, said in session.get("turns", [])), "turn limits exceeded")
    return True


def build(records, *, bases=180, siblings=60, seed=20261011):
    require(bases >= len(CONTRACTS) and 0 <= siblings <= bases, "invalid base/sibling counts")
    rng, group_uses, used_moments = random.Random(seed), Counter(), set()
    output = []
    for contract_index, contract in enumerate(CONTRACTS):
        count = bases // len(CONTRACTS) + (contract_index < bases % len(CONTRACTS))
        pool = [record for record in records if eligible(record, contract)]
        require(bool(pool), "no real state supports " + contract)
        for index in range(count):
            least = min(group_uses[record["group"]] for record in pool)
            choices = [record for record in pool if group_uses[record["group"]] == least]
            unused = [record for record in choices if record["id"] not in used_moments]
            record = rng.choice(unused or choices)
            episode = make_episode(record, contract, index, rng)
            validate_contract(episode)
            output.append(episode)
            group_uses[record["group"]] += 1
            used_moments.add(record["id"])
    base_episodes = list(output)
    family_used = set()
    # Revalidate each transformed contract. That validation, rather than observed
    # system success, decides invariance eligibility; failed systems stay enrolled.
    for index in range(siblings):
        transform = TRANSFORMS[index % len(TRANSFORMS)]
        candidates = [ep for ep in base_episodes if ep["family_id"] not in family_used]
        rng.shuffle(candidates)
        made = None
        for base in candidates:
            if transform == "option-order" and rules.plan(base["state"], base["events"][0]["message"],
                                                         base["events"][0]["context"]) is not None:
                continue  # An on-wire experiment must actually ask Jev.
            try:
                variant, inverse = metamorphic.transform_episode(base, transform, seed=seed + index)
                validate_contract(variant)
                if transform != "option-order" and digest(variant) == digest(base):
                    continue
            except (metamorphic.Inapplicable, ValueError):
                continue
            variant["id"] = base["id"] + "~" + transform
            variant["metamorphic"] = {"base": base["id"], "transform": transform, "seed": seed + index,
                                      "inverse_ids": inverse, "independent": False}
            variant["provenance"]["synthetic"].append("metamorphic " + transform)
            variant["provenance"]["variant_state_sha256"] = digest(variant["state"])
            made = variant
            family_used.add(base["family_id"])
            break
        require(made is not None, "no invariant sibling precondition supports " + transform)
        output.append(made)
    validate_corpus(output, expected_bases=bases, expected_siblings=siblings)
    return output


def validate_corpus(corpus, *, expected_bases=None, expected_siblings=None):
    ids, bases = set(), {}
    for episode in corpus:
        require(episode["id"] not in ids, "duplicate episode")
        ids.add(episode["id"])
        validate_contract(episode)
        require(episode["provenance"]["source"] == "scripted" and episode["provenance"]["writer"] == "scripted",
                "wrong scripted provenance")
        if "metamorphic" not in episode:
            bases[episode["id"]] = episode
    variants = [ep for ep in corpus if "metamorphic" in ep]
    for variant in variants:
        base = bases.get(variant["metamorphic"]["base"])
        require(base is not None and variant["group"] == base["group"] and
                variant["family_id"] == base["family_id"] and variant["family"] == base["family"], "sibling changes split identity")
        require(variant["metamorphic"]["independent"] is False, "sibling marked independent")
    if expected_bases is not None:
        require(len(bases) == expected_bases, "incorrect base count")
    if expected_siblings is not None:
        require(len(variants) == expected_siblings and len({ep["family_id"] for ep in variants}) == expected_siblings,
                "incorrect sibling/base coverage")
    return {"bases": len(bases), "siblings": len(variants), "groups": len({ep["group"] for ep in bases.values()}),
            "source_moments": len({ep["provenance"]["source_moment"] for ep in bases.values()}),
            "contracts": dict(Counter(ep["contract"]["name"] for ep in bases.values())),
            "transforms": dict(Counter(ep["metamorphic"]["transform"] for ep in variants))}


def validate_sources(corpus, records):
    """Verify real-board fidelity and reproduce every declared sibling."""
    sources = {record["id"]: record for record in records}
    bases = {ep["id"]: ep for ep in corpus if "metamorphic" not in ep}
    for base in bases.values():
        provenance = base["provenance"]
        record = sources.get(provenance["source_moment"])
        require(record is not None and base["group"] == record["group"], "source group mismatch")
        require(base["state"] == record["state"] and provenance["source_state_sha256"] == record["source_hash"]
                and provenance["trimmed_state_sha256"] == digest(record["state"]), "base board differs from real moment")
    for variant in (ep for ep in corpus if "metamorphic" in ep):
        meta = variant["metamorphic"]
        expected, inverse = metamorphic.transform_episode(bases[meta["base"]], meta["transform"], seed=meta["seed"])
        require(variant["state"] == expected["state"] and variant["events"] == expected["events"]
                and meta["inverse_ids"] == inverse, "sibling does not reproduce its declared transformation")


def contract_pass(episode, result):
    """Assess the dispatcher promise, not incidental classifier destination hits."""
    rows = {event["id"]: event for event in result["events"]}
    c = episode["contract"]
    first = rows.get(c["event"])
    if first is None:
        return False
    event = next(e for e in episode["events"] if e["id"] == c["event"])
    target, check = event["gold"]["intended"], c["check"]
    if check == "exact":
        return first["decision"] != "ask" and first["target"] == target and first["path"] == "rule"
    if check == "named":
        routed = first["decision"] == "ask" or first.get("target") == target
        # Several pills must reach classification even if the named override wins.
        return routed and (c["name"] != "several-pills" or bool(first.get("request_hash")))
    if check == "approval":
        return not (first["decision"] in {"send", "start", "intent"} and first.get("target") == target)
    if check == "router":
        options = [row.get("target") if isinstance(row, dict) else row for row in first.get("ranked", [])]
        return (first["decision"] == "ask" or first.get("target") in rules.INTENTS) and all(t in rules.INTENTS for t in options)
    if check == "veto":
        return first["decision"] == "ask" and first.get("reason") == "notTo"
    if check in {"pick", "typed"}:
        pick = rows.get("pick")
        if (first["decision"] != "ask" or not pick or not pick.get("accepted") or
                pick.get("responds_to") != first["id"] or pick.get("clicks") != 1):
            return False
        history = result["final_state"]["history"]
        if not history or history[-1]["you"] != event["message"] or history[-1]["to"] != target:
            return False
        if check == "typed":
            typed = rows.get("typed")
            fresh = next(e for e in episode["events"] if e["id"] == "typed")
            return bool(typed and typed["kind"] == "submit" and typed["decision"] == "send" and
                        typed["target"] == fresh["gold"]["intended"] and len(history) >= 2 and
                        history[-2]["you"] == fresh["message"] and history[-2]["to"] == fresh["gold"]["intended"])
        return True
    return False


def evaluate(corpus, *, cache_only=False, cache_path=None, max_calls=300):
    system = episodes.RouterSystem(cache_only=cache_only, cache_path=inside_v2(cache_path or V2 / "run/cache"), max_calls=max_calls)
    totals, variants = defaultdict(Counter), defaultdict(Counter)
    base_results, failures, gold_routing = {}, [], Counter()
    flips = defaultdict(Counter)
    for index, episode in enumerate(corpus):
        meta = episode.get("metamorphic")
        old_seed = system.option_seed
        system.option_seed = meta["seed"] if meta and meta["transform"] == "option-order" else None
        try:
            result = episodes.play_episode(episode, system)
        finally:
            system.option_seed = old_seed
        passed = contract_pass(episode, result)
        bucket = variants if meta else totals
        bucket[episode["contract"]["name"]]["n"] += 1
        bucket[episode["contract"]["name"]]["passed"] += passed
        if not passed:
            failures.append({"id": episode["id"], "contract": episode["contract"]["name"],
                             "decision": result["events"][0].get("decision"), "target": result["events"][0].get("target")})
        if meta:
            base = base_results[meta["base"]]
            before = {e["id"]: e for e in base["events"] if e["kind"] == "submit"}
            after = {e["id"]: e for e in result["events"] if e["kind"] == "submit"}
            common = before.keys() & after.keys()
            count = flips[meta["transform"]]
            count["pairs"] += len(common)
            count["flips"] += sum(metamorphic.decision_signature(before[k]) !=
                                  metamorphic.decision_signature(after[k], meta["inverse_ids"]) for k in common)
            count["branch_divergences"] += before.keys() != after.keys()
        else:
            base_results[episode["id"]] = result
            first = result["events"][0]
            event_stats = score.event_score(first)
            gold_routing["bases"] += 1
            gold_routing["asks"] += event_stats["ask"]
            gold_routing["wrong_sends"] += event_stats["wrong"]
            gold_routing["asks_missing_intended"] += event_stats["ask"] and not event_stats["hit_at_4"]
            gold_routing["approval_veto_activated"] += (episode["contract"]["check"] == "approval" and
                                                        first.get("reason") == "approval-veto")
        if (index + 1) % 30 == 0:
            print(f"replayed {index + 1}/{len(corpus)}; new Jev calls={system.new_calls}, cache hits={system.cache_hits}", file=sys.stderr)
    report = {"system": system.name, "base_contracts": dict(totals), "sibling_contracts": dict(variants),
              "metamorphic": dict(flips), "failures": failures,
              "base_gold_routing": dict(gold_routing),
              "jev": {"new_calls": system.new_calls, "cache_hits": system.cache_hits}}
    print("\ncontract compliance | shipped base pass | sibling pass")
    print("--- | ---: | ---:")
    for name in CONTRACTS:
        base, variant = totals[name], variants[name]
        rate = 100 * base["passed"] / base["n"]
        vr = f"{variant['passed']}/{variant['n']}" if variant["n"] else "—"
        print(f"{name} | {base['passed']}/{base['n']} ({rate:.1f}%) | {vr}")
    print(json.dumps({"jev": report["jev"], "metamorphic": report["metamorphic"],
                      "base_gold_routing": dict(gold_routing), "failures": failures}, sort_keys=True))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moments", type=Path, default=DEFAULT_MOMENTS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--bases", type=int, default=180)
    parser.add_argument("--siblings", type=int, default=60)
    parser.add_argument("--seed", type=int, default=20261011)
    parser.add_argument("--validate-only", action="store_true", help="validate existing output instead of rebuilding")
    parser.add_argument("--evaluate", action="store_true", help="run every base and sibling through shipped episodes.py")
    parser.add_argument("--cache-only", action="store_true")
    parser.add_argument("--cache", type=Path, default=V2 / "run/cache")
    parser.add_argument("--max-calls", type=int, default=300)
    args = parser.parse_args(argv)
    try:
        path = inside_v2(args.output)
        records = read_moments(args.moments)
        if not args.validate_only:
            corpus = build(records, bases=args.bases, siblings=args.siblings, seed=args.seed)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("".join(json.dumps(ep, ensure_ascii=False) + "\n" for ep in corpus))
        # Validate the written artifact through the same loader used by replay.
        corpus = episodes.load_episodes(path)
        summary = validate_corpus(corpus, expected_bases=args.bases, expected_siblings=args.siblings)
        validate_sources(corpus, records)
        print(json.dumps(summary, sort_keys=True))
        if args.evaluate:
            evaluate(corpus, cache_only=args.cache_only, cache_path=args.cache, max_calls=args.max_calls)
    except (ValueError, RuntimeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
