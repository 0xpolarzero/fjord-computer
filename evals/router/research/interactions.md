# Every way you talk to the Router, and what our evals cover

Sources: the Router spec, Router*.swift (dispatcher, route, live target, cards, waiting, triage, card judge, runs),
SessionLauncher.swift; eval sets `cases/` (210), `heldout/` (150), `real.jsonl` (611), `routerstyle_*` (332); Router* Swift tests.

Legend: **E** covered by a Jev eval set; **P** partly; **U** Swift unit tests only (Jev stubbed, never measured);
**N** nothing. Path: **D** deterministic, **J** Jev + fusion, **D→J** a rule may settle it, else Jev.

## 1. The pipeline, as the code runs it

1. `plan()`: a message wholly for the Router (`@router` line) → classify among intents only, even with a reply armed;
   reply armed → that card's session (D); pinned target → there (D); one `@project` pill with a start phrase, or a
   project with no card and no live session → start there (D); else classify (J), narrowed to pilled projects.
2. `classifyAndAct`: reuses the sure pick shown for these exact words; a waved-off target forces an ask; a destination
   your words name ("start a session in X", "tell X to", "X:", X a project with one session) overrides Jev (D); a
   session with an open **approval** card gets unaddressed words only by a click; a vanished target → ask; sure → act,
   else an ask-back with up to 4 options, "Something else…", Dismiss.
3. `reply()`: a message that is exactly an option of a single-question form answers it (D); plans are never answered by
   text; else the words are sent and Jev judges which of the session's cards they resolved (card judge, separate call).
4. Intents: a fresh Haiku. `change_fjord` (settings, categories, groups, inbox marks; change cards with Revert),
   `question` (read-only), `compound` (Lookout part done, the rest *said back*: nothing is sent to sessions).

## 2. Message contexts

| # | Context | How it arises | Correct behaviour | Path | Evals |
|---|---|---|---|---|---|
| C1 | Free composer, nothing armed | type and Return | route by board + words; ask when unsure | J | **E** (all 1,303 cases) |
| C2 | Reply armed on a card | click a card / its header / banner, Reply, keys | always that session; form answered if exact option | D | **U** (no context field in cases) |
| C3 | Armed reply that *follows* to the next card | the card was handled while the draft was empty | goes to the next card's session; with a draft, stays on the old one | D | **U** |
| C4 | Armed reply but the message is clearly for elsewhere ("turn off notifications" with a reply on a CI card) | user forgets the chip | today: sent to the card's session regardless; only a whole `@router` line escapes | D | **N** (open question: should a strong intent/other-session signal warn?) |
| C5 | One `@project` pill, start phrase or empty project | `@` suggestions | new session there, title from the task, model/effort clause parsed | D | **U**; **P** in evals (1 case with a leading @ in text; pills not representable) |
| C6 | One `@project` pill, project has sessions/cards | | Jev narrowed to that project's sessions + `new:` | J | **N** (no `projects` narrowing in eval schema) |
| C7 | Several pills | | Jev narrowed to those projects | J | **N** |
| C8 | Pinned target (clicked prediction, non-card) | click ghost chip | send there, logged as confirmed | D | **U** |
| C9 | Live prediction shown and sent as shown | pause typing, chip appears, Return | go with it, no second call, `confirmed` | D (reuses J) | **U**; prediction accuracy on *drafts/prefixes* **N** |
| C10 | Live prediction waved off (Esc) | | never sent there unasked: forced ask if Jev picks it again | J+D | **U** |
| C12 | `@router` aside inside a message for a session (`(@router no rush)`) | | aside stripped, rest routed normally | D→J | **U** (Addressing tests); **N** in evals |
| C13 | Whole message for the Router (`@router what needs me?`) | | intents only; ask if Jev's top isn't an intent | D→J | **U**; **N** in evals |
| C14 | Start phrase without pill: "start a session in lcu to …" | | `new:lcu` if one project matches | D | **E** 21 start-phrase cases, **U** |
| C15 | Start phrase, no project named ("new session to fix the docs") | | Jev picks project; ask if unsure | J | **P** |
| C16 | "tell X to …" / "X: …", X a project with one session | | that session, even against Jev | D | **E** 7 tell/ask + ~15 "X:" (some prose); **U** |
| C17 | "tell X to …", X has several sessions or is a session title | | not deterministic; Jev, `spokenAddressee` ranks the ask | J | **P** (traps `addressed` 10) |
| C18 | Model/effort in a start ("…, with opus, high effort") | | parsed into settings, stripped from the task | D | **U** (19 Prepare tests) |
| C19 | Text typed while an ask-back waits | | a new message of its own, never a pick | D | **U** |
| C20 | Pasted code / error / URL / long multi-point brief | | routed by content; one long brief for one session is not `compound` | J | **P** (pasted-error 4, pasted 3, pasted-url 1) |
| C21 | French, typos, abbreviations | | as English | J | **E** (~23 French-ish, typo ~9, abbrev 4) |
| C23 | "Ask the Router" inbox action | inbox row action | one clone → start; several → Jev picks clone; none → fails | D→J | **U**; clone pick **N** |

