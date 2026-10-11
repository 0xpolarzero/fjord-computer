# Router benchmark v2: specification

Synthesised from evals/router/research/ (audit.md, literature.md, interactions.md, behavior.md,
codex-benchmark-design.md). This is the contract the builders implement; the rationale is in those files and in
docs/design/router-research.md.

## Goals

Measure whether the Router gets your words to the right place safely, on traffic like yours, with honest uncertainty:
- realistic: real board states and timelines from your sessions; Router-phrased messages in your style; the contexts a
  message really comes with; multi-turn flows;
- unbiased: written and labelled by three model families (Anthropic, OpenAI, Google), never labelled by its writer's
  family; agreement measured; a human anchor (you) on a blind sample;
- un-overfittable: a sealed test set nobody tunes on, read only through an aggregate-only evaluator;
- decision-useful: a loss in clicks, slices, paired comparisons, invariance flip rates, intervals clustered by session.

## Data boundary

Raw transcripts (`real/data/corpus.jsonl`, `~/.claude`) are read only by local code and Claude agents. Every derived file
is redacted (`real/boards.py` `redact`) before any model sees it; Codex and Gemini read redacted derived files only.
Everything under `v2/data/` is gitignored; code and specs are committed.

## Layout (evals/router/v2/)

```
v2/
  schema.md              the episode schema (this file's §Schema, kept in sync)
  build/                 builders: states.py (real timelines → states), triage.py (card kinds), generate_*.py,
                         label_*.py, audit_realism.py, split.py
  run/                   episodes.py (runner), rules.py (deterministic layer, mirrors RouterDispatcher.plan),
                         score.py, metamorphic.py, compare.py, seal.py (aggregate-only evaluator for sealed)
  data/                  (gitignored) states/, episodes/{dev,calib,sealed}/, labels/, audits/
```

## Schema

One JSON object per line, one episode per object.

```json
{
  "schema": 2,
  "id": "ep-…", "family": "…", "group": "…",          // group: the independence unit for splits/bootstrap (source session-day)
  "provenance": {"source": "real-moment|real-rewrite|goal|scripted", "anchors": ["re-…"], "writer": "claude|gpt|gemini|human",
                 "writer_model": "…", "state_fidelity": "transcript|board|synthetic", "synthetic": ["what was invented"]},
  "tags": {"primary": "<message family>", "flow": "<flow>", "slices": ["…"], "lang": "en|fr|mix"},
  "state": {                                           // the board at the first event (Lookout's view)
    "now": "<iso>", "projects": ["…"],
    "sessions": [{"id": "s…", "title": "<title at that time>", "project": "…", "running": bool,
                  "activity": "…", "summary": "…", "idle_min": n, "archived": false,
                  "turns": [["you", "said"], …]}],     // redacted recent turns (for BM25); [] when unknown
    "cards": [{"id": "c…", "session": "s…", "kind": "question|plan|asks|approval|done|stuck|waiting",
               "text": "…", "options": ["…"], "created_min_ago": n}],
    "history": [{"ago_min": n, "you": "…", "to": "s…|new:<p>|<intent>"}]
  },
  "events": [
    {"id": "e1", "kind": "submit", "message": "…",
     "context": {"replyTo": "c…|null", "pinned": "<target>|null", "pills": ["<project>"], "notTo": "<target>|null",
                 "shown": "<target>|null", "router_aside": false},
     "gold": {"intended": "<target>", "acceptable": ["<target>"], "clarify": ["<target>"],
              "ask": "required|allowed|forbidden", "consequential": bool, "evidence": "…"},
     "on": {"ask": "e2", "wrong": "e3"}},            // which event follows each router outcome (branching)
    {"id": "e2", "kind": "pick", "target": "<target>"},
    {"id": "e3", "kind": "submit", "message": "no, that was for …", "context": {…}, "gold": {…}},
    {"id": "e4", "kind": "board", "delta": {"cards+": […], "cards-": ["c…"], "sessions~": [{…}]}}
  ]
}
```

Targets: `session:<id>`, `new:<project>`, `change_lookout`, `question`, `compound`. A reply to a card is its session.
`acceptable`: interchangeable successful destinations (sending there is right). `clarify`: competing interpretations
(sending there is wrong; they belong on the ask card). `ask`: required (no safe send), allowed (asking is fine),
forbidden (the destination is plain; asking is a needless click).

## Message families (tags.primary)

