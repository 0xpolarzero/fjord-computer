"""Conditional invariance checks; variants remain members of their source group.

Run from ``evals/router``: ``python3 -m v2.run.metamorphic fixtures.jsonl``.
Option permutations change RouterSystem.option_seed, hence the insertion order in
the *request* built by formats.build. Reordering only a returned ranking is not a
valid option-order experiment. Paraphrases are an explicit caller-supplied hook;
this module does not pretend an automatic rewrite preserves the hidden goal.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import random
import re
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any

TRANSFORMATIONS = ("option-order", "paraphrase", "case", "typo", "ids",
                   "irrelevant-sessions", "title-noise")
PROTECTED_WORDS = frozenset("router start session launch begin create new tell ask please approve approval yes not stop delete push".split())


class Inapplicable(ValueError):
    """The transformation's stated precondition does not hold."""


def _sessions(episode: dict) -> list[dict]:
    rows = list(episode.get("state", {}).get("sessions", []))
    for event in episode.get("events", []):
        delta = event.get("delta", {})
        rows.extend(delta.get("sessions+", []))
        rows.extend(delta.get("sessions~", []))
    return rows


def _messages(episode: dict) -> list[str]:
    return [event.get("message", "") for event in episode.get("events", [])
            if event.get("kind") == "submit"]


def _id_map(episode: dict, seed: int) -> dict[str, str]:
    """Rename opaque session/card identifiers, including board-delta additions."""
    session_ids = {str(row["id"]) for row in _sessions(episode) if row.get("id")}
    cards = list(episode.get("state", {}).get("cards", []))
    for event in episode.get("events", []):
        cards.extend(event.get("delta", {}).get("cards+", []))
        cards.extend(event.get("delta", {}).get("cards~", []))
    card_ids = {str(row["id"]) for row in cards if row.get("id")}
    session_ids.update(str(row.get("session", row.get("sessionID"))) for row in cards
                       if row.get("session", row.get("sessionID")))
    for event in episode.get("events", []):
        delta = event.get("delta", {})
        session_ids.update(str(identifier) for identifier in delta.get("sessions-", []))
        card_ids.update(str(identifier) for identifier in delta.get("cards-", []))
    salt = hashlib.sha256(f"{episode.get('id', '')}:{seed}".encode()).hexdigest()[:12]
    occupied = session_ids | card_ids
    mapping = {}
    for prefix, identifiers in (("session", session_ids), ("card", card_ids)):
        for index, identifier in enumerate(sorted(identifiers)):
            renamed = f"meta_{prefix}_{salt}_{index}"
            while renamed in occupied:
                renamed += "_"
            mapping[identifier] = renamed
            occupied.add(renamed)
    return mapping


def _rewrite_reference(value: Any, mapping: dict[str, str]) -> Any:
    """Rewrite an ID-valued field, preserving projects in ``new:<project>``."""
    if not isinstance(value, str):
        return value
    for prefix in ("session:", "answer:"):
        if value.startswith(prefix):
            identifier = value[len(prefix):]
            return prefix + mapping.get(identifier, identifier)
    if value.startswith("new:"):
        return value
    return mapping.get(value, value)


def _rewrite_prose(value: Any, mapping: dict[str, str]) -> Any:
    """Only explicit canonical references in prose denote opaque IDs.

    A session ID can equal a project name or an ordinary word. Replacing bare
    tokens would change the task and invalidate this invariance experiment.
    """
    if isinstance(value, list):
        return [_rewrite_prose(item, mapping) for item in value]
    if not isinstance(value, str) or not mapping:
        return value
    identifiers = "|".join(re.escape(key) for key in sorted(mapping, key=len, reverse=True))
    pattern = r"(?<![\w-])(session:|answer:)(" + identifiers + r")(?![\w-])"
    return re.sub(pattern, lambda match: match.group(1) + mapping[match.group(2)], value)


