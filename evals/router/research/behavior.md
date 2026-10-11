# How you really talk to your sessions (behaviour study for the Router benchmark)

Source: `evals/router/real/data/corpus.jsonl` (277 transcripts), analysed with throwaway scripts outside the repo.
Aggregates only; quoted snippets are short. Times are Europe/Paris.

## Cleaning (what the numbers stand on)

- **81 sessions dropped as automated**: probe/test projects (`lcu-xturn`, `project-cli`, `proj`, `lookout-live`,
  `approvals-test`, `router-probe`, ...) and one-turn scripted prompts ("Bounded probe...", "Call the mcp__...").
- **28 forks/resumes** share their prefix with the original; turns deduplicated by (timestamp, text).
- **18 agent-written first messages** (13 handoffs that start "Background (from the session that started this one)",
  5 compaction continuations) count as session starts but not as typed messages. 8 injected `<ci-monitor-event>`
  turns are excluded.
- Left: **195 sessions, 1,686 typed messages, 14 active days (Sep 28 – Oct 11), ~104 active hours.**
- Message types and "what the session last said" come from regex heuristics, so read them as ±5 points.

## 1. Volume and rhythm

| | p25 | median | p75 | p90 |
|---|---|---|---|---|
| messages / day | 75 | 118 | 172 | 176 |
| sessions touched / day | 11 | 16 | 19 | 29 |
| new sessions / day | 6 | 9 | 12 | 16 |
| projects touched / day | 3 | 4 | 4 | 6 |

- About **16 messages per active hour**. The gap between consecutive messages has a median of about 2 min whether the
  next one goes to the same session, another session, or a new one (p90 12–19 min). You don't pause before switching.
- Hours: almost nothing before 10:00, then steady 11:00–01:00 (peaks at 11–12 and 19, 21–00). Weekends are as
  active as weekdays.
- Language: about **97% English**, 2.5–3% French (a few whole sessions, one-word retries).

## 2. Concurrency: what the board looks like when you type