bare-answer, option-pick, approval, rejection, topical-follow-up, next-instruction, question-to-session,
explicit-address, switch, correction, new-session, lookout-setting, board-question, compound, paste (error/log/URL),
small-talk.

## Flows (tags.flow)

single, ask-pick-follow, ask-then-typed, correction-after-wrong, chain (2–4 to one session), switch-back (A→B→A),
card-arrives-midway (board event), backlog (answer older waiting sessions), new-then-follow, armed-reply,
pill-start, pinned, prediction-shown/waved-off, intent-then-session.

## Sources (provenance.source) and target mix for v2.0

| source | what | share |
|---|---|---|
| real-moment | the real message on the real-state board (as round 2, with faithful states); gold from where it went, ask policy labelled | 25% |
| real-rewrite | the real moment's intent re-phrased as one would type it in the Router, by a writer family, in your style | 30% |
| goal | a goal grounded on a real-state board, written fresh (intents, compound, new sessions, corrections, contexts) | 35% |
| scripted | deterministic contracts (pills, armed replies, pins, approval veto, notTo, @router) and metamorphic variants | 10% |

Behaviour targets (research/behavior.md): next message to the same session 51%, another existing 40%, new 9%; questions
to sessions ~10× questions to Lookout; 16% of messages ≤ 5 words; boards: median 2 running, 4–6 active in 2 h, many
finished-unanswered; on a switch, recency rank of the target 1st 36% / 2nd 32% / 3rd 18%. Report prevalence-weighted
(natural) and slice-balanced (stress) numbers separately.

## Sizes (v2.0)

~1,500 base episodes (≥ 1 submit; ≥ 40% multi-submit): dev 600, calib 300, sealed 600. Sealed: ≥ 40 per message family
and ≥ 60 per major flow where the source allows; thin slices are reported as exploratory. Metamorphic variants (≥ 3 per
base on 300 bases) stay with their base's split and never count as independent.

## Labels

Three blind annotators per submit event, one per family (Claude, GPT via Codex, Gemini), excluding the writer's family
where possible, each seeing only what the Router sees at that event: `intended` guess, `acceptable`, `clarify`, `ask`,
`consequential`, confidence 1–4, evidence. Gold: majority with adjudication by a fourth pass when they disagree;
keep every raw label (soft labels). Report Krippendorff's α for `ask` and exact-action agreement per slice. For
real-moment events, `intended` is where it went; annotators judge the rest. Human anchor: 60 blind events for you.

## Scoring (run/score.py)

Click-equivalent loss per submit (sensitivity at wrong = 10/25/100):
right send 0 · ask containing the intended target 1 (ask required/allowed) or 2 (ask forbidden, needless) ·
ask without the intended target in the first four 4 · wrong send/start/intent 25 · consequential wrong (approval,
push, delete…) 100. Per episode: total loss, wrong sends, clicks, completion within budget.
Report: loss, wrong/all, wrong/sends, coverage, hit@1/@4 of the ask card, per family/flow/slice, natural vs stress
mixes. Intervals: 2,000 bootstrap replicates resampling `group`s. Comparisons: paired by episode, paired bootstrap on
Δloss, McNemar on wrong-send discordance where independent. Invariance: flip rate per transformation.
Baselines: always-ask, recency-only, lexical-only, round-1, round-2, round-3 (shipped).

## Splits and sealing (run/seal.py)

Split by `group` (source session-day), never by case. Sealed episodes are written encrypted-at-rest is not needed, but
kept in `v2/data/episodes/sealed/` which explorers and optimizers must not read; `seal.py` runs a named format+policy
on them and prints only aggregate tables (no per-case output), and appends the run to `v2/data/ledger.jsonl`. A sealed
read is budgeted: once per round, for a preregistered candidate. Ship rule: on calib, Δloss < 0 with paired 95% CI
excluding 0, no flow/family slice worse beyond its CI, invariance flips not up; then sealed confirms once.

## Runner (run/episodes.py)

Plays an episode against a format+policy: for each submit, apply the deterministic layer (run/rules.py, a mirror of
RouterDispatcher.plan and its vetoes: armed reply, pin, single pill start, start phrase + project, "tell X to",
@router-only, notTo, the approval-card veto, the live-shown pick), else ask Jev (format) and decide (policy); then follow
the branch for the outcome (`on.ask` → the pick event, `on.wrong` → the correction event), apply board deltas, and
update history with what the Router actually did. Jev answers cached as today (`JEV_ORDERED=1` always).