def _rename_episode_ids(episode: dict, mapping: dict[str, str]) -> None:
    """Rename structural identity/reference fields, never arbitrary strings."""
    def fields(row, names):
        for name in names:
            if name in row:
                row[name] = _rewrite_reference(row[name], mapping)

    def prose(row, names):
        for name in names:
            if name in row:
                row[name] = _rewrite_prose(row[name], mapping)

    def sessions(rows):
        for row in rows:
            if "id" in row:
                row["id"] = mapping.get(row["id"], row["id"])
            prose(row, ("title", "activity", "summary", "turns"))

    def cards(rows):
        for row in rows:
            for name in ("id", "session", "sessionID"):
                if name in row:
                    row[name] = mapping.get(row[name], row[name])
            prose(row, ("text", "options"))

    def history(rows):
        for row in rows:
            fields(row, ("to", "corrected_from"))
            prose(row, ("you",))

    def ranking(rows):
        renamed = []
        for row in rows:
            if isinstance(row, dict):
                fields(row, ("target", "destination", "to"))
                renamed.append(row)
            elif isinstance(row, (list, tuple)):
                values = list(row)
                if values:
                    values[0] = _rewrite_reference(values[0], mapping)
                renamed.append(values)
            else:
                renamed.append(_rewrite_reference(row, mapping))
        return renamed

    state = episode.get("state", {})
    sessions(state.get("sessions", []))
    cards(state.get("cards", []))
    history(state.get("history", []))
    if "tasks" in state:
        state["tasks"] = {mapping.get(key, key): value for key, value in state["tasks"].items()}
    for event in episode.get("events", []):
        # Episode/event/group identity and branch links stay untouched.
        fields(event, ("target",))
        prose(event, ("message",))
        context = event.get("context", {})
        fields(context, ("replyTo", "pinned", "notTo", "shown", "target", "predicted"))
        carried = context.get("jev")
        if isinstance(carried, dict):
            fields(carried, ("target", "top"))
            if "ranked" in carried:
                carried["ranked"] = ranking(carried["ranked"])
        gold = event.get("gold", {})
        fields(gold, ("intended",))
        for name in ("acceptable", "clarify"):
            if name in gold:
                gold[name] = [_rewrite_reference(value, mapping) for value in gold[name]]
        prose(gold, ("evidence",))
        delta = event.get("delta", {})
        for suffix in ("+", "~"):
            sessions(delta.get("sessions" + suffix, []))
            cards(delta.get("cards" + suffix, []))
        for collection in ("sessions", "cards"):
            if collection + "-" in delta:
                delta[collection + "-"] = [mapping.get(value, value) for value in delta[collection + "-"]]
        history(delta.get("history+", []))
        history(delta.get("history", []))


def _protected_tokens(episode: dict) -> set[str]:
    values = list(episode.get("state", {}).get("projects", []))
    for session in _sessions(episode):
        values.extend([session.get("id", ""), session.get("title", ""), session.get("project", "")])
    return PROTECTED_WORDS | {token.lower() for value in values
                              for token in re.findall(r"\w+", str(value))}


