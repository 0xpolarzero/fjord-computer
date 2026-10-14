# Palette integration map

Where the palette's data and actions live in the code (as of main 4059470e). Paths under `Sources/Fjord/`. Line numbers are
approximate; signatures are verbatim. Check before relying on one.

## Surprises

1. `AppWindow.swift` `watchKeys()` (~L1011) is the only window-level key hook and runs before any view or field editor. It
   calls `RouterKeys.key` on the Router and `inboxKeys.key` elsewhere. `RouterKeys` turns Esc (nothing left to step out
   of) into `close()` (closes the window) and any printable key with no focused text field into composer typing. Skipped
   when `store.settings.toolsPicked != true` or `store.isRecordingShortcut`.
2. ⌘K is bound nowhere. The local monitor runs before menu key equivalents.
3. `AppRootFollow` (`AppWindow.swift` ~L1309) runs `search.end(); routerModel.endSearch()` on every `navigator.selection`
   change, then clears `hub.selection`/`hub.keyboardSelection` unless the pick is in `store.entries(in: place.tab)`. Set
   `hub.selection` before `navigator.go` so it survives.
4. `store.entries` includes entries of hidden categories; `.category(hidden).resolved(...)` falls back to the first shown
   category, where that entry isn't listed. With Triage off, `.category`/`.done` resolve elsewhere. Things matching no
   category are only in `store.things` and have no place.
5. Per-entry actions today: Open on GitHub, Open in Router, Copy link, mark read/unread, Archive/Back to inbox. Re-run and
   hand-to-session exist only as category actions run automatically; no manual per-entry trigger.
6. Settings scrolls by section only (anchors below), not to a row.
7. No NSTextField/NSTableView wrapper exists. The only text-input representable is `MentionField` (an NSTextView tied to
   `RouterModel`).
8. Shots never run the key monitor; a shot can't depend on first responder.
9. `.claude/worktrees/router-lanes/` (in the main checkout) is a stale full copy of the sources; `RouterFilter.swift-E` is
   not compiled. Tests constructing touched types: `AppWindowKeysTests`, `RouterSearchTests`, `AppContentTests`.

## Router

- `RouterModel` (`RouterView.swift` ~L390), `@Observable @MainActor`, not on `Store`. `AppWindowController.routerModel`
  passes it to `AppRootView`/`AppContent`.
- On the store: `store.router: RouterState` (`cards: [RouterCard]`, `decisions`, `summaries: [RouterSummary]`,
  `origins: [String: SessionOrigin]`, `enabled`), `store.claudeSessions: [String: ClaudeSession]` (all, archived
  included), `store.allAgentRows: [AgentRow]` (listed sessions only: running, unread, with tasks, or active in the last
  hour, not muted/hidden), `store.sessionRow(_ id: String) -> AgentRow?` (`RouterSessions.swift` ~L230, any session),
  `store.routerZones: RouterPage` (`RouterPage.swift` ~L194), `store.routerWorkingRows`, `store.routerCounts`.
- `ClaudeSession` (`Claude.swift:7`): `id, title, folder: String?, isArchived, completedTurns, lastActivity: Date,
  lastFocused, lastUserMessage, summary, running, cliID: String?, sshHost`; computed `folderName`, `folderKey`.
- `AgentRow` (`Agents.swift` ~L88): `session, entry, label, color, project, activity, tasks`; `projectName`, `id`
  (session id), `unread`, `waitsForYou`, `group`, `workingSince`.
- `RouterCard` (`Router.swift` ~L228): `id` (`<session>#t<turns>` / `<session>#w<ms>`), `sessionID, kind: Kind, title,
  folder, text, createdMs, addressedAt, addressedBy, origin: SessionOrigin?, triage: RouterTriage?, brief, asks, unread`;
  `createdAt`, `isOpen` (`addressedAt == nil`), `tier`. `Kind`: `question, plan, done, stuck, asks, approval, waiting,
  finish` (labels Question, Plan, Done, Stuck, Asks you, Needs your OK, Waiting, Finish up); `kind.needsYou` for all but
  done and waiting.
