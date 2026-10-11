# Router: a dispatcher, not a chat

Agreed with the user (2026-10-10). Replaces the single long-lived Claude Code session with a transcript.

## Principle
Every trigger is a typed event that runs a short workflow. Deterministic rules first, Jev second, a Claude run (Haiku) only when judgment or tools are needed. Each run builds its own context; there is no transcript and no resume. Every run appends one entry to the decision log, which is the Router page's history.

## Surfaces
- Router: Claude Code sessions, and Lookout itself (app tools, changes shown as cards with Revert). Never GitHub.
- Inbox actions: the Router (start a session with a prompt) and GitHub (comment, re-run checks).

## Workflows
### A. From Claude Code (session asks, plans, finishes, is stuck, works)
Deterministic, as today (RouterFeed): cards, banners, the live Working line. The feed is the subscription.
- A session cannot message the Router: with no long-lived process there is no peer named "Lookout" to receive it (Claude Code delivers `SendMessage` over a per-process socket it lists in `~/.claude/sessions/<pid>.json`, a private protocol Lookout does not imitate). What a session wants from you reaches you as its own cards (question, plan, done, stuck).
- Working cards are live, with a 1–2 sentence explanation of what is happening, and a 1–2 sentence summary of what the turn did when it ends. Source: the session's activity stream and the Claude app's own summary when present; Haiku fills gaps, only on change (turn start, at most every ~30 s while tools run, turn end). The end-of-turn line is the card's text in the history and context for later runs.

### B. You type
1. Deterministic: a reply armed on a card, or a typed `@project`, fixes the target. The text gets a deterministic edit of the user's own bytes, never a model's rewrite: the `@project` pills it starts with (by where the composer put them, never by matching words against a project's or a session's name) and `@router` asides are taken out, in two explicit forms only, never in code (fenced, indented or inline): a bracketed aside opened right before the marker and closed, balanced, on the same line (`(@router no rush)`, `[@router later]`), its bracket and marker outside code but code inside it its own (`(@router don't wait on `` `CI` ``)`), brackets in that code not counted, never one opened inside a double-quoted span on its line (`"(@router no rush)"`, `“…”`: the quote's text; single quotes are apostrophes as often and never count), or a whole line that starts with `@router`. Anything else, "tell <session> to …" and a `@router` anywhere else in the text (`ask @router`, `print(f'ask @router')`) included, is sent verbatim: no quote or code is guessed at, so nothing is cut short and nothing is refused for it. Nothing is added or reworded, so what is signed as the user's words is always theirs.
2. Otherwise Jev classifies (RouterRoute.swift; measured in evals/router): one option per destination (a session, its open card part of it; a new session per project; change Lookout, question, compound, unclear), named by the session's title and described by its project, what it is doing now and what you last told it; the message alone as the state. In the same call: whether the message answers each card waiting on you, whether it changes how Lookout behaves, whether it asks for several things.
   - Confident: a gate sure of its intent; else one card's answer standing out (unless the route is sure of another session); else the route's pick at the bar of what a wrong one costs (a session 0.7, a new session or Lookout's own 0.6). Act; the history shows what was done.
   - Unsure: an ask-back card under the message with the top targets as buttons plus "Something else…"; nothing is sent until the user picks. Only a click picks (a button, "Something else…", or Dismiss): text typed while it waits is a message of its own, routed as itself, even when it reads like a target's name, so a session titled "Don't deploy" is never picked for saying "don't deploy". The pick is logged as a decision.
3. A Claude run (Haiku) only for: changing Lookout, compound requests, questions about state. Fresh `claude -p` with a context built for this run (live-state snapshot, last 10 decisions, the message), only the tools that intent needs, a typed result (`--json-schema`). Starting a session may carry a model and effort (`--model`, `--effort`).

### C. From an inbox action ("Ask the Router")
Through the Router (logged, visible), without a model:
- The action knows the repo: one local clone is used; several → Jev picks; none → the run fails "no local clone".
- The session starts with the user's prompt (GitHub content fenced as untrusted), optionally with the action's model and effort overrides.
- The session is tagged with its origin (category, thing, action, run); its later cards say "⚡ from <category> · <thing>", and the inbox row links to it.

## Memory
The decision log: one entry per run (trigger, decision, what was done, outcome: sent, started, changed, reverted, corrected). The last 10 entries are part of every Claude run's context; Jev reads only what you last told each session, on that session's option. Entries where the user chose something other than the suggestion are labelled as corrections. Nothing else.

## Cards: addressed
- Explicit: submitting a form, approving or sending back a plan, "Mark handled".
- Otherwise Jev decides, after any message that touches a session with open cards, per card: resolved → history ("addressed by your message"); partly (e.g. 1 of 3 questions) → stays, showing what is left; not → stays. Unsure → stays.
- Reopen from the history puts a card back in Needs you.

## Page
Bottom-anchored: Needs you (prominent, one card open), Working (live lines), above them the history (the decision log and addressed cards, one line each, expandable). The composer has inline @project pills.

## Removed
The long-lived process, `--resume`, the transcript (`chat`), peer turns and the ability of a session to message the Router, the single serial queue (runs are independent), the role prompt's header grammar. What stays of the old file: `changes` (the records behind change cards); old `chat` and `claudeSessionID` keys are read (changes migrated) and dropped on the next save.

## Phases (each tested and committed on its own)
1. Decision log, and the history built on it.
2. Typed runs: dispatcher → rules → Jev → Haiku; the ask-back card.
3. Inbox actions start sessions directly, tagged with their origin; model and effort overrides.
4. Model and effort for sessions the Router starts. Asked for before the task ("with opus: …") or in a closing clause set apart from it by a comma, semicolon, dash or parentheses (", with opus", " — using haiku, high effort", "(with opus)"); an unseparated "with <model>" at the end is the task's own words. Nothing named: the session runs on the user's Claude Code defaults; nothing (Jev included) picks them for the task.
5. Jev decides what a message addresses.
6. Live Working explanations and end-of-turn summaries.
7. Remove the long-lived process, resume and transcript.
