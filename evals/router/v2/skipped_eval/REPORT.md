# Skipped asks: does a reply leave a card's question untouched? (Jev, one call per reply)

Real data only: 188 finished turns of your own sessions (KEEP projects, started by you) whose final message asks something,
each with the message you typed next (after the turn ended, not queued, not a command). Asks from the app's Haiku asks call
(ported in `../asks_eval/common.py`); every multi-ask card found (88) plus 100 single-ask cards. Everything sent to Jev
redacted (`real/boards.py redact`), the asks fenced (`SessionFence`). Reference: one Opus label per question (`label.py`),
~20 spot-checked by hand (about 17 clearly right, 3 judgement calls: implicit coverage, asking back about a question).

    python3 v2/skipped_eval/sample.py --multi 200 --single 220   # cases.jsonl (Haiku asks, cached)
    python3 v2/skipped_eval/label.py                             # labels.jsonl (Opus)
    python3 v2/skipped_eval/jev_run.py --wordings A,B,B1,C [--sample 1]
    python3 v2/skipped_eval/score.py --wordings A,B,B1,C

Positive = `skipped`; `responded`, `moved_on` (the reply ignores every question and turns the session elsewhere: a redirect)
and `unclear` are negatives, so a flag on any of them is a false flag. False-flag rate = false flags / negatives.

## Labels (Opus)

| card | responded | moved_on | skipped | unclear |
|---|---|---|---|---|
| single | 85 | 9 | 5 | 1 |
| multi | 175 | 11 | 50 | 1 |

cases 188 (single 100, multi 88); questions 337

## Wordings

- A (yes = skipped): "Does the user's message leave question {key} untouched? …" — flag when p_yes ≥ gate.
- B (yes = responded): "Does the user's message respond to question {key} in any way: …" — flag when p_yes ≤ 1 − gate.
- B1: B with the questions keyed q1..qN instead of q0..qN-1 (replies that refer to questions by number count from 1).
- C (yes = skipped): "Does the user's message respond to another of the session's questions but leave question {key} out? …"

Rules: `plain` = the gate alone. `partly` = the gate, and another question of the same card read as responded (its
"skipped" probability under 0.5). `partly` never flags a single-question card or a reply that moves on from all of them.

## Summary (all 337 questions: 55 skipped, 282 not; multi-ask cards: 50 skipped, 187 not)

| wording | rule | gate | flagged | precision | recall | false-flag rate |
|---|---|---|---|---|---|---|
| A | plain | 0.9 | 37 | 54% | 36% | 6.0% (17/282) |
| B | plain | 0.95 | 37 | 54% | 36% | 6.0% (17/282) |
| C | plain | 0.8 | 19 | 84% | 29% | 1.1% (3/282) |
| A | partly | 0.9 | 15 | 87% | 24% | 0.7% (2/282) |
| B | partly | 0.9 | 21 | 86% | 33% | 1.1% (3/282) |
| B1 | partly | 0.9 | 20 | 90% | 33% | 0.7% (2/282) |
| B | partly | 0.95 | 12 | 100% | 22% | 0% (0/282) |
| B1 | partly | 0.95 | 12 | 100% | 22% | 0% (0/282) |