## 3. Card states (what a card on the board makes a message mean)

Kinds: `question` (form), `plan`, `asks`, `approval`, `done`, `stuck`, `waiting` (CI / another session; "Tell it").
Addressed by: you, reply, router (card judge), answered, opened, superseded, gone.

| # | Card state | Correct behaviour for a matching message | Path | Evals (360 written; real/style) |
|---|---|---|---|---|
| K1 | question, single, message = option label | form answered | D (with C2, or when Jev picks the session) | **U**; Jev side **P** (49 question cards, option-content 7, option-number 5) |
| K2 | question, answer by content/ordinal ("the second one", "go with postgres") | sent as text to that session | J | **P** (ordinal 10, option-content 7) |
| K3 | question, multi-select / several questions, partial answer | sent; card stays showing what is left | J + card judge | **N** (card judge never evaluated) |
| K4 | plan to approve ("lgtm", "go", "change step 3 first") | sent as text (never answers the plan form); the Accept button is the explicit path | J | **P** (11 plan cards) |
| K5 | approval ("yes", "do it") | forced ask unless addressed by project name or clicked | J+D | **P** (38 approval cards; the forced ask is Swift-only, absent from the Python policy, so evals over-credit sends here) |
| K6 | asks (free-text question in the last message) | reply there | J | **E** (97 written; 979 in real, 510+ style) |
| K7 | done, follow-up ("now commit it", "also add tests") | the session that just finished, usually | J (recency, BM25, next-message) | **E** (real: 550 follow-ups) |
| K8 | stuck ("try with sudo", "skip that test") | that session | J | **P** (19 cards; none in real) |
| K9 | waiting on CI / another session | "Tell it" button (D); a typed "CI is green, continue" should go to it | J | **N** (no `waiting` kind in any set) |
| K10 | several open cards in one session | one destination (latest card); card judge decides which resolve | J | **P** (10 cases) |
| K11 | two or four sessions waiting on you, bare "yes" | ask (unless one stands out) | J | **E** (two-waiting 19, four-waiting 8) |
| K12 | card of a session not in the offered 20+working (old) | offered as its own option | J | **N** |
| K13 | card addressed/hidden/superseded while Jev was asked | ask among what's there now | D | **U** |
| K14 | card of an archived session; Reopen of an old card | not eligible / `canReopen` false | D | **U** |
| K15 | replying to an older card while a newer one is open in the same session | same session; the old card may be judged resolved | J | **N** |

## 4. Session states

| # | State | Correct behaviour | Evals |
|---|---|---|---|
| S1 | working (live line) | can receive more work; fusion penalises "running" | **E** written (running ~16 tags); real: never gold (extraction artefact) |
| S2 | stopped on a question (turn open) | counts as waiting, not working | **N** (no case has `running: true` with a waiting card) |
| S3 | idle, finished minutes ago vs days ago | recency weighs; the 20-most-recent cut drops old ones | **E** (idle_min everywhere; real) ; beyond-cutoff **N** |
| S4 | many sessions in one project, related topics | content decides; ask when close | **E** (same-project 18, overlap 12) |
| S5 | same titles | named "Title (project)"; across one project indistinguishable by name | **P** (5 cases with repeated titles) |
| S6 | project with no session | `new:` | **E** |
| S7 | archived sessions | never targets | **N** (schema has no archived sessions) |
| S8 | big boards (20–80 sessions, 60 projects) | prefix limits | **P** (max 25 sessions; transforms.py pads to 22) |
| S9 | session with background tasks after its turn | `done` card hidden | **N** |

## 5. Lookout's own intents

| # | Intent | Example | Correct behaviour | Evals |
|---|---|---|---|---|
| L1 | change a setting | "turn off jev labels", "stop notifying me for drafts" | `change_fjord` → Haiku with tools, change card + Revert | **E** 24 gold written; style ~40 |
| L2 | categories / groups / rules / inbox marks | "add a category for dependabot", "mark those read" | same | **P** (category 2, groups 5, rules 1) |
| L3 | setting vs building the feature | "turn off jev labels" with a session building them | `change_fjord`, not the session | **E** (traps 5, setting-vs-code) |
| L4 | question about the board | "what's waiting on me?", "is the CI one done?" | `question` | **E** 32 written; style ~50 |
| L5 | question *to* a session about its work | "what does that flag do?" | the session, never `question` | **E** (real: the cause of round-1 wrong sends) |
| L6 | compound | "commit it and add a category" | `compound` (Lookout part done, rest said back) | **E** 11 written; style ~30 |
| L7 | one long multi-point brief for one session | | not compound | **P** (near-compound 3) |
| L8 | two sessions in one message ("tell lcu to X and silo to Y") | `compound`; nothing is sent to either session | **P** (two-sessions 3); whether the user expects both sends: **N** |
| L9 | small talk / fragment ("hmm", "wait") | ask or nothing | **E** (small-talk 10) |
| L10 | quality of the Haiku run's answer / change | correct tool calls, honest reply | **U** (stubbed); **N** measured |

## 6. Multi-turn flows