- Zones (`RouterZones.swift`): `needs, notes, waiting, working` ("Needs you", "Worth a look", "Waiting", "Working").
  `RouterPage.make` (`RouterPage.swift` ~L75): open cards passing `shows` → `needsYou` kinds to `page.needs`; other open
  kinds but waiting to `page.notes`; waiting cards with `tier == .needsYou` and an idle session to `page.ready` (drawn and
  counted in Needs you); other waiting to `page.waiting`; working sessions are `page.working: [AgentRow]`.
  `RouterPage.zone(of:)` (~L635).
- Navigate: `routerModel.select(_ id: String?, store: Store, reveal: Bool = true, expand: Bool = true)` (`RouterView.swift`
  ~L693: selects, ends a hiding search/filter, expands, reveals with a highlight) then `navigator.go(.router)`. That is
  `AppRootActions.openRouter` (`AppWindow.swift` ~L1253, env `\.openRouter`). A working session with no card:
  `navigator.go(.router)` + `routerModel.reveal(RouterModel.workingID(sessionID))`.
- Card/session actions: reply `model.reply(to card: String, store: Store, reveal: Bool = true, expand: Bool = true)`;
  open in Claude `store.openAgent(_ id: String)` / `store.openCard(_ id: String)`; archive card `model.address(_ id:
  String, store:)`; reopen `model.reopen(_:store:)` (gate `store.routerCanReopen`); fork `store.forkSession(_ session:
  String, point: SessionFork.Point = .whole, …)` (`RouterFork.swift` ~L247; offered when `store.routerOn &&
  row.session.cliID != nil`; `.beforeLast` variant); summary `model.summarizer.request(_ sessionID: String, store:)`.
- Composer: `model.prefill(_ pointers: [RouterPointer], text: String = "")` (focuses it); "Open in Router" on a thing is
  `routerModel.open(thing: String, in navigator: AppNavigator)` (`AppWindow.swift` ~L1159); env `\.openInRouter` is nil
  unless `store.offers(.openInRouter)`. `RouterPointer`: `project(String), session(String), notification(String),
  category(UUID), thisItem`.
- Send programmatically: `store.sendToRouter(_ text: String, context: RouterContext = RouterContext(), now: Date = Date())
  -> Bool` (`RouterView.swift` ~L87) or `sendToRouter(_ parts: [RouterMessagePart], …)` (`RouterPointer.swift` ~L151).
  `model.canSend(_ store: Store) -> Bool` (Router on and Claude Code found). Demo/playground (`store.routerIsPretend`)
  only logs a canned reply.
- On/off: `store.routerOn`, `store.isOn(.router)`, `store.tools`.

## Triage

- `InboxEntry` (`InboxModel.swift` ~L730): `thing: Thing, categoryID: UUID, facts: [Fact], isDone, isUnread, importance,
  labels`; `id` = thing id. One entry per thing (first matching category, hidden included).
- `Thing` (`InboxModel.swift` ~L533): `id` (`pr:owner/repo#12`, `issue:…`, `workflow:owner/repo:<wfid>@<branch>`),
  `kind: ThingKind` (`.pr .issue .workflow`), `repo, number: Int?, title, url: URL, author: Person?, status` (`.open
  .draft .merged .closed`), `labels, createdAt, updatedAt, checks: CheckState?, workflowName, branch, failingJobs`.
- `store.entries` (memoized), `store.entries(in category: UUID)`, `store.entries(in tab: InboxTab)`, `store.doneEntries`,
  `store.things: [String: Thing]`, `store.inboxSearchKeys: [String: String]` (lowercased title, repo, `#number`,
  `@author`, workflow, category, facts). `enum InboxTab { case category(UUID), done }`.
- Show an entry in the window (as `AppWindowController.show(entry:)` ~L921 does): `hub.selection = "i:" + entry.id`;
  `go(entry.isDone ? .done : .category(entry.categoryID))` (resolved); `hub.requestScroll("i:" + entry.id)`.
