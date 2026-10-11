# Exploring how the Router asks Jev

Read README.md (round 1) and this file first. Work in `evals/router/` of this worktree.

## The benchmark

`python3 bench.py FORMAT [--sets synth,heldout,real,style] [--policy final|module:name] [--saved]`

| set | what | gold |
|---|---|---|
| synth | 210 written cases (cases/) | 2 labelers |
| heldout | 150 written cases, bigger boards | 2 labelers |
| real | 611 real moments: a message the user really typed into a session, the board as it was then, where it went (real/data/real.jsonl) | strict: only where it went is right; `label` clear/plausible/unclear says whether the board alone shows it (clear: asking is needless) |
| style | Router-style messages written on those real boards (real/data/routerstyle_*.jsonl) | writer's |
| realA / realB | the real set split by session: tune on realA, report realB too | |

Scores per set: right, wrong (and wrong to a session), ask, needless ask, top1. A wrong send is the costly outcome
(the user's words land in the wrong session, or Lookout answers what a session should have); a needless ask costs a click.

Jev: `jev.py` (TypeSafe, key from the Keychain, answers cached on disk in `cache/`, ~0.25 s, input tokens only,
~$0.04 per million). Asking is cheap: run whatever you need, but keep concurrency at the default (8 workers) and do one
benchmark at a time. Jev docs: https://docs.typesafe.ai/llms.txt (choice / noul / score questions; structured criteria
and instructions; up to 255 options; questions of one call are answered in parallel; known weak spots in jev-1.13:
numbers, dates, counting, indirection, long irrelevant state, first-option bias).

## Where we are (shipped: format `swift`, policy `final`)

synth 64% right / 2.4% wrong · heldout 75% / 1.3% · real 15% / 20% (top1 38%).

On real moments the shipped router is unsafe. Known causes:
- the `question` intent catches questions meant FOR a session ("what does X mean?") with p > 0.95;
- the compound gate fires on one long multi-point message for one session;
- the per-card "does it answer this card?" check fires for "Go", "Implement that" with several cards waiting;
- recency is ignored: the most recently finished session is where a real message went 60% of the time (one of the
  last two: 84%); "the only session finished in the last 5 minutes" is right 74% of the time; Jev's top1 is 38%.
  Jev reads "finished 3m ago" poorly (numbers/dates are a weak spot).
- the old format (`v0`, opaque keys) has better real top1 (46%) than the shipped one.

## How to explore

- Put your formats in `explore/<yourname>.py` exposing `FORMATS = {"name": build}`; `build(case, rng=None)` returns
  `(state, questions, keymap)` like formats.py (keymap: route option name → destination, and `answersN` → session for
  card checks; `gate_*` nouls are read as gates). Reuse formats.py helpers. Don't edit shared files; if you need a new
  reading or policy, put it in your module and pass `--policy explore.yourname:policy` (a function of a reading
  dict as run.reading returns, returning ("send", dest) or ("ask", top3)). You may also wrap run.reading in your module.
- Report on every set, with realB as the honest number for anything tuned on realA. Prefer one simple change that
  moves real wrong down without hurting synth/heldout, over a pile of tuned knobs.
- Latency matters: one Jev call is ~0.25 s; a second sequential call doubles it (fine only if it clearly pays).
- End with: what you tried (one line each, with numbers), what worked, what didn't, the best format+policy and its
  table on all sets. Keep your module tidy so the winner can be ported to Swift.
