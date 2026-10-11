"""Preregister and run a candidate once per round with aggregate-only feedback.

From evals/router::

    python3 -m v2.run.seal preregister --round v2.0 --candidate shipped
    python3 -m v2.run.seal run --round v2.0 --candidate shipped

Preregistration freezes format, policy, scoring settings, and evaluator code
without reading sealed episodes. The read budget is consumed before opening any
sealed file, including when evaluation fails. The append-only ledger is locked
across processes. No traces, raw Jev answers, case identifiers, exception text,
or per-case files leave this evaluator. Cache files live inside sealed storage.

This is an operational access boundary, not an OS permission boundary: a person
who can read the repository can bypass it. Explorers must not read sealed files.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from datetime import datetime, timezone
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).resolve().parent
DEFAULT_SEALED = HERE.parent / "data" / "episodes" / "sealed"
DEFAULT_LEDGER = HERE.parent / "data" / "ledger.jsonl"


class SealError(RuntimeError):
    """A safe-to-display violation of the sealed evaluation contract."""


def _timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def _configuration(format_name: str, policy_name: str, baseline: str | None,
                   sealed_dir: Path, bootstrap: int, seed: int, max_calls: int) -> dict:
    if not isinstance(bootstrap, int) or bootstrap < 0:
        raise SealError("bootstrap must be a nonnegative integer")
    if not isinstance(max_calls, int) or max_calls < 0:
        raise SealError("max_calls must be a nonnegative integer")
    return {"format": format_name, "policy": policy_name, "baseline": baseline,
            "sealed_dir": str(sealed_dir.resolve()), "bootstrap": bootstrap, "seed": seed,
            "max_calls": max_calls}


def evaluator_fingerprint() -> str:
    """Freeze the replay, format/policy, lexical model and scoring implementation."""
    router = HERE.parent.parent
    files = sorted(HERE.glob("*.py"))
    files.extend(router / name for name in ("run.py", "jev.py", "formats.py", "bench.py", "analyze.py"))
    files.extend(sorted((router / "explore").glob("*.py")))
    repository = router.parents[1]
    files.append(repository / "Sources" / "FjordComputer" / "RouterRoute.swift")
    digest = hashlib.sha256()
    for path in sorted(set(files)):
        digest.update(str(path.relative_to(repository)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


@contextmanager
def _ledger(path: Path):
    """Hold an exclusive lock through the budget check and its durable append."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            stream.seek(0)
            try:
                rows = [json.loads(line) for line in stream if line.strip()]
            except (json.JSONDecodeError, UnicodeError):
                raise SealError("ledger is malformed; refusing sealed access") from None
            if any(not isinstance(row, dict) for row in rows):
                raise SealError("ledger is malformed; refusing sealed access")
            yield stream, rows
        finally:
            fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _append(stream, row: dict) -> None:
    stream.seek(0, os.SEEK_END)
    stream.write(json.dumps(row, sort_keys=True, allow_nan=False) + "\n")
    stream.flush()
    os.fsync(stream.fileno())


def _validate_names(round_name: str, candidate: str) -> None:
    if not isinstance(round_name, str) or not round_name.strip():
        raise SealError("round must be named")
    if not isinstance(candidate, str) or not candidate.strip():
        raise SealError("candidate must be named")


def preregister(*, round_name: str, candidate: str, format_name: str = "combo-o",
                policy_name: str = "explore.final3:best", baseline: str | None = None,
                sealed_dir: str | Path = DEFAULT_SEALED,
                ledger_path: str | Path = DEFAULT_LEDGER,
                bootstrap: int = 2000, seed: int = 7, max_calls: int = 40) -> dict:
    """Record the sole nominated candidate without inspecting the sealed data."""
    _validate_names(round_name, candidate)
    configuration = _configuration(format_name, policy_name, baseline, Path(sealed_dir), bootstrap, seed, max_calls)
    code_hash = evaluator_fingerprint()
    with _ledger(Path(ledger_path)) as (stream, rows):
        if any(row.get("round") == round_name for row in rows):
            raise SealError("round already registered or consumed; choose a fresh confirmatory round")
        row = {"kind": "preregister", "round": round_name, "candidate": candidate,
               "at": _timestamp(), "configuration": configuration, "evaluator_sha256": code_hash}
        _append(stream, row)
    return {"round": round_name, "candidate": candidate, "status": "preregistered",
            "configuration": configuration, "evaluator_sha256": code_hash}


def _consume(*, round_name: str, candidate: str, configuration: dict,
             code_hash: str, ledger_path: Path) -> None:
    with _ledger(ledger_path) as (stream, rows):
        registered = [row for row in rows if row.get("kind") == "preregister" and row.get("round") == round_name]
        if len(registered) != 1:
            raise SealError("round needs exactly one preregistered candidate before any sealed read")
        registration = registered[0]
        if registration.get("candidate") != candidate:
            raise SealError("candidate does not match the round's preregistration")
        if registration.get("configuration") != configuration:
            raise SealError("configuration changed since preregistration")
        if registration.get("evaluator_sha256") != code_hash:
            raise SealError("evaluator changed since preregistration")
        if any(row.get("round") == round_name and row.get("kind") != "preregister" for row in rows):
            raise SealError("round's single sealed read is already consumed")
        _append(stream, {"kind": "started", "round": round_name, "candidate": candidate,
                         "at": _timestamp(), "configuration": configuration,
                         "evaluator_sha256": code_hash})