| at the moment you type | p25 | median | p75 | p90 | max |
|---|---|---|---|---|---|
| other sessions running | 1 | 2 | 3 | 3 | 5 |
| sessions active in the last 30 min | 3 | 4 | 5 | 7 | |
| sessions active in the last 2 h | 4 | 6 | 8 | 11 | |
| finished and unanswered within 24 h (the board's "waiting" set) | 13 | 16 | 25 | 35 | 43 |

- **82%** of messages are typed while at least one other session is running, and **26%** while three or more are.
- A realistic board has **2 running, 4–6 recently active, and 10–40 idle-but-unanswered sessions**, across 3–6
  projects. Boards of 2–5 sessions are unrepresentative.
- **Project folder ≠ topic.** LCU work often runs in the `microsandbox-workspaces` folder, and `scratch` holds personal
  questions (games, invoices, hardware). Of the 154 new sessions, 89% opened in a project that already had a session
  active in the past 24 h. Same-project siblings are the norm, not the exception.

## 3. Switching and chains

- After a typed message, the next one goes to **the same session 51%**, **a different existing session 40%**, and
  **a new session 9%** of the time. This holds within 3 h windows too.
- Chains (consecutive messages to one session): median 1, mean 2.05, p90 4. Of 828 chains, 467 have length 1. You
  interleave constantly.
- Where a message goes, ranked by when each session last finished:
  - all continuations: the most recent 69%, second 19%, third 5.5%, fourth or later about 4%;
  - **switches only**: most recent 36%, second 32%, third 18%, fourth to sixth 13%. Ignoring the session you just
    left, the most recent other session gets 52%, the next 27%, the next 11%.
  - by when you last *messaged* it (rather than when it finished): most recent 56%. Finish-recency is the better
    signal.
- **Only 28% of switches go to a session that finished since your previous message.** The other 72% go to a session
  that had already been sitting finished: you work through a backlog, not just the newest card. When you switch, a
  median of 1 other session (p90 2) also finished in that window, so there is usually a competitor.
- Time since the destination finished, on a switch: median 5.7 min, p75 22 min, p90 2 h, p95 7.5 h.
- Broadcasts: 9 texts went to 2–3 sessions within 15 min, mostly crash recovery ("we crashed, resume").

## 4. Reply latency and session tempo

- Delay from a session's turn ending to your reply into it: p10 0.3 min, **median 2.2 min**, p75 7 min, p90 29 min,
  p95 94 min. 29% of replies come within 1 min and 70% within 5 min. Only 6% come after more than 1 h, and 0.4% after
  more than a day.
- Turn duration: median 0.8 min, p75 5 min, p90 25 min, p95 56 min. Median 4 tool calls per turn, p90 28.
- Turns per session (human-started): median 5, p75 11, p90 22. 18% are one-turn sessions. Session lifetime has a
  median of 1.1 h and a p75 of 13 h, so sessions are often picked up the next day.
- Caveat: the extraction never shows a message sent while its session was running (queued input), so "running
  session as destination" is invisible here, not absent from real use.

## 5. What messages look like

Length (all typed): chars p10 20, p25 40, **median 88**, p75 190, p90 393, p95 700. Words: median 16, p25 8,
p90 73. 16% have 5 words or fewer, 35% have 10 or fewer.

| type (heuristic) | continuations (1,540) | new-session firsts (154) |
|---|---|---|
| instruction / statement | 56% | 39% |
| question (ends in "?" or opens with what/how/is/can...) | 32% | 36% |
| terse, 3 words or fewer | 8.6% | 0.6% |
| long, over 1,200 chars (pasted reports, prompts from other agents) | 2.4% | 12% |
| contains a URL (GitHub issue/PR, X post) | 0.8% (2.6% overall) | 12% |
| pasted error/log | under 1% | under 1% |

- First messages are a different population: longer (median 27 words, p90 284), with URLs and pasted
  specifications. Continuations are short and conversational.
- Common terse messages: "yes", "do it", "go ahead", "commit it", "approved", "show me", "perfect", "give full
  prompt", "we crashed, resume", "réessayer".
- **20% of continuations open with an anaphor or deictic word** (it/this/that/yes/no/so/and/then/ok/alright). They only
  make sense with the session's last answer.
- **Only 11% of continuations name a project/product** (Lookout, LCU, Silo, ...). Addresses are almost never given.
- 13% multi-line; 4% open with a correction ("no", "wait", "actually").
- 44 continuations and 6 first messages refer to another agent or session ("an agent told me...", "report from
  another agent"). This is cross-session relay, which is a known router trap.

## 6. What the session said last, and what you answered

Last assistant message before a continuation (by its tail):

| session's last message | share | your reply: instruction / question / terse |
|---|---|---|
| asks you something ("Want me to...?", "Should I...?") | 32% | 59 / 30 / 9% |
| report, no clear call to action | 25% | 55 / 31 / 9% |
| done (committed, pushed, fixed, passing) | 23% | 55 / 35 / 7% |
| proposes next steps / options | 14% | 51 / 36 / 10% |
| failed / blocked | 5% | 54 / 27 / 9% (+10% long pastes) |

- About **46% of replies follow a session that asked or proposed something**. The other 54% follow a report or a
  finish, where you start new work in the same thread or question the result.
- Terse replies (146) follow asks 30%, plain reports 28%, done 19%, proposals 16%, failures 6%. A bare "yes" or "do
  it" is **not** reliably tied to a question card. It is often "do the obvious next step" after a report.
- Switch and same-session messages look alike (switches slightly more questions and terse: 34/10% vs 30/7%).
- Questions are 30–36% whatever the session's state. Most are **questions to the session about its own work**
  ("what does X mean?", "did you...?", "so all good?"). This is the population that falsely triggered Lookout's
  question intent in round 2.

## 7. New sessions vs. continuing

- 9% of messages start a session (154, about 9 a day). Per project: microsandbox-workspaces 46, lookout 42, lcu 28,
  scratch 24.
- Resemblance to sessions active in the prior 24 h (TF-IDF cosine against each one's transcript): median best match
  0.07, p90 0.26. 13% score 0.2 or more and 8% score 0.3 or more. Most new sessions are lexically distinct, but a
  clear minority look like an existing session. The patterns behind them:
  1. **Re-launching the same prompt** in a fresh session (retry, or a second attempt in parallel: 3 copies of one
     French prompt; repeated verification prompts).
  2. **A prompt written by one session to start another** (a session drafts a designer prompt, which becomes a new
     redesign session; "give full prompt" appears as a terse continuation).
  3. **The same question asked in two projects** (e.g. an agent-completion question sent to both lookout and
     microsandbox-workspaces).
  4. **Handoffs**: 13 sessions spawned by another session.
- Same-project siblings of a new message are almost always on the board (89%). Picking the project is easy; deciding
  "new vs. that sibling" is the hard part.

## 8. Requirements for a realistic Router benchmark

Episodes should be **sequences replayed on an evolving board**, not isolated cases. Recency, backlog, and "what the
session last said" carry most of the signal. Target distributions:

**Board state at each message**
- Sessions on board: median 16 (range 8–40) unanswered within 24 h, of which 4–6 active in the last 30–120 min. Others
  running: 0 (18%), 1–2 (56%), 3–5 (26%). 3–6 projects with 2–15 sessions each. Same-project siblings with
  overlapping vocabulary in most episodes. Include sessions whose folder doesn't match their topic (a "scratch" or
  "workspaces" folder hosting another product's work).
- Waiting cards: last-message state mixes about 32% asks, 14% proposes, 23% done, 25% plain report, 5% failed.
- Recency: the newest finished session should be the destination about 69% of the time overall and only about 36%
  on switches. Make 30% of switches target the 2nd–3rd most recent and about 13% the 4th or older. Make about 70% of
  switches go to a session that was already waiting before the previous message. A benchmark where the newest card is
  usually right will overrate recency.

**Message mix** (continuations / firsts as above)
- Next-message transition: 51% same session as your previous message, 40% switch, 9% new session. Chain lengths
  geometric-like (mean 2, p90 4).
- Length: median about 15 words; 16% of 5 words or fewer; 2–3% pastes over 1,200 chars; 12% of new-session starts
  with URLs or pasted specifications.
- Types: about 56% instructions, 32% questions to the session about its own work, 9% terse, 2–3% pastes, 4%
  corrections, 20% anaphoric openers, 11% naming a project, about 3% French or mixed, 2–3% cross-session relays
  ("an agent told me...").
- Terse replies after **every** state, not only after asks (about 30% asks, 28% report, 19% done, 16% proposes).
- Timing: reply delays log-normal-like (median 2 min, p90 30 min, a 5% tail of hours to the next day). Inter-message
  gaps of about 2 min regardless of destination. Include next-morning resumptions of yesterday's sessions.

**Episode types to include, with rough weights**
1. Quick back-and-forth with one session while 1–3 others run (about 35%).
2. Clearing a backlog: switching through 3–6 finished sessions in a row, each reply terse or anaphoric (about 20%).
3. A card arrives mid-chain and you either answer it or keep going (about 15%).
4. New-session starts, including near-duplicates of a sibling, re-launches, prompts written by another session, and
   the same question in two projects (about 10%).
5. Crash recovery and broadcasts ("we crashed, resume" to 3 sessions; "commit it" to 2) (about 3%).
6. Cross-session relays, where the message quotes or summarises another session's output (about 3%).
7. Corrections and follow-ups after a wrong route ("no, I meant the other one"), plus Router-native intents
   (settings, board questions, compound messages). The corpus can't measure these, so they must be authored, about
   10–15%, and kept separately weighted so they don't dominate.

**Scoring requirements**
- Score per episode and per step. Report separately by switch/same/new, by recency rank of the gold, by message type
  (terse, question, paste), and by board size. The last two set the real error rate.
- Questions-to-session must outnumber questions-to-Lookout by about 10:1 or more in the mix, or Lookout-intent
  false positives will be under-measured.
- Keep the "running destination" and "queued while running" cases as an explicit authored slice (invisible in the
  transcripts).
