# Post-turn triage with attention tiers: an evaluation on 505 real turns

Main has not landed the change (`git show main:Sources/Lookout/RouterTriage.swift` only differs in its tints), so it is
implemented from the description in `jev_variants.py`: the reworded hints (state `waiting` "outside it and outside the
user", `asks` "or says it waits on the user", waitingOn `review` "by someone other than the user"), `next` (you | note |
nothing) in the same bundle, `trivial` kept. Tier rules (`score.py`): asks/approval/blocked → 1, waiting → 2, else `next`
(you → 1, note → 3, nothing → 4). Unverified lifts 4 → 3, and a sure trivial (≥ 0.8) drops 3 → 4.

## Data and method

- **Sample** (`sample.py`): 505 turn cards from the 1,543 on the boards of `moments.jsonl`, stratified by today's kind:
  done 204, asks 149, waiting 83, approval 54, stuck 15. Each turn is rebuilt with `states.py`'s reader, and the
  rebuild is byte-identical to stage A: 491/491 cached calls give the same kind (`parity.py`). Distributions are
  reweighted to the pool's kinds.
- **What you did next**: you replied in that session within 10 min 315 times, within 60 min 396, later 44, never 65.
  Sonnet read the end of each turn's final message and your reply, and classed the reply as answer 59, approve 67,
  finish-up step 23, continue 11, react to content 179, or new task 101.
- **Behavioural tier** (noisy): answer, approve, finish or continue → B1 (160). Otherwise a task notification, peer
  message or CI event before your reply, or a reply saying the wait ended → B2 (28). React → B3 (170). New task or no
  reply → B4 (147). Its limits: a finish-up step you did outside the session (merging on GitHub, trying the app) shows
  up as B3 or B4, and B3 vs B4 only says whether you engaged with the content.
- **Blind labels** (`labels.py`): Sonnet (`claude -p`) and GPT-6.1 Sol (`codex exec`, high effort), 10 turns per call.
  They saw only the redacted final message and today's card kind, and gave a tier plus finish_up, worth_a_look,
  offer_only and blocker. The two agree on 84% of turns (κ 0.71), giving 425 consensus turns. Against behaviour they
  agree poorly: κ 0.22–0.25 on 1/2/3+4, and tier 1 has precision 0.39–0.42 and recall 0.78–0.84. Most label-tier-1
  turns you never answered as such. Pool-weighted, the consensus is 76/7/11/6 (tiers 1/2/3/4).
- **Jev** (`jev_variants.py`): one call per turn and bundle, cached; 3,535 calls in all. Bundles: **old** (today's
  questions + trivial); **newC / newC0** (`next` as a choice, with / without examples); **newG / newG0** (two yes/no
  gates, `step` "leaves the user a step to do?" and `worth` "worth reading?", with / without examples); **newCO /
  newGO** (newC / newG with an asks hint saying a closing offer is not asking). Floors and fallbacks are applied after.

## Results (all 505 turns; P/R against the consensus labels)

| configuration | tiers 1/2/3/4 % (pool) | acc / κ | t1 P/R | t2 P/R | t3 P/R | t4 P/R | t1 P/R vs behaviour |
|---|---|---|---|---|---|---|---|
| today (no tier 3) | 54/10/0/36 | .63 / .41 | .96/.65 | .70/.94 | – | .17/1.0 | .45/.61 |
| today, unverified → 3 | 54/10/9/27 | .67 / .47 | .96/.65 | .70/.94 | .41/.32 | .23/1.0 | .45/.61 |
| **planned**: choice, floor 0.6, unsure → note | 68/7/23/1 | .83 / .66 | .95/.87 | .88/.88 | .42/.80 | 1.0/.26 | .40/.77 |
| choice, floor 0.6, unsure → nothing | 68/7/19/5 | .84 / .68 | .95/.87 | .88/.88 | .51/.76 | .52/.52 | .40/.77 |
| **recommended**: gates, step ≥ 0.6, worth ≥ 0.7, else 4 | 74/7/11/7 | .86 / .71 | .93/.92 | .90/.90 | .55/.52 | .66/.78 | .37/.79 |

Most of the gain over today comes from the hints and `next` together: tier-1 recall rises from .65 to .87–.92 at the
same precision. Tier 2 gets cleaner: of the turns both labellers say wait on the user, Jev files 19 as waiting today and
4 under the new hints; of those waiting on someone else, it keeps 46 of 49 as waiting; tier-2 precision .70 → .88.
Against behaviour, tier-1 recall rises .61 → .77–.79 while precision slips .45 → .37–.40.

**Where the configurations differ** is the 141 consensus turns Jev reads as done, progress or unsure, where `next` or
the gates apply (labels there: 1 = 66, 3 = 43, 4 = 26). Δ is the paired bootstrap 95% interval against the plan.

