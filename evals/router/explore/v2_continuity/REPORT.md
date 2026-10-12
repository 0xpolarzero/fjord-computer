# A5 continuity: always check the last-told session (2026-10-12)

Dev split, real moments only (216 episodes, 393 submits, 91 groups); provisional ask gold ("allowed"). Paired
bootstrap 95% CIs over groups. No calib or sealed file opened. Code: `told.py` (format `combo-o-told`), `replay.py`,
`cv.py` (grouped-CV refits), `metrics.py`, `stats.py`, `diff.py`, `why.py`. Outputs in `out/` (gitignored: they hold
per-case boards).

**Variant `combo-o-told`:** the shipped call plus one next-message yes/no for the session your previous message went
to, when it isn't already among the three latest finished sessions checked (asked in 25% of calls; +0.7% input tokens;
no latency change). Shipped weights unchanged.

| metric | shipped | told | Δ [95% CI] |
|---|---:|---:|---|
| top-1 of the fused ranking | 63.1% | 63.1% | 0.0 [−0.8, +0.7] |
| loss per submit | 1.891 | 1.695 | −0.196 [−0.415, −0.021] |
| wrong sends | 3.6% (14) | 2.8% (11) | −0.8 [−1.7, 0.0] |
| card hit@4 among asks | 83.7% | 84.7% | +1.0 [−0.4, +2.5] |
| AUROC of sureness | 0.797 | 0.800 | +0.003 |

Ten submits change; the 3 avoided wrong sends are in 2 groups (McNemar p = 0.5). In only 1 of the 9 changed losses is
the last-told session the answer: the extra yes mostly lowers the fusion's confidence in a wrong first pick (a hedge,
not a find). The extra answer separates target from not at AUC 0.67 (shipped checks 0.70); when the last-told session
isn't already checked it is the answer only 17% of the time. Whole dev mix: no harm (natural −0.063 [−0.203, +0.067]).

**Refits (grouped CV):** the shipped fusion under-weights the next-message checks (`nxt` 0.87 → 2.2 fitted) and the
last-told session (`told0` 0.72 → 1.4). Refitting without recalibrating sureness sends 6–7 points more with wrong sends
flat or up (loss +0.18); with recalibration the loss change is within noise. Transition features (`told_run`, `fresh`,
`backlog`, `told_fin`, `finx0`, `told_short`) add nothing beyond that, and are fold-seed dependent.

**Decision (main session):** not ported yet. The gain rests on 3 wrong sends in 2 groups and the mechanism is a hedge;
re-test with real ask gold and on calib, together with the send-bar work (A2), starting a real-weighted refit (A8) from
`nxt` ≈ 2.2, `told0` ≈ 1.4 with sureness recalibrated.