def _aggregate_only(report: Any) -> dict:
    """Fail closed if a scorer ever adds trace-level fields to its output."""
    forbidden = {"events", "traces", "case", "cases", "case_id", "episode_id", "id", "target",
                 "ranked", "gold", "message", "state", "history", "answers", "wrongs", "misses"}
    forbidden.update({"per_case", "per_cases", "by_episode", "case_ids", "episode_ids", "results", "predictions"})
    def inspect(value):
        if isinstance(value, dict):
            if forbidden & value.keys():
                raise SealError("scorer returned per-case fields; aggregate-only evaluation refused")
            for item in value.values():
                inspect(item)
        elif isinstance(value, (list, tuple)):
            for item in value:
                inspect(item)
    if not isinstance(report, dict):
        raise SealError("scorer must return aggregate metrics")
    inspect(report)
    # JSON validates finite metrics and removes non-JSON custom values.
    return json.loads(json.dumps(report, allow_nan=False))


def run_sealed(*, round_name: str, candidate: str, format_name: str = "combo-o",
               policy_name: str = "explore.final3:best", baseline: str | None = None,
               sealed_dir: str | Path = DEFAULT_SEALED,
               ledger_path: str | Path = DEFAULT_LEDGER,
               bootstrap: int = 2000, seed: int = 7, max_calls: int = 40, cache_only: bool = False,
               per_case_output: Any = None,
               system_factory: Callable | None = None,
               runner: Callable | None = None,
               scorer: Callable | None = None) -> dict:
    """Consume one read, replay privately, append and return only aggregates.

    Dependency hooks support deterministic contract tests. They are unavailable
    through the CLI and must not be used to replace a preregistered evaluator.
    """
    if per_case_output is not None:
        raise SealError("per-case output is forbidden for sealed evaluation")
    _validate_names(round_name, candidate)
    sealed_dir, ledger_path = Path(sealed_dir), Path(ledger_path)
    configuration = _configuration(format_name, policy_name, baseline, sealed_dir, bootstrap, seed, max_calls)
    code_hash = evaluator_fingerprint()
    _consume(round_name=round_name, candidate=candidate, configuration=configuration,
             code_hash=code_hash, ledger_path=ledger_path)
    try:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            if system_factory is None or runner is None:
                from .episodes import RouterSystem, play_episode
                system_factory = system_factory or RouterSystem
                runner = runner or play_episode
            if scorer is None:
                from .score import evaluate
                scorer = evaluate
            # Do not use normal load_episodes: development loaders refuse sealed.
            files = sorted(sealed_dir.rglob("*.jsonl"))
            if not files:
                raise SealError("sealed directory contains no episode JSONL files")
            manifest = hashlib.sha256()
            episodes = []
            for path in files:
                raw = path.read_bytes()
                manifest.update(str(path.relative_to(sealed_dir)).encode())
                manifest.update(b"\0")
                manifest.update(raw)
                manifest.update(b"\0")
                episodes.extend(json.loads(line) for line in raw.decode("utf-8").splitlines() if line.strip())
            if not episodes:
                raise SealError("sealed directory contains no episodes")
            system = system_factory(format_name=format_name, policy_name=policy_name, baseline=baseline,
                                    cache_path=sealed_dir / ".jev-cache", cache_only=cache_only,
                                    quiet=True, legacy_cache=False, max_calls=max_calls)
            results = [runner(episode, system) for episode in episodes]
            report = _aggregate_only(scorer(results, bootstrap=bootstrap, seed=seed))
            if evaluator_fingerprint() != code_hash:
                raise SealError("evaluator changed during the sealed run")
        row = {"kind": "evaluated", "round": round_name, "candidate": candidate, "at": _timestamp(),
               "configuration": configuration, "evaluator_sha256": code_hash,
               "sealed_sha256": manifest.hexdigest(), "aggregate": report}
        with _ledger(ledger_path) as (stream, _):
            _append(stream, row)
        return {"round": round_name, "candidate": candidate, "aggregate": report}
    except Exception as error:
        # Exception messages can include complete failed requests or case IDs.
        try:
            with _ledger(ledger_path) as (stream, _):
                _append(stream, {"kind": "failed", "round": round_name, "candidate": candidate,
                                 "at": _timestamp(), "error_type": type(error).__name__})
        except Exception:
            # The durable started row already consumes the budget. A failure to
            # append must not expose the original exception through chaining.
            raise SealError("sealed evaluation failed; failure ledger append also failed; round remains consumed") from None
        if isinstance(error, SealError):
            raise error from None
        raise SealError(f"sealed evaluation failed ({type(error).__name__}); round remains consumed") from None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("preregister", "run"):
        sub = subparsers.add_parser(command)
        sub.add_argument("--round", required=True, dest="round_name")
        sub.add_argument("--candidate", required=True)
        sub.add_argument("--format", default="combo-o", dest="format_name")
        sub.add_argument("--policy", default="explore.final3:best", dest="policy_name")
        sub.add_argument("--baseline", choices=["always-ask", "recency-only", "lexical-only"])
        sub.add_argument("--sealed-dir", type=Path, default=DEFAULT_SEALED)
        sub.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER, dest="ledger_path")
        sub.add_argument("--bootstrap", type=int, default=2000)
        sub.add_argument("--seed", type=int, default=7)
        sub.add_argument("--max-calls", type=int, default=40,
                         help="maximum new HTTP requests, frozen at preregistration (default: 40)")
        if command == "run":
            sub.add_argument("--cache-only", action="store_true")
            # Explicitly reject the familiar runner option rather than ignore it.
            sub.add_argument("--output", help=argparse.SUPPRESS, dest="per_case_output")
            sub.add_argument("--per-case-output", help=argparse.SUPPRESS, dest="per_case_output")
    args = vars(parser.parse_args(argv))
    command = args.pop("command")
    try:
        result = preregister(**args) if command == "preregister" else run_sealed(**args)
    except SealError as error:
        parser.exit(2, f"seal: {error}\n")
    print(json.dumps(result, indent=2, sort_keys=True, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