- Entry actions: `store.open(_ entry:)` (GitHub, marks seen), `store.finish(_ entry:)` (archive, 30 s undo),
  `store.restore(_ entry:)`, `store.markSeen(_:)`/`markUnread(_:)`, Open in Router `routerModel.open(thing: entry.id, in:
  navigator)`, Copy link (inline in `EntryMenu`, `HubComponents.swift` ~L368).
- Item ↔ session: `store.actionLedger.runs: [String: ActionRun]` (`ActionRun.thing` = real thing id, `sessionID:
  String?`, `computerRunID: UUID?`); `store.actionChips(for entry:) -> [InboxActions.Chip]` (targets `.session(String)`,
  `.url`, `.router`, `.computerRun(UUID)`); `RouterCard.origin: SessionOrigin` (`thing` is display text, not an id);
  `RouterTriage.Watch.Target.ci(thing:)` on a waiting card holds a thing id.
- Categories: `store.categories: [InboxCategory]` (`id, name, symbol, color, rules, notifies, hidden, isCI, actions,
  section, title`), `store.shownCategories`, `store.category(_ tab:)`. Edit: `store.editCategory(_ id: UUID, go:
  (AppDestination) -> Void)`.
- Triage runs: `store.actionLedger.computerRuns: [UUID: ComputerRunRecord]` (`id, thingID, computerName, repo, branch,
  taskTitle, phase (.title), startedAt, updatedAt, pullRequestURL`); `go(.computerRun(id))`.

## Places

- `AppDestination` (`AppNavigation.swift:8`): `category(UUID), done, router, computers, computerDetail(String),
  computerRun(UUID), settings, categories, snippets`; `static func all(shown: [UUID], tools: Set<Tool>)` (sidebar order),
  `resolved(shown:tools:)`, `isOn(_:)`, `tool`. Display names: `AppWindowController.title(for:)` (~L952, instance method:
  "Router", "Archive", "Inbox categories", "Triage run"…).
- Computers: `store.computers: ComputersModel`; `store.computers.inventory?.allComputers: [ComputerRow]` (`id, name, kind,
  displayState (.title), detail`); `go(.computerDetail(row.id))`; real data only when `store.computersEngineReady`.
- Snippets: `store.snippets: [Snippet]` (`id: UUID, name, text`, `title`, `preview`); page `.snippets`; no way to open
  one snippet; insert into the composer with `routerModel.prefill([], text:)`.
- Projects: `store.projectFolders: [String]`, `store.folderName(_:)`, `store.projectColor(_:)`; no destination; route
  with `RouterPointer.project(folder)` via `prefill`.
- Settings: `go(.settings)`; scroll a section with `hub.settingsScroll = ScrollRequest(id: anchor, seq: (hub.settingsScroll?.seq
  ?? 0) + 1)`. Anchors (`SettingsView.swift` ~L19): `notifications`, `updates`, `general`, `router` (the Router row of
  Tools). Sections and rows in order, with conditions:
  - Tools: Triage, Router, Computers.
  - Computer defaults (computersOn && engine ready): Automatic checkpoints, Retain automatic checkpoints, Start computers at launch.
  - Connected Macs (same): Allow other Macs to connect, Add a Mac, SSH setup.
  - GitHub (triageOn): sign-in, Personal access token.
  - Notifications: Desktop notifications, Snooze banners.
  - Claude (routerOn): Router style, Muted folders, Let Jev read what you type, Let Jev label new comments, Icons picked for you, TypeSafe API key.
  - Code folders (triageOn || routerOn): Where your clones are, Repos found.
  - Shortcuts: one row per offered `ShortcutAction`, then All shortcuts.
  - Updates: Fjord <version>, Check for updates automatically.
  - General: Check every, Launch at login, Center the bar on its edge, Quit Fjord.
- Tools: `enum Tool { triage, router, computers }`; `store.isOn(_:)`, `store.tools`, `store.triageOn`, `store.routerOn`,
  `store.computersOn`, `store.toolsLinked`, `store.setTool(_:on:)`.

## Keys and search today