def transform_episode(episode: dict, name: str, *, seed: int = 1,
                      paraphrase: Callable[[str], str] | None = None,
                      extra_sessions: int = 3) -> tuple[dict, dict[str, str]]:
    """Return a deep-copied variant and a new-to-old ID map for scoring.

    The caller must run ``option-order`` with ``option_seed=seed``. Title noise
    skips title-referencing messages. Irrelevant additions are older than every
    existing session and use only spare candidate slots; they cannot evict a target.
    Typos transpose one interior pair in an unprotected word, preserving IDs,
    project/title references, ordinals, and command/addressing keywords.
    """
    if name not in TRANSFORMATIONS:
        raise ValueError(f"unknown transformation: {name}")
    variant = copy.deepcopy(episode)
    rng = random.Random(seed)
    if name == "option-order":
        return variant, {}
    if name == "paraphrase":
        if paraphrase is None:
            raise Inapplicable("paraphrase needs a reviewed, meaning-preserving hook")
        for event in variant.get("events", []):
            if event.get("kind") == "submit":
                rewritten = paraphrase(event["message"])
                if not isinstance(rewritten, str) or not rewritten.strip():
                    raise ValueError("paraphrase hook must return a nonempty string")
                event["message"] = rewritten
        return variant, {}
    if name == "ids":
        mapping = _id_map(episode, seed)
        _rename_episode_ids(variant, mapping)
        return variant, {new: old for old, new in mapping.items()}
    if name == "case":
        for event in variant.get("events", []):
            if event.get("kind") == "submit":
                event["message"] = event.get("message", "").swapcase()
        return variant, {}
    if name == "typo":
        protected = _protected_tokens(episode)
        changed = False
        for event in variant.get("events", []):
            if event.get("kind") != "submit":
                continue
            text = event.get("message", "")
            candidates = []
            for match in re.finditer(r"\b[A-Za-z]{5,}\b", text):
                word = match.group(0)
                if word.lower() in protected:
                    continue
                pairs = [index for index in range(1, len(word) - 2) if word[index] != word[index + 1]]
                if pairs:
                    candidates.append((match, pairs))
            if not candidates:
                continue
            match, pairs = rng.choice(candidates)
            index = rng.choice(pairs)
            word = match.group(0)
            noisy = word[:index] + word[index + 1] + word[index] + word[index + 2:]
            event["message"] = text[:match.start()] + noisy + text[match.end():]
            changed = True
        if not changed:
            raise Inapplicable("no non-addressing word admits a conservative typo")
        return variant, {}
    if name == "title-noise":
        messages = "\n".join(_messages(episode)).casefold()
        titles = [row.get("title", "").strip() for row in _sessions(episode)]
        if any(title and title.casefold() in messages for title in titles):
            raise Inapplicable("a submit refers to a session title")
        changed = False
        for session in _sessions(variant):
            if "title" in session:
                session["title"] += f" [note {rng.randrange(100, 1000)}]"
                changed = True
        if not changed:
            raise Inapplicable("no session title to perturb")
        return variant, {}
    if extra_sessions < 1:
        raise ValueError("extra_sessions must be positive")
    sessions = variant.setdefault("state", {}).setdefault("sessions", [])
    visible_idle = [row for row in sessions if not row.get("archived") and not row.get("running")]
    spare_slots = max(0, 20 - len(visible_idle))  # formats.sessions_ordered's cap
    if not spare_slots:
        raise Inapplicable("no spare finished-session candidate slot; addition would be invisible")
    words = set(re.findall(r"\w+", "\n".join(_messages(episode)).casefold()))
    topics = ["lunar philately", "quartz beetle measurements", "ceramic turbine catalogue",
              "medieval sundial restoration", "glacial lichen taxonomy"]
    topic = next((candidate for candidate in topics
                  if not set(candidate.split()) & words), None)
    if topic is None:
        raise Inapplicable("irrelevant topic overlaps the current submit")
    oldest = max((row.get("idle_min", 0) for row in _sessions(variant)), default=0) + 525600
    occupied = {session.get("id") for session in _sessions(variant)}
    for index in range(min(extra_sessions, spare_slots)):
        identifier = f"meta_irrelevant_{seed}_{index}"
        while identifier in occupied:
            identifier += "_"
        occupied.add(identifier)
        sessions.append({"id": identifier, "title": f"Old {topic} {index}",
                         "project": "fixture-irrelevant", "running": False,
                         "activity": "", "summary": f"A closed archive of {topic}.",
                         "idle_min": oldest + index, "archived": False, "turns": []})
    return variant, {}


def _target(value: Any, inverse_ids: dict[str, str]) -> Any:
    if isinstance(value, dict):
        value = value.get("target", value.get("destination", value.get("to")))
    elif isinstance(value, (tuple, list)):
        value = value[0] if value else None
    if isinstance(value, str):
        return _rewrite_reference(value, inverse_ids)
    return value


def decision_signature(trace: dict, inverse_ids: dict[str, str] | None = None) -> tuple:
    """Compare legal action and semantic destination, ignoring ask-button order."""
    inverse_ids = inverse_ids or {}
    decision = trace.get("decision")
    if isinstance(decision, dict):
        decision = decision.get("kind", decision.get("decision"))
    if decision == "ask":
        options = trace.get("options", trace.get("ranked", []))
        if isinstance(trace.get("target"), list):
            options = trace["target"]
        members = {_target(item, inverse_ids) for item in options[:4]}
        return "ask", tuple(sorted(str(item) for item in members if item is not None))
    return decision, _target(trace.get("target"), inverse_ids)


