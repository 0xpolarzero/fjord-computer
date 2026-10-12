# Fusion directions A3, A4 and the real-only refit (2026-10-12)

Dev split, real moments only (216 episodes, 393 submits, 91 groups); no new Jev calls; no calib or sealed file opened.
Moments frozen along the shipped path (`extract.py`; the replica reproduces shipped sureness and send/ask on 393/393).
10-fold CV grouped by `group`, λ chosen by inner grouped CV, sureness fitted on inner out-of-fold P; paired bootstrap
over groups; conclusions checked on three fold seeds. Code: `extract.py`, `core.py`, `experiments.py`, `summary.py`,
`slices.py`, `policy.py`, `written_cv.py`, `port.py`. Frozen moments live in /tmp (they hold message text).

Shipped baseline: top-1 63.1%, card hit@4 88.0%, sureness AUROC 0.797, wrong rate at 30/40/50% coverage 5.1/7.6/14.8%,
overconfident (ECE 0.056; predicted 0.85 → observed 0.74).

| direction | result |
|---|---|
| A4 BM25 absolute strength (raw strength, log BM25, IDF coverage, sureness features) | dead end: top-1 +0.0 to +1.0 n.s.; the AUROC rise comes from the sureness refit itself; only log BM25 lifts hit@4 +1.0 and costs AUROC on top of the refit |
| A3 unused Jev signals (route confidence, entropy, margins; Jev's pick; same-title sibling mass) | dead end: AUROC ±0.005 against the refit; sibling-mass weight fits negative; fused top two are siblings on 2 of 393 moments |
| sureness refit only | AUROC +0.040 [+0.013, +0.067], ECE 0.012, top-1 unchanged |
| all 24 weights refit | top-1 +5.1 [+1.8, +8.5], but Jev's weight `lp` drops 0.84 → 0.53 and intents become unreachable (dev real has no intent gold): −11 to −17 top-1 on written goal episodes |
| 14 session weights (pre-specified) | top-1 +4.8 [+1.3, +8.4] |
| **6 weights (`fin0`, `fin2`, `run`, `reply`, `nxt`, `f_you`) + sureness** | **top-1 +4.3 [+1.6, +7.3]** (seeds 1, 2: +4.6, +4.6), ECE 0.023; written goal −2.0, rewrites +1.5, scripted unchanged |
| written episodes mixed into the fit (×1 / ×0.5 / ×0.2) | +2.5 n.s. / +3.1 / +3.8: the more written weight, the less real gain |

About half of the gain is messages to a session still running (31 of 393; shipped 5 right, refit 16), the rest +7 net
on finished sessions. The six-weight subset was chosen after seeing the full refit, so its estimate is slightly
optimistic; the pre-specified 14-weight refit shows the effect is real.

Ported (Sources/Lookout/RouterRoute.swift): `fin0` 1.36, `fin2` 1.08, `run` 1.79, `reply` 1.54, `nxt` 1.70, `f_you`
−0.64, and the refit sureness — except for intent picks, which keep the earlier sureness (`surenessIntent`): your
transcripts predate the intents, so the refit had learned `top_intent` from intents that could only count as wrong,
and a sure setting gate no longer sent (caught by RouterDispatcherTests).