- `AppWindowKeys.key` (`AppWindowKeys.swift` ~L93): false on marked text; ⌘F → `search.start()`; Esc ladder (end search,
  clear pick, close); printable/dead key → `search.start(replaying: event)`; ↑/↓ move; only on `.category`/`.done`.
- `InboxSearch` (`AppWindowKeys.swift:11`): `query, focused, focusRequest, caretAtEnd, pendingKeys`, `start(replaying:)`,
  `typePendingKeys()`, `end()`. `InboxSearchField` (~L284): SwiftUI TextField, 200×26 pill, `.help("Search · ⌘F")`.
- Used at `AppContent.swift` ~L41 (inbox header), `RouterCode.swift` ~L122 (`InboxSearchField(search: model.search,
  label: "Search the Router")`). `AppWindow.swift` ~L196 `let search = InboxSearch()`.
- `RouterKeys.key` (`RouterKeys.swift` ~L29): false on marked text; ⌘1–⌘4 ask-back buttons; ⌘F → `model.search.start()`;
  Esc ladder → `close()`; printable → composer.
- Shortcuts: `struct Shortcut { keyCode: UInt16; modifiers: UInt }`, `.display` ("⌘K"), `.caps` (`["⌘","K"]`).
  `ShortcutAction` cases `togglePanel, router, openItem, toggleRead, discard, markAllRead, refresh, openInRouter`;
  `store.shortcut(_:)`, `store.offers(_:)`. Menu bar: `System.swift` ~L840 (no Find item).

## Shots

`AppWindowShots.swift`: `struct Shot { name, destination: (Store) -> AppDestination, sidebarHidden, size, compose:
((RouterModel, Store) -> Void)?, prepare: ((Store) -> Void)?, appearance }`, `static let catalog`. `open(_ shot:)` makes a
`Store`, `Demo.populate(store, .router)`, `prepare`, an `AppNavigator`, a `RouterModel` + `compose`, then `AppRootView(...)`
(it already accepts an optional injected `search: InboxSearch?`) in an offscreen `ShotWindow`. Run:
`.build/debug/Fjord --window-shots .build/shots palette`.

## Styling

- `ClaudeDesign.swift`: `CDS.Surface.s0…s3` (s3: popovers, menus), `CDS.Text.primary/secondary/muted/…`,
  `CDS.Fill.field/secondary/secondaryHover/ghostHover/ghostSelected/…`, `CDS.border`, `CDS.hairline`,
  `CDS.PanelShadow.far/.near`, `CDS.Keycap` (size 18, radius 4), `CDS.Density.compact/comfortable`, `CDS.sans(_:_:)`,
  `CDS.nsSans`, `.cdsText(role, weight, color)`. `Theme.Radius.shape(_:)`.
- Overlay precedent: `ComputersQuitDialog` (`ComputersView.swift` ~L617), attached in `AppRootView.body` as `.overlay { …
  .zIndex(100) }` (`AppWindow.swift` ~L1241). Closest list look: `MentionList` (`RouterComposer.swift` ~L393).
- Keycaps: private `Keycaps(caps:ink:)` (`Shortcuts.swift` ~L500), `CDSShortcut(keys:ink:)` (`RouterForms.swift` ~L523).
- Row parts: `SessionGlyph(row:size:dot:)`, `ProjectLabel(name:color:)` (`RouterSessions.swift`), `KindTag`, `FactChip`.
- VoiceOver: `Announce.say(_:)`.

## Existing search code worth reusing

- `RouterMentions.candidates(_ store: Store, except:, query:, first:) -> [MentionSuggestion]` (`RouterPointer.swift`
  ~L427): projects, sessions (non-archived, working first), open notifications, categories, snippets — the `@` corpus.
- `RouterMentions.score(_ name: String, query: String) -> Int?` (~L539): 0 prefix, 1 word prefix, 2 contains, 3
  subsequence.
- `RouterSearch.key(_ card: RouterCard, project: String)` and friends: lowercased search text per card, history line,
  working row. `store.inboxSearchKeys` per entry.
