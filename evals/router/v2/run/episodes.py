"""Replay v2 episodes through deterministic dispatch, ordered Jev and a policy.

Run from evals/router: python3 -m v2.run.episodes --help.
The shipped final3 policy uses Swift's frozen weights instead of its legacy
training loader. New responses go under run/cache; old Jev cache is read-only.
"""
import argparse
import copy
import glob
import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
os.environ["JEV_ORDERED"] = "1"

from . import adapter, rules

HERE = Path(__file__).resolve().parent
ROUTER = HERE.parents[1]
SEALED = HERE.parent / "data" / "episodes" / "sealed"
INTENTS = {"change_lookout", "question", "compound"}


def _is_sealed(path):
    path = Path(path).resolve()
    return path == SEALED.resolve() or SEALED.resolve() in path.parents


def load_episodes(paths, *, allow_sealed=False):
    """Read explicit JSONL paths/globs only. Explorers cannot open sealed cases."""
    if isinstance(paths, (str, Path)):
        paths = [paths]
    files = []
    for pattern in paths:
        if not allow_sealed and _is_sealed(pattern):
            raise ValueError("sealed episodes may only be evaluated with v2.run.seal")
        matches = sorted(glob.glob(str(pattern)))
        if not matches:
            raise ValueError(f"no episode files match {pattern}")
        for match in matches:
            path = Path(match)
            if not allow_sealed and _is_sealed(path):
                raise ValueError("sealed episodes may only be evaluated with v2.run.seal")
            if path.is_dir():
                files.extend(sorted(path.glob("*.jsonl")))
            else:
                files.append(path)
    episodes = []
    seen = set()
    for path in dict.fromkeys(files):
        if not allow_sealed and _is_sealed(path):
            raise ValueError("sealed episodes may only be evaluated with v2.run.seal")
        with path.open() as source:
            for number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                episode = json.loads(line)
                validate_episode(episode)
                if episode["id"] in seen:
                    raise ValueError(f"duplicate episode id at {path}:{number}")
                seen.add(episode["id"])
                episodes.append(episode)
    return episodes


def validate_episode(episode):
    if episode.get("schema") != 2:
        raise ValueError("episode schema must be 2")
    for key in ("id", "group", "state", "events"):
        if key not in episode:
            raise ValueError(f"episode lacks {key}")
    ids = [event["id"] for event in episode["events"]]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate event id")
    if not ids:
        raise ValueError("an episode needs at least one event")
    if not any(event["kind"] == "submit" for event in episode["events"]):
        raise ValueError("an episode needs at least one submit")
    for event in episode["events"]:
        if event["kind"] not in {"submit", "pick", "board"}:
            raise ValueError("unsupported event kind")
        if event["kind"] == "submit":
            if "message" not in event or "gold" not in event:
                raise ValueError("submit needs message and gold")
            if event["gold"].get("ask") not in {"required", "allowed", "forbidden"}:
                raise ValueError("gold.ask must be required, allowed or forbidden")
        for target in event.get("on", {}).values():
            if target is not None and target not in ids:
                raise ValueError("branch references an absent event")


def _shipped_weights():
    """Read only Swift's numeric tables; source text never controls execution."""
    source = ROUTER.parents[1] / "Sources" / "Lookout" / "RouterRoute.swift"
    text = source.read_text()
    tables = []
    for name in ("weights", "sureness"):
        match = re.search(r"static let " + name + r": \[String: Double\] = \[(.*?)\n    \]", text, re.S)
        if match is None:
            raise RuntimeError("shipped Swift fusion table missing")
        tables.append({key: float(value) for key, value in re.findall(r'"([\w]+)":\s*(-?[\d.]+)', match[1])})
    return tuple(tables)


def _legacy_modules(format_name, policy_name):
    import formats
    import jev
    import run
    from explore import cal, combo, final3, fusion
    lexical = adapter.install_lexical()
    # Register the shipped format directly. Avoid importing every explorer just
    # to discover combo-o (some explorers install their own fusion functions).
    formats.FORMATS.update(combo.FORMATS)
    formats.FORMATS.update(cal.FORMATS)
    lexical.install()
    lexical.STATE["fields"] = True
    fusion.case_features = final3.case_features
    final3._FIT["combo-o"] = _shipped_weights()
    if policy_name == "explore.final3:best":
        policy = final3.best
    else:
        import bench
        policy = bench.policy(policy_name)
    jev.ordered = True
    return formats, jev, run, policy, lexical, fusion, final3


