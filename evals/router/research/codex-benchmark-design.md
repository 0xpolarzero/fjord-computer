# Router benchmark design

The benchmark must measure whether a user completes work safely with fewer routing clicks than manually choosing a session. Destination accuracy alone cannot establish that. Freeze the task distribution, action contracts, labels, loss function, and acceptance criteria before optimizing Jev or RouteFusion.

## 1. Evidence and limits

The [research history](../../../docs/design/router-research.md) establishes that written cases concealed dangerous real-message errors. Inspection confirms 210 synthetic cases, 150 heldout cases, 611 reconstructed real moments, and 332 Router-style cases. The real moments cover 150 target sessions over 14 days; boards contain 0–25 sessions, median 11. Every real card is regex-derived `done` or `asks`, with no question options. The six `labels_*.jsonl` files partition one annotation pass, rather than providing six independent annotations.

Real message lengths are 43/228/271/69 in the ≤3/4–15/16–60/>60-word buckets; Router-style lengths are 26/290/16/0. This is measurable generation bias. Session-input messages provide style evidence, not Router demand or prevalence. Existing `realA`, `realB`, and heldout results have influenced three rounds: all are development evidence now.

Missing evidence: actual Router utterances, historical titles, native triage/forms, complete timelines, visible composer state, and observed correction costs. `real.jsonl` cannot recover these. No safety claim should silently substitute invented evidence.

## 2. Versioned episodes and production replay

Use one JSONL record per episode, with an initial state and a branching event graph. Keep the existing board vocabulary; expand its fidelity rather than replacing it with prose.

| Field | Contract |
|---|---|
| `schema_version`, `id`, `family_id`, `split_group` | Version, unique episode, semantic siblings, source independence group. |
| `provenance` | `source_case_ids`, source dates, board/card/lexical fidelity, generator family/version, prompt hash, seed, synthetic transitions. |
| `initial_state` | `now_ms`, `board`, `pendingForms`, `lexical_turns`, `card_revisions`, pending asks, settings relevant to the episode. |
| `events` | IDs, timestamps, event payloads, exogenous board changes, action-conditioned successors, completion assertions. |
| `oracle` | Hidden user goal/intended destination, safe action labels, response requirements, evidence references, consequence tier. Never model input. |
| `annotations`, `sampling` | Original judgments/adjudication, strata, selection probability, evaluation weight. |

Retain `board.projects`, `sessions`, `cards`, `history`. Sessions retain `id/title/project/running/activity/summary/idle_min`; add `cliID`, `isArchived`, `lastActivity_ms`, `completedTurns`, and separate `summary_blocked`. Cards retain `id/session/kind/text/options`; add native `title/folder/createdMs/toolUseID/turnMessage/addressedAt/addressedBy/left/total/triage` and revision. The Swift adapter maps `session` to `sessionID` and project identifiers to fixture folder keys.

Use all seven `RouterCard.Kind` values: `question`, `plan`, `asks`, `approval`, `done`, `stuck`, `waiting`. Preserve `triage.state/questions/work/waitingOn/watch/ready/told/circles`; a session waiting on the user can have `running=true`. `pendingForms` contain `id`, `createdAt`, `cliSessionID`, `toolUseID`, `questions[{question,header,multiSelect,options[{label,description}]}]`, and optional `plan`. Native tool-call identity matters; an options array alone is insufficient. Use inert fixture-only pid/path fields where native constructors require them.

Events are `board_delta`, `predict`, `submit`, `pick`, `dismiss`, `stop`, and controlled effect completion/failure. Serialize every `RouterContext` field: `replyTo/projects/target/notTo/predicted/jev/shown/pills`. Pills use Swift Character ranges, validated in Swift for accents and emoji. A pick references the pending ask's event ID and target, resolving its runtime UUID; it is a click, never an invented utterance.

Example branch:

```json
{
  "id": "e1", "kind": "submit", "at_ms": 1000,
  "message": "go ahead", "context": {"projects": [], "pills": []},
  "oracle": {
    "acceptable_targets": [], "clarification_targets": ["session:s1", "session:s2"],
    "ask_policy": "required", "allowed_actions": ["ask"],
    "intended_to": "session:s2", "expected_effects": []
  },
  "successors": {"ask": "click-s2", "wrong_delivery": "correct-s2"}
}
```