Second sample (same requests asked again): B partly 0.9 → 21 flagged, 19 right, 2 false; B partly 0.95 → 12/12, 0 false.
A partly 0.95 flags only 2 (A's "yes" rarely passes 0.95); C's probabilities top out around 0.85, so its gate window is narrow.

Without `partly`, a third (gate 0.7) to most (gate 0.9+) of the false flags are `moved_on` replies (all questions read as untouched) and most of
the rest are single-ask cards, where Opus found only 5 skipped of 100. Single-ask cards: skip the call or never flag.

Recommendation: B wording, keys q1..qN, `partly` rule, gate 0.95 (flag q when p_yes ≤ 0.05 and another question of the
card has p_yes > 0.5): 0 false flags in 2 samples, catches ~1 in 4 skipped questions on multi-ask cards. Gate 0.9 catches
~1 in 3 for ~1% false flags (2–3 of 282).

Jev: 188 calls per wording, 0 failures, latency median 0.30 s, p90 0.33–0.35 s (jev-1.13.0).

## Full tables

## Wording A (yes = skipped)

calls 188, failures 0, latency median 0.30 s, p90 0.35 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 97 | 44% (43/97) | 78% (43/55) | 19% (54/282) | 18 |
| plain | 0.7 | single | 23 | 17% (4/23) | 80% (4/5) | 20% (19/95) | 9 |
| plain | 0.7 | multi | 74 | 53% (39/74) | 78% (39/50) | 19% (35/187) | 9 |
| plain | 0.8 | all | 72 | 49% (35/72) | 64% (35/55) | 13% (37/282) | 17 |
| plain | 0.8 | single | 16 | 19% (3/16) | 60% (3/5) | 14% (13/95) | 8 |
| plain | 0.8 | multi | 56 | 57% (32/56) | 64% (32/50) | 13% (24/187) | 9 |
| plain | 0.85 | all | 58 | 52% (30/58) | 55% (30/55) | 10% (28/282) | 14 |
| plain | 0.85 | single | 11 | 18% (2/11) | 40% (2/5) | 9% (9/95) | 7 |
| plain | 0.85 | multi | 47 | 60% (28/47) | 56% (28/50) | 10% (19/187) | 7 |
| plain | 0.9 | all | 37 | 54% (20/37) | 36% (20/55) | 6% (17/282) | 14 |
| plain | 0.9 | single | 9 | 11% (1/9) | 20% (1/5) | 8% (8/95) | 7 |
| plain | 0.9 | multi | 28 | 68% (19/28) | 38% (19/50) | 5% (9/187) | 7 |
| plain | 0.95 | all | 10 | 30% (3/10) | 5% (3/55) | 2% (7/282) | 7 |
| plain | 0.95 | single | 3 | 33% (1/3) | 20% (1/5) | 2% (2/95) | 2 |
| plain | 0.95 | multi | 7 | 29% (2/7) | 4% (2/50) | 3% (5/187) | 5 |
| partly | 0.7 | all | 43 | 63% (27/43) | 49% (27/55) | 6% (16/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 43 | 63% (27/43) | 54% (27/50) | 9% (16/187) | 0 |
| partly | 0.8 | all | 29 | 72% (21/29) | 38% (21/55) | 3% (8/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 29 | 72% (21/29) | 42% (21/50) | 4% (8/187) | 0 |
| partly | 0.85 | all | 25 | 72% (18/25) | 33% (18/55) | 2% (7/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 25 | 72% (18/25) | 36% (18/50) | 4% (7/187) | 0 |
| partly | 0.9 | all | 15 | 87% (13/15) | 24% (13/55) | 1% (2/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 15 | 87% (13/15) | 26% (13/50) | 1% (2/187) | 0 |
| partly | 0.95 | all | 2 | 100% (2/2) | 4% (2/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 2 | 100% (2/2) | 4% (2/50) | 0% (0/187) | 0 |

## Wording B (yes = responded)

calls 188, failures 0, latency median 0.30 s, p90 0.35 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 126 | 37% (47/126) | 85% (47/55) | 28% (79/282) | 20 |
| plain | 0.7 | single | 32 | 12% (4/32) | 80% (4/5) | 29% (28/95) | 9 |
| plain | 0.7 | multi | 94 | 46% (43/94) | 86% (43/50) | 27% (51/187) | 11 |
| plain | 0.8 | all | 99 | 43% (43/99) | 78% (43/55) | 20% (56/282) | 18 |
| plain | 0.8 | single | 25 | 16% (4/25) | 80% (4/5) | 22% (21/95) | 9 |
| plain | 0.8 | multi | 74 | 53% (39/74) | 78% (39/50) | 19% (35/187) | 9 |
| plain | 0.85 | all | 83 | 46% (38/83) | 69% (38/55) | 16% (45/282) | 18 |
| plain | 0.85 | single | 21 | 14% (3/21) | 60% (3/5) | 19% (18/95) | 9 |
| plain | 0.85 | multi | 62 | 56% (35/62) | 70% (35/50) | 14% (27/187) | 9 |
| plain | 0.9 | all | 66 | 48% (32/66) | 58% (32/55) | 12% (34/282) | 15 |
| plain | 0.9 | single | 17 | 18% (3/17) | 60% (3/5) | 15% (14/95) | 8 |
| plain | 0.9 | multi | 49 | 59% (29/49) | 58% (29/50) | 11% (20/187) | 7 |
| plain | 0.95 | all | 37 | 54% (20/37) | 36% (20/55) | 6% (17/282) | 11 |
| plain | 0.95 | single | 11 | 9% (1/11) | 20% (1/5) | 11% (10/95) | 8 |
| plain | 0.95 | multi | 26 | 73% (19/26) | 38% (19/50) | 4% (7/187) | 3 |
| partly | 0.7 | all | 44 | 57% (25/44) | 45% (25/55) | 7% (19/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 44 | 57% (25/44) | 50% (25/50) | 10% (19/187) | 0 |
| partly | 0.8 | all | 33 | 70% (23/33) | 42% (23/55) | 4% (10/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 33 | 70% (23/33) | 46% (23/50) | 5% (10/187) | 0 |
| partly | 0.85 | all | 28 | 79% (22/28) | 40% (22/55) | 2% (6/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 28 | 79% (22/28) | 44% (22/50) | 3% (6/187) | 0 |
| partly | 0.9 | all | 21 | 86% (18/21) | 33% (18/55) | 1% (3/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 21 | 86% (18/21) | 36% (18/50) | 2% (3/187) | 0 |
| partly | 0.95 | all | 12 | 100% (12/12) | 22% (12/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 12 | 100% (12/12) | 24% (12/50) | 0% (0/187) | 0 |

## Wording B1 (yes = responded)

calls 188, failures 0, latency median 0.30 s, p90 0.33 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 124 | 38% (47/124) | 85% (47/55) | 27% (77/282) | 20 |
| plain | 0.7 | single | 32 | 12% (4/32) | 80% (4/5) | 29% (28/95) | 9 |
| plain | 0.7 | multi | 92 | 47% (43/92) | 86% (43/50) | 26% (49/187) | 11 |
| plain | 0.8 | all | 98 | 45% (44/98) | 80% (44/55) | 19% (54/282) | 18 |
| plain | 0.8 | single | 23 | 17% (4/23) | 80% (4/5) | 20% (19/95) | 9 |
| plain | 0.8 | multi | 75 | 53% (40/75) | 80% (40/50) | 19% (35/187) | 9 |
| plain | 0.85 | all | 82 | 46% (38/82) | 69% (38/55) | 16% (44/282) | 17 |
| plain | 0.85 | single | 20 | 15% (3/20) | 60% (3/5) | 18% (17/95) | 9 |
| plain | 0.85 | multi | 62 | 56% (35/62) | 70% (35/50) | 14% (27/187) | 8 |
| plain | 0.9 | all | 62 | 52% (32/62) | 58% (32/55) | 11% (30/282) | 15 |
| plain | 0.9 | single | 16 | 19% (3/16) | 60% (3/5) | 14% (13/95) | 8 |
| plain | 0.9 | multi | 46 | 63% (29/46) | 58% (29/50) | 9% (17/187) | 7 |
| plain | 0.95 | all | 37 | 57% (21/37) | 38% (21/55) | 6% (16/282) | 10 |
| plain | 0.95 | single | 12 | 8% (1/12) | 20% (1/5) | 12% (11/95) | 8 |
| plain | 0.95 | multi | 25 | 80% (20/25) | 40% (20/50) | 3% (5/187) | 2 |
| partly | 0.7 | all | 41 | 61% (25/41) | 45% (25/55) | 6% (16/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 41 | 61% (25/41) | 50% (25/50) | 9% (16/187) | 0 |
| partly | 0.8 | all | 33 | 73% (24/33) | 44% (24/55) | 3% (9/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 33 | 73% (24/33) | 48% (24/50) | 5% (9/187) | 0 |
| partly | 0.85 | all | 29 | 79% (23/29) | 42% (23/55) | 2% (6/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 29 | 79% (23/29) | 46% (23/50) | 3% (6/187) | 0 |
| partly | 0.9 | all | 20 | 90% (18/20) | 33% (18/55) | 1% (2/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 20 | 90% (18/20) | 36% (18/50) | 1% (2/187) | 0 |
| partly | 0.95 | all | 12 | 100% (12/12) | 22% (12/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 12 | 100% (12/12) | 24% (12/50) | 0% (0/187) | 0 |

## Wording C (yes = skipped)

calls 188, failures 0, latency median 0.30 s, p90 0.33 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 36 | 58% (21/36) | 38% (21/55) | 5% (15/282) | 0 |
| plain | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.7 | multi | 36 | 58% (21/36) | 42% (21/50) | 8% (15/187) | 0 |
| plain | 0.8 | all | 19 | 84% (16/19) | 29% (16/55) | 1% (3/282) | 0 |
| plain | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.8 | multi | 19 | 84% (16/19) | 32% (16/50) | 2% (3/187) | 0 |
| plain | 0.85 | all | 4 | 75% (3/4) | 5% (3/55) | 0% (1/282) | 0 |
| plain | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.85 | multi | 4 | 75% (3/4) | 6% (3/50) | 1% (1/187) | 0 |
| plain | 0.9 | all | 2 | 50% (1/2) | 2% (1/55) | 0% (1/282) | 0 |
| plain | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.9 | multi | 2 | 50% (1/2) | 2% (1/50) | 1% (1/187) | 0 |
| plain | 0.95 | all | 0 | – (0/0) | 0% (0/55) | 0% (0/282) | 0 |
| plain | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.95 | multi | 0 | – (0/0) | 0% (0/50) | 0% (0/187) | 0 |
| partly | 0.7 | all | 36 | 58% (21/36) | 38% (21/55) | 5% (15/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 36 | 58% (21/36) | 42% (21/50) | 8% (15/187) | 0 |
| partly | 0.8 | all | 19 | 84% (16/19) | 29% (16/55) | 1% (3/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 19 | 84% (16/19) | 32% (16/50) | 2% (3/187) | 0 |
| partly | 0.85 | all | 4 | 75% (3/4) | 5% (3/55) | 0% (1/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 4 | 75% (3/4) | 6% (3/50) | 1% (1/187) | 0 |
| partly | 0.9 | all | 2 | 50% (1/2) | 2% (1/55) | 0% (1/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 2 | 50% (1/2) | 2% (1/50) | 1% (1/187) | 0 |
| partly | 0.95 | all | 0 | – (0/0) | 0% (0/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 0 | – (0/0) | 0% (0/50) | 0% (0/187) | 0 |

## Wording A_s1 (yes = skipped)

calls 188, failures 0, latency median 0.30 s, p90 0.34 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 98 | 45% (44/98) | 80% (44/55) | 19% (54/282) | 18 |
| plain | 0.7 | single | 22 | 14% (3/22) | 60% (3/5) | 20% (19/95) | 9 |
| plain | 0.7 | multi | 76 | 54% (41/76) | 82% (41/50) | 19% (35/187) | 9 |
| plain | 0.8 | all | 72 | 49% (35/72) | 64% (35/55) | 13% (37/282) | 17 |
| plain | 0.8 | single | 16 | 19% (3/16) | 60% (3/5) | 14% (13/95) | 8 |
| plain | 0.8 | multi | 56 | 57% (32/56) | 64% (32/50) | 13% (24/187) | 9 |
| plain | 0.85 | all | 56 | 52% (29/56) | 53% (29/55) | 10% (27/282) | 15 |
| plain | 0.85 | single | 12 | 17% (2/12) | 40% (2/5) | 11% (10/95) | 8 |
| plain | 0.85 | multi | 44 | 61% (27/44) | 54% (27/50) | 9% (17/187) | 7 |
| plain | 0.9 | all | 36 | 56% (20/36) | 36% (20/55) | 6% (16/282) | 14 |
| plain | 0.9 | single | 9 | 11% (1/9) | 20% (1/5) | 8% (8/95) | 7 |
| plain | 0.9 | multi | 27 | 70% (19/27) | 38% (19/50) | 4% (8/187) | 7 |
| plain | 0.95 | all | 9 | 22% (2/9) | 4% (2/55) | 2% (7/282) | 7 |
| plain | 0.95 | single | 2 | 0% (0/2) | 0% (0/5) | 2% (2/95) | 2 |
| plain | 0.95 | multi | 7 | 29% (2/7) | 4% (2/50) | 3% (5/187) | 5 |
| partly | 0.7 | all | 46 | 65% (30/46) | 55% (30/55) | 6% (16/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 46 | 65% (30/46) | 60% (30/50) | 9% (16/187) | 0 |
| partly | 0.8 | all | 32 | 75% (24/32) | 44% (24/55) | 3% (8/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 32 | 75% (24/32) | 48% (24/50) | 4% (8/187) | 0 |
| partly | 0.85 | all | 25 | 80% (20/25) | 36% (20/55) | 2% (5/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 25 | 80% (20/25) | 40% (20/50) | 3% (5/187) | 0 |
| partly | 0.9 | all | 17 | 94% (16/17) | 29% (16/55) | 0% (1/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 17 | 94% (16/17) | 32% (16/50) | 1% (1/187) | 0 |
| partly | 0.95 | all | 2 | 100% (2/2) | 4% (2/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 2 | 100% (2/2) | 4% (2/50) | 0% (0/187) | 0 |

## Wording B_s1 (yes = responded)

calls 188, failures 0, latency median 0.30 s, p90 0.34 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 126 | 37% (47/126) | 85% (47/55) | 28% (79/282) | 20 |
| plain | 0.7 | single | 31 | 13% (4/31) | 80% (4/5) | 28% (27/95) | 9 |
| plain | 0.7 | multi | 95 | 45% (43/95) | 86% (43/50) | 28% (52/187) | 11 |
| plain | 0.8 | all | 102 | 42% (43/102) | 78% (43/55) | 21% (59/282) | 18 |
| plain | 0.8 | single | 27 | 15% (4/27) | 80% (4/5) | 24% (23/95) | 9 |
| plain | 0.8 | multi | 75 | 52% (39/75) | 78% (39/50) | 19% (36/187) | 9 |
| plain | 0.85 | all | 83 | 47% (39/83) | 71% (39/55) | 16% (44/282) | 18 |
| plain | 0.85 | single | 20 | 15% (3/20) | 60% (3/5) | 18% (17/95) | 9 |
| plain | 0.85 | multi | 63 | 57% (36/63) | 72% (36/50) | 14% (27/187) | 9 |
| plain | 0.9 | all | 63 | 52% (33/63) | 60% (33/55) | 11% (30/282) | 14 |
| plain | 0.9 | single | 17 | 18% (3/17) | 60% (3/5) | 15% (14/95) | 8 |
| plain | 0.9 | multi | 46 | 65% (30/46) | 60% (30/50) | 9% (16/187) | 6 |
| plain | 0.95 | all | 35 | 57% (20/35) | 36% (20/55) | 5% (15/282) | 10 |
| plain | 0.95 | single | 12 | 8% (1/12) | 20% (1/5) | 12% (11/95) | 8 |
| plain | 0.95 | multi | 23 | 83% (19/23) | 38% (19/50) | 2% (4/187) | 2 |
| partly | 0.7 | all | 45 | 58% (26/45) | 47% (26/55) | 7% (19/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 45 | 58% (26/45) | 52% (26/50) | 10% (19/187) | 0 |
| partly | 0.8 | all | 34 | 68% (23/34) | 42% (23/55) | 4% (11/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 34 | 68% (23/34) | 46% (23/50) | 6% (11/187) | 0 |
| partly | 0.85 | all | 28 | 79% (22/28) | 40% (22/55) | 2% (6/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 28 | 79% (22/28) | 44% (22/50) | 3% (6/187) | 0 |
| partly | 0.9 | all | 21 | 90% (19/21) | 35% (19/55) | 1% (2/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 21 | 90% (19/21) | 38% (19/50) | 1% (2/187) | 0 |
| partly | 0.95 | all | 12 | 100% (12/12) | 22% (12/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 12 | 100% (12/12) | 24% (12/50) | 0% (0/187) | 0 |

## Wording C_s1 (yes = skipped)

calls 188, failures 0, latency median 0.30 s, p90 0.34 s

| rule | gate | split | flagged | precision | recall | false-flag rate | false flags on moved_on |
|---|---|---|---|---|---|---|---|
| plain | 0.7 | all | 36 | 61% (22/36) | 40% (22/55) | 5% (14/282) | 0 |
| plain | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.7 | multi | 36 | 61% (22/36) | 44% (22/50) | 7% (14/187) | 0 |
| plain | 0.8 | all | 19 | 79% (15/19) | 27% (15/55) | 1% (4/282) | 0 |
| plain | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.8 | multi | 19 | 79% (15/19) | 30% (15/50) | 2% (4/187) | 0 |
| plain | 0.85 | all | 4 | 75% (3/4) | 5% (3/55) | 0% (1/282) | 0 |
| plain | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.85 | multi | 4 | 75% (3/4) | 6% (3/50) | 1% (1/187) | 0 |
| plain | 0.9 | all | 2 | 50% (1/2) | 2% (1/55) | 0% (1/282) | 0 |
| plain | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.9 | multi | 2 | 50% (1/2) | 2% (1/50) | 1% (1/187) | 0 |
| plain | 0.95 | all | 0 | – (0/0) | 0% (0/55) | 0% (0/282) | 0 |
| plain | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| plain | 0.95 | multi | 0 | – (0/0) | 0% (0/50) | 0% (0/187) | 0 |
| partly | 0.7 | all | 36 | 61% (22/36) | 40% (22/55) | 5% (14/282) | 0 |
| partly | 0.7 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.7 | multi | 36 | 61% (22/36) | 44% (22/50) | 7% (14/187) | 0 |
| partly | 0.8 | all | 19 | 79% (15/19) | 27% (15/55) | 1% (4/282) | 0 |
| partly | 0.8 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.8 | multi | 19 | 79% (15/19) | 30% (15/50) | 2% (4/187) | 0 |
| partly | 0.85 | all | 4 | 75% (3/4) | 5% (3/55) | 0% (1/282) | 0 |
| partly | 0.85 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.85 | multi | 4 | 75% (3/4) | 6% (3/50) | 1% (1/187) | 0 |
| partly | 0.9 | all | 2 | 50% (1/2) | 2% (1/55) | 0% (1/282) | 0 |
| partly | 0.9 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.9 | multi | 2 | 50% (1/2) | 2% (1/50) | 1% (1/187) | 0 |
| partly | 0.95 | all | 0 | – (0/0) | 0% (0/55) | 0% (0/282) | 0 |
| partly | 0.95 | single | 0 | – (0/0) | 0% (0/5) | 0% (0/95) | 0 |
| partly | 0.95 | multi | 0 | – (0/0) | 0% (0/50) | 0% (0/187) | 0 |