class RouterSystem:
    """A named format/policy or unconditional reference baseline.

    Baselines bypass dispatch rules: always-ask really asks on every submission;
    recency-only really sends to the latest session. This makes their costs clear.
    max_calls bounds new HTTP requests, never counts existing cache hits.
    """
    def __init__(self, format_name="combo-o", policy_name="explore.final3:best", baseline=None,
                 cache_path=None, cache_only=False, option_seed=None, quiet=True,
                 legacy_cache=True, max_calls=40):
        if baseline not in {None, "always-ask", "recency-only", "lexical-only"}:
            raise ValueError("unknown baseline")
        self.format_name, self.policy_name, self.baseline = format_name, policy_name, baseline
        self.cache_path = Path(cache_path) if cache_path is not None else HERE / "cache"
        self.cache_only, self.option_seed, self.quiet = cache_only, option_seed, quiet
        self.legacy_cache, self.max_calls = legacy_cache, max_calls
        self.new_calls = self.cache_hits = 0
        self._modules = None

    @property
    def name(self):
        return self.baseline or f"{self.format_name}+{self.policy_name}"

    def _load(self):
        if self._modules is None:
            self._modules = _legacy_modules(self.format_name, self.policy_name)
        return self._modules

    def _ask(self, state, questions):
        _, jev, _, _, _, _, _ = self._load()
        raw = json.dumps({"model": "jev-latest", "state": state, "questions": questions}, sort_keys=False)
        digest = hashlib.sha256((raw + "#0").encode()).hexdigest()
        relative = Path(digest[:2]) / f"{digest}.json"
        caches = [self.cache_path]
        if self.legacy_cache:
            caches.append(ROUTER / "cache")
        for cache in caches:
            path = cache / relative
            if path.exists():
                try:
                    answer = json.loads(path.read_text())
                    if not isinstance(answer.get("answers"), dict):
                        continue
                    self.cache_hits += 1
                    return answer, digest, True
                except (ValueError, AttributeError):
                    continue
        if self.cache_only:
            raise RuntimeError("ordered Jev response absent from cache")
        if self.new_calls >= self.max_calls:
            raise RuntimeError("new Jev call budget exhausted")
        self.new_calls += 1
        old_cache, old_ordered = jev.CACHE, jev.ordered
        try:
            jev.CACHE, jev.ordered = self.cache_path, True
            return jev.ask(state, questions), digest, False
        finally:
            jev.CACHE, jev.ordered = old_cache, old_ordered

    def decide(self, state, event):
        message, context = event["message"], event.get("context", {})
        case = adapter.to_case(state, event)
        if self.baseline:
            ordered = sorted(case["board"]["sessions"], key=lambda s: (s["idle_min"], s["id"]))
            rank = [{"target": "session:" + s["id"], "score": 1 / (i + 1)} for i, s in enumerate(ordered)]
            if self.baseline == "lexical-only":
                lexical = self._load()[4]
                scores = lexical.scores(case)
                rank = [{"target": "session:" + sid, "score": score}
                        for sid, score in sorted(scores.items(), key=lambda item: -item[1])]
            if self.baseline == "always-ask" or not rank:
                rank += [{"target": "new:" + p, "score": 0} for p in case["board"]["projects"]]
                rank += [{"target": target, "score": 0} for target in sorted(INTENTS)]
                return {"decision": "ask", "target": None, "ranked": rank[:4], "path": "baseline"}
            return {"decision": "send", "target": rank[0]["target"], "ranked": rank[:4], "path": "baseline"}
        planned = rules.plan(state, message, context)
        if planned is not None:
            return {**planned, "path": "rule"}
        formats, _, legacy_run, policy, lexical, fusion, final3 = self._load()
        built_state, questions, keymap = formats.build(self.format_name, case, shuffle_seed=self.option_seed)
        answer, digest, cache_hit = self._ask(built_state, questions)
        row = {"id": case["id"], "keymap": keymap, "answers": answer["answers"]}
        reading = legacy_run.reading(row)
        # Existing policies looking up r._id see ONLY this episode's visible case.
        if not getattr(policy, "needs_case", False):
            fusion._CASES = {case["id"]: case}
        kind, what = policy(reading, case) if getattr(policy, "needs_case", False) else policy(reading)
        sureness = None
        if self.policy_name == "explore.final3:best":
            fs = lexical.features(reading, case)
            if fs:
                weights, confidence = final3.fitted()
                probabilities = fusion.probs(fs, weights)
                top, sureness = fusion.confidence(reading, case, fs, weights, confidence)
                ranking = sorted(probabilities.items(), key=lambda item: -item[1])
            else:
                ranking, top = [], None
        else:
            ranking = [(target, reading["dests"].get(target, 0)) for target in legacy_run.ranked_targets(reading)]
            top = ranking[0][0] if ranking else None
        if kind == "ask":
            # Score the actual four buttons chosen by the policy, not Jev's raw
            # route ranking. Keep its probability/feature rank when available.
            order = list(dict.fromkeys(what))[:4]
            ps = dict(ranking)
            ranking = [(target, ps.get(target, 0)) for target in order]
            target = None
        else:
            target = adapter.canonical_target(what, state)
            top = what
            if top not in {item[0] for item in ranking[:1]}:
                ranking = [(what, reading["dests"].get(what, 0))] + [item for item in ranking if item[0] != what]
        ranked = [{"target": adapter.canonical_target(target, state), "score": probability}
                  for target, probability in ranking[:4]]
        decision = {"decision": kind, "target": target, "top": adapter.canonical_target(top, state),
                    "ranked": ranked, "sureness": sureness, "sure": kind != "ask", "assisted": True}
        result = rules.post_jev(state, message, context, decision, ranked=ranked)
        result["path"] = "rule" if result.get("reason") in {"named-destination", "live-shown"} else "jev"
        result.update(request_hash=digest, cache_hit=cache_hit, latency=answer.get("_latency"),
                      tokens=(answer.get("usage") or {}).get("input_tokens"))
        return result


