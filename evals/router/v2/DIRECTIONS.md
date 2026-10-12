# Router: directions for round 4 (2026-10-12)

Ranked directions for lowering the Router's click-equivalent loss on **real moments**. Sources: the research history
(docs/design/router-research.md), the spec, BENCHMARK.md, research/*.md, EXPLORE.md, the Swift (RouterRoute,
RouterDispatcher, RouterLexical, Jev, RouterMCP), a literature pass (links per item), aggregate statistics computed on
`v2/data/episodes/dev/` real moments (no sealed or calib file opened), and an independent opinion from GPT-6.1 Sol
(`codex exec`, read-only; where it agrees or adds something it is marked **[Sol]**).

## 0. What the loss says before any idea

Loss per submit: right 0, ask with the target in the four 1 (2 if needless), ask without it 4, wrong 25, consequential
wrong 100. Plugging in the shipped round-3 numbers on realB (40.7 right / 2.8 wrong / 56.5 ask) with ask hit@4 ≈ 84%
(the 79–89% range):

| part | per 100 submits | share |
|---|---|---|
| wrong sends: 2.8 × 25 | ≈ 70 | ≈ 45% |
| asks that contain the target: 56.5 × 0.84 × 1 | ≈ 47 | ≈ 31% |
| asks that miss it: 56.5 × 0.16 × 4 | ≈ 36 | ≈ 24% |
| total | ≈ 153 | |

Consequences that set the ranking:
- **Sending more is a weak lever under this loss.** Turning an ask (cost c) into a send pays only if 25·(1−p) < c:
  p > 96% for a one-click ask, > 92% for a two-click one, > 99% against a consequential 100 **[Sol]** (Chow's reject
  rule / Elkan's cost threshold: [Chow 1970](https://dspace.mit.edu/entities/publication/3d09633b-df6a-4051-8915-66bb2ae5b236),
  [Elkan 2001](https://cseweb.ucsd.edu/~elkan/rescale.pdf); Horvitz's act / dialog / don't-act bands,
  [CHI 99](https://erichorvitz.com/chi99horvitz.pdf)). Converting 10 points of asks to sends at 97% precision saves
  only ≈ 7 per 100; at 99% ≈ 12.
- **The big levers are the wrong sends (≈ 70) and the ask card's misses (≈ 36).** Halving wrong sends saves ≈ 35;
  lifting hit@4 from 84% to 94% saves ≈ 17, with zero new risk.
- **Changing the cost of a wrong send (product, section C) moves everything.** If most wrong sends could be caught
  before delivery at a cost of ~2–3 clicks, the wrong term falls by more than half and the send bar drops from 96%
  toward 75–85%, which is where coverage starts to pay.
- "Should it ask" is ambiguous on real moments (α ≈ 0.38): optimise the click loss against `intended`, never imitate
  the labellers' ask flag. Gold `ask` in dev is still provisional (every real submit `allowed`, none consequential), so
  until labels merge, bracket ask costs at 1 and 2 **[Sol]**.

Dev facts used below (real-moment subset of `dev/provisional.jsonl`, aggregates only): 216 episodes, 393 submits, 91
groups; 53% of submits go to the session the previous message went to (the 52% of the history holds); at an episode's
first submit the target is the latest-finished session 50%, 2nd 17%, 3rd 7%, older 11%, and a new or not-finished
destination 14%; new sessions 5%; length 1–2 words 5%, 3–8 27%, 9–30 46%, 31+ 22%. On 171 of 216 boards two or more
sessions share a title in one project, and in 22 episodes the target is one of them.

**Prerequisite (experiment 0).** There is no scored dev baseline yet: `v2/run/results/dev_*_prov.report.json` are empty
because every run stopped at "new Jev call budget exhausted". Run shipped, always-ask, recency-only and lexical-only on
dev with a call budget that covers it (dev real moments ≈ 400 calls for the shipped format, written ≈ 450 more; cents),
so every experiment below compares against a cached, paired baseline at zero further Jev cost.

**Common protocol for section A.** Dev only; folds grouped by `group`; fit inside folds (out-of-fold predictions);
report `real_only` loss with the paired group bootstrap (`v2.run.compare`), wrong/all, wrong/sends, ask rate, ask
hit@1/@4, slices same/switch/new and by length; scripted contracts must still pass (0 wrong). A candidate dies when the
paired 95% interval on Δloss (real_only) does not lie below 0, or when a slice's wrong sends rise beyond its interval.
Written episodes are reported as stress only.

## Ranked list

Rank is global: (expected loss reduction on real moments) × (confidence) ÷ (cost). Sections group them by what they
need.

| rank | id | direction | expected Δloss / 100 real submits | confidence | cost | Jev |
|---|---|---|---|---|---|---|
| 1 | A1 | Ask card built for hit@4, not from the send ranking | −8 to −17 | high | ½–1 day | 0 |
| 2 | A2 | One cost-aware send/ask selector, by path and destination type | −10 to −30 | medium-high | 1–2 days | 0 |
| 3 | A3 | Use the Jev signals already paid for (route confidence, margins, same-title mass) | −3 to −10 | medium | ½ day | 0 |
| 4 | A4 | Keep BM25's absolute strength, not only the ratio to the best | −3 to −10 | medium-high | 1 day | 0 |
| 5 | A5 | Continuity: the last-told session always checked, transition features | −5 to −15 | medium | 1–2 days | +1 noul in the same call |
| 6 | C1 | Hold before delivery (undo window) | −20 to −45 (changes the loss) | medium (catch rate unknown) | UI pilot | 0 |
| 7 | C2 | Keyboard-first ask card, Return takes the first option | −10 to −25 click-equivalents of effort | medium | 1–2 days | 0 |
| 8 | A6 | Refit the fusion on real dev moments, real-weighted | −3 to −10 | medium | 1 day | 0 |
| 9 | B1 | Decision traces with outcomes (prerequisite of all of B) | 0 directly | high | 1–2 days | 0 |
| 10 | B2 | Per-user refit from observable labels | −5 to −20 (late) | medium | 2–3 days + traffic | 0 |
| 11 | A7 | Live predictions bound to the board they were read on | unknown, safety | high (mechanism) | 1–2 days | +1 call when stale |
| 12 | C3 | The shown prediction as the ask (send-as-shown, widened) | −5 to −20 | low-medium | UI pilot | 0 (calls already made while typing) |
| 13 | A8 | Lexical turn boundary for running sessions | −1 to −5 | medium | 1 day | 0 |
| 14 | B3 | Implicit-feedback defect detection (corrections, quick re-sends, undos) | enables B2 | medium | 2 days + traffic | 0 |
| 15 | C4 | Explicit "continue with X" after a send or pick | −3 to −10 | medium | UI pilot | 0 on armed submits |
| 16 | A9 | Shortlist then rerank: fewer, better options to Jev | ±5, cuts tokens | low-medium | 1 day | fewer tokens |
| 17 | A10 | Short replies after a report (one rejected cohort) | −1 to −4 | low-medium | ½ day | 0 |
| 18 | B4 | Randomised positions 2–4 on the ask card (unbiased pick data) | enables B2/A1 refits | medium | ½ day + traffic | 0 |
| 19 | B5 | Online bar adaptation under drift (adaptive conformal) | guards wrong/sends | medium | 1 day + traffic | 0 |
| 20 | B6 | Running and queued targets from native traffic | unknown (unmeasured slice) | low on size | traffic | 0 |
| 21 | A11 | One on-device embedding feature beside BM25 | −0 to −5 | low | 2–3 days | 0 |
| 22 | A12 | Two wordings of the route question in one call | −0 to −5 | low | ½ day | +tokens, same latency |
| 23 | B7 | Soft evidence from the card you just opened | unknown | medium | traffic | 0 |

Ranges are rough: they come from the decomposition above and the closest measured effects in the history, not from a
run. The first job of each experiment is to replace them with a dev number.

---

## A. Router-side, measurable offline now

### A1. Build the ask card for hit@4, separately from the send ranking — rank 1

**Idea.** Today the card shows the fused top four, ranked to make the *first* choice safe to send. The card has a
different job: the target anywhere in four distinct, eligible options. Fill it with a small listwise slate: the fused
top, then guaranteed slots for the strongest continuity candidates (the session your last message went to, the latest
and second-latest finished) and the best BM25 match when they are not already in, deduplicated by session; or a
regularised ranker fitted on hit@4 (a RAPS-style "fill until the calibrated mass is covered, penalise the tail" rule
for choosing what goes in).

**Why here.** Misses cost ≈ 36 per 100 submits, a quarter of the loss, and the target is missing from 11–21% of real
asks. The dev first-submit ranks say the latest three finished sessions plus the last-told one cover most targets
(50 + 17 + 7% by finish rank, and 53% continuity), so a slot rule should close much of the gap without touching sends.

**Cheapest experiment.** On the cached dev baseline, freeze the moments the shipped policy asks, and score three slates
on exactly the four rendered options: current, reciprocal-rank fusion of (fused P, BM25, finish rank, last-told), and a
grouped-CV ranker. No Jev call.

**Metric / kill.** Ask loss and hit@4 on real asks; kill under +3 points hit@4 or if any same/switch/new slice loses
more than it gains **[Sol]**.

**Cost.** 0 Jev calls, microseconds.

**Tried?** The four-option card shipped (round 3) and explore/selective.py measured top-k recall of fused vs Jev vs
recency vs one blend; a slate optimised for membership was not built. **Sources:** conformal sets with a size penalty,
[RAPS, Angelopoulos et al. 2020](https://arxiv.org/abs/2009.14193); asking with a calibrated option set,
[KnowNo, Ren et al. 2023](https://arxiv.org/abs/2307.01928); shortlist/rerank split of recall and precision,
[Kim et al. 2018 (HypRank)](https://arxiv.org/abs/1804.08064).

### A2. One cost-aware send/ask selector, by path and destination type — rank 2

**Idea.** Keep the destination model; learn P(the proposed action is right) with out-of-fold predictions and
features of *how* the send was reached (rules path vs fused path, which rule, destination type session / new /
intent, length, short-reply), then act only where 25·(1−p) < expected ask cost (1 + 3·P(card misses)). This replaces
the fixed `rulesSure` 0.6 / `sure` 0.9 / `shortSure` 0.95 bars, which were chosen against right − λ·wrong, not this
loss, and calibrates the two paths separately.

**Why here.** The paths are different populations: in round 3 the rules path made 24 of 25 real wrong sends while the
fused pick at 0.9 was right 78 of 79 **[Sol]**; 5 of 6 realB wrong sends went to a labeller's alternative (soft
wrong), so some are recoverable by a tighter bar on a narrow path rather than globally. Wrong sends are ≈ 45% of the
loss. Making the ask cost depend on the card's predicted hit (A1) also means the selector asks less where the card is
likely to miss, which is correct under the loss.

**Cheapest experiment.** Offline on the cached dev baseline: (a) list every dev real wrong send with its path, rule,
destination type and fused sureness (counts only); (b) fit the selector in grouped folds and compare against the
shipped bars with a tiny fixed grid. Report the precision of *newly accepted* and *newly refused* sends.

**Metric / kill.** Δloss (real_only); kill if marginal new sends fall under the 96% / 92% break-even, or if no setting
lowers wrong sends without raising loss.

**Cost.** 0 Jev calls.

**Tried?** Partly: risk–coverage and Learn-then-Test (round 3) showed a ≤ 5% wrong-send guarantee isn't certifiable at
useful coverage, and the rules guard shipped. New: optimise the actual click loss with per-path calibration and a
card-aware ask cost, not a coverage bar. Avoid claiming a guarantee: groups are correlated and shifted.
**Sources:** [Mozannar & Sontag 2020, learning to defer](https://arxiv.org/abs/2006.01862) (cost-sensitive
reduction); [Geifman & El-Yaniv 2017](https://arxiv.org/abs/1705.08500); [Conformal risk control](https://arxiv.org/abs/2208.02814)
for controlling an expected loss rather than coverage; [Kamath et al. 2020](https://aclanthology.org/2020.acl-main.503/)
(selective answers calibrated in-domain over-send under shift: calibrate on real only).

### A3. Use the Jev signals already paid for — rank 3

**Idea.** Three free features for the sureness logistic and the selector: (1) Jev's own `confidence` on the route
choice, which TypeSafe returns and the cache stores but nothing reads (only the Haiku cascade read a confidence);
(2) route entropy and the margin between the top two *sessions* (not only the fused gap); (3) mass split between
options that are the same session family: when two options share a title (the `'` suffix in `unique()`) Jev's
probability splits between them, as merged session+card options did in round 1 (+18 points when merged). Sum their mass
for the "is it this title" question, then let recency/BM25 choose between them; or name siblings apart in their
criteria.

**Why here.** TypeSafe documents confidence as distinct from probability and meant for "whether to act". The fused
sureness was fitted without it. Same-title siblings are on 171 of 216 dev boards and hold the target in 22 episodes,
the exact case where split mass forces an ask.

**Cheapest experiment.** Read `confidence` from the cached dev answers; add (1)+(2) to the sureness refit in grouped
folds; for (3), count dev asks whose top two are same-title siblings and rescore with merged mass.

**Metric / kill.** Δloss and wrong/sends; kill if the selector's AUC for "right when sent" moves < 0.01 and Δloss
interval includes 0.

**Cost.** 0 Jev calls.

**Tried?** Not documented. Different from the round-1 merge (session + its card) and from the content-free calibration
dead end (which divided out a bias; this adds Jev's own uncertainty). **Sources:**
[TypeSafe docs](https://docs.typesafe.ai/llms.txt) (confidence vs probability);
[Guo et al. 2017](https://arxiv.org/abs/1706.04599) (post-hoc calibration on a held-out set).

### A4. Keep BM25's absolute strength — rank 4

**Idea.** `RouterLexical.scores` divides each session's BM25 by the best session's, so the top lexical match is 1.0 even
when it shares one weak word. Add raw strength: the best raw score, the share of the message's informative tokens
matched, and the gap between the best and second session, first into the selector (A2), then into the destination
model **[Sol]**.

**Why here.** BM25 alone names the real follow-up 54% of the time (Jev 40–48%), and its fields carry three of the
largest fusion weights (+1.11, +1.36, −0.84): a feature that strong is miscalibrated when weak and strong matches look
the same.

**Cheapest experiment.** Recompute lexical fields on dev boards (local, no Jev), add ≤ 4 features, grouped CV; add an
"irrelevant session" metamorphic check (`v2.run.metamorphic`) because the ratio depends on the board.

**Metric / kill.** Δloss, wrong sends on low-overlap messages, hit@4; kill without a positive out-of-fold Δloss or if
metamorphic flips rise.

**Cost.** 0 Jev, milliseconds.

**Tried?** Round 3 varied windows, user/assistant turns, stemming, stop words and IDF (all within 3 points); the
normalisation was not varied. **Sources:** [Carvalho & Cohen 2008](http://www.cs.cmu.edu/~vitor/papers/ecir2008.pdf)
(recipient prediction from text), [Robertson & Zaragoza 2009, BM25](https://www.staff.city.ac.uk/~sbrp622/papers/foundations_bm25_review.pdf).

### A5. Continuity: always check the last-told session, add transition features — rank 5

**Idea.** The "is it your next message in this conversation?" noul is asked for the three latest *finished* sessions
(`nextLatest = 3`), so the session your last message went to gets no check when it is running, waiting on an approval,
or ranked 4th or lower. Ask it for the last-told session too (one more noul in the same call), and add code-side
transition features: finished since your previous message, finish rank excluding the previous destination, already
waiting before it **[Sol]**, and `told0` × short message.

**Why here.** 53% of dev real submits continue the previous destination, while `told0` weighs only 0.72 against
`fin1` 1.16; 72% of switches go to a backlog session that had already finished, so the newest finish isn't enough.
Dialogue-state work treats carry-over from the previous turn as its own decision, not a by-product of ranking.

**Cheapest experiment.** A new format name (`combo-o-told`) with the extra noul on dev real moments (≈ 400 calls, cents),
plus the transition features in grouped CV; score teacher-forced and free-running (`v2.run.episodes` replays actual
decisions into history).

**Metric / kill.** Δloss, same/switch slices; kill if the gain disappears in free-running replay or the switch slice
worsens.

**Cost.** +1 noul in the existing call (parallel inside the call: ~0 latency, +~5% tokens).

**Tried?** Round 2 added the next-message check for the 3 latest and `told0`; message-type × state features were
noise; a state field naming the last-finished session was obeyed as an instruction (rejected: keep these facts in code,
never in Jev's state). New: the last-told session is checked whatever its rank. **Sources:**
[Naik et al. 2018, contextual carryover](https://arxiv.org/abs/1806.01773);
[Kummerfeld et al. 2019, disentanglement](https://aclanthology.org/P19-1374/);
[Anderson et al. 2014, repeat consumption is recency-driven](https://doi.org/10.1145/2566486.2568018);
[TIAGE, topic-shift detection](https://arxiv.org/abs/2109.04562) (κ 0.48: switch detection is itself ambiguous).

### A6. Refit the fusion on real dev moments, real-weighted — rank 8

**Idea.** The shipped weights were fitted on realA + synth + styleA. Refit on v2 dev, real-dominant (written episodes
as small-weight stress, contracts as hard constraints), strongly regularised toward the shipped weights, with the
click loss (or a cost-weighted likelihood) rather than plain NLL.

**Why here.** Written episodes continue the same session 26% of the time against 52% real and are told apart at AUC
0.90; a mixed fit learns a switch-heavy prior. Calibration fitted in one distribution doesn't transfer under shift.

**Cheapest experiment.** Three frozen source weightings (shipped / real-only / 80-20) in grouped CV on dev; hold the
selector fixed.

**Metric / kill.** real_only Δloss, slice table, contracts 100%; kill if the gain exists only on written episodes or
needs breaking an intent boundary.

**Cost.** 0 Jev.

**Tried?** Partly: personal.py refits by MAP per user; the global real-only refit with episodes was not. **Sources:**
[Ovadia et al. 2019](https://arxiv.org/abs/1906.02530); [Kamath et al. 2020](https://aclanthology.org/2020.acl-main.503/).

### A7. Live predictions bound to the board they were read on — rank 11

**Idea.** A pick read while typing is reused at send for 120 s keyed on the text and pills only; it is dropped when its
target is gone or after a correction, but not when the board changed (a card arrived, another session finished, your
previous message went elsewhere). Key it on a board revision (cards, finish order, last-told) too **[Sol]**.

**Why here.** A stale sure pick is sent without a fresh read: a wrong send at 25 with no fusion check. Users type for a
median of ~2 minutes between messages while 2 sessions run, so the board often changes in that window.

**Cheapest experiment.** In dev episodes, count submits preceded by a board event within 120 s whose shipped decision
differs between the pre-event and post-event board (cached answers + a few new calls).

**Metric / kill.** Number of decisions that change; kill (keep only target-gone invalidation) if under 1% of submits
change and none is a wrong send.

**Cost.** +1 call (~0.25 s) only on invalidated reuse.

**Tried?** No. **Sources:** none needed; it is a cache-coherence check.

### A8. Lexical turn boundary for running sessions — rank 13

**Idea.** While a session works, `RouterLexical.turns` blanks its latest answer, so its last *completed* answer only
counts in `f_old` (decayed) **[Sol]**. Keep the last completed answer in `f_said` for running sessions, and check that
transcript and board fallbacks cut turns at the same place.

**Why here.** 82% of messages are typed while another session runs; the assistant's turns carry the lexical evidence.
Matters more once running targets exist (B6).

**Experiment / kill / cost.** Recompute fields on dev, compare on running-board and multi-submit slices; kill without
a ranking gain. 0 Jev.

**Tried?** Context windows were varied (noise); the boundary was not.

### A9. Shortlist then rerank — rank 16

**Idea.** Send Jev only the top ~8 sessions by a recall-tuned prior (finish rank, last-told, BM25, cards waiting) plus
new-session and intents, and let the fusion rerank. Fewer options means less first-option and long-list dilution and
fewer tokens per call (most of the cost is while-typing calls).

**Why here.** Boards hold a median of 21 sessions in dev; Jev's known weak spots include long irrelevant state and
first-option bias.

**Experiment / kill.** Shortlist recall on dev first (must be ≥ 98% of targets within the 8), then a new format name on
dev; kill if Δloss ≥ 0 or recall < 98%. Cost: same calls, ~40–60% fewer input tokens.

**Tried?** Round 2 "fewer options (only the last N hours): no gain". Different now: the cut is by a recall-tuned prior,
not by time, and the main gain sought is tokens with no loss. **Sources:**
[HypRank shortlister/reranker](https://arxiv.org/abs/1804.08064); [Lost in the middle](https://arxiv.org/abs/2307.03172).

### A10. Short replies after a report — rank 17

**Idea.** Messages under 3 words are sent by the fused path only when the session's last message asks or proposes
something. Look at the cohort refused *only* by that condition after a report or a finish **[Sol]**.

**Why here.** Terse replies follow plain reports 28% and finishes 19% of the time. Dev has only 19 one-to-two-word
submits, so this is small.

**Experiment / kill.** Count and precision of that cohort at sureness ≥ 0.95; kill if under 96% or under ~10 cases.
0 Jev. **Tried?** The short-reply rule shipped in round 3; this tests one excluded cohort only.

### A11. One on-device embedding feature — rank 21

**Idea.** A sentence-embedding similarity between the message and each session's last completed answers (Apple's
NLContextualEmbedding, mean-pooled; local, no data leaves the machine), as one feature, first for the ask card.

**Why here.** BM25 misses paraphrase; nobody has measured how much of its 46% miss is paraphrase vs missing context, so
measure that first on lexical-disagreement cases.

**Kill.** < +3 points hit@4 or > 30 ms warm **[Sol]**. 0 Jev. **Tried?** No dense feature tried; the Haiku cascade
(different: a bigger model) was a dead end. **Sources:** [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding),
[Sentence-BERT](https://arxiv.org/abs/1908.10084).

### A12. Two wordings of the route question in one call — rank 22

**Idea.** Ask the route twice in the same call with differently worded instructions (not a different option order),
average log-probabilities. Questions in one call run in parallel, so no latency.

**Why here / honesty.** Self-consistency helps big models; here the order-averaging variant was a dead end and a fixed
order already removed variance. Only worth a half-day check because it costs no latency.

**Kill.** Δloss interval includes 0 → stop. Cost: ~2× route tokens. **Sources:** [Wang et al. 2022](https://arxiv.org/abs/2203.11171).
**Tried?** Order permutation averaging: dead end (round 3). Wording ensembles: not tried.

## B. Needs real traffic logs

### B1. Decision traces with outcomes — rank 9

**Idea.** Log per decision (locally, like `real/data`): the redacted request, board revision, raw Jev answers incl.
confidence, BM25 fields, fused P, path, rendered card, shown chip, action, and the outcome (kept, corrected to X,
pick, dismissed, retyped within N s, undone). This is open lead 3; it turns corrections and picks into labelled Router
traffic, the only data free of the in-session proxy.

**Experiment.** Reconstruct trace records from a dev replay and check decision parity against the Swift fixture;
reject a design under 99% completeness **[Sol]**. Δloss directly: 0; it gates B2–B7. Cost 0 Jev.

**Note.** A deterministic logger gives no propensities: "would B have sent it elsewhere?" is only answerable where
the true destination is revealed (picks, corrections), which is full information there; kept sends are weak positives
to audit by sampling. **Sources:** [Dudík et al. 2011](https://arxiv.org/abs/1103.4601),
[Kossen et al. 2021, active testing](https://arxiv.org/abs/2103.05331).

### B2. Per-user refit from observable labels — rank 10

**Idea.** MAP refit of a few fusion weights around the global prior after ~50 verified labels (picks, corrections,
explicit addresses), in the background.

**Why here.** The strongest unshipped positive: late real wrong sends 4.5% → 2.3% in a time-ordered replay. But that
replay used an older guard and treated every past destination as known **[Sol]**.

**Cheapest experiment now.** Re-run explore/personal.py's replay on dev real moments with labels limited to what the
current policy would reveal (asks answered, wrong sends corrected), against the optimistic replay. Kill if the effect
disappears under observable labels. 0 Jev.

**Tried?** Yes, promising; kNN and per-user thresholds added nothing. **Sources:**
[Aberdeen et al. 2010, Priority Inbox](https://research.google.com/pubs/archive/36955.pdf);
[Kim et al. 2018, personalised domain classification](https://aclanthology.org/P18-1206/).

### B3. Implicit-feedback defect detection — rank 14

**Idea.** Detect failed routes from behaviour: a pick that differs from the suggestion, a quick correction or re-send of
similar words elsewhere, an undo (C1), an interrupt of the receiving session within seconds. Use these as labels for
B2 and as a monitored defect rate.

**Why here.** Corrections are under-reported; Alexa's production self-learning works from exactly such friction
signals, with a guardrail test before trusting a learned fix.

**Experiment.** Needs B1; offline, simulate on dev correction episodes (`on.wrong` branches) that the detector fires.
**Sources:** [Ponnusamy et al. 2020](https://arxiv.org/abs/1911.02557).

### B4. Randomise positions 2–4 on the ask card — rank 18

**Idea.** Shuffle the card's lower three options on a small share of asks and log positions, so picks become unbiased
labels for A1's ranker and B2 (position bias in clicks).

**Cost / risk.** None on sends; the first option stays. **Sources:**
[Joachims et al. 2017, unbiased LTR](https://arxiv.org/abs/1608.04468);
[Swaminathan & Joachims 2015, CRM](https://arxiv.org/abs/1502.02362).

### B5. Online bar adaptation under drift — rank 19

**Idea.** Track wrong/sends prequentially on revealed labels and nudge the selector's bar (one parameter) to hold a
target, as adaptive conformal inference does for coverage.

**Why here.** Real use will drift from the in-session proxy (new projects, phrasing aimed at the Router); fixed bars
over-send under shift. **Sources:** [Gibbs & Candès 2021](https://arxiv.org/abs/2106.00170).

### B6. Running and queued targets — rank 20

**Idea.** The extraction never has a running gold (0 of 550), yet the fusion carries `run` −1.26 learned from that.
Collect native messages to working sessions and refit that weight conservatively.

**Kill.** If refitting moves ordinary follow-ups to working distractors **[Sol]**.

### B7. Soft evidence from the card you just opened — rank 23

**Idea.** A decaying feature for the card or session the user opened or read just before typing (not an armed reply).
Needs native logging to tell deliberate selection from passive visibility **[Sol]**. Only 11% of continuations name a
project, so the UI may hold the missing address.

## C. Product changes that change the loss

### C1. Hold before delivery (undo window) — rank 6

**Idea.** A Router send is held 3–5 s (Gmail's default is 5 s, up to 30) with the destination shown and Esc / a click
to cancel or retarget; the original bytes are kept. Consequential paths (approvals) keep their own gate.

**Why here.** Wrong sends are ≈ 45% of the loss. If a share q of them is caught at ~2–3 clicks, the wrong term falls by
≈ q × 0.9; at q = 0.5 that is −30 per 100, and the break-even send bar falls from 96%, which then makes coverage pay.
Horvitz's principles name it: "minimize the cost of poor guesses" with timeouts and easy rejection.

**Cheapest experiment.** First a blind check: on dev real wrong sends of the baseline, render the destination line the
user would see and count how many name a session the user would recognise as wrong (proxy for q, by the user on ~30
cases). Then a pilot measuring cancellations and added latency.

**Metric / kill.** Intercepted wrong sends / all wrong sends; kill under 30% interception or if delivery delay costs
more than it saves **[Sol]**. Keep scoring post-delivery wrong sends at 25 until observed recovery data justify a new
cost.

**Cost.** 0 Jev; +3–5 s to delivery (not to the user's typing). **Sources:**
[Horvitz 1999](https://erichorvitz.com/chi99horvitz.pdf); Gmail Undo Send (delayed dispatch, 5–30 s, a product
pattern, no peer-reviewed study found).

### C2. Keyboard-first ask card — rank 7

**Idea.** Number keys 1–4 and Return for the first option; distinguishing context on same-title siblings (171 of 216
dev boards have them). Typed text stays its own message, so selection must be a distinct key action.

**Why here.** The card appears on ~56% of real moments; a one-keystroke pick is cheaper than a pointer click, and the
fixed scorer can't see that, so measure time per pick **[Sol]**. If the first option is right in a large share of
asks (hit@1 among asks, measurable on dev), Return-to-accept makes many asks near-free.

**Experiment / kill.** Dev: hit@1 among asks, and count of visually indistinguishable buttons; then timed blind picks.
Kill under 20% time reduction or any rise in mis-picks.

### C3. The shown prediction as the ask — rank 12

**Idea.** The composer already shows a sure pick while typing and a send with it shown counts as confirmed. Widen it:
always show the best guess (marked unsure below the bar), so sending with an unsure chip is a confirmation and Esc /
a click picks another before sending. The ask moves before the send and costs 0 when the guess is right.

**Why here.** Live predictions are already most of Jev's calls (≈ 5 calls per message), so this spends nothing new.
The risk is habituation (users send without looking), which turns a confirmed chip into an unexamined wrong send.

**Experiment / kill.** Offline: hit@1 at the moments that ask (the share that would become 0-click). Pilot: kill if
confirmed-then-corrected sends exceed the wrong-send rate of the automatic path. **Sources:**
[Horvitz 1999](https://erichorvitz.com/chi99horvitz.pdf) (graceful degradation of service precision under uncertainty).

### C4. An explicit "continue with X" after a send or pick — rank 15

**Idea.** After a delivery or a pick, offer a visible one-key way to arm the next draft for the same session. Not an
automatic sticky default: 42% of real messages switch **[Sol]**.

**Experiment / kill.** On dev, count asks inside confirmed same-session chains (the opportunity); kill if under 10%
of asks.

## Not re-proposed (dead ends in the history, still dead)

Content-free contextual calibration; averaging option orders; a state field naming the last-finished session (Jev
obeys it); categorical recency words / a `latest` flag; richer per-option context; per-session yes/no instead of one
choice; a second verification call; a Haiku cascade on the asks; identifiers alone; examples of past routings in the
state; more rules in the instruction text. None gains a new justification from v2 alone **[Sol]**.

## First six experiments, and what can run in parallel

0. **Dev baseline** (prerequisite, ~1 h): run shipped / always-ask / recency-only / lexical-only on dev with enough call
   budget; merge provisional ask labels when ready. Touches only `v2/run/results/` and `v2/run/cache/`.
1. **A1 ask slate** — new module `explore/slate.py` (ask ordering only).
2. **A2 selector + wrong-send forensics** — new module `explore/selector.py`; consumes A3/A4 features when ready
   (re-run, don't wait).
3. **A3 free Jev signals** — new module `explore/jevsignals.py` (reads cached answers).
4. **A4 BM25 strength** — new module `explore/lexstrength.py` (wraps the lexical fields; no edit to `RouterLexical`
   during exploration).
5. **A5 continuity** — new format name in `explore/continuity.py` (+1 noul, ≈ 400 new Jev calls on dev).
6. **C1 undo window, blind interception check** — reads the baseline's wrong sends only; no router code.

Parallel: after experiment 0, **1, 3, 4, 5 and 6 can run at once**: each is its own module under `explore/` (or none),
none edits `v2/run/*.py`, `formats.py`, `run.py` or the Swift; 5 is the only one that calls Jev, under its own format
name and cache keys. **2 runs alongside** with today's features and is re-run once 3 and 4 report. Ports to Swift
(`RouterRoute.swift`: features, weights, selector; `RouterDispatcher.swift`: card order) are sequential, one winner at
a time, each with `parity.py` and `RouterFusionParityTests` rebuilt; A7 (`RouterDispatcher` live cache) and A8
(`RouterLexical` turns) touch different Swift files and can be ported independently of the fusion changes.
