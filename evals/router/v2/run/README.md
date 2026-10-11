# Router v2 replay

Run commands from `evals/router`; Python's standard library is sufficient.

```sh
python3 -m unittest discover -s v2/run -t .
python3 -m v2.run.episodes v2/run/fixtures/smoke.jsonl --cache-only --output v2/run/results/shipped.jsonl
python3 -m v2.run.episodes v2/run/fixtures/smoke.jsonl --baseline always-ask --output v2/run/results/always-ask.jsonl
python3 -m v2.run.episodes v2/run/fixtures/smoke.jsonl --baseline recency-only --output v2/run/results/recency-only.jsonl
python3 -m v2.run.score v2/run/results/shipped.jsonl
python3 -m v2.run.compare v2/run/results/always-ask.jsonl v2/run/results/shipped.jsonl
python3 -m v2.run.metamorphic v2/run/fixtures/smoke.jsonl --transform option-order --cache-only
```

Omit `--cache-only` to permit new Jev calls, bounded by `--max-calls` (default 40).
Every request uses `JEV_ORDERED=1`. Existing `evals/router/cache` is read-only;
new answers go to `v2/run/cache`. All CLI modules support `--help`.
Historical policies are selectable with `--format swift --policy final` (round 1)
and `--format combo --policy explore.fuse2:guarded` (round 2). `lexical-only` is
also available as a baseline.

`rules.py` ports [RouterDispatcher](../../../../Sources/FjordComputer/RouterDispatcher.swift),
[RouterMCP](../../../../Sources/FjordComputer/RouterMCP.swift), and the Addressing/start
contracts in [RouterPrepare](../../../../Sources/FjordComputer/RouterPrepare.swift).
`test_rules.py` names the Swift behaviors it ports. The default policy remains
`explore.final3:best`; its rounded numeric tables come from the shipped
[RouterRoute](../../../../Sources/FjordComputer/RouterRoute.swift). The evaluator seeds
final3's fit cache with those tables instead of refitting on legacy data.
The adapter installs a redacted-state `past_turns` seam in memory and disables
all corpus loaders. Legacy source files are unchanged.

The runner sends only the current visible state and message to formats/policies.
Board fingerprints prevent lexical cache reuse after a turn, delta, or transform.
History records actual destinations, including misdeliveries and clicked choices;
asks do not invent a destination. Known session turns receive delivered text,
with project pills and Router asides removed. The replay models dispatch and board
state; it does not execute native permission forms, launch settings, or intent tools.

## Conventions where the schema is incomplete

- Events continue in list order, skipping direct branch entry nodes. `on.ask` and
  `on.wrong` choose those nodes; a pick then rejoins the next ordinary event.
  Optional `on.right`/`on.next` make joins explicit. Executed cycles fail.
- A successful correction resolves only the goal whose `on.wrong` entered it.
  A typed message while an ask waits is a new submit. Unanswered goals remain
  incomplete. A stale pick cannot deliver.
- Picks deliver the pending original message; an option outside the first four
  needs two clicks (Something else, then the target). Ask loss already includes
  its first click; observed clicks are counted separately without double charging.
- `shown` represents a sure, assisted chip displayed for these exact words.
  Optional `context.jev` supplies its classification explicitly. The schema omits
  that classification, card visibility/revisions, and pill character ranges.
- `turns: []` means unknown, so BM25 uses board text. A started session gets the
  stable runtime ID `started-<event-id>` because the schema supplies no launch ID.
- Natural weighting uses the specification's source shares, renormalized over
  present sources, or explicit positive `natural_weight`/`weight` on every episode.
  Stress weighting balances primary families. Neither establishes measured Router
  traffic prevalence. Explicit `click_budget` overrides two clicks per submit.
- Baselines are unconditional strategies and bypass the deterministic layer.
  This keeps always-ask and recency-only literal and exposes their contract costs.

Scoring APIs `event_score`, `episode_score`, and `evaluate` provide per-submit,
per-episode, and aggregate metrics. Reports retain wrong actions after recovery,
include 2,000 source-group bootstrap replicates, and show wrong costs 10/25/100.
Comparisons pair episodes and resample groups. Exact McNemar uses independent
group indicators; episode-level McNemar is omitted when episodes share a group.
Metamorphic reports distinguish matched-event flips and branch divergence;
paraphrases require a reviewed caller-supplied hook.

## Sealing

```sh
python3 -m v2.run.seal preregister --round v2.0 --candidate shipped
python3 -m v2.run.seal run --round v2.0 --candidate shipped
```

Only `seal.py` reads `v2/data/episodes/sealed`. It freezes configuration and code,
consumes the round before reading, emits aggregates, and appends a locked ledger
at `v2/data/ledger.jsonl`. Failure consumes the read too. Per-case output is
refused, logs/errors are suppressed, and its isolated cache stays in sealed
storage. This enforces the operational contract, not filesystem access control.
Development replay, scoring, comparison, and metamorphic loaders refuse sealed
paths. Tests use disposable fixtures and ledgers under `run`; implementation
never opens the real sealed cohort.

## Hand-written smoke evidence

The fixture contains eight synthetic episodes, not real traffic. Saved traces,
aggregate reports, comparisons, and option-order results are under `results`.

| System | Total loss | Wrong automatic actions | Clicks | Completed |
| --- | ---: | ---: | ---: | ---: |
| Shipped combo-o + final3 | 29 | 1 | 3 | 8/8 |
| Always ask | 25 | 0 | 14 | 8/8 |
| Recency only | 252 | 7 | 1 | 5/8 |

The shipped mistake enters the correction branch and keeps its 25-point loss.
Its approval-card case asks before delivery. One of 14 matched submits changes
under the tested on-wire option permutation (one of eight episodes); no branch
diverges. Sixteen new Jev responses were cached across baseline-order and
permuted-order smoke runs. The fixture proves replay behavior, not safety or
deployment performance.

The aggregate-only seal also ran on a copy of this fixture under `run/seal-smoke`,
using only cached answers and `results/smoke-ledger.jsonl`. The real sealed cohort
and production ledger were never accessed.

One quota needs correction: the spec lists 16 primary message families and asks
for at least 40 sealed examples per family, but allocates 600 sealed episodes.
If those quotas count primary-tagged episodes, their minimum is 640. Count
submits explicitly or increase the episode allocation before enforcing quotas.
