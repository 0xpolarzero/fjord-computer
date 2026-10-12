# A8: the lexical turn boundary for running sessions — dead end (2026-10-12)

Dev real moments (216 episodes, 393 submits, 91 groups), cache-only replay with the weights Lookout ships, 0 Jev calls,
paired bootstrap over groups; the base replay matches `real_dev_cur.jsonl` on all 393 submits. No calib or sealed file
opened. Variants rewrite the turns `adapter.past_turns` hands to `explore.lexical` (`patch.py`): while a session runs,
its latest turn's answer becomes the previous turn's (`prev`), also removed from the previous turn (`move`), only for
`f_said` (`prevonly`), or for any session whose latest answer is empty (`nonempty`).

The premise was partly wrong: `f_old` (skip the latest, decay 0.5) counts the turn before the latest at full weight,
so a running session's last completed answer already counts, at the larger weight (`f_old` 1.36 vs `f_said` 1.11).

| metric | base | variants (all four alike) |
|---|---:|---|
| top-1, all | 68.4% | −0.5 [−1.3, 0.0] |
| top-1, target running (n=30) | 53.3% | −3.3 [−10.3, 0.0] |
| card hit@4 | 89.3% | +0.0 |
| loss, wrong sends, sends | | +0.0 |

The fused top changes on 3–5 moments (0 wrong→right, 2 right→wrong): another running session's `f_said` jumps. On 18
of the 30 target-running submits the shipped top is another running session: the errors are confusion between running
sessions, which this doesn't touch. A lexical refit (`refit.py`, grouped CV, three seeds) on any variant is no better
than one on the shipped boundary (`move` −0.5 to −1.0 top-1); a separate running-session `f_said` feature fits at
+0.01. Transcript and board-fallback cuts agree on where the answer goes; the board fallback is never used for a
running session in replay, and forcing it changes no ranking. Side finding: board-only text costs about 2 points
against transcripts (hit@4 −1.7 [−3.1, −0.5]).
