# Router evals audit (2026-10-11)

Scope: sets `synth` (210), `heldout` (150), `real` (611, realA 397 / realB 214), `style` (332, styleA 150 / styleB 182);
`real/extract.py`, `real/boards.py`, `real/split.py`, `bench.py`, the labels, and Swift's `RouterRoute.destinations`.
All numbers come from Python run over the data on this machine. Scores are for the shipped policy
(`combo-o` + `explore.final3:best`, saved answers). Severity: **S1** can flip a ship decision, **S2** biases a number
in a known direction, **S3** costs precision or coverage.

## Verdict

The real set was the right call and fixed the round-1 illusion. It still measures a proxy, though: **an in-session
continuation task with strict gold, on boards that differ from what Lookout shows**, scored with intervals about twice
as narrow as they should be, on halves that have been read many times. None of the Router's own interaction surface
(ask-back picks, corrections, armed replies, pins, pills, follow-ups after a decision, typing a message while a session
works) is measured anywhere. The headline "realB 40.7 / 2.8" is really **right 29–52%, wrong 0.9–5.4%** (cluster
bootstrap, below), and 5 of its 6 wrong sends went to a session the labeller had listed as also acceptable.

## Threats

| # | threat | sev | evidence | fix |
|---|---|---|---|---|
| 1 | Real moments are not Router traffic | S1 | below | log real Router traffic (T-LOG); simulated-Router set (T-SIM) |
| 2 | A running session is never gold | S1 | 0 of 550 follow-ups; 88% of boards have a running session | mine queued and interrupt messages; write running-target cases |
| 3 | Card kinds come from a regex, not Lookout's triage | S2 | only `done`/`asks`; 17% of `done` texts hold an offer | run RouterTriager's Jev call over the cards |
| 4 | Boards ≠ what Lookout shows | S2 | 8 h window, KEEP filter, ~4 projects vs ≤60 folders, final titles, no summaries | rebuild with Swift's `destinations()` rules |
| 5 | Strict gold, `alt` unused | S1 | 303 of 610 labels have `alt`; 16 of 20 real wrong sends go to an `alt` | three-tier scoring |
| 6 | Labels anchored and from one model family | S2 | labellers see WENT TO; "clear" tracks recency | blind relabel, second family, human audit |
| 7 | Intervals too narrow; clustered data | S1 | one session = 65 cases; cluster CI ±11 vs the ±5–7 quoted | cluster bootstrap and paired tests |
| 8 | Leakage and overfitting | S1 | 24 saved runs on realA, 16 on full `real`, 8 on realB, 23 on heldout; synth is training data; styleA/B split by case | freeze a new test set; fix the style split |
| 9 | Halves unbalanced by project and size | S2 | amont and sic only in A; vesper and ai_academic only in B | stratified split by session, k-fold over sessions |
| 10 | Lookout's own intents and new sessions barely tested on real | S1 | 0 real intent golds; 61 first messages, 3 clear | Router-native cases |
| 11 | Missing interaction types | S1 | no schema field for armed reply, pin, pill, prior ask, live prefix | extend the case schema |
| 12 | Metric choice | S2 | right/wrong/ask with no cost weighting; the ask's quality only on the side | utility, risk–coverage, ask@4 |
| 13 | Small strata | S2 | first msgs n=61, realB first n=26, ≤3 words 7% | stratified targets per cell |
| 14 | Written sets unlike real use | S2 | style median 8 words, 0% over 60; real median 18, 11% over 60 | sample lengths from the real distribution |

## 1. Representativeness (S1)

Real messages were typed **inside** a session: the user had already picked the target, so the text has no address.
Router text will be terser (armed reply, pill) or more explicit ("the CI one: …"); neither shape is in `real`.
- One user, 13 days (09-28 to 10-11), 150 sessions; a 120-per-project cap flattens lookout/msb/lcu/scratch while sic
  gets 23 and ai_academic 7.
- 254 of 611 cases (42%) directly follow another sampled turn of the same session: correlated runs.
- `style` was written by agents on 85 real boards (up to 12 per board), writer's gold only, no blind relabel.

Fix: **T-LOG** (open lead 3), the only fully valid source: the exact request, Jev's reading, the decision, the outcome
(kept, corrected to X, ask answered with X). Until then **T-SIM**: a second family (GPT via Codex) rewrites sampled
real moments as Router messages under a style guide fitted to real lengths; keep each pair to measure the gap.

## 2. Running sessions (S1)

`extract.py` closes a turn at the next user message, so the target is never running: 0 of 550 golds, against 1,227
running rows on boards (88% of boards). The "running" weight is fitted to never pick one, yet "also X" or "stop" to a
working session is common in Lookout. 87 golds went idle under 30 s before the message (likely queued); interrupted
turns, exactly those corrections, are dropped. And every running row's `activity` is "working on: <your message>",
not Lookout's live line.

