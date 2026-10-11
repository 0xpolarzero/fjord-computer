# Router routing evals

How well Jev routes what you type in the Router, measured on boards like yours.

- `cases/` (210: everyday, hard, traps) and `heldout/` (150, written independently, bigger boards): see CASES.md. Gold
  was relabelled blind; what either labeler accepts counts, asking is fine when either allows it.
- `jev.py`: TypeSafe client (key from Lookout's Keychain item), answers cached in `cache/`.
- `formats.py`: ways of asking. `v0` is what Lookout sent before (opaque t-keys, fenced descriptions, the last
  decisions); `v3-told+g` is what it sends now.
- `run.py FORMAT --orders 3 [--cases "heldout/*.jsonl" --tag=-ho] [--pad 22]`: asks every case (each order shuffles
  the options), saves the answers in `runs/`.
- `analyze.py`, `crossval.py`, `cv.py`: policies swept over saved answers, tuned on one set and tested on the other,
  pooled k-fold cross-validation.
- `rerank.py` (a second pass over the top candidates), `transforms.py` (boards padded to 22 sessions), `veto.py`
  (Lookout's word-overlap veto).

## Findings (jev-1.13.0, 2026-10-11)

Both sets pooled (360 cases, 2–3 option orders each), one configuration fixed in advance:

| | right sends | wrong session | wrong, to Lookout's own (question, compound) | needless asks |
|---|---|---|---|---|
| before | 42.9% | 1.7% | 0% | 29.8% |
| now | 68.6% | 1.1% | 1.2% | 11.4% |

What moved it, and what did not:

1. A card and its session were two options, so Jev's sureness of the session was split between them (p 0.5 + 0.4
   reads as unsure). One option per destination: +18 points of right sends on the first set, no new call.
2. Opaque keys whose descriptions sat in a fenced state blob flipped the top answer with the options' order in 38 of
   210 cases. Options named by the session, described in their own criteria, ranked better (top1 89% vs 85%).
   Correction (round 2): jev.py sends `json.dumps(sort_keys=True)`, so named options always reached Jev in the same
   (alphabetical) order and their "0–8 flips" measured nothing; only v0's flips are real, as its keys change with the
   order. Lookout sends the options in Swift dictionary order, which varies from run to run.
3. Context: what you last told a session belongs on that session's option. The global list of your last 10 messages
   was worse with it (61% vs 69% right) and caused the worst errors: "yes" sent to the session you last messaged
   instead of the one asking. Examples of past routings had no measurable effect on these sets and were dropped.
4. Bare replies ("yes", "lgtm", "nope", "the second one") read as `unclear` in the route question even with one card
   waiting. A yes/no per waiting card ("is `message` the answer to `card`?") gets them: 0.6–0.85 where the route said
   0.05. When it and the route both point elsewhere with confidence, ask.
5. "Turn a setting off" went to the session building that feature, in every format. A yes/no gate on whether the
   message changes how Lookout behaves, and one on whether it asks for several things, decide those first.
6. Thresholds by what a wrong pick costs: a session ≥ 0.7, a new session ≥ 0.6, Lookout's own intents (answered, or a
   change you can revert) ≥ 0.6. One bar for all (0.75 with a 0.3 lead) asked on a third of clear messages.
7. The word-overlap veto (`evidenced`) blocked 48 right sends and no wrong one on top of this.
8. Not worth it: a second, narrower pass (better top-1, overconfident), asking per-session yes/no instead of one
   choice (77% top-1 vs 89%), averaging several option orders (helps the old format only), instruction rules
   (more rules, worse), shortening long-idle sessions (noise).
9. Latency: one call, median 0.24 s, p95 0.3–0.4 s, about 1–2k input tokens.

Differences under ~5 points between similar variants are noise at this size (bootstrap 95% intervals ±5–7).

## Round 2 (2026-10-11): real moments

Written cases misled. `real/` rebuilds 611 moments from your own Claude Code transcripts (the message you typed into
a session, the board as Lookout would have shown it then, where it went; labelled by whether the board alone shows
it; keys and tokens redacted before anything reaches Jev; data stays in gitignored `real/data/`), and 332 Router-style
messages were written on those boards (`style`). `bench.py` scores every set; tune on `realA`, judge on `realB`
(sessions never tuned on) and `heldout`. On real moments round 1's router was right 15% of the time and wrong 20%.

