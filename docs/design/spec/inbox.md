# Inbox: categories of things

Agreed with the user (2026-10-10). Replaces Needs you / Bots / Done tabs and the Repositories page entirely; no migration, delete what's obsolete.

## Shape
- The bar's inbox cell is the GitHub mark (not the tray icon).
- Categories are user-made, plus two built-ins: **Done** (always there, not a category, special) and **CI** (default, deletable? no: default, can be hidden).
- Each category: name, SF Symbol (preselected by Jev from the name as you type), color (CategoryColor), rules, notifies (native notifications on/off), hidden.
- Each visible category (not Done) has its own icon in the bar with a notification dot/count when something arrives; clicking opens it.
- Categories are drag-reorderable; order = priority (first match wins).
- Show/hide categories like showing/hiding table columns (a checkmark menu). Hidden = muted (no notifications, no bar icon) but still collects; the menu shows its count.
- ⌃1…9 jumps to category N in order.
- Category pill/dot styling shared with the Router's dots and badges.

## Rules
A category is a list of rules; a thing is in it if any rule matches. A rule:

```
[PRs] by [me] in [Contributing]   (+ to, + in … added with +; unset slot = any, not shown)
when [any ▾ | all] of:
  • condition chip
  • condition chip
```
No conditions = every open thing in scope.

### Kinds and what they offer (menus only offer these)
- **PRs** — slots: by · to (menu on the word: assigned / review requested / mentioned) · in.
  Activity (new since you last marked it done): new comment by · new review by · new commits by · mentions.
  Conversation: last comment by (Conversation tab; reviews with text count; inline threads don't) · unresolved threads started by · last reply by (both optional).
  Review (each reviewer's latest review): approved by · changes requested by.
  Checks: checks failing / pending / passing · has conflicts.
  Status: is draft / ready / merged / closed · labeled · no activity for N days.
  Signals: Greptile score below N (read from `<!-- greptile_confidence_score:N -->` in the PR body; Greptile edits it each review; account is `greptile-apps[bot]`).
- **Issues** — slots: by · to (assigned / mentioned) · in. Activity: new comment by · mentions. Conversation: last comment by. Status: is closed · labeled · no activity for N days.
- **Workflows** — slots: in (required) · on branch (default: repo's default branch) · named. Status: is failing / passing / running.
  CI category = `Workflows in [repos] when is failing`; its editor only takes repos.

### Values
- People: me · @login (autocomplete; @greptile → greptile-apps[bot]) · user groups · **Maintainers** (GitHub authorAssociation OWNER/MEMBER/COLLABORATOR on that repo) · **Bots** (accounts GitHub marks as bots) · `except …`.
- Repos: owner/repo · owner/* · user groups · **Repos I own** · **Repos I contribute to** (repos with a merged PR of yours) · **anywhere you're involved** (PRs/issues only: author, assignee, requested reviewer, mentioned, commented — GitHub's `involves:`) · `except …`.
- Other: labels, branches, workflow names, N days, score 1–5 — autocompleted from repos in scope.
- Groups: named people or repo lists, usable as one chip in any slot of their kind; editing a group updates every rule. Created in a Groups section or inline ("Save as group…" from selected chips).

### Impossible combinations
- Never-matching values aren't offered: with `by me` → no "to me (review requested)", no "approved by me", no "changes requested by me".
- With `all of`, mutually exclusive values disappear (draft vs merged, failing vs passing).
- A value can't be both included and excepted in one slot.
- An edit that makes an existing chip impossible turns it red with the reason; can't save until fixed. Never silently greyed out.
- Switching kind keeps only supported chips and says which were dropped.

## Lifecycle (same for every kind)
- **Notify** when a thing gains a matching fact; the same fact (Fact.key) never notifies twice. CI: one notification per failure, until green.
- **Done** acknowledges the current facts; the item returns only when a new fact matches.
- **Leaves** quietly when nothing matches anymore (thread resolved, checks green).
- **Closed/merged** things only show in rules asking for them (is merged / is closed).
- **First match wins** top to bottom (drag order). Unmatched things dropped.
- Activity before the rule was created, or before Done, is old.
- **Rows** show the matched facts as chips in the rule's words: `Greptile 4/5 · 2 unresolved · last comment: @toksdotdev`.
- **Live preview** in the editor: the rule evaluated in memory against already-fetched things, debounced; no API calls. A repo never fetched says "no history yet for owner/repo".

## Fetching
One GraphQL search per refresh for PRs/issues covers every fact (threads + isResolved, comments, latest reviews, statusCheckRollup, mergeable, isDraft, labels, body for Greptile score, authorAssociation, author __typename Bot). Workflows via the existing REST CI code: one list of workflow runs plus the commit's checks and statuses per repo and branch gives one Thing per workflow (`workflow:owner/repo:<workflowId>@branch`, with its own state and failed jobs; external checks and statuses together are one more, `external`), so `named` filters and CI counts and notifies per failing workflow. Polled repos = repos named by rules + CI repos; `involved` uses `involves:@me` search.

## Code map
- `InboxModel.swift` — types (contract). `InboxEngine.swift` — pure matching. `InboxStore.swift` — Store API. `InboxSync.swift` — fetching. `CategoriesView.swift` — editor. Hub* — bar, lists.