def apply_delta(state, delta):
    """Apply exogenous changes by identity, preserving all unrelated state."""
    for collection in ("cards", "sessions"):
        rows = state.setdefault(collection, [])
        removed = set(delta.get(collection + "-", []))
        rows[:] = [row for row in rows if row["id"] not in removed]
        for added in delta.get(collection + "+", []):
            if any(row["id"] == added["id"] for row in rows):
                raise ValueError("board delta adds a duplicate identity")
            rows.append(copy.deepcopy(added))
        for change in delta.get(collection + "~", []):
            row = next((row for row in rows if row["id"] == change["id"]), None)
            if row is None:
                raise ValueError("board delta updates an absent identity")
            row.update(copy.deepcopy(change))
    state.setdefault("history", []).extend(copy.deepcopy(delta.get("history+", [])))
    for key in ("now", "projects", "history"):
        if key in delta:
            state[key] = copy.deepcopy(delta[key])


def _wrong(decision, gold):
    return decision["decision"] != "ask" and (
        gold["ask"] == "required" or decision.get("target") not in gold.get("acceptable", []))


def _delivery(state, message, target, event_id, context=None, corrected_from=None):
    history = {"ago_min": 0, "you": message, "to": target}
    if corrected_from:
        history["corrected_from"] = corrected_from
    state.setdefault("history", []).append(history)
    body = rules.edit(message, (context or {}).get("pills", []))
    if target and target.startswith("session:"):
        session = next((s for s in state.get("sessions", []) if s["id"] == target[8:]), None)
        if session:
            session["running"], session["idle_min"] = True, 0
            session.setdefault("turns", []).append([body, ""])
    elif target and target.startswith("new:"):
        # Stable replay identity, visible to subsequent board updates. The schema
        # has no launch-result ID; do not borrow an oracle's future session ID.
        state.setdefault("sessions", []).append({"id": "started-" + event_id, "title": message[:80],
            "project": target[4:], "running": True, "activity": "", "summary": "", "idle_min": 0,
            "archived": False, "turns": [[body, ""]]})