def _submits(result: dict) -> dict[str, dict]:
    traces = result.get("events", result.get("traces", []))
    return {str(trace.get("id", trace.get("event_id", index))): trace
            for index, trace in enumerate(traces)
            if trace.get("kind", "submit") == "submit"}


def evaluate_invariance(episodes: Iterable[dict], system: Any, *,
                        transformations: Iterable[str] = TRANSFORMATIONS,
                        seed: int = 1, paraphrase: Callable[[str], str] | None = None,
                        runner: Callable | None = None) -> dict:
    """Aggregate flips on matched submits and branch divergence per episode.

    Descendants are never counted as independent cases. First-submit flips have
    a fixed denominator; later-event rates report only the common branch. A
    changed branch counts as an episode flip, even without a matched later turn.
    """
    if runner is None:
        from .episodes import play_episode
        runner = play_episode
    episodes = list(episodes)
    names = tuple(transformations)
    unknown = set(names) - set(TRANSFORMATIONS)
    if unknown:
        raise ValueError(f"unknown transformations: {sorted(unknown)}")
    aggregate = {name: {"episodes": 0, "skipped": 0, "event_pairs": 0,
                        "event_flips": 0, "episode_flips": 0,
                        "first_submit_pairs": 0, "first_submit_flips": 0,
                        "branch_divergences": 0} for name in names}
    for episode_index, episode in enumerate(episodes):
        base = _submits(runner(episode, system))
        for name in names:
            counts = aggregate[name]
            variant_seed = seed + episode_index
            try:
                variant, inverse_ids = transform_episode(episode, name, seed=variant_seed, paraphrase=paraphrase)
            except Inapplicable:
                counts["skipped"] += 1
                continue
            original_seed = system.option_seed
            try:
                if name == "option-order":
                    system.option_seed = variant_seed
                # One system owns the HTTP budget and counters for every base
                # and variant; copying its integer counters would reset budget.
                changed = _submits(runner(variant, system))
            finally:
                system.option_seed = original_seed
            common = base.keys() & changed.keys()
            flips = sum(decision_signature(base[key]) != decision_signature(changed[key], inverse_ids)
                        for key in common)
            divergent = base.keys() != changed.keys()
            counts["episodes"] += 1
            counts["event_pairs"] += len(common)
            counts["event_flips"] += flips
            counts["branch_divergences"] += divergent
            counts["episode_flips"] += bool(flips or divergent)
            if base:
                first = next(iter(base))
                if first in changed:
                    counts["first_submit_pairs"] += 1
                    counts["first_submit_flips"] += decision_signature(base[first]) != decision_signature(changed[first], inverse_ids)
    for counts in aggregate.values():
        counts["event_flip_rate"] = counts["event_flips"] / counts["event_pairs"] if counts["event_pairs"] else None
        counts["episode_flip_rate"] = counts["episode_flips"] / counts["episodes"] if counts["episodes"] else None
        counts["first_submit_flip_rate"] = counts["first_submit_flips"] / counts["first_submit_pairs"] if counts["first_submit_pairs"] else None
    return {"base_episodes": len(episodes), "transformations": aggregate,
            "paraphrase": "hook supplied" if paraphrase else "skipped: reviewed hook not supplied"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("episodes", nargs="+", help="development episode JSONL files or globs")
    parser.add_argument("--format", default="combo-o")
    parser.add_argument("--policy", default="explore.final3:best")
    parser.add_argument("--baseline", choices=["always-ask", "recency-only", "lexical-only"])
    parser.add_argument("--transform", nargs="+", choices=TRANSFORMATIONS, default=TRANSFORMATIONS)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cache-only", action="store_true")
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args(argv)
    from .episodes import RouterSystem, load_episodes
    system = RouterSystem(format_name=args.format, policy_name=args.policy, baseline=args.baseline,
                          cache_only=args.cache_only, cache_path=args.cache, quiet=True)
    result = evaluate_invariance(load_episodes(args.episodes), system,
                                 transformations=args.transform, seed=args.seed)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