Fix: mark user records that arrive while the assistant is still emitting (timestamp before the turn's last assistant
record, or right after an interrupt) and gold them to the running session. Feed `activity` from the last tool or
assistant text, as Lookout does. Target at least 60 running-gold cases.

## 3. Card realism (S2)

Real and style boards hold only `done` (5,231) and `asks` (979). The regex `QUESTION` decides between them. Lookout
asks Jev (RouterTriager: done / asks / approval / blocked / waiting / progress), and forms give `question` and `plan`
with options. Of 671 distinct `done` texts, 115 (17%) contain an offer cue ("I can…", "if you want", "let me know"),
which is the case the short-reply rule exists for. 151 are cut at 300 characters. `summary` is empty on every real
row (Lookout sends one). `approval`, `stuck`, `waiting`, `plan`, `question` and card options exist only on written
boards.

Fix: run the real triage call (cached, cheap) over every card text and store `kind`, `urgency` and `waitingOn`. Report
the confusion between regex and triage. Recover AskUserQuestion / ExitPlanMode tool calls from transcripts as
`question` / `plan` cards with their real options.

## 4. Board reconstruction (S2)

- **Window and size**: `boards.py` keeps sessions active in the last 8 h, at most 25. Lookout offers working + 20
  recent + every card's session, and a new-session option for up to **60 known folders**. Real boards list a median of
  4 projects (max 6), so "new session in X" competes against far fewer options than in the app.
- **KEEP filter**: 67 corpus sessions (lcu-xturn, project-cli, lookout-live, router-probe…) are removed from every
  board. Lookout would show them, and they are confusable (lookout-live vs lookout).
- **Titles**: `extract.py` keeps the **final** custom title, which can describe work done after the moment (future
  leakage into the title feature). 516 of 7,713 rows use the first message as the title (untitled sessions).
- **Order/recency**: `idle_min` is exact, but the non-running median idle is 127 min with the gold at a median of 3
  min. 60% of follow-ups go to recency rank 0 (realA 62%, realB 57%). The task is therefore dominated by one heuristic,
  and the set hardly samples the hard regime: several sessions finished within minutes of each other.

Fix: build boards by porting `destinations()` and `status()` (working + 20 recent, all folders, card-status lines).
Take titles from the first `custom-title` record after the moment (or the first message until one exists). Add a
reweighted "hard recency" stratum: two or more sessions idle under 10 min.

## 5. Gold strictness (S1)

Real gold is where the message went. Labellers listed `alt` destinations on 303 of 610 cases, and no scorer reads
`alt` (grep: 0 uses). On the shipped policy, **16 of 20 real wrong sends (realA 11/14, realB 5/6) went to a
labeller's `alt`**. The "wrong send" number mixes clearly wrong sends with defensible ones, and the 4.7 → 2.8 change
between rounds is within that noise. Meanwhile `ask_ok` on real is just `label != clear`, so an ask on a "clear" case
counts as needless even when four plausible sessions existed.

Fix: score three tiers. **Hard-wrong** is a send outside gold ∪ alt; **soft-wrong** is a send to `alt`; **right** is
gold. Report hard-wrong as the safety metric. Re-adjudicate `alt` blind (see 6).

## 6. Label quality (S2)

- `split.py` prints `WENT TO:` above the board, so labellers rate whether the board explains a known answer
  (post-hoc), not whether the board determines it. "clear" correlates with recency: 205 of 302 clear follow-ups are
  rank 0 (68%), against 106 of 197 plausible (54%). Label notes lean on "match" (51), "just" (34) and "only" (33).
- Every labeller, every case writer, every relabel and the style writers are Claude agents, all one family. Jev is a
  different model, but the fusion was fitted on cases those agents wrote and judged.
- No inter-annotator agreement is computed for real; first messages are 3 clear / 43 plausible / 15 unclear.

Fix: a blind relabel. Show the board and the message without the destination, ask for a ranked destination set and a
"would a careful assistant ask?" flag, and run it with two families (Claude, GPT 6.1 via Codex). Report Cohen's κ and
the human-vs-model agreement on a 100-case sample the user labels (about 30 minutes, the gold standard for ask_ok).
Use "both labellers name gold first" as the clean-clear subset.

## 7. Statistics (S1)

Cases cluster heavily. One session alone is 65 cases, 10.6% of real and 16% of realA. The
next sessions have 27, 24, 23 and 17; 62 sessions have one case each. The docs' "±5–7" is a Wilson interval on
independent cases. A session-cluster bootstrap on the shipped policy gives:

| set | right | 95% (cluster) | wrong | 95% (cluster) |
|---|---|---|---|---|
| realA | 37.5 | 27.1–46.6 | 3.5 (14) | 1.7–6.1 |
| realB | 40.8 | 29.4–52.0 | 2.8 (6) | 0.9–5.4 |
| heldout | 72.0 | 64.3–78.6 (Wilson) | 2.7 (4) | 1.0–6.7 |