After the ask, click `answer:c2`, verify the original message reaches s2 once, then submit “also add the regression case.” A wrong send instead triggers a scripted correction with an explicit s2 target, followed by the same request. Its harm remains charged. Add ask→unrelated typed message, dismissal, missing-option→Something else, three-instruction chains, A→B→A switching, partial question answers, and CI updates during routing. Reactions depend on observed actions and fixed goals, never router confidence or a forgiving free-running judge.

Replay through `RouterDispatcher.Effects`, `asker`, `configure`, and `onFinish`, with controlled clock/scheduler seams. Exercise real destination construction, fusion, guards, preparation, and card handling; stub external sending, launching, forms bridges, and intent tools. Never open fixture transcript paths. Use `RouterLexical.boardTurns` with `reader=nil` for current anchors; future captures supply redacted pre-event turns. Label lexical fidelity explicitly.

Apply exogenous deltas at declared scheduler barriers, including while classification/preparation is pending; let actual router actions update history/cards/asks. Compare post-state assertions instead of replacing state with the expected board. Initialize `history` as native `RouterDecision` records with authentic effect kinds: `lastTold()` counts sent/started deliveries, not every form answer. Initialize pending asks/caches by replaying preceding events. Record raw target, canonical session, ranked scores, sureness, assisted/live flags, rendered ask options, delivery body/original/rephrased, effects, decision outcome, and state hash. Preserve `answer:<card>` versus `session:<id>` for action scoring while normalizing their semantic destination.

## 3. Content generation and realism

Build source packets exclusively from allowed `real.jsonl` boards/messages and permitted style/label files. Sort `at` and `re-<session>-<turn-index>` to find partial chronology; attach only evidence present before each moment. `boards.py` uses an eight-hour window, 25-session cap, forced target inclusion, 300-character assistant paragraphs, and 200-character history. Do not run its extractor or lexical scripts that load `corpus.jsonl`. Mark invented forms, triage, continuations, and transitions synthetic.

Use two generation modes: minimal Router rephrasing of a real instruction, and fresh utterances pursuing a board-grounded goal. First write the scenario and hidden goal; then write the user's words from the visible board. Do not give writers router predictions or optimization failures. Preserve underspecification instead of adding a title to make every case solvable.

Maintain at least four independent model families in the pool. Use three writer families, for example Anthropic, OpenAI, and an independently trained open-weight family, plus a fourth family for labeling; freeze exact versions. Balance writers within every primary stratum. Hold one writer family out during generator-pipeline development. For each episode, the other three families label it; neither writer nor its family judges its output. Include human-written cases and later genuine Router traffic as separate provenance tracks.

Condition on measured style profiles: terse continuation, technical paste, direct address, French/code switching, typo-heavy mobile-like text, detailed constraints, and blunt correction. Profiles derive from allowed messages; they are not invented demographic personas. Cross style with intent so approvals are not always terse and board questions are not always polished. Sample wording length, casing, politeness, title mentions, referents, spelling, and pasted code independently where coherent. Include negation, conditional consent, one long multi-point instruction for one session, and actual paths/PR references replaced consistently with safe fixture identifiers.

Audit realism before any router run:

- Compare conditional distributions of length, language, casing, punctuation, pronouns, explicit mentions, code/paste frequency, ordinals, and lexical overlap. Report effect sizes and clustered intervals against source messages, then fresh Router traffic. Do not force Router addressing rates to match in-session rates.
- Train lexical and semantic real-versus-generated discriminators with metadata removed and source-family/time-disjoint evaluation. Inspect leakage and distinguishing features. Predeclare AUC >0.65 as an investigation trigger, not a realism verdict; near-chance discrimination is supporting evidence only.
- Blind humans review 10% of each batch, minimum 30 per generator, all consequential cases, and every rare state/language slice. Show the exact board: ask whether this person would type these words here, whether the goal is coherent, and whether the state is possible. Reject factual inventions and nonsensical messages; retain natural ambiguity. Track rejection reasons and rates.

