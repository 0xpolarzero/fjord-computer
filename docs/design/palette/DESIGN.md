# The ⌘K palette

The window's header search fields become one palette: ⌘K (or a click on the header's trigger, or ⌘F, or typing on an inbox
page) opens it over the window. Built on branch `palette` (worktree `.claude/worktrees/palette`); each piece below has one
owner and its own files. Where things live in the code today: [integration-map.md](integration-map.md). The look:
[search-tabs-avatars.md §1](../spec/search-tabs-avatars.md) (Claude desktop's palette, traced). Why it is built this way:
[docs/research/command-palettes/report.md](../../research/command-palettes/report.md).

## What it is for

Three jobs, nothing else. Not a list of every command.

1. **Empty: what needs you now.** No query shows, in order:
   - **Needs you**: Router cards waiting on you (questions, plans, asks, approvals; then stuck), oldest first; then the
     Triage items that need a look (unread in a shown, non-archived category; failing CI on your PRs), newest first, at
     most 5 of those.
   - **Recents**: the last items picked in the palette (usage store), at most 5, not repeating the group above.
   - If both are empty: **Go to**, the pages (Router, Inbox categories, Archive, Computers, Settings…).
   ⌘K ↩ takes you to the next thing waiting on you.
2. **Typing: find anything Fjord knows, one ranked list.** Sessions (title, project, branch), Router cards, inbox items
   (title, `#482`, `repo#482`, a pasted GitHub URL; archive included, ranked below), projects, categories, computers and
   Triage runs, saved prompts, pages, settings rows ("token" → the GitHub token row's section), a handful of commands.
   Best match first, ↩ opens it. Where Fjord knows a PR and a session belong together (a Triage action handed the PR to the
   session, a waiting card watches its CI), each lists the other as an action ("Open its session", "Open the PR").
3. **No good match: send it.** While typing, the last row is **Send to the Router: "…"** (only when the Router can send).
   With no results it is the only row, so ↩ sends. The Router picks the session, as from its composer.

**Actions belong to rows.** ↩ runs a row's first action. Tab or ⌥↩ opens the selected row's actions page (Claude's
pattern), listing all its actions with the shortcut that does the same outside the palette. Backspace on an empty query or
Esc goes back. Free-standing commands are only the few with no row to hang off: New category, Add a code folder (Settings,
Code folders), Refresh now, Check for updates, Turn a tool on/off (Settings, Tools).

**Left out on purpose:** commands already one click away in the menu bar, theme and view toggles, nested pages beyond the
actions page, AI rows beyond the Router send, full-transcript search.

## Entry points

- ⌘K anywhere in the window (once past onboarding) toggles it. Fixed shortcut, `Palette.shortcut`.
- The header's trigger replaces `InboxSearchField` on the inbox pages and the Router page: same pill (200×26), magnifier,
  muted "Search", and a ⌘K keycap badge at its end (`Palette.shortcut.caps`). A click opens the palette.
- ⌘F opens it (on every page that had a search).
- On an inbox page, typing a printable key (or a dead key) opens it with that key typed into it, as the inbox search did.
  On the Router page typing keeps going to the composer.
- The in-page searches stop being reachable: their models stay until a later piece removes them.

## Architecture

```
PaletteSources (3)  ──make(ctx)──▶  PaletteModel.open()  ──PaletteIndex──▶  PaletteRanker.rank(query)  ──▶  PaletteView
  router / triage / places             corpus built once per open              per keystroke, synchronous        rows
```

- **Overlay inside the app window**, attached like `ComputersQuitDialog` (`AppRootView` `.overlay`, high `zIndex`):
  50% backdrop over the window, surface positioned and sized per spec §1.2. No separate window, no sheet.
- **SwiftUI for the static chrome** (backdrop, surface, header row, footer, rows).
- **AppKit for the query field** (an `NSTextField` in an `NSViewRepresentable`): keys are handled in
  `control(_:textView:doCommandBy:)` (`moveUp:`, `moveDown:`, `insertNewline:`, `insertTab:`, `cancelOperation:`,
  `deleteBackward:` on empty), so dead keys and input methods finish before the palette sees anything (AZERTY `^` then
  `e`). Filtering runs from `controlTextDidChange`, never on marked text.
- **The list** is a `ScrollView` + `LazyVStack` of fixed-height rows (36 rows, 37 group headers per spec), stable ids
  (item ids), no animation when results change, rows `Equatable`, the selection held apart from the results so moving it
  redraws two rows, not the list. Results are capped (50 while typing). If measuring shows a keystroke over budget
  (docs/performance.md), switch the list to an `NSTableView`.
- **The window's key monitor** (`AppWindow.watchKeys`) runs before any field editor. While the palette is open it passes
  every key through untouched except ⌘K (closes) — no Router/inbox handler sees them. While closed it opens the palette
  on ⌘K, ⌘F, and inbox typing.
- **Selection:** a new query selects the first row; data changing under the same query keeps the selected item if still
  listed. The pointer selects a row only after it has moved more than 3 pt since the last key or scroll, and a hover never
  scrolls. Keyboard moves scroll the row into view (nearest edge). ↑ on the first row and ↓ on the last stay put.
- **Running:** picking closes the palette, gives the keyboard back to what had it, then runs the action on the next run
  loop turn (so the action applies to what you were looking at), and records the pick in the usage store.
- **Opening:** the corpus is built synchronously when it opens (a few thousand items at most); the first frame already
  holds the empty palette's groups. No open/close animation beyond a fade per spec; never a window capture.

## Ranking

`PaletteRanker.rank(query, in: index, usage:)`, synchronous on the main actor, folded text prepared once per open.

1. **Tier first** (a higher tier always wins): exact title → title prefix → word-start prefix (each query word starts a
   title word, any order) → acronym (`gubi` → getUserById, `rt` → Router tools) → title substring → title subsequence
   (fuzzy, scored by gaps, word starts, consecutive runs) → keyword match (`#482`, URL, project, section) → nothing.
   Multi-word queries: every word must match somewhere (title or keywords); the tier is the worst word's.
2. **Within a tier:** the match score, times the item's `weight`, times a usage boost: frecency of the item (recent and
   frequent picks; half-life about 7 days) and the per-query learning (picked after typing this query or a prefix of it).
   Usage reorders only within a tier.
3. **Ties:** newer `date` first, then title, then id, so the order never shuffles between keystrokes.

**Folding:** lowercased, accents dropped (é→e, ç→c), and œ→oe, æ→ae, ß→ss (Foundation's diacritic folding leaves œ/æ
alone), on both the query and the items; curly quotes to straight. The highlight ranges map back to the original title.

## Pieces and owners

| Piece | Files (owned) | Touches (small hunks) |
|---|---|---|
| **Core**: model, overlay view, field, keys, trigger, shots, signposts | `PaletteModel.swift`, `PaletteView.swift`, `PaletteField.swift`, new tests | `AppWindow.swift` (monitor, overlay, model ownership), `AppContent.swift` + `RouterCode.swift` (trigger in place of the field), `AppWindowKeys.swift` + `RouterKeys.swift` (⌘F/typing → palette), `AppWindowShots.swift` |
| **Matcher**: folding, tiers, highlight, usage store | `PaletteMatch.swift`, `Tests/FjordTests/PaletteMatchTests.swift` | — |
| **Router source** | `PaletteRouterSource.swift`, its tests | — |
| **Triage source** | `PaletteTriageSource.swift`, its tests | — |
| **Places source** | `PalettePlacesSource.swift`, its tests | — (settings row anchors only if a row can't be reached through its section) |

`Palette.swift` (the shared types) is fixed: change it only by asking the coordinator.

## Rules for every piece

- Read `CLAUDE.md`, `DEVELOPMENT.md`, `docs/performance.md` and this file first.
- Match the code around you: comment density, naming, idiom (doc comments say what a thing is for, in plain sentences).
- Verify with `swift build`, filtered `swift test --filter <Suite>` (one run at a time, never in parallel or in loops),
  and `--window-shots` PNGs you then read. Never build the app bundle, never launch the app, no LCU.
- Commit each verified piece on your branch, conventional prefix (`feat: `, `fix: `, `test: `…), no scope, plain sentence
  about the result. Never push, never touch `main`.