Round 2 to round 3 on realB, 4.7 → 2.8 wrong, is 10 → 6 events: not distinguishable. Between variants, the honest test
is **paired** (same cases): McNemar on the cases that change, plus a paired cluster bootstrap of the difference. That
test is much more sensitive than comparing two marginal intervals, and the evals already have the paired data.

Fix: make `bench.py` print cluster-bootstrap and paired-difference intervals by default, and the count of events, not
only percentages. Cap each session's weight (for example, weight a case by 1/√cases of its session).

## 8. Leakage and overfitting (S1)

- Saved runs: realA 24, real (whole, which includes realB) 16, realB 8, heldout 23, synth 39, style 39. Explorers
  `lexical.probe`, `diag`, `within_latest` and `fuse3` print realB and heldout while features are chosen: field signs
  (title −0.57, last instruction −0.84), the short-reply bars and C1=0.6 were picked with them in view. Neither realB
  nor heldout is untouched any more.
- `synth` is in the fusion's training set (`fit on realA + synth + styleA`) and is still reported as a result
  (65.2 / 1.4).
- **The style split leaks**: `half()` hashes `rs0-001`-style ids, so styleA/B is split by case, not by session. 50 of
  182 styleB golds are realA sessions, and every style board is a real board (85 distinct, shared across halves).
  styleB's 71.4 / 0.0 is partly in-sample.
- The fusion and lexical features read whole corpus statistics (corpus IDF option, the BM25 ablations), which are
  computed with future turns in them. The shipped board IDF is fine.

Fix: freeze a **sealed test set** before round 4 (new real moments from 2026-10-12 onwards, plus T-SIM and the
Router-native cases), score it once per round, and keep it out of explorers. Split style by its board's gold session.
Report synth as a training score. Use k-fold over sessions (`cv.py` grouped by session) for all tuning.

## 9. Split balance (S2)

A 397 / B 214; amont (68), sic (23) only in A; vesper (14), ai_academic (7) only in B; rank-0 share 62% vs 57%. Fix:
grouped k-fold by session, stratified by project and first/follow-up, mean and spread reported.

## 10. Destinations barely tested on real (S1)

Real has **0** Lookout-intent golds (question, change_lookout, compound) and 61 new-session golds (35 in A, 26 in B).
6 of realA's 14 wrong sends are first messages (17% of that stratum). Intents are tested only on written sets: synth
36, heldout 25, style 126, all agent-written. The `gate_you` and question-wording fixes were therefore validated on
real data only as "never fire", never as "fire when right".

Fix: Router-native intent cases on real boards (questions about the board, setting changes, compounds), written by two
families blind to each other and adjudicated. Include near-misses where the session itself is the right answer.

## 11. Missing interaction types (S1)

The schema is {board: projects, sessions, cards, history; message; gold}. Nothing encodes: **armed reply**, **pinned
target**, **@pills** (1 written message uses "@"); **ask-back follow-ups** ("3", "the other one", new text);
**corrections** (4 history rows have `corrected_from`; no "no, the CI one" after a wrong send); **multi-turn** ("and
tell it to push", "same for lcu"); **live prediction** on prefixes (most of Jev's cost; no flip metric); **pasted
errors** (0 real messages hold fences or tracebacks); **French** (20 real, unscored).

Fix: add `ui: {armed_card, pinned, pills, prefix_of}` and `thread: [{message, decision, user_action}]`; scenario
scripts of 3–6 steps on an evolving board, scored per step and per scenario; live prediction scored as prefix vs final
agreement and flip count.

## 12. Metrics (S2)

- An ask is neither right nor wrong (always-ask scores 0% wrong); ask quality (gold in the top 4: realA 206/234) is a
  side number. No cost model: propose utility right +1, ask with gold −0.2, ask without −0.5, soft-wrong −2,
  hard-wrong −5 (weights agreed with the user), plus risk–coverage curves and AURC so threshold changes are moves along
  a curve. No calibration (ECE) and no latency/cost per case.

## 13. Small strata (S2)

realB first messages (26) carry ±19 points at 40%; ≤3-word messages are ~43 cases; running targets 0. Fix: ≥80 per
cell for {reply to asks, terse, new session, running target, intent, close recency, correction, armed/pinned}.

## 14. Written sets (S2)

synth/heldout: median 6–7 words, 21–24% ≤3 words, none over 60 (real: 18, 7%, 11%). Use them as rule unit tests, not
performance estimates.

## Proposed eval stack (priority order)

1. **Sealed real test**: moments after 2026-10-12, boards rebuilt with Swift's `destinations()` rules, triaged cards,
   running targets, and a blind two-family relabel with a human-labelled subsample. Score once per round.
2. **Router-native set (T-SIM plus scenarios)**: each real moment paired with its Router phrasing, written by a second
   family; multi-step scenarios covering asks, corrections, pins, pills, armed replies and live prefixes; every cell
   ≥80.
3. **Scoring**: three-tier gold, utility, risk–coverage, ask@4, cluster and paired bootstrap, McNemar between variants.
4. **Traffic logging in Lookout (T-LOG)**: the long-run ground truth, which also feeds per-user learning.
