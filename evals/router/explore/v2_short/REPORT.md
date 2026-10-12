# A9 shortlist then rerank, A12 two wordings in one call — both dead ends (2026-10-12)

Dev real moments (216 episodes, 393 submits, 91 groups), the weights Lookout ships, free-running replay reproducing
`real_dev_cur.jsonl` exactly; paired group bootstrap. Jev calls: A9 1,490, A12 404. No calib or sealed file opened.
Baseline: top-1 68.4%, loss 1.580, 9 wrong sends of 117, card hit@4 85.5% among asks, 4,659 input tokens per call.

**A9 recall (0 calls):** sessions per call median 21. Gold within the first K of Lookout's own order (working, then
latest finished): K=4 92.1%, 6 98.0%, 8 98.5%, 10 99.0%, 12 99.5% (ceiling 99.7%). Priors mixing last-told, BM25,
waiting cards and running sessions add nothing beyond recency.

**A9 replay (Lookout-order shortlist; left-out sessions given Jev's floor so the fusion still ranks the board):**

| K | tokens per call | Δtop-1 (CI) | Δloss (CI) | wrong sends |
|---|---|---|---|---|
| 6 | −36% | −0.3 (−2.2, +1.8) | +0.188 (+0.003, +0.423) | 12 |
| 8 | −31% | 0.0 (−2.1, +2.2) | +0.160 (+0.025, +0.339) | 11 |
| 10 | −26% | −0.3 (−2.7, +2.2) | +0.155 (+0.020, +0.334) | 11 |
| 12 | −21% | −0.8 (−2.9, +1.3) | +0.008 (−0.166, +0.167) | 9 |

Jev's own top-1 is 45–47% at every K: fewer options don't help him; they change his probability mass, which the fused
sureness was fitted to read on full lists (AUROC −0.01 to −0.03). K=12 is loss-neutral at −21% tokens and would need
a sureness refit on shortlisted readings and a calib check; a Swift port is also more than a prefix
(`RouterRoute.destinations` re-adds cards of sessions it doesn't offer).

**A12 (route asked twice, geometric mean):** Δtop-1 −0.8 (−2.2, +0.7), Δloss +0.081 (0.000, +0.221), card hit@4 −1.7
(−3.4, −0.4), +68% tokens. The second question also shifts Jev's answer to the first (15 outcomes change reading the
shipped wording back from the two-question call). Beside round 3's order-permutation dead end.