| in scope | acc [95%] | Δ vs planned | t1 P/R | t4 P/R | you reacted to it: t3 vs t4 |
|---|---|---|---|---|---|
| planned (choice 0.6 → note) | .57 [.50–.66] | – | .87/.52 | 1.0/.27 | 36/95 vs 0/7 |
| choice 0.5 → note | .61 | – | .86/.56 | 1.0/.38 | |
| choice 0.7 / 0.8 → note | .50 / .47 | – | .93/.38, .95/.30 | 1.0/.15, 1.0/.12 | |
| choice 0.6 → nothing | .61 | [+.00, +.08] | .87/.52 | .52/.54 | 31/75 vs 5/27 |
| gates step .6, worth .7 → note | .60 | [−.05, +.11] | .77/.71 | 1.0/.19 | |
| **gates step .6, worth .7 → nothing** | **.68 [.61–.76]** | **[+.01, +.20]** | .77/.71 | .68/.81 | 23/47 vs 4/31 |
| gates step .5, worth .7 → nothing | .70 | [+.02, +.23] | .75/.80 | .77/.77 | 19/42 vs 3/26 |
| gates step .7, worth .7 → nothing | .67 | [+.01, +.19] | .81/.65 | .68/.81 | 27/55 vs 4/31 |

1. **The choice question collapses to "note."** In scope Jev picks note 117 times, you 56, nothing 12. Falling back to
   note when unsure removes tier 4 (1% of cards), and every higher floor makes it worse (.57 → .50 → .47). When it does
   say "nothing" it is right: 11 of 11 consensus turns are tier 4.
2. **The fallback matters more than the shape.** Gates with unsure → note are no better than the plan. Sending what
   isn't surely worth reading to tier 4 is the gain, and it holds behaviourally: you reacted to the content of 49% of the
   recommended tier-3 turns, against 13% of its tier-4 ones.
3. **The gates find more finish-ups** (in-scope tier-1 recall .71 against .52) at lower precision (.77 against .87).
   Behaviour can't settle this: finish-up steps mostly happen outside the session. Jev's misses filed as note are mostly
   research answers ending on a recommendation that is yours to take ("I'd do option 1").
4. **Examples help.** Without them the `you` choice over-fires and the `worth` gate stops separating; every variant
   without examples is equal or worse.
5. **`trivial` and unverified barely matter here.** Trivial reaches 0.8 on 3 of 185 in-scope turns; unverified (42
   turns) only changes anything under the → 4 fallback.
6. **Side effect of the asks hint:** 13 of 54 approvals and 15 waits become asks. Both stay tier 1 or correct, but the
   approval card loses its tint.
7. **Closing offers** ("Want me to also…?"): the 23 offer-only turns sit in tier 1 under every configuration; only 3 of
   23 were answered. An asks hint excluding them changed nothing (21 → 20); Jev does not follow it.

## Recommendation

- **Question shape:** two yes/no gates in the same bundle, both with examples, instead of the choice:
  - **step**: "Does the turn leave the user a step to do before the work is finished, for instance merge, push,
    release, relaunch or try it, run a command, test by hand, add a setting or a key?"
  - **worth**: "Even with nothing to do, is the message worth the user reading, for instance a caveat, a risk, a
    decision it took alone, something untested or that 'should work', a finding?"
  Apply them only when the state is done, progress or nil.
- **Floors:** step ≥ 0.6 → tier 1 (finish up); otherwise worth ≥ 0.7 → tier 3; otherwise tier 4.
- **When unsure:** tier 4 ("Done, unread"), not note; keep "unverified ≥ 0.7 ⇒ at least tier 3"; keep `trivial`.
- **Hints:** ship the three rewordings. Consider "(an OK before acting is approval)" in `asks` to keep approvals, and
  "choose among options it recommends" in step's examples for research answers (both untested).
- **Not solved:** Needs you grows from 54% of cards to 68–74% in every configuration, and closing offers are a large
  share of it. That needs its own question or rule, not a hint.

## Caveats

- Labels are model judgments; the labellers saw today's card kind (flatters agreement on kinds) and rate almost
  everything as worth a look (326/505).
- Behaviour cannot tell a finish-up done elsewhere from no action, nor tier 3 from 4 beyond engagement with content.
- Floors were picked on the same 141 in-scope turns they are scored on; intervals are wide and ~16 combinations were
  tried, so the best are optimistic. Confirm on held-out turns.
- Not covered: wait options, circles, "depends", the app's one-line summary, auto-continue, tier 5.
- Jev saw options in sorted key order (as stage A did), so `nothing` came before `note` and `you`; the app's order varies.

Scripts: `sample.py`, `parity.py`, `jev_variants.py`, `labels.py`, `score.py` (`--detail` for confusions). Outputs in
`v2/data/triage_eval/` (gitignored).
