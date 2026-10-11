# Router routing research (2026-10-11)

What we learned making the Router decide where a typed message goes: what was measured, what shipped, what was not
enough, what was a dead end, and the mistakes made on the way. The code and data live in `evals/router/` (README.md
has the per-round tables, EXPLORE.md the protocol for explorers); the decision itself is in
`Sources/Lookout/RouterRoute.swift` (RouteFusion), `RouterLexical.swift` and `RouterDispatcher.swift` (the rank effect).

## The problem

A message typed in the Router's composer goes to one of your Claude Code sessions (a reply to its card or more work),
to a new session in a project, to Lookout itself (change a setting, a question about the board, several things at
once), or Lookout asks you (an ask-back card). Deterministic rules come first (an armed reply, a pinned target,
`@project` pills, "start a session in X", "tell X to"); what they leave goes to Jev (TypeSafe's decision model: typed
choice / yes-no / score questions over a state, one call, ~0.25 s, input tokens only, ~$0.04 per million) and to code
around it.

A wrong send is the costly outcome (your words land in the wrong session, or Lookout answers what a session should
have); an ask costs a click. Every number below is right sends / wrong sends as a share of messages, unless said.

## How it is measured (evals/router)

| set | what | gold |
|---|---|---|
| synth | 210 cases written by agents: everyday, hard disambiguation, traps | relabelled blind by a second agent, merged (either's acceptable destination counts, asking is fine if either allows it) |
| heldout | 150 cases written independently, bigger boards (15–21 sessions) | same blind relabel |
| real | 611 real moments: a message you really typed into a session, the board rebuilt as it stood then from your transcripts, where it went | strict (only where it went is right); labelled by agents clear / plausible / unclear by whether the board alone shows it |
| style | 332 Router-style messages written on those real boards | writer's |
| realA / realB | real split by session: tune on A, judge on B | |

- `bench.py FORMAT --policy ...` scores a format (how Jev is asked) and a policy (how its answers are decided) on every
  set. Always run with `JEV_ORDERED=1` (see the order mistake below). Answers are cached on disk (`cache/`), so policies
  are swept offline for free (`analyze.py`, `crossval.py`, `cv.py`).
- Real data stays on this machine: `evals/router/real/data/` is gitignored; keys and tokens are redacted before
  anything reaches Jev (`real/boards.py` `redact`).
- Differences under ~5 points between similar variants are noise at these sizes (bootstrap 95% intervals ±5–7).
- The lesson that shaped everything after round 1: **written cases mislead**. Agents write explicit, addressed
  messages; real ones are terse ("go", "commit it"), lean on recency, and ask questions meant for the session.
  Never judge a router change on written cases alone.

## Where it went

| | synth | heldout | real (B) |
|---|---|---|---|
| before round 1 (opaque keys, global history, 0.75/0.3 bar, word veto) | 36.5 / 2.5 | 62.7 / 1.0 | 14.5 / 21.5 (round-1 router) |
| round 1 (shipped, merged to main) | 64.3 / 2.4 | 75.3 / 1.3 | 14.5 / 21.5 |
| round 2 (`combo` + fusion, Lookout's order) | 57.1 / 1.4 | 67.3 / 2.0 | 37.9 / 4.7 |
| round 3 (`combo-o` + `final3`, branch router-jev-2) | 65.2 / 1.4 | 72.0 / 2.7 | 40.7 / 2.8 |

Round 1 looked excellent on written cases and was unsafe on real ones (one real message in five to the wrong place);
round 2 fixed that at a cost on written cases; round 3 recovered the written cases and cut real wrong sends further.

## Round 1: how Jev is asked

Shipped (merged into main as 46d50e6..62c0b94):
- **One option per destination.** A session and its open card were two options, so Jev's sureness of the session was
  split between them (0.5 + 0.4 read as unsure). Merging them: +18 points of right sends, no new call.
- **Options named by the session, described in their own structured criteria** (project, what it is doing now, what
  you last told it), instead of opaque keys `t1..tN` pointing into a fenced state blob. TypeSafe's docs say the same:
  option names are read, indirection costs accuracy. Top-1 89% vs 85%.
- **The message alone as the state.** The global list of your last 10 decisions made "yes" go to the session you last
  wrote to rather than the one asking; what you last told a session belongs on that session's option (69% vs 61%).
- **A yes/no per waiting card**: "is `message` the answer to `card`?". Bare replies ("lgtm", "nope") read as `unclear`
  in the route with one card waiting; the card check gets them (0.6–0.85 where the route said 0.05).
- **Gates**: yes/no checks for "changes how Lookout behaves" and "several things", decided first: "turn off jev labels"
  went to the session building that feature in every format.
- **Bars by what a wrong pick costs**: a session 0.7, a new session or Lookout's own 0.6 (one 0.75 bar with a 0.3 lead
  asked on a third of clear messages).
- **The word-overlap veto removed**: on top of the above it blocked 48 right sends and no wrong one.
- **Routing deadline 2.5 s** (was 20 s).

Not worth it in round 1:
- A second, narrower pass over the top candidates: better top-1, overconfident.
- One yes/no per session instead of one choice: 77% top-1 vs 89%.
- Averaging several option orders: helps the opaque format only.
- More rules in the instruction text: worse (56.7% vs 68.6%).
- Compact descriptions for long-idle sessions: noise.
- Examples of past routings in the state: no measurable effect, dropped.

## Round 2: real sessions

Built the real benchmark (above). On it the round-1 router was 15 / 20. Five explorers (`explore/intents`, `recency`,
`fusion`, `context`, `verify`), then a combination.

Causes of the real wrong sends, and what fixed them:
- **`question` caught questions you ask a session about its own work** ("what does X mean?") at p > 0.95. Fix: word
  Lookout's options by who the message is for ("a question to Lookout about the board … not a question for a session
  about its own work"), plus `gate_you` ("does it speak to one agent as you?") vetoing Lookout's intents. Real wrong
  20% → 9%.
- **The compound gate fired on one long multi-point message for one session.** Fix: `gate_compound2` ("meant for
  different places … several points for one session is no"), required beside the first.
- **Recency ignored.** The session that finished last is where a real message went 60% of the time (one of the last two:
  84%); Jev reads "finished 3m ago" poorly (numbers and dates are a known weak spot). Fix: a yes/no per latest session,
  "is `message` the user's next message in this conversation?" (right 91 of 95 times when one stands out and the route
  doesn't disagree), and a **fused model**: a conditional logit P(destination) ∝ exp(w · features) over Jev's log p,
  recency ranks, running, the checks and gates, with a logistic sureness on the moment; the rules' send when the fusion
  agrees, else the fusion's own pick at sureness 0.9, never for a message under 3 words or to Lookout's own.
- **A session stopped on a question counts as running in Lookout** (its turn is open); in the real boards a waiting
  session was never running, so the fusion's "running" penalty would have misfired. Fixed in Swift: a session waiting on
  you is not working.
- **Options reach Jev in Lookout's order** (working, then latest finished). Shuffled, the decision changed on 14% of real
  moments; Lookout's order was the best of the orders tried. Swift used to send them in dictionary order (random per
  run); `JevClient.orderedObject` now keeps the order.

Explored in round 2 and not enough on its own:
- Categorical recency words ("a few minutes ago"), a `latest: true` field: noise.
- A state field naming the session that finished last: top-1 37 → 57% but Jev obeys it as an instruction (realB 32%
  wrong). Rejected.
- Richer context per option (first ask, last 2 paragraphs): +4–5 top-1, within noise, +40% tokens.
- Fewer options (only the last N hours): no gain.
- A second verification call (pairwise or "fits"): mostly blocks wrong `question` sends; pairwise barely helps; +0.25 s.
- Raising intent bars alone: real wrong 20 → 12%; Jev is confidently wrong there (bars 0.8–0.95 identical).
- Asking intents only through gates (no intents in the route): leaks intent messages into sessions on written cases.

## Round 3: research and the words

A literature pass first; the ideas, what we did with them:

| idea (source) | result |
|---|---|
| Contextual calibration: ask about a content-free input, divide out the bias (Zhao et al. 2021, "Calibrate Before Use") | **Dead end.** Asked in the same call about an empty `nothing` field; dividing out (or weighting) its pull changed nothing beyond noise. Jev's bias here isn't a stable per-option pull. |
| Permutation debiasing / self-consistency (PriDe, Zheng et al. 2024; Tang et al. 2024) | **Dead end.** The route asked twice in one call, in Lookout's order and reversed, averaged: no gain. A fixed order already removes the variance. |
| Batch / domain-conditional calibration (Zhou et al. 2024; Holtzman et al. 2021) | Not pursued after the content-free result. |
| Disentanglement cues: time gaps, speaker, mentions (Elsner & Charniak 2008; Kummerfeld et al. 2019) | Recency already in the fusion; explicit message-type × session-state features (explore/state.py) were **noise**, except one rule (below). |
| Exact identifiers (URLs, PR numbers, paths) as "mentions" | **Not enough.** Only 39 of 611 real messages hold one; a unique best match is right 60%. |
| Lexical overlap / BM25 (disentanglement, email recipient prediction, Carvalho & Cohen 2008) | **Shipped.** Between the message and each session's transcript turns: alone it names where a real follow-up went 54% of the time (Jev 40–48%); by field (last answer +, older turns +, your last instruction −, title −) in the fusion. |
| Selective prediction with guarantees (Learn-then-Test, Angelopoulos et al.) | **Partly.** Risk–coverage showed the rules' path made 24 of 25 real wrong sends while the fused pick at 0.9 was right 78 of 79: a guard (the fused pick must agree at sureness 0.6) shipped. A wrong-send guarantee ≤ 5% isn't certifiable on our real data at useful coverage. |
| Per-user models and thresholds (Gmail Priority Inbox, Aberdeen et al. 2010) | **Promising, not built.** Refitting the fusion weights per user (MAP around the global weights) after ~50 labels: late real wrong 4.5 → 2.3% in a time-ordered replay. kNN over past messages and per-user thresholds added nothing on top. Needs Lookout to record labels (proposed as its own task). |
| Cascades (FrugalGPT, RouteLLM): a bigger model on the uncertain cases | **Dead end.** Haiku (via the CLI, 300 calls) on the asks: on real asks as wrong as right and confident either way (72–92 on both); +1–4 s. It looked good on written cases only (the round-2 trap again). |
| Response selection (Ubuntu next-utterance) | Already ours: the "next message?" yes/no. Asking it for BM25's top candidates too: no gain. Per-candidate checks instead of one choice: worse (round 1 again). |

Shipped in round 3 (branch router-jev-2): BM25 per field (RouterLexical, read from transcripts while Jev answers, the
board's text when there is none), the rules guard, a short-reply rule (under 3 words, fused sureness ≥ 0.95, and that
session's last message asks or proposes something), the ask card with four options (the right one among them on
79–89% of real asks), secret redaction on everything sent to Jev, Jev's question gate in the fusion.

Context-richness, again in round 3 (explore/lexical): text windows (last 1–6 turns, all with decay), user-only vs
assistant-only turns, stemming, French stop words, corpus vs board IDF: all within 3 points; the assistant's turns carry
the evidence, the user's own words are weak (and point away: a message repeating your last instruction starts
something new).

## Mistakes, and what they taught

- **Sorted keys hid option order.** `jev.py` sent `json.dumps(sort_keys=True)`, so named options always reached Jev in
  alphabetical order and round 1's "0 order flips" for them measured nothing. Found by the round-2 recency explorer.
  Fixed (`JEV_ORDERED=1`), and Lookout itself was found to send options in random dictionary order (fixed).
- **Two live keys reached TypeSafe** inside eval requests: an OpenRouter key and a z.ai key from transcripts, before
  redaction existed and then past the first pattern. Redaction now also strips any long letters-and-digits token, in
  the evals and in Lookout (`RouterTools.redacted`). Both keys should be rotated.
- **Porting slips caught only by parity tests** (`RouterFusionParityTests`, fixture from `evals/router/parity.py`):
  a gate the format asked but Swift didn't (`gate_question`), a BM25 quirk (a zero-weight field's words still count for
  IDF), weights rounded in Swift but not in Python, and "Jev's top" breaking ties by dictionary order (now: a tie counts
  as agreement). Every port since round 2 checks decision parity on all 360 written cases.
- **Credits ran out mid-round 2** (HTTP 402) after ~43,000 calls / 106M input tokens (≈ $4.50): benchmarks, not real use.
  Real use is ~5 calls per message (live prediction while typing, the send, card checks), ≈ $0.04/day at 100 messages.
  Most of that is the while-typing predictions.
- **Real-moment caveats**: the real set is messages typed inside a session (no address, context from the
  conversation), a stress test rather than the Router's own traffic; gold is strict; labels come from agents; a
  session's title is its final one; a running session is never the gold in this data (an artefact of the extraction).

## Open leads

1. Per-user learning from corrections, kept sends and answered asks (explore/personal.py has the replay and the
   recipe; proposed as a task).
2. Fewer while-typing Jev calls (they are most of the cost): cancel superseded predictions, longer debounce.
3. Real traffic logs: save the exact request and the outcome with each decision, so corrections become real labelled
   cases of the Router's own traffic (better than in-session moments).
4. Alternatives to Jev, not tested: Cloudflare Clef (Jev-compatible API, better on intent benchmarks per Cloudflare,
   ~6× the price), Laya (open, runs on-device, weak zero-shot past ~20 options). We stayed on Jev (2026-10-11).