Style, meaning, and source divergence are separate quality axes, following [Chim et al.](https://aclanthology.org/2025.cl-1.6/). Realism acceptance cannot depend on whether the router gets the case right. Redact every nested message/title/card/history/lexical field and outgoing trace, not just `message`; use synthetic credential canaries and consistent identifier placeholders to check redaction without sacrificing referential meaning. A new pipeline uses explicit allowlisted paths and never imports legacy loaders with private-data defaults.

## 4. Coverage and sample sizes

Target 10,000 base episodes: 3,000 development/fitting, 1,000 threshold calibration, 6,000 sealed test. Initially build a 120-episode development walking skeleton covering every action and flow; validate replay and labels before scaling. Base episodes contain 1–6 submissions, plus clicks and board events; at least half exercise multiple submissions. Variants do not increase base sample counts.

Assign one primary message family: bare answer; option selection; approval/rejection; topical follow-up; next instruction; explicit address; session switch; correction; new-session request; Lookout setting; board question; multi-destination compound. Tag ambiguity, no-safe-target, small talk, negation, language, message length, paste, and consequentiality separately. Reserve ≥400 test episodes requiring clarification and ≥200 unsupported/non-actionable utterances; include empty projects and router-disabled states.

Cross these with:

- Board: all seven card kinds; 0/1/multiple waiting cards; working versus waiting; same-project overlap; duplicate titles; older correct target versus recent distractor; missing context; renamed/archived targets; pending asks; CI/deploy/review waiting.
- Size: 0, 1, 2–5, 6–15, 16–25, >25 sessions. Exercise 20 recent nonrunning candidates, 80 offered sessions, 60 projects, and overflow cards explicitly.
- Flow: direct send; ask→pick→follow-up; ask→independent text; correction before delivery; recovery after misdelivery; instruction chain; switching; partial resolution; stale/concurrent state; outage/timeout/cancellation.

Use pairwise factor coverage and dangerous triples: bare approval × multiple waiting sessions × recent distractor; correction × stale prediction × session switch. Include running-session gold destinations, absent from the reconstructed real target distribution.

In sealed test, require ≥400 distinct base episodes per primary message family, ≥200 per board/flow reporting slice, and ≥100 per preregistered interaction. Quotas overlap. Worst-case 95% Wilson half-widths for independent binary observations are approximately 4.9, 6.9, and 9.8 percentage points respectively; use ≥1,000 for approximately 3.1 points. Thin interactions are exploratory.

These are independent-observation targets, not permission to multiply 611 anchors into statistical evidence. Report source-session/day/world clusters and effective sample sizes; expand fresh collection when dependence prevents the required precision. Publish balanced stress results separately from prevalence-weighted natural traffic. Without Router prevalence, publish macro averages and plausible-mixture sensitivity, not a deployment average.

## 5. Gold labels and ask-back quality

Keep hidden `intended_to` distinct from board-observable safe actions. `acceptable_targets` contains genuinely interchangeable successful destinations; competing plausible interpretations belong in `clarification_targets` and often require asking. Use `ask_policy=required|allowed|forbidden`, `allowed_actions`, `expected_effects`, and evidence pointers. Replace permissive union-of-labelers gold with adjudication. Never treat the historical typed destination as proof that a router could infer it.

Three blind annotators from different model families independently label every episode, seeing only router-visible state at each event. Hide author gold, actual historical destination, legacy `why/tags/label/alt`, router output, and future events. Require evidence for destination, asking, card/form operation, and consequences; permit “insufficient evidence.” Preserve judgments before discussion. Two humans adjudicate disagreements, unsupported judgments, and consequential actions; independently double-label a stratified 10% of the rest.

Report exact safe-action agreement, destination-set Jaccard, Krippendorff alpha for action/ask categories, and set-distance alpha using [MASI](https://aclanthology.org/L06-1392/), with slice intervals. Proposed readiness targets: alpha ≥0.8 overall, ≥0.7 per major slice. Diagnose poor agreement; do not delete difficult cases to meet a number. Document unresolved cases separately.

Score asks on successful-target inclusion among the four actual buttons: credit genuinely interchangeable `acceptable_targets`, or hidden-goal resolution when clarification is required. Also score valid/distinguishable titles/details, unnecessary candidates, escape availability, clicks to resolution, stale-pick rejection, and absence of premature sends. “Something else” has measurable extra cost; it is not automatic hit@4 credit. Include indistinguishable same-title/same-project buttons.

Production contracts from [RouterDispatcher](../../../Sources/Lookout/RouterDispatcher.swift) override generic conversational assumptions: typed “second” while an ask waits is a new message; unaddressed approvals require a click unless the visible prediction was confirmed; session-generated title words do not authorize approval. Exact question-label replies can answer matching forms; ordinal prose can be forwarded. Sending alone does not close a card: score partial/resolved/unchanged outcomes and revision safety.

For Lookout intents, specify answer facts and tool-effect contracts: a board question identifies the right working/waiting sessions without invented progress; a setting request changes only the named setting; compound requests perform every intended sub-action without duplicates. Evaluate dispatch and sandboxed intent execution separately.

Use deterministic assertions for targets, bytes, effects, clicks, and post-state. Use blinded independent semantic graders only for free-text answer adequacy, preserving rubrics and grading versions; humans audit disagreements. Label intended model/effort on new-session requests and verify defaults when none is requested.

## 6. Metamorphic tests

Attach ≥5 transformations to 1,000 base episodes, all kept with their parent split. Check semantic destination and legal action stability under paraphrase, case/typo edits, bijective ID renaming, harmless title noise, irrelevant sessions, and serialization/Jev option permutations. Preserve meaning and visible evidence; ask option order can change without changing membership or click identity. Record flips and worst transformation risk.

Conditional invariances need preconditions: title changes are invariant only without title-dependent references; extra sessions must not create ambiguity or evict the target. Card-option reordering preserves a content answer but changes what “second” denotes. A new competing approval can turn a safe send into required asking; aging a card or removing a target can change legality. Label these equivariance tests explicitly, not as failures of invariance. Raw Jev permutations must reach the wire with `JEV_ORDERED=1`; shuffled dictionaries later sorted prove nothing.

## 7. Splits, freezing, and refresh

Group source timelines, shared task content/boards, style rewrites, branches, and metamorphic descendants before splitting. Audit shared distractors and near-duplicate text, not just the target-session hash used by `bench.half`. If connected groups collapse the dataset, report that limitation and use later independent cohorts with temporal embargoes rather than weakening grouping.

All legacy data and derivatives stay in development. New scenarios on familiar boards remain an anchor-known stress track. A controlled fresh-scenario test measures synthetic generalization; a prospectively collected, consented redacted Router cohort measures deployment generalization. Keep both reported separately. Capture exact pre-event boards, native cards/forms, composer context, safe lexical turns, visible predictions, clicks, and outcomes without raw transcript paths. Silence after a send is not confirmation; audit a random sample beyond corrections.

Freeze manifests, content hashes, labels, versions, costs, weights, and evaluator code before a candidate runs. Keep sealed cases inaccessible to optimizer agents; an evaluator returns aggregate release results. Nominate one candidate per confirmatory cohort; aggregate-guided revisions require a fresh cohort. Never tune from sealed failures. An inspected cohort becomes regression/development data only after a replacement is sealed. Maintain a permanent anchor for longitudinal diagnostics plus rolling confirmatory cohorts. Restricted feedback reduces but does not eliminate adaptive test [overfitting](https://arxiv.org/abs/1506.02629/).

## 8. Metrics and comparisons

Use provisional click-equivalent loss: correct delivery 0; resolving necessary ask 1; needless ask 2; ask omitting every successful option 4; wrong send/start/intent 25; unauthorized consequential action or user-text corruption 100. Choose the highest applicable base loss per event; ask losses include the first selection click, then add extra recovery clicks. Retain misdelivery cost after recovery. These are policy assumptions; estimate real recovery costs and show sensitivity with wrong-send costs 10/25/100.

Primary harm is episodes with any harmful automatic action / enrolled base episodes, preventing dilution by policy-created correction turns. Utility is negative summed episode loss, macro-averaged with fixed episode weights; report loss per exogenous goal submission separately for length comparisons. Report wrong/all submissions, wrong/automatic actions, automatic coverage, completion within two routing clicks per exogenous goal, corrections, duplicate deliveries, card/form correctness, body preservation, p50/p95 latency, deadline failures, tokens, and cost. Separate reactive submissions from exogenous goals and separate wrong session, wrong new-project/duplicate start, and wrong Lookout intent. Include ranking hit@1/@4 and ask usability. Always-ask and manual target selection are the workaround baselines; also compare recency-only, lexical-only, and the current shipped policy.

Plot risk–coverage at frozen thresholds by deterministic/model/confirmed-live paths and every major slice, following [selective classification](https://arxiv.org/abs/1705.08500). Calibrate thresholds on the calibration set only. [Learn then Test](https://arxiv.org/abs/2110.01052) supports multiplicity-aware threshold selection; guarantees require appropriate independent calibration samples and do not survive unexamined distribution shift.

Use 10,000 paired source-group bootstrap replicates for loss/risk/completion differences and stratified weighting. Cluster turns, variants, shared worlds, and user-days; report Wilson intervals only where independence is justified. Use exact binomial upper bounds for rare harms: zero errors needs 299 independent automatic actions for <1% at one-sided 95%, 598 for <0.5%; twelve simultaneous <1% slice claims need about 546 zero-error actions each. Correlated synthetic variants cannot certify those bounds. See [NIST's exact-binomial method](https://itl.nist.gov/div898/software/dataplot/refman2/auxillar/exacbino.htm).

Compare identical episodes/schedules/seeds. Use paired clustered permutation tests; exact McNemar only for independent binary episode outcomes. Preregister primary comparisons and use Holm correction for confirmatory slices. Do not choose the test frontier's best threshold.

## 9. Implementation and daily operation

Proposed scripts under `evals/router/episodes/`, not created by this design:

| Script | Output and responsibility |
|---|---|
| `inventory.py`, `build.py` | Allowlisted inventory, source packets, generation provenance, sampling manifest. |
| `validate.py`, `audit_realism.py` | Schema/timeline/reference/redaction checks, duplicates, distribution/discriminator and human audits. |
| `label.py`, `adjudicate.py` | Blinded packets, independent annotations, agreement, frozen gold. |
| `split.py`, `freeze.py`, `metamorphic.py` | Grouped splits, manifests, seal enforcement, validated transformations. |
| `export.py`, `run.py`, `score.py`, `compare.py` | Swift fixtures, request/trace capture, utility/slices/intervals, paired reports. |

Add `RouterEpisodeReplayTests.swift` using production seams. Extend `parity.py` and `RouterFusionParityTests` from probability decisions to dispatcher traces; retain meaningful existing contracts in `RouterDispatcherTests`. Run offline recorded-signal parity separately from live-model evaluation. Cache keys include exact ordered redacted requests, model/format/schema versions, and board/context fingerprints; record failures instead of dropping them. No fixture path may trigger private filesystem reads or live effects.

Persist proposed `data/episodes.v2.jsonl`, `annotations.v2.jsonl`, `splits.v2.json`, and `runs/<candidate>.jsonl` behind track/split access controls. CLI contracts: `build.py --track anchor-dev --n 120 --seed 7`; `run.py --split dev --mode swift-replay --candidate NAME`; `score.py --manifest MANIFEST --run RUN`; `compare.py --baseline BASE --candidate RUN`. A sealing steward, not ordinary development commands, unlocks test execution.

Daily: run deterministic contracts and 120 development smoke episodes; substantive changes run full development slices. Fit weights on development, select thresholds on calibration, nominate one preregistered candidate for sealed evaluation. Log hypotheses, candidates, failures, versions, and comparisons. Proposed release gate: lower paired 95% utility-improvement bound >0 versus current/manual baselines, no contract violations, and upper natural-traffic wrong-action risk ≤1%. Require ≥50% automatic coverage on actionable, unpinned submissions, reporting each major slice; fix this floor before collection. Insufficient independent data means uncertified, not safe. Add 500 later-source episodes monthly when available; seal a replacement every quarter. Keep thin cohorts separate rather than relabeling old data fresh.

## 10. Ten risks of getting this wrong

1. **Reusing contaminated tests or moving gates:** creates apparent progress without new evidence.
2. **Counting paraphrases as independent:** manufactures narrow confidence intervals.
3. **Inventing real timelines/triage:** certifies states the app never produces.
4. **Confusing plausible with safe:** rewards confident ambiguous sends.
5. **One-family generation and judging:** turns shared bias into gold.
6. **Synthetic prevalence:** hides long messages and uncommon costly workflows.
7. **Oracle-assisted user reactions:** makes recovery easier than real use.
8. **Ranking without dispatcher replay:** misses approval, click, byte, and stale-state failures.
9. **Abstention denominator games:** reports low risk by asking on everything.
10. **Privacy or context leakage:** exposes secrets or supplies answers unavailable at routing time.

Next action: build and human-adjudicate the 120-episode production replay skeleton before changing routing weights or prompts.