The eval schema is one message on one frozen board; `history` holds earlier messages (and `corrected_from` in 4 cases).
No set replays a sequence where the board and the log change between messages.

| # | Flow | Correct behaviour | Path | Evals |
|---|---|---|---|---|
| M1 | ask-back → pick → follow-up a minute later ("also run the tests") | follows the pick (lastTold, recency) | J | **N** as a sequence; **P** via static history (≤2 min history in 18 cases) |
| M2 | ask-back → Something else → project | start there | D | **U** |
| M3 | ask-back dismissed, message retyped more explicitly | route the new words | J | **N** |
| M4 | wrong send → correction ("no, that was for the lcu one") | today: a new message; ideally to lcu with the previous text, or ask | J | **N** (and no product behaviour for it beyond Pick-corrects-ask) |
| M5 | correction recorded → similar message later | per-user learning (not built) | J | **P** (`explore/personal.py` replay) |
| M6 | session just finished → immediate reply ("ok push it") | that session | J (short-reply rule) | **E** (real; just-finished 6) |
| M7 | a chain of instructions to one session while it runs ("also…", "and…") | same session; it is working | J | **P** (real chains exist, but gold never a running session) |
| M8 | switching between sessions ("back to the inbox bug: …") | content + title decide | J | **P** |
| M9 | replying to an older card / older session after newer ones finished | content must beat recency | J | **P** (stale-live 5, old-session 2, long-gap 1) |
| M10 | reply sent, card judge resolves/partially resolves, next bare "yes" | the next card waiting, not the one just answered | J | **N** |
| M11 | live prediction changes as you type more words | the chip follows the draft; sent words decide | J | **N** (no prefix evals) |
| M12 | "Tell it" on a waiting card / auto-continue | D send | D | **U** (51 Waiting tests) |
| M13 | two messages in flight at once to different places | independent runs | D | **U** |
| M14 | reply armed, user changes their mind mid-draft (Backspace removes chip) | classify instead | D→J | **U** |

## 7. Coverage matrix (rolled up)

| Area | Items | E | P | U only | N |
|---|---|---|---|---|---|
| Message contexts | 21 | 4 | 3 | 11 | 3 |
| Card states | 15 | 3 | 5 | 3 | 4 |
| Session states | 9 | 4 | 2 | 0 | 3 |
| Lookout intents | 10 | 6 | 3 | 1 | 0 |
| Multi-turn flows | 14 | 1 | 4 | 4 | 5 |
| **Total** | 69 | 18 | 17 | 19 | 15 |

Data facts behind it:
- Written sets (360): cards `done` 798, `asks` 97, `question` 49, `approval` 38, `stuck` 19, `plan` 11, `waiting` 0;
  waiting-on-you cards per case: none 225, one 92, two 34, three 1, four 8; 4–25 sessions (mean 11.6); 59 messages under
  three words. Gold: session ~210, `new` 52, `question` 32, `change_fjord` 24, `compound` 11, must-ask 12.
- Real (611): `done`/`asks` cards only; gold 550 sessions + 61 new, **no intents**, never a running session; typed
  *inside* a session, so not Router traffic.
- Style (332): real boards, written messages; `done`/`asks` cards only; covers intents and compound.
- No set has: a `context` (armed reply, pills, pin, prediction), `@router`, archived sessions, running sessions
  stopped on a question, `waiting` cards, multi-question forms, sessions past the 20-recent cut, transcripts for written
  cases, or message sequences.
- Never measured: the card judge, end-of-turn triage (a card's kind), live predictions on partial drafts, the inbox
  clone pick, Haiku run outcomes.

## 8. What a top-tier eval set needs

1. **A `context` field** (`reply_to`, `pills`, `pinned`, `shown`, `not_to`) and a scorer that runs `plan()` and the
   in-classify rules (named destination, approval forced ask, eligibility) before the fusion, so deterministic and Jev
   paths are scored together; include C4 cases (reply armed, message plainly elsewhere).
2. **Sequences**: initial board + N turns, the expected effect applied after each (card addressed, session running,
   lastTold, ask pending, correction); covers M1, M3, M4, M7, M9, M10.
3. **Full card vocabulary**: `waiting`, forms (labels, multi-select, several questions), plans, several cards per
   session, cards beyond the offered list, running sessions stopped on a question, archived look-alikes.
4. **Real Router traffic**: log request + decision + outcome in Lookout (open lead 3); meanwhile convert real
   in-session moments to Router form and keep the in-session set as the stress test.
5. **Card-judge and triage evals** (resolved / partly / not; card kind of a final message): shipping Jev decisions, unmeasured.
6. **Live-prediction evals** on prefixes (2, 4, 8 words): a sure wrong chip the user accepts is a confirmed wrong send.
7. **Intents on real boards**, plus Haiku-run outcome checks (tool calls vs gold change, answer faithful to the board).
8. **Scale**: 40–80 sessions, 30+ projects, many "Quick bug fix" titles; French and mixed-language messages.
9. Explicit gold per case (must-send / ask-ok / must-ask); wrong sends scored separately for rule vs Jev paths (round 3:
   24 of 25 real wrong sends came from the rules' path).