def play_episode(episode, system):
    """Follow one outcome path, never feed gold or unvisited events to the router.

    Default continuation is list order, skipping direct branch entry nodes.
    on.ask/on.wrong choose those nodes; optional on.right/on.next support an
    explicit join. Each event executes at most once; cyclic graphs are rejected.
    Picks deliver the pending original message, never a fabricated utterance.
    """
    validate_episode(episode)
    state = copy.deepcopy(episode["state"])
    events = episode["events"]
    positions = {event["id"]: index for index, event in enumerate(events)}
    branch_entries = {target for event in events for target in event.get("on", {}).values() if target}
    traces, visited = [], set()
    pending = None
    recoveries = {}
    outstanding = set()
    index = 0
    while index is not None and index < len(events):
        event = events[index]
        if event["id"] in visited:
            raise ValueError("episode contains an executed branch cycle")
        visited.add(event["id"])
        trace = {"id": event["id"], "kind": event["kind"], "decision": event["kind"],
                 "target": None, "ranked": [], "path": "rule"}
        outcome = "next"
        if event["kind"] == "board":
            apply_delta(state, event["delta"])
            trace["delta"] = copy.deepcopy(event["delta"])
        elif event["kind"] == "pick":
            if pending is None:
                raise ValueError("pick without a pending ask")
            target = adapter.canonical_target(event["target"], state)
            options = [item["target"] if isinstance(item, dict) else item for item in pending["ranked"]]
            accepted = rules.eligible(state, target)
            trace.update(decision="pick", target=target, accepted=accepted,
                         responds_to=pending["id"], clicks=1 if target in options else 2,
                         ranked=pending["ranked"])
            if accepted:
                recovery = recoveries.get(pending["id"])
                _delivery(state, pending["message"], target, event["id"], pending["context"],
                          recovery["wrong_target"] if recovery else None)
                if target == pending["gold"].get("intended") or target in pending["gold"].get("acceptable", []):
                    outstanding.discard(pending["id"])
                    if recovery:
                        outstanding.discard(recovery["origin"])
                pending = None
            else:
                trace["reason"] = "stale-pick"
        else:
            # Typing while an ask waits starts a new classification. It is never
            # interpreted as choosing an ordinal button on the older ask.
            decision = system.decide(state, event)
            target = decision.get("target")
            kind = decision["decision"]
            if kind == "send" and target:
                kind = "start" if target.startswith("new:") else "intent" if target in INTENTS else "send"
            decision = {**decision, "decision": kind}
            trace.update(decision)
            trace.update(message=event["message"], context=copy.deepcopy(event.get("context", {})),
                         gold=copy.deepcopy(event["gold"]))
            if "tags" in event:
                trace["tags"] = copy.deepcopy(event["tags"])
            if event.get("duplicate_of_real"):
                trace["duplicate_of_real"] = True
            outstanding.add(event["id"])
            if kind == "ask":
                pending = {**trace, "ranked": decision.get("ranked", [])}
                outcome = "ask"
            else:
                wrong = _wrong(decision, event["gold"])
                recovery = recoveries.get(event["id"])
                if recovery:
                    trace["recovery_of"] = recovery["origin"]
                _delivery(state, event["message"], target, event["id"], event.get("context"),
                          recovery["wrong_target"] if recovery else None)
                trace["wrong"] = wrong
                if wrong:
                    outcome = "wrong"
                    correction = event.get("on", {}).get("wrong")
                    if correction:
                        recoveries[correction] = {"origin": event["id"], "wrong_target": target}
                else:
                    outstanding.discard(event["id"])
                    # A scripted correction resolves the preceding misdelivery
                    # goal while retaining its charged wrong in the trace.
                    if recovery:
                        outstanding.discard(recovery["origin"])
                    outcome = "right"
        traces.append(trace)
        branches = event.get("on", {})
        if outcome in branches:
            following = branches[outcome]
            index = positions[following] if following is not None else None
        elif "next" in branches:
            following = branches["next"]
            index = positions[following] if following is not None else None
        else:
            index += 1
            while index < len(events) and events[index]["id"] in branch_entries:
                index += 1
    result = {key: copy.deepcopy(value) for key, value in episode.items() if key not in {"state", "events"}}
    result.update(system=system.name, events=traces, completion=not outstanding and pending is None,
                  final_state=state, visited=len(visited))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("episodes", nargs="+", help="explicit JSONL files or globs (dev/calib only)")
    parser.add_argument("--format", default="combo-o")
    parser.add_argument("--policy", default="explore.final3:best")
    parser.add_argument("--baseline", choices=["always-ask", "recency-only", "lexical-only"])
    parser.add_argument("--cache", type=Path, default=HERE / "cache")
    parser.add_argument("--cache-only", action="store_true")
    parser.add_argument("--max-calls", type=int, default=40)
    parser.add_argument("--option-seed", type=int)
    parser.add_argument("--output", type=Path, help="write event traces as JSONL")
    parser.add_argument("--bootstrap", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args(argv)
    try:
        episodes = load_episodes(args.episodes)
        system = RouterSystem(args.format, args.policy, args.baseline, args.cache, args.cache_only,
                              args.option_seed, max_calls=args.max_calls)
        results = [play_episode(episode, system) for episode in episodes]
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text("".join(json.dumps(result, ensure_ascii=False) + "\n" for result in results))
        from .score import evaluate
        report = evaluate(results, bootstrap=args.bootstrap, seed=args.seed)
        report["system"] = system.name
        report["jev"] = {"new_calls": system.new_calls, "cache_hits": system.cache_hits}
        print(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False))
    except (ValueError, RuntimeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
