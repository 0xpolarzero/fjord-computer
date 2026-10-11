# Evaluating the Router: methodology from the literature (2026-10-11)

What the literature says about evaluating a router like ours (addressee + intent classification with an abstain/ask
option, over a changing board) and about building test sets that look like real use, and exactly how each idea maps
onto `evals/router/`. Read with docs/design/router-research.md (rounds 1–3) in mind: our central lesson, "written cases
mislead", is the same finding the user-simulation literature now calls the *Sim2Real gap*.

Where we stand, in those terms: one frozen-ish real set (611 in-session moments, strict single gold, agent labels), two
written sets (360, merged double labels), one style set (332). Metrics are right/wrong sends at a fixed operating
point, bootstrap CIs of ±5–7 points. Gaps: no Router-native traffic, no multi-turn episodes, no slices, no invariance
tests, the real set reused for every round's decisions, no paired tests, no cost-weighted utility, no per-session
clustering in the CIs.

---

## 1. User simulation and the Sim2Real gap

**Method.** Two families. *Agenda-based* simulators (Schatzmann et al. 2007, [N07-2038](https://aclanthology.org/N07-2038/))
keep an explicit goal/agenda stack and emit dialogue acts; controllable, but stilted surface text. *LLM user simulators*
role-play a persona and goal (τ-bench, Yao et al. 2024, [2406.12045](https://arxiv.org/abs/2406.12045); τ²-bench
[2506.07982](https://arxiv.org/abs/2506.07982)), giving fluent text and multi-turn behaviour.

**Evidence on validity.** Zhou et al. 2026, "Mind the Sim2Real Gap" ([2603.11245](https://arxiv.org/abs/2603.11245)):
31 LLM simulators vs 451 humans on τ-bench. Simulators are "excessively cooperative, stylistically uniform"; humans use
short turns ("Okay", "Sure") and show frustration; agent success was 77.8% with the best simulator vs 63.6% with humans
(simulators are *easy mode*). "Real or Robotic?" ([2409.08330](https://arxiv.org/abs/2409.08330)): LLMs match meaning
better than style, length and dynamics. realsim ([2605.02624](https://arxiv.org/abs/2605.02624)) argues for
*distribution-level* comparison over 8 dimensions (intent, feedback, emotion, knowledge, personal context, length,
linguistic features, errors) rather than per-dialogue realism judgments. ConvApparel
([Google](https://research.google/blog/convapparel-measuring-and-bridging-the-realism-gap-in-user-simulators/)) adds
*counterfactual validation*: check that the simulator reacts to a bad agent the way humans do. CRAB-Bench
([2606.01815](https://arxiv.org/abs/2606.01815)): a more human-like simulator cut pass rates by 38%.

**Apply to us.**
- Our synthetic sets are exactly "easy mode": explicit, addressed, well-formed messages. Never treat a simulator-written
  set as the primary metric; it is a *coverage* set for slices the real data lacks.
- Build simulators **grounded in real data** (ParaStudent-style, [2507.12674](https://arxiv.org/abs/2507.12674)): give the
  generator 20–40 real messages sampled from `real/data` as style exemplars (length, terseness, no address, French
  mixed in, typos), plus the real board, and ask for the *next* message the user would type for a stated goal. Use the
  real board and its card states as the context; vary only the goal.
- Validate realism at the **distribution** level, not per case (section 2): word-count histogram, share under 3 words,
  share with a session/project name, share of questions, imperative verbs, language mix, typo rate, referring
  expressions ("it", "that", "the other one"). Our real numbers are the target.
- Counterfactual validation for follow-ups: when the Router asks or misroutes, does the simulated user react the way
  real users do (correct with a pill, resend shorter, say "no, the other one")? Seed this from `corrected_from` once
  logs exist (section 9).

## 2. Synthetic test sets: generation and realism checks

**Evidence.** Using the same model family to write and solve the test inflates scores for smaller models
(Maheshwari et al., "Efficacy of Synthetic Data as a Benchmark", [2409.11968](https://arxiv.org/abs/2409.11968)); they
find synthetic data tracks method rankings on *simple* tasks like intent classification but not harder ones, and
recommend multiple large generators. Multi-source generation reduces distribution collapse and self-preference
("Synthetic Eggs in Many Baskets", [2511.01490](https://arxiv.org/abs/2511.01490)). LLM judges favour their own
generations (Panickssery et al. 2024, [2404.13076](https://arxiv.org/abs/2404.13076)). LLM personas skew upbeat and
"too perfect" ([Springer 2026](https://link.springer.com/article/10.1007/s10462-026-11641-3)). Diversity metrics:
Distinct-n, Self-BLEU (Texygen, [1802.01886](https://arxiv.org/abs/1802.01886)); distribution distance: MAUVE
([2102.01454](https://arxiv.org/abs/2102.01454)); and the strongest simple test, the **classifier two-sample test**
(Lopez-Paz & Oquab, [1610.06545](https://arxiv.org/abs/1610.06545)): if a classifier can tell synthetic from real
better than chance, they differ, and its features tell you how.

**Apply to us.**
- **Generator mix**: write cases with at least three families (Claude, GPT via codex, Gemini), tag each case with its
  generator, and report results per generator. A gap between generators is a realism warning. Jev is a separate model,
  so self-preference is less direct, but the *labelers* are LLMs too: never let the generator family label its own cases.
- **Realism gate** before a synthetic set counts: (a) a two-sample test, a logistic regression on cheap features
  (length, punctuation, names mentioned, pronouns, question mark, first word) real-vs-synthetic; AUC near 0.5 passes,
  and the top coefficients say what to fix in the prompt; (b) matched histograms of the features above; (c) Self-BLEU /
  distinct-2 against the real set's own values (too diverse is as wrong as too uniform); (d) a 30-case human spot check
  by the user, blind-mixed with real messages: "which ones did you write?" If he can't tell, it passes.
- **Board realism too**: the states matter as much as the text. Sample boards from the real reconstructions (session
  counts, share of `done` cards, several sessions per project, idle-time distribution) rather than writing them.
- **Rank-agreement check**: a synthetic set is useful if it ranks *our variants* the same way the real set does. Keep
  the round 1–3 variants' cached answers; a new synthetic set must reproduce the known ordering (round 1 < round 3 on
  real wrong sends) before it is trusted to judge new ones. This is the cheapest validity test we have.

## 3. Annotation: multiple labels, agreement, soft gold

**Evidence.** Agreement must be measured with chance-corrected coefficients (Cohen/Fleiss κ, Krippendorff α; Artstein &
Poesio 2008, [J08-4004](https://aclanthology.org/J08-4004/)). Plank 2022 ([2211.02570](https://arxiv.org/abs/2211.02570))
argues that disagreement is often signal, not noise; evaluate against the label *distribution* where items are
genuinely ambiguous. The follow-up empirical study ([CL 2025](https://direct.mit.edu/coli/article/52/1/85/133833/Training-and-Evaluating-with-Human-Label-Variation))
finds JSD-based metrics and soft micro-F1 the most reliable. ClariQ ([2009.11352](https://arxiv.org/abs/2009.11352))
labels *clarification need* on a 1–4 scale, the right shape for our `ask_ok`.

**Apply to us.**
- Our gold is already set-valued (`to` list + `ask_ok`); make it **graded**: per case, k = 3 independent labelers from
  different model families plus the user on a sample, each giving a destination and a 1–4 "how sure would a careful
  human be". Store all labels (disaggregated), not only the merge.
- Report κ / α between labelers per slice. Low-agreement items are the "ambiguous" slice: on those, asking is correct
  and sending to any labeler's choice is acceptable, so they should not count against the router's wrong-send rate the
  same way.
- Score against the distribution: the cost of a send = share of labelers who reject that destination; the cost of an
  ask = share who say it was obvious. This replaces the arbitrary "either labeler accepts" merge with a quantity.
- **Adjudication**: items where the user's real destination (in `real/`) disagrees with all labelers go to the user
  for a 10-second look. Those are the most informative items in the whole benchmark.
- **Prediction-powered inference** (Angelopoulos et al. 2023, [2301.09633](https://arxiv.org/abs/2301.09633)): combine
  many agent labels with a small set of user labels to get unbiased estimates with valid CIs, correcting the agent
  labelers' bias. Ideal for us: agents label hundreds, the user labels ~50.

## 4. Selective prediction: the right metrics for send-or-ask

**Evidence.** Risk–coverage curves and AURC (Geifman & El-Yaniv 2017; [SelectiveNet](https://arxiv.org/abs/1901.09192)).
Traub et al. 2024 ([2407.01032](https://arxiv.org/abs/2407.01032)) show AURC is non-monotonic and over-weights a few
confident failures; they propose **AUGRC** (area under *generalized* risk = P(accepted and wrong)), which is exactly our
"wrong sends as a share of all messages". Kamath et al. 2020 ([acl-main.503](https://aclanthology.org/2020.acl-main.503/))
show selective QA calibrated in-domain over-sends under shift: tune on one distribution, judge on another. Learn-then-Test
([2110.01052](https://arxiv.org/abs/2110.01052)) gives threshold choices with finite-sample risk guarantees.

**Apply to us.**
- Keep the operating-point metrics (right / wrong / needless ask) but add one **cost-weighted utility** fixed in advance,
  e.g. U = right − λ·wrong − μ·needless ask, with λ ≈ 5–10, μ ≈ 0.5 (ask the user once to set λ: "how many clicks is one
  misrouted message worth?"). Report U with CIs; it settles "fewer wrong but fewer right" debates without hand-waving.
- Plot **generalized risk vs coverage** (wrong-send share vs send share) per set and report AUGRC alongside; compare
  variants by the whole curve, not one threshold, so a change that only moves the threshold is not mistaken for a gain.
- Split errors by *destination type*: wrong session, wrong to Lookout's own (question/change/compound), wrong new-session
  project. They cost differently; a router that converts session errors into Lookout-intent errors may look flat on
  "wrong" while being better or worse.
- Thresholds are tuned on realA and checked on realB (already done); add the Kamath lesson explicitly: always report the
  same thresholds on a *shifted* set (Router-native traffic once logged; the style set until then).

## 5. Statistics: CIs and comparing two routers

**Evidence.** Miller 2024, "Adding Error Bars to Evals" ([2411.00640](https://arxiv.org/abs/2411.00640)): treat cases as a
sample, use **clustered** standard errors when items share a source, and **pair** comparisons (same items, analyze
per-item differences) to shrink variance; plan sample sizes with power analysis. Dror et al. 2018
([P18-1128](https://aclanthology.org/P18-1128/)) for test choice; Koehn 2004 paired bootstrap
([W04-3250](https://aclanthology.org/W04-3250/)); McNemar's test for two classifiers on the same items (Dietterich 1998).
Card et al. 2020 ([emnlp-main.745](https://aclanthology.org/2020.emnlp-main.745/)): most NLP comparisons are underpowered.

**Apply to us.**
- Our "±5–7, differences under 5 are noise" is an *unpaired* figure. Two variants on the same 611 moments differ on
  only a few dozen items; a **paired** bootstrap / McNemar on the discordant items detects 2–3-point effects that the
  unpaired CI hides. Report, for every comparison: discordant counts (A right & B wrong, the reverse), McNemar p, and a
  paired-bootstrap CI on the difference in U.
- **Cluster by session and by day**: the 611 real moments come from far fewer sessions; consecutive moments in one
  session are correlated. Resample sessions (cluster bootstrap), not moments. Expect wider, more honest CIs.
- **Power plan**: to detect a 2-point change in wrong sends at a 4% base rate with paired data needs on the order of
  1,000–1,500 items with typical discordance; write that into the plan for the next real set size.

## 6. Overfitting to the benchmark

**Evidence.** Repeatedly selecting on one holdout overfits it (Dwork et al. 2015, "The reusable holdout",
[Science](https://www.science.org/doi/10.1126/science.aaa9375), [1506.02629](https://arxiv.org/abs/1506.02629)). The
Ladder (Blum & Hardt 2015, [1502.04585](https://arxiv.org/abs/1502.04585)) only reports a new score when it beats the
best by a margin, rounding otherwise, which bounds leakage. Yet empirical studies find less adaptive overfitting than
feared on large sets (Roelofs et al. 2019, [meta-analysis](https://dl.acm.org/doi/10.5555/3454287.3455110)); the
bigger danger is distribution shift between a re-collected test set and the original (Recht et al.,
[1902.10811](https://arxiv.org/abs/1902.10811)).

**Apply to us.** Our sets are small (150–611) and have been used for dozens of decisions across three rounds: that is
the regime where adaptive overfitting is real.
- **Three tiers**: *dev* (everything existing: synth, realA, style; free to sweep), *validation* (realB and heldout;
  report through a Ladder-style gate: a variant only "beats" the best if U improves by more than the paired CI margin,
  otherwise the reported number is the old one), and a **sealed test** collected fresh (new real moments since 2026-10-11
  and the first Router-native logs), hashed and committed, read *once per round* for the final shipped config.
- Log every evaluation call on validation/test (variant, date, set) in a ledger; the count of looks is part of the result.
- Refresh: each round, move the sealed test into validation and collect a new one. Real moments accrue daily, so this is
  cheap.

## 7. Behavioral tests: slices, invariance, directional expectations

**Evidence.** CheckList (Ribeiro et al. 2020, [acl-main.442](https://aclanthology.org/2020.acl-main.442/)): test
capabilities with Minimum Functionality Tests (simple must-pass cases), **INV**ariance (perturbations that must not
change the output) and **DIR**ectional tests (perturbations that must move it a known way); it found many bugs in
models with high held-out accuracy. Contrast sets (Gardner et al. 2020,
[findings-emnlp.117](https://aclanthology.org/2020.findings-emnlp.117/)): minimal edits that flip the gold. Metamorphic
testing ([Chen et al. survey](https://dl.acm.org/doi/10.1145/3143561)). Prompt-format sensitivity (Sclar et al.,
[2310.11324](https://arxiv.org/abs/2310.11324)) and option-order bias (our round-1/2 finding) are the LLM-specific cases.

**Apply to us.** This is the largest gap and cheap to build from the real boards, with no new labels needed for INV:
- **Slices** (tag every case, report U per slice): message length (1–2 words / 3–8 / longer); addressed vs unaddressed;
  reply to a waiting card vs new work vs Lookout intent; number of waiting cards (0/1/2+); same-project siblings (0/1/3+);
  board size (≤5 / 6–15 / 16+); the target's recency rank (1st, 2nd, older); running target; language (EN/FR/mixed);
  identifier present; labeler agreement (high/low). A slice with fewer than ~30 cases is reported as counts, not %.
- **INV tests** (output must not change): option order shuffles (Lookout order vs others, measured as flip rate); adding
  an irrelevant idle session from another project; renaming irrelevant sessions; whitespace/case/punctuation and typo
  noise on the message; EN↔FR translation of the message; idle times scaled ×2 for all sessions (relative order intact);
  redaction placeholders swapped.
- **DIR tests** (output must move): add "@project" → must go there; mark the target's card as resolved → a bare "yes"
  must ask; make a second session ask a yes/no too → "yes" must ask; move recency (another session finishes after the
  target) → a short reply's sureness must drop; add "in a new session" → `new:`; prefix "in Lookout, " → intent.
- **Contrast pairs** from real cases: minimally edit the message or one card so gold flips ("commit it" with the
  committer's card waiting vs resolved). Report *pair accuracy* (both right), which punishes reliance on spurious cues.
- **MFTs** for rules: pinned target, armed reply, pills, "tell X to …": 100% expected, run on every commit
  (fits the parity tests already in Swift).

## 8. Episodic, multi-turn evaluation

**Evidence.** τ-bench's **pass^k** (all k trials succeed) exposes unreliability hidden by single-trial averages
([2406.12045](https://arxiv.org/abs/2406.12045)). Dialogue state tracking work (MultiWOZ, DSTC) evaluates turns *in
context*, where earlier errors condition later ones; the Sim2Real paper shows binary end-rewards miss what users
perceive. Disentanglement evaluation (Kummerfeld et al. 2019, [P19-1374](https://aclanthology.org/P19-1374/)) scores
whole threads, not single links.

**Apply to us.** Real Router use is sequences: a burst of messages across sessions, an ask-back answered, a correction,
a follow-up to the session just addressed, cards appearing between messages.
- Build **episodes** from real transcripts: replay a whole hour of the user's activity across sessions, in order, with the
  board evolving (cards open and close, sessions finish) and the Router's own previous decisions fed back as history.
  Two modes: *teacher-forced* (history uses the true destinations; isolates each decision) and *free-running* (history
  uses the Router's own picks; measures error compounding, e.g. a misroute that makes the next "and also…" go wrong too).
- Episode metrics: wrong sends per episode, asks per episode, share of episodes with zero wrong sends (pass^1 analogue),
  and *recovery* (after an ask or correction, is the next related message right?).
- Ask-back is a turn too: score whether the right destination is among the ask card's options (we have this: 79–89%) and
  whether the follow-up after the user's pick routes consistently.
- Use LLM simulators only for the *reactions* (how the user answers an ask, how they correct), seeded from real
  corrections, and validate those reactions distributionally (section 1).

## 9. Evaluating from logs (Router-native traffic)

**Evidence.** Offline replay (Li et al. 2011, [1003.5956](https://arxiv.org/abs/1003.5956)) and IPS / doubly robust
estimators (Dudík et al. 2011, [1103.4601](https://arxiv.org/abs/1103.4601)) evaluate a new policy from logged
decisions, but need the logging policy's propensities; with a **deterministic** logger they cannot value actions never
taken, and DR falls back to a reward model (Narita et al., [2212.01925](https://arxiv.org/abs/2212.01925)). Active
testing (Kossen et al. 2021, [2103.05331](https://arxiv.org/abs/2103.05331)) picks which logged items to label to
estimate accuracy with few labels, without bias.

**Apply to us.** Logs are the only source of the Router's own distribution, and the README's open lead 3.
- Log, per decision: the redacted request sent to Jev (or its hash plus the board snapshot), all fused scores, the action,
  and the outcome signals: kept (no correction within N minutes), corrected (moved to another session, `corrected_from`),
  ask answered (which option), message withdrawn. Keep it local, like `real/data`.
- Our router is deterministic, so classic OPE does not apply to "would variant B have sent this elsewhere?". But
  routing outcomes are **full-information when labelled**: a corrected or ask-answered message reveals the true
  destination, so any variant can be scored on it directly (no propensities needed). Only "kept" sends are partial
  labels (the user may not notice or bother); treat them as weak positives and audit a sample.
- Bias: logs only contain messages the user chose to type in the Router given its past behaviour, and corrections are
  under-reported. Estimate the correction rate on a hand-audited sample and report it.
- Use **active testing** to choose which kept sends the user audits: prioritize those where variants disagree, so each
  label maximally separates candidates.

## 10. Related intent-classification practice

CLINC150 (Larson et al. 2019, [D19-1131](https://aclanthology.org/D19-1131/)) set the norm of evaluating in-scope
accuracy and out-of-scope recall *separately*, with a large OOS test set; our analogue is reporting "should ask" recall
(gold empty or low agreement) separately from send accuracy. Dynabench (Kiela et al. 2021,
[naacl-main.324](https://aclanthology.org/2021.naacl-main.324/)): collect cases adversarially against the current model,
so the test set keeps tracking its weaknesses; for us, an "adversarial writer" agent that sees the router's errors and
writes realistic cases near them, kept in dev only.

---

## The resulting protocol (proposed)

1. **Data tiers**: dev (synth, style, realA, adversarial), validation (realB, heldout, episodes from older days),
   sealed test (fresh real moments + first Router-native logs). Ledger every validation/test look; Ladder-style gate.
2. **New sets**: (a) grounded-simulator Router-style messages on real boards from three generator families, passing the
   two-sample, histogram and user-spot-check gates; (b) CheckList INV/DIR suites and contrast pairs generated
   mechanically from real cases; (c) teacher-forced and free-running episodes from real hours; (d) logs, when they exist.
3. **Labels**: 3 labelers from different families + graded ask-need (1–4), disaggregated; κ/α per slice; user adjudicates
   conflicts with the real destination; PPI to correct agent-label bias with ~50 user labels.
4. **Metrics**: right / wrong (by destination type) / needless ask; cost-weighted U fixed in advance; generalized
   risk–coverage and AUGRC; ask-card contains-gold rate; per-slice table; INV flip rates; DIR pass rates; episode
   zero-wrong share.
5. **Statistics**: session-clustered bootstrap CIs; every comparison paired (discordant counts, McNemar, paired CI on
   ΔU); power planned before collecting.
6. **Decision rule**: ship a variant only if ΔU > 0 with the paired CI excluding 0 on validation, no slice's wrong-send
   rate rises beyond its CI, INV flip rates do not rise, and the sealed test confirms once.
