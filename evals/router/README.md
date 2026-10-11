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