| set (right / wrong) | round 1 | now (`combo` + `explore.fuse2:guarded`) |
|---|---|---|
| synth | 64.3 / 2.4 | 58.6 / 1.4 |
| heldout | 75.3 / 1.3 | 68.0 / 2.0 |
| style | 70.8 / 1.8 | 69.6 / 0.9 |
| realB | 14.5 / 21.5 | 34.6 / 4.7 |

Every real wrong send left is one the labellers found ambiguous (mostly a session's first message where a near-identical
session existed). What did it (explore/, one module per explorer):
1. `question` caught questions you ask a session about its own work (p > 0.95); worded as "a question to Lookout
   about the board, not to a session about its own work", plus a gate on whether the message speaks to one agent as
   "you" that vetoes Lookout's intents, and a compound gate that says one long message for one session is no:
   real wrong 20% → 9%.
2. Recency: a real message went to the session that just finished 60% of the time; Jev reads "3m ago" poorly. A
   yes/no per latest session ("is `message` your next message in this conversation?") is right 91 of 95 times when one
   stands out and the route doesn't disagree; a small fitted model (P ∝ exp(w·features): Jev's log p, recency ranks,
   running, the checks, the gates) weighs Jev with the board, and a logistic on the moment says how sure its pick is.
3. The decision: the rules' send when the fusion agrees (P ≥ 0.5), else the fusion's own pick at sureness 0.9, for
   three words or more, never Lookout's own.
4. Order: jev.py used to sort keys, so named options were never shuffled; shuffled for real, the decision changed on
   14% of real moments, and Lookout's own order (working, then latest finished) was the best. Lookout now sends them in
   that order (JevClient.orderedObject).
5. Not worth it: categorical recency words, a "latest" field (Jev obeys it as an instruction: 32% wrong), richer
   context (+4–5 top1 at +40% tokens), fewer options, a second verification call.
Swift (RouteFusion) decides exactly as the measured policy on all 360 written cases (RouterFusionParityTests).

## Round 3 (2026-10-11): research, and the words

A literature pass (disentanglement, calibration, selective prediction, per-user learning, cascades) and five explorers
(explore/state, personal, cascade, selective, lexical). Measured with options in Lookout's order (`combo-o`).

| set (right / wrong) | round 2 | round 3 (`combo-o` + `explore.final3:best`) |
|---|---|---|
| synth | 57.1 / 1.4 | 65.2 / 1.4 |
| styleB | 68.1 / 0.0 | 71.4 / 0.0 |
| realA | 29.2 / 3.8 | 37.5 / 3.5 |
| realB | 37.9 / 4.7 | 40.7 / 2.8 |
| heldout | 67.3 / 2.0 | 72.0 / 2.7 |

What helped:
1. Words (real/lexical.py, explore/lexical.py): BM25 between the message and each session's transcript, per field
   (its last answer +1.11, older turns halving with age +1.36, what you last told it −0.84: a message repeating your own
   last instruction starts something new; title −0.57). Alone it names where a real follow-up went 54% of the time.
2. A guard on the rules (explore/selective.py, lexical.py): 24 of 25 real wrong sends came from the rules' path, the
   fused pick at sureness 0.9 was right 78 of 79; a rules' send now needs the fused pick to agree at sureness ≥ 0.6.
3. Short replies (explore/state.py): "go", "2", "yes do it" go to the fused pick at sureness ≥ 0.95 when that
   session's last message asks or proposes something.
4. The ask card shows four options: the right one is among them 79–89% of the time on real asks.
What didn't: calibrating against a content-free message, averaging two option orders, exact identifiers (in 39 of
611 real messages), session-state × message-type features beyond the short-reply rule, Haiku on the asks (as wrong as
right on real asks, +1–4 s), a second Jev pass per candidate.
Promising, not built: a per-user refit of the fusion weights from your own corrections and kept sends (explore/
personal.py): after ~50 labels, late real wrong sends 4.5% → 2.3% in a time-ordered replay.
Two live keys in your transcripts (an OpenRouter and a z.ai key) reached TypeSafe in eval requests before redaction
caught them; real/boards.py now also strips any long letters-and-digits token, and Lookout redacts the same way
before anything goes to Jev (RouterTools.redacted).
