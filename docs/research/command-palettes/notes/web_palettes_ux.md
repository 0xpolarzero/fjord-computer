# Web/Electron command palettes: interaction details and engineering techniques

Scope: cmdk, kbar, VS Code Quick Open / Command Palette, Superhuman, Linear, Slack Quick Switcher, GitHub, Vercel, Notion, Claude. Source code was read directly from fresh clones and raw files on 2026-10-14: cmdk at commit dd2250e (v1.1.1, Oct 2025), kbar main (last commit 2026-08-10), and VS Code `main`. GitHub links point to `main` and may drift.

## 1. cmdk: what the library does, and what its history shows about edge cases

### Takeaway
cmdk is an unstyled combobox and listbox. The text input keeps focus, and a "selected" value moves among the items through `aria-activedescendant`. On every keystroke it filters and sorts synchronously with a memoized recursive scorer (command-score), reorders the DOM by hand, and auto-selects the first item. It has no virtualization and its README rates it for about 2,000–3,000 items. Most of its fixes are small feel bugs: IME composition, hover stealing the selection, and the list scrolling under a mouse.

### Cited Findings

**Origin and adoption**
- Paco wrote it in 2019 to test a composable combobox API. Rauno used it for "the Vercel command menu and autocomplete" in 2020, and it was "Re-written independently in 2022 with a simpler and more performant approach." — [cmdk README](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- The GitHub repo now shows as `dip/cmdk`; `pacocoursey/cmdk` redirects there. — [dip/cmdk issues](https://github.com/pacocoursey/cmdk/issues)

**Scoring (command-score, `cmdk/src/command-score.ts`)** — [command-score.ts](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts)
- Constants:
  - `SCORE_CONTINUE_MATCH = 1` for a contiguous match.
  - `SCORE_SPACE_WORD_JUMP = 0.9` for a new match after a space or `-`.
  - `SCORE_NON_SPACE_WORD_JUMP = 0.8` for a new match after `\ / _ + . # " @ [ ( { &`.
  - `SCORE_CHARACTER_JUMP = 0.17` for a mid-word jump.
  - `SCORE_TRANSPOSITION = 0.1`.
  - `PENALTY_SKIPPED = 0.999` per skipped character or word break.
  - `PENALTY_CASE_MISMATCH = 0.9999`.
  - `PENALTY_NOT_COMPLETE = 0.99` when the target is longer than the query, so "html" beats "html5".
- The source comments explain the intent. A match at a word start "is more likely" because users type word fragments. Transpositions are "significantly penalized". The decay terms don't change the order "until 100 characters are inserted between matches."
- The algorithm recurses over every occurrence of each query character with `indexOf`, memoized on `stringIndex,abbreviationIndex`. It keeps the best score and returns a value in [0,1]. A score of 0 hides the item.
- Lowercasing happens once before recursion, not on every call. The comment says per-call `toLowerCase()` "was the dominating cost".
- Spaces and hyphens are normalized to a single space, so either one matches the other.
- Keywords (aliases) are appended to the value as `value + ' ' + aliases.join(' ')` and scored as one string.
- Lowercasing of value and keywords at registration was removed in [commit 3dae25d, fixes #150](https://github.com/pacocoursey/cmdk/commit/3dae25d). Case still affects rank only through the 0.9999 penalty.

**Filtering and sorting pipeline (`cmdk/src/index.tsx`)** — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- When `search` changes, it runs "Filter synchronously before emitting back to children": `filterItems()`, then `sort()`, then `schedule(1, selectFirstItem)`. There is no debounce and no async step.
- `filterItems()` scores every registered item into a `Map<id, score>`, counts items with a score above 0, and marks a group visible if any of its items scored above 0.
- `sort()` orders items by descending score inside each group. Ungrouped items are appended to the list root. Groups are then ordered by their best item's score through `appendChild`, which is manual DOM reordering. The FAQ admits this "Uses risky approaches like manual DOM ordering."
- With an empty search, nothing is filtered or sorted, so items keep their authored order.
- `shouldFilter={false}` turns off built-in filtering and sorting so the app can do its own. The FAQ says this gives "Better memory usage and performance. Bring your own virtualization this way." — [README FAQ](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- "**Virtualization?** No. Good performance up to 2,000-3,000 items, though." — [README FAQ](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- An item's value defaults to its trimmed `textContent` when no `value` prop is given ([commit 39d58db](https://github.com/pacocoursey/cmdk/commit/39d58db)). The FAQ warns: "Make sure your `Command.Item` has a `key` and unique `value`."
- `forceMount` keeps an item or group rendered whatever the filter says ([#101](https://github.com/pacocoursey/cmdk/commit/a502db2)).
- Groups are hidden with the `[hidden]` attribute, not unmounted ([#27](https://github.com/pacocoursey/cmdk/commit/e9ef1e5)).

**Selection model**
- Selection is keyed by item value, not by index.
- After every filter, `selectFirstItem()` picks the first non-disabled item in DOM order, which is the best-scored item. In practice, the highlight resets to the top result on every keystroke.
- Changing `value` also re-focuses the input (or the root) "so accessibility works", then updates `selectedItemId` for `aria-activedescendant`.
- Keyboard bindings:
  - ↑/↓ move one item.
  - **⌘↑/⌘↓** jump to the first or last item.
  - **⌥↑/⌥↓** jump to the first item of the previous or next group.
  - Home and End jump to the first or last item.
  - With `vimBindings` (on by default), **Ctrl-N/J** move down and **Ctrl-P/K** move up ([#5](https://github.com/pacocoursey/cmdk/commit/238d878); toggle added in [#168](https://github.com/pacocoursey/cmdk/commit/dc0d0e5)).
  - Enter dispatches a custom `cmdk-item-select` event on the selected item.
  — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- `loop` wraps from last to first and back. It is off by default. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx), [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- Disabled items are skipped by every navigation query (`:not([aria-disabled="true"])`).

**Pointer vs keyboard selection**
- Items select on `onPointerMove`, not on `mouseenter`.
- A pointer selection calls `setState('value', v, true)`. The third argument means "should NOT be scrolled into view", so a hover never scrolls the list. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- Issue #3, "Do not scroll item into view from pointer events", calls it "jarring from a mouse event to have the list scroll 'underneath' you"; auto-scroll should happen only on keyboard changes. It was fixed in [#5](https://github.com/pacocoursey/cmdk/commit/238d878). — [dip/cmdk#3](https://github.com/pacocoursey/cmdk/issues/3)
- `disablePointerSelection` turns hover-to-select off entirely, "like Raycast" ([PR #116](https://github.com/pacocoursey/cmdk/commit/e97839f), v1.0.0). With it on, hover only styles the row and clicks still run the item. — [v1.0.0 release](https://github.com/pacocoursey/cmdk/releases/tag/v1.0.0)
- Scroll-into-view runs only on first render and on keyboard changes ([#135](https://github.com/pacocoursey/cmdk/commit/9b97580)).
- It uses `scrollIntoView({block:'nearest'})`, so the list scrolls only as far as needed.
- When the selected item is the first in its group, the group heading is scrolled into view first, so the header stays visible. — [index.tsx `scrollSelectedIntoView`](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- Issue #317 asks for a way to stop the mount-time scroll "when no user interaction has occurred, yet". — [dip/cmdk#317](https://github.com/pacocoursey/cmdk/issues/317)

**IME composition**
- [#166](https://github.com/pacocoursey/cmdk/commit/5c24283) stopped Enter from running an item while `isComposing` is true.
- [#339 (Mar 2025)](https://github.com/pacocoursey/cmdk/commit/f34d463) went further and skips all key bindings during composition. Its check is `e.nativeEvent.isComposing || e.keyCode === 229`, where 229 covers legacy CJK IME events. Before this, arrow keys and Ctrl-N/P "double-triggered" while composing.

**ARIA**
- Input: `role="combobox"`, `aria-autocomplete="list"`, `aria-expanded`, `aria-controls`, and `aria-activedescendant` ([#108](https://github.com/pacocoursey/cmdk/commit/5a61d5f)).
- List: `role="listbox"` with `aria-label`, default "Suggestions".
- Item: `role="option"` with `aria-selected` and `aria-disabled`, mirrored as `data-selected` and `data-disabled` for styling.
- Group: the wrapper has `role="presentation"`, the heading is `aria-hidden`, and the items container has `role="group"` with `aria-labelledby`.
- `Command.Loading`: `role="progressbar"`.
- Issue #322: keyboard nav fails when there's no `Command.Input`, because of focus. — [dip/cmdk#322](https://github.com/pacocoursey/cmdk/issues/322)
- Sources for the above: [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx), [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)

**Height animation**
- `Command.List` puts a ResizeObserver on an inner sizer. In a `requestAnimationFrame`, it writes the measured `offsetHeight` to the CSS variable `--cmdk-list-height`, so CSS can animate the list's height as the result count changes.
- The rAF was added to avoid "ResizeObserver loop limit exceeded" ([#65](https://github.com/pacocoursey/cmdk/commit/605ae13)).
- `offsetHeight` replaced `getBoundingClientRect` ([#121](https://github.com/pacocoursey/cmdk/commit/64bef04)).
- Sources: [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx), [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)

**Pages, async items and empty states**
- Nested "pages" are app state, not a library feature. The README's recipe keeps a stack of page names and pops it when "Escape goes to previous page" or "Backspace goes to previous page when search is empty".
- "Show sub-items when searching" renders deeper items only when `search` is non-empty, read through `useCommandState`.
- For async items, render them as they arrive inside `Command.Loading`; filtering and sorting apply automatically.
- `Command.Empty` renders when the filtered count is 0. First-render logic was removed in [be4388e, fixes #149](https://github.com/pacocoursey/cmdk/commit/be4388e).
- Source for the above: [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)

**Batching**
- All side effects (select first, scroll into view, update the active id) go through `useScheduleLayoutEffect`. It is a keyed map of callbacks flushed in one layout effect, which coalesces repeated work in a single commit. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)

### Inferences
- For a native port, the details worth copying are:
  - Hover selects only on real pointer motion (`mouseMoved`, never tracking-area enter from content scrolling).
  - Pointer selection never auto-scrolls.
  - Keyboard selection scrolls "nearest" and reveals the group header for a group's first item.
  - ⌘↑/↓ and ⌥↑/↓ jumps.
  - Ctrl-N/P.
  - Keys are suppressed while `NSTextInputClient.hasMarkedText()` is true, which is the native equivalent of `isComposing`.
- The reset-to-top-on-every-keystroke behavior is deliberate in cmdk. Holding the selection on the same value across a result change is not built in; see section 5.

### Gaps
- I couldn't run GitHub issue search: the API was rate-limited and the repo rename broke `repo:` search. So the issue list here comes from the commit history plus a few issues found by web search. I didn't find a specific cmdk issue measuring performance with thousands of items beyond the README's 2–3k figure.

## 2. kbar

### Takeaway
kbar is a more opinionated palette with built-in virtualization (TanStack Virtual), Fuse.js matching, throttled search, nested actions with Backspace-to-parent, an undo/redo stack, and animation hooks that include a "bump" on page change.

### Cited Findings
- Matching uses Fuse.js with weighted keys. The final rank is the match score plus `action.priority`. Sections have their own priority, and a higher priority sorts higher. — [useMatches.tsx](https://github.com/timc1/kbar/blob/main/src/useMatches.tsx)
- Search input and filtered actions pass through `useThrottledValue(value, ms = 100)`, a 100 ms throttle. — [utils.ts](https://github.com/timc1/kbar/blob/main/src/utils.ts), [useMatches.tsx](https://github.com/timc1/kbar/blob/main/src/useMatches.tsx)
- Results are virtualized with `useVirtualizer` from `@tanstack/react-virtual`.
- `scrollToIndex(activeIndex, { align: activeIndex <= 1 ? "end" : "auto" })` aligns the first rows to the end, so the section header above stays visible.
- When the first row is a section-header string, the active index skips to row 1.
- Rows select on `onPointerMove` and only when the index actually changes.
- Source: [KBarResults.tsx](https://github.com/timc1/kbar/blob/main/src/KBarResults.tsx)
- Nested actions use `parent` IDs. Backspace in an empty search with a `currentRootActionId` returns to the parent, and the placeholder becomes the parent action's name. — [KBarSearch.tsx](https://github.com/timc1/kbar/blob/main/src/KBarSearch.tsx), [types.ts](https://github.com/timc1/kbar/blob/main/src/types.ts)
- Options include `enableHistory` (`undoStack`, `redoStack`, `undo`, `redo`), a `toggleShortcut` defaulting to `$mod+k`, and `disableDocumentLock`/`disableScrollbarManagement`. By default the page scroll is locked while the palette is open. — [types.ts](https://github.com/timc1/kbar/blob/main/src/types.ts), [InternalEvents.tsx](https://github.com/timc1/kbar/blob/main/src/InternalEvents.tsx)
- Animation:
  - Entry: opacity, then scale .99 → 1.01 → 1.
  - Height: tweened from the previous ResizeObserver height over `enterMs/2`.
  - Bump: scale 1 → .98 → 1 whenever `currentRootActionId` changes, i.e. on entering or leaving a nested page.
  - `enterMs` and `exitMs` default to 0.
  - Source: [KBarAnimator.tsx](https://github.com/timc1/kbar/blob/main/src/KBarAnimator.tsx)
- Global action shortcuts are registered longest-sequence-first, so with actions `['t','s']` and `['s']`, typing "t s" doesn't fire both (tinykeys issue #37). — [InternalEvents.tsx](https://github.com/timc1/kbar/blob/main/src/InternalEvents.tsx)

### Inferences
- The kbar "bump" is a cheap way to make a page transition register without a slide animation, and it fits Rauno's "don't animate high-frequency surfaces" advice better than a full transition.
- The 100 ms throttle trades latency for throughput. cmdk and VS Code's in-memory picks filter on every keystroke instead (see section 6).

### Gaps
- I found no kbar benchmark numbers.

## 3. VS Code Quick Open / Command Palette

### Takeaway
VS Code has two filters:
1. A matrix-based fuzzy scorer for files and editors (`fuzzyScorer.ts`), with tiered thresholds: exact path match, then label prefix, then label match, then label+description match.
2. A stricter word or contiguous-substring filter for commands.

Recency is a persisted LRU, 50 commands by default, that sorts above everything else and gets its own "recently used" separator. Async providers return "fast and slow picks", which merge after a 200 ms grace period to avoid flicker. Requests are cancelled per keystroke. The progress bar appears only after 800 ms busy. The list is a virtualized tree with fixed row heights.

### Cited Findings

**fuzzyScorer.ts** — [fuzzyScorer.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts)
- `scoreFuzzy` builds a query × target matrix. A cell keeps a match only if the previous query character also matched on the diagonal, so matches stay in sequence; the comment's example is "ede" vs "de".
- It also tracks consecutive-match length. Positions are recovered by walking back from the bottom-right cell.
- `computeCharScore` adds:
  - +1 per matched character.
  - A consecutive bonus of `min(seq,3)*6 + max(0,seq-3)*3`, which caps the boost from long runs.
  - +1 for same case.
  - +8 at the start of the target.
  - A separator bonus: 5 after path separators, 4 after other separators.
  - +2 for an uppercase character inside a word (camelCase, so "NPE" matches NullPointerException). It is not given inside a contiguous run, so "HTTP" vs "HTTP" gets no boost.
- Item tiers:
  - `PATH_IDENTITY_SCORE = 1<<18` for an exact path.
  - `LABEL_PREFIX_SCORE_THRESHOLD = 1<<17` for a label prefix match, plus `round(query.length / label.length * 100)`, so `window.ts` beats `windowActions.ts` for "window".
  - `LABEL_SCORE_THRESHOLD = 1<<16` for any other label match.
  - Otherwise the score comes from `description + sep + label`.
- `compareItemsByFuzzyScore` tie-breaks in this order: identity, then label score, then a more compact label match (for non-prefix matches), then the shorter label, then the label+description score, then a label match beating a description-only match, then a more compact overall match distance, then a fallback compare.
- `prepareQuery` splits on whitespace into pieces, all of which must match. A query wrapped in `"…"` sets `expectContiguousMatch`, which turns off fuzzy matching. Normalization strips `*`, `…`, whitespace and quotes, and a trailing `#`.
- Results are cached in a `FuzzyScorerCache` keyed by a hash of label, description, query and options.

**Commands palette** — [commandsQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/commandsQuickAccess.ts)
- The filter is `WORD_FILTER = or(matchesBaseContiguousSubString, matchesWords)`. It matches the label or an alias by contiguous substring or by word prefixes; it does not use fuzzyScorer. — [filters.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/filters.ts)
- Sort order:
  1. tf-idf "similar commands" results go to the bottom.
  2. Then MRU order by counter, where a used command beats an unused one.
  3. Then "suggested" command IDs.
  4. Then non-Developer before Developer category.
  5. Then `localeCompare` on the label.
- Separators are inserted for "recently used", "similar commands", "commonly used" and "other commands".
- Recently used rows have a "Remove from Recently Used" button.
- The aria label includes the keybinding.
- `CommandsHistory` is an `LRUCache<string, number>` mapping commandId to a monotonically increasing counter. `DEFAULT_COMMANDS_HISTORY_LENGTH = 50`, set by `workbench.commandPalette.history`. It is persisted to profile storage only when changed. There is also a `preserveInput` config.

**Anything / file picker** — [anythingQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/search/browser/anythingQuickAccess.ts)
- `MAX_RESULTS = 512`.
- `TYPING_SEARCH_DELAY = 200` ms. A `ThrottledDelayer` wraps the file search, with the comment "accommodates for the user typing a word and then stops typing". It is used only while the file query cache isn't loaded yet; once warm, search runs immediately.
- `SYMBOL_PICKS_MERGE_DELAY = 200` ms: "allow some time to merge fast and slow picks to reduce flickering".
- Editor history ("recently opened") is the fast pick and is matched on label only, unless the query contains a path separator. Its sort order is configurable as fuzzy or `recency`.
- File and symbol results come after a separator and exclude anything already in history.
- The empty state reads "No matching results".

**Async provider contract** — [pickerQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/pickerQuickAccess.ts)
- `_getPicks(filter, disposables, token)` can return picks, a Promise, or `FastAndSlowPicks {picks, additionalPicks: Promise, mergeDelay?}`.
- Each keystroke cancels the previous `CancellationTokenSource`, and every await checks `isCancellationRequested`.
- Fast picks are applied at once, or after `mergeDelay`, skipping an empty list "to reduce flicker". Slow picks are then appended and `busy` is set during the wait.
- Updates that shouldn't jump use `keepScrollPosition = true`.

**Busy indicator** — [quickInput.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickInput.ts)
- `busy` starts the infinite progress bar only after an 800 ms `TimeoutTimer`. Fast operations never flash a spinner.
- `itemActivation` defaults to `FIRST`.
- `matchOnLabelMode` can be `'fuzzy'` or `'contiguous'`.

**Virtualized rendering** — [quickInputList.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickInputList.ts)
- The list is a `WorkbenchObjectTree` with an `IListVirtualDelegate`.
- Row heights: 22 px for an item, 44 px with a detail line, 30 px for a separator.
- Highlights are rendered by `IconLabel` with `supportHighlights`.

**Input selection on reopen** — [quickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickAccess.ts)
- With `preserveValue`, the cursor goes to the end of the text.
- Otherwise the text after the provider prefix (such as `>`) is selected, so typing replaces the old query but keeps the mode prefix.
- If the value is unchanged, the previous picker's selection range carries over.

### Inferences
- VS Code makes the first result predictable through tiers, not pure scores: prefix > anywhere, and label > path. That approach suits a native palette whose rows have a title plus a subtitle.
- Showing a spinner only after 800 ms, and merging fast and slow results after 200 ms, are concrete numbers worth copying for async groups.

### Gaps
- I did not verify in source this session that file search goes through ripgrep (`ripgrepFileSearch.ts` in `workbench/services/search/node`), so treat it as unconfirmed here.
- I did not trace how the quick-pick list behaves on mouse hover (focus vs hover styling).

## 4. Superhuman, Linear, Slack, GitHub, Vercel, Notion, Claude

### Takeaway
The published sources stress five things:
1. One palette for every command.
2. Context-aware boosts rather than hiding commands.
3. Aliases shown inline.
4. The shortcut shown in each row, to teach it.
5. Measured speed, with sub-100 ms as the goal and Slack's 7 ms open and 12 ms render as a real data point.

Linear has published almost nothing about how its ⌘K is built; its changelog is the main source.

### Cited Findings

**Superhuman**
- Rules from Tim Boucher, "How to build a remarkable command palette", Superhuman blog, 12 Oct 2021:
  - Use one app-wide shortcut, and the same shortcut dismisses the palette.
  - Remember the previously focused element and restore focus on close.
  - If ⌘K already means something (e.g. insert link in an editor), a second press opens the palette.
  - Every command lives in the palette, and commands are registered from anywhere and decoupled from the UI.
  - Place it centered and large, with a monospaced font.
  - Show about 5 rows with the last one cut off, so the list "invites scrolling".
  - Give each command an icon.
  - Match fuzzily and case-insensitively with command-score, with a filter threshold such as 0.0015.
  - Support aliases, displayed as "Title (matching alias)".
  - Give each command a default score that decides what shows before typing; a score of 0 means hidden.
  - Apply per-command scale multipliers and "follow" ordering constraints.
  - Use last-used ordering in some lists.
  - Hide commands only when fully irrelevant, and otherwise boost them by context (draft focused, list vs conversation view).
  - Show the shortcut in each row so users learn it.
  - Source: [Superhuman blog](https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/)
- Rahul Vohra on why Command exists: users "would forget our shortcuts. They knew what they wanted to do, but they didn't know how to do it", so ⌘K both does it and teaches the shortcut. — [Superhuman blog: game design](https://blog.superhuman.com/game-design-not-gamification/)
- Vohra cites a goal of 100 ms or less for every interaction. — [Antler Early Days](https://www.antler.co/blog/antler-early-days-episode-2-superhuman-with-rahul-vohra); [Acquired](https://www.acquired.fm/episodes/special-superhuman-part-ii-designing-software-to-feel-like-a-game-with-rahul-vohra)
- One third-party write-up claims an internal 50–60 ms target. — [blakecrosley.com](https://blakecrosley.com/guides/design/superhuman) (unverified; Superhuman's own sources don't confirm it)

**Linear** (changelog only)
- Oct 2019: the command menu "gives you access to all actions applicable to your view or selection".
- It also opens from UI controls (assign, priority) next to the element that invoked it. It "acts almost like a drop-down element but still retains its searchability and keyboard controllability".
- Opening it deactivates Peek.
- Source: [Linear changelog 2019-10-07](https://linear.app/changelog/2019-10-07-contextual-command-menu)
- Later changelog entries (from a search summary; I did not fetch them individually):
  - 2019 redesign: commands grouped by function, with groups ordered by focus and current view. — [Linear newsletter](https://newsletter.linear.app/issues/linear-changelog-new-command-menu-215797)
  - May 2021: a "clear recent" command for recent searches and viewed issues, and an "Open issue" recents list (O I). — [Linear changelog 2021-05-20](https://linear.app/changelog/2021-05-20-improving-performance-for-large-workspaces)
  - Apr 2024: fixed ⌘K not closing an open menu, and mixed selections now show as a dash (a partial checkbox). — [Linear changelog 2024-04-24](https://linear.app/changelog/2024-04-24-editor-improvements)
  - Jun 2026: paste a GitHub PR link into the menu to open it. — [Linear changelog 2026-06-04](https://linear.app/changelog/2026-06-04-team-documents)
  - 2026: "Improved command menu to now use fuzzy search". — [Linear changelog](https://linear.app/changelog)

**Slack Quick Switcher** — [Slack Engineering, "A faster, smarter Quick Switcher"](https://slack.engineering/a-faster-smarter-quick-switcher/) (2016, updated 2020)
- Performance went from 85 ms to open and 100 ms to render to a median 7 ms open and 12 ms render. The team used a 16.67 ms frame budget.
- How they got there:
  - Search data is fetched when the switcher opens, not on keydown.
  - The initial view shows only unread channels and DMs, capped at 24.
  - A simpler sort with fewer special cases.
  - Fewer DOM elements.
  - Timing measured in production.
- Frecency:
  - Stored per query: the query text, the selected ID, a count, and the last 10 visit timestamps.
  - Buckets: 100 points (≤4 h), 80 (≤1 day), 60 (≤3 days), 40 (≤1 week), 20 (≤1 month), 10 (≤90 days), 0 beyond.
  - Score = `count × sum(bucket points) / number of timestamps`.
  - A selection also gives half points to the other queries that reached it.
- Matching:
  - Word starts across `-` and `_`, ranked by start-of-word.
  - Separators may be skipped ("devweb" matches "devel-webapp").
  - Words can come in any order.
  - Initials ("dh" matches "Duretti Hirpa").
  - Implemented as a graph search with cheaper edges for the next letter.

**GitHub command palette** — [GitHub Docs](https://docs.github.com/en/get-started/accessibility/github-command-palette)
- The scope breadcrumb at top-left comes from the current page.
- Tab adds the highlighted repo to the scope. Backspace removes it, and ⌘⌫ clears scope and text.
- Prefix modes:
  - `>` commands
  - `#` issues/PRs/discussions/projects
  - `!` projects
  - `@` users/orgs/repos
  - `/` files or repos
  - `?` help
- A separate shortcut (⌘⇧K) opens command mode directly.
- ⌘↵ opens in a new tab. ⌘C copies the highlighted result's URL.
- Default suggestions come from location and recent resources.
- Commands are context-gated: per issue, per PR, per file, per repo, or global.

**Vercel**
- Its command menu was built on cmdk by Rauno (2020). — [cmdk README](https://github.com/pacocoursey/cmdk/blob/main/README.md)

**Rauno Freiberg, "Invisible Details of Interaction Design" (2023)**
- On command menus: "It's tempting to throw an opacity and scale fade on the overlay", but menus opened "hundreds of times a day" make that animation "more like cognitive burden".
- macOS context menus appear without motion. The chosen item blinks the accent color, then the menu fades out.
- The Cmd-Tab switcher never animates, and a quick press-release switches without showing UI.
- Source: [rauno.me/craft/interaction-design](https://rauno.me/craft/interaction-design)

**Notion**
- "Quick Find" was renamed "Search" in Sept 2022, described as "40-50% faster", opened with ⌘P or ⌘K. — [Notion on X](https://x.com/NotionHQ/status/1567183564554338304)
- A later post on SQLite caching lists search performance as a next focus. — [Notion blog](https://www.notion.com/blog/faster-page-load-navigation)

**Claude.ai / Claude desktop**
- Only third-party shortcut lists say ⌘K opens a chat search palette that can also start a new chat. — [fastshortcuts](https://fastshortcuts.com/shortcuts/claude/), [mfsinitishk guide](https://mfsinitishk.github.io/claude-mastery-guide/14-reference/keyboard-shortcuts/)
- The sources disagree (some say ⌘K means "new chat").

### Inferences
- Superhuman's "default score / scale / follow" model and VS Code's MRU-first ordering are two answers to the same problem: what to show before typing, and how to stop rare commands from crowding out key ones. A native palette needs both: a curated empty-state order and usage-based recents.
- Linear's anchored palette, opened from a control, shows that one list engine can drive both the global ⌘K and contextual dropdowns.

### Gaps
- I found no first-party Linear engineering write-up on ⌘K internals (rendering, latency targets).
- I found no Superhuman post on selection or recents behavior beyond last-used in label lists.
- I found nothing reliable on how Notion search works or on Raycast for Windows; I did not research Raycast for Windows.
- I found no Anthropic documentation for the Claude ⌘K palette.
- Maggie Appleton's "Command K Bars" essay surfaced in search but I did not read it.

## 5. Common UX patterns across palettes

### Takeaway
The shared pattern:
- The input keeps focus, with a virtual highlight.
- The first result is auto-selected after every query change.
- Ranked groups are reordered by their best item.
- Recents or MRU appear in the empty state.
- Each row shows its shortcut.
- Backspace on an empty query leaves a page or scope.
- Async results append without a layout jump, and a spinner appears only after a delay.

### Cited Findings

**First-item auto-select and selection persistence**
- cmdk reselects the first valid item after each filter. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- VS Code defaults to `ItemActivation.FIRST`. — [quickInput.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickInput.ts)
- VS Code keeps the scroll position while slow picks merge (`keepScrollPosition`). — [pickerQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/pickerQuickAccess.ts)
- cmdk keys selection by value, so a re-render that doesn't change the query keeps the selection. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)

**Section ordering**
- cmdk orders groups by their best item's score while searching, and by authored order when empty. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)
- VS Code uses fixed separators: recently used → similar → commonly used → other. — [commandsQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/commandsQuickAccess.ts)
- Linear prioritizes groups by focus and view. — [Linear newsletter](https://newsletter.linear.app/issues/linear-changelog-new-command-menu-215797)
- kbar ranks sections by section priority. — [useMatches.tsx](https://github.com/timc1/kbar/blob/main/src/useMatches.tsx)

**Nested pages**
- cmdk's recipe: Esc, or Backspace on an empty query, pops the page. — [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- kbar: Backspace on an empty query goes to the parent, the placeholder becomes the parent's name, and the panel bumps. — [KBarSearch.tsx](https://github.com/timc1/kbar/blob/main/src/KBarSearch.tsx), [KBarAnimator.tsx](https://github.com/timc1/kbar/blob/main/src/KBarAnimator.tsx)
- GitHub uses a scope breadcrumb with Tab to narrow and Backspace to widen. — [GitHub Docs](https://docs.github.com/en/get-started/accessibility/github-command-palette)

**Shortcut hints**
- Superhuman shows the shortcut in each row, to teach it. — [Superhuman blog](https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/)
- VS Code shows the keybinding in rows and in the aria label. — [commandsQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/commandsQuickAccess.ts)

**Empty and no-results states**
- cmdk renders `Command.Empty` when the count is 0. — [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- VS Code shows "No matching results". — [anythingQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/search/browser/anythingQuickAccess.ts)
- Slack's empty state is unread channels and DMs, capped at 24. — [Slack Engineering](https://slack.engineering/a-faster-smarter-quick-switcher/)

**Loading without a layout jump**
- VS Code: 800 ms spinner delay, 200 ms fast/slow merge delay, empty fast picks skipped, and scroll position kept. — [quickInput.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickInput.ts), [pickerQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/pickerQuickAccess.ts)
- cmdk animates list height through `--cmdk-list-height`. — [index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)

**Query on reopen**
- VS Code can preserve the query, with the cursor at the end. Otherwise it selects everything after the prefix, so the old query is visible but replaced by typing. — [quickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickAccess.ts)

**Open, close and focus**
- The same key toggles the palette, and focus is restored on close. — [Superhuman blog](https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/)
- Linear fixed ⌘K-to-close in 2024. — [Linear changelog 2024-04-24](https://linear.app/changelog/2024-04-24-editor-improvements)
- GitHub: the open shortcut or Esc closes. — [GitHub Docs](https://docs.github.com/en/get-started/accessibility/github-command-palette)

**Motion**
- No open animation on high-frequency surfaces. — [Rauno](https://rauno.me/craft/interaction-design)
- kbar's default `enterMs` and `exitMs` are 0. — [KBarAnimator.tsx](https://github.com/timc1/kbar/blob/main/src/KBarAnimator.tsx)

### Inferences
- "Selection persistence on result change" is mostly *not* done by these libraries while typing; each keystroke resets to the top result, because the top result is what Enter should run. Persistence matters in two cases:
  - Async results arriving while the user has already moved the highlight (VS Code's keepScrollPosition path).
  - Live data updating with no query change (cmdk's value-keyed selection).
- A native implementation should key the highlight by item ID, and reset it to the first item only when the query changes.

### Gaps
- I found no source describing a standard "keyboard hints footer" (e.g. ↵ Open · ⌘↵ New tab) other than GitHub documenting the keys themselves; Raycast-style footers weren't covered by the sources here.

## 6. Performance techniques

### Takeaway
For in-memory command lists (up to a few thousand items), the praised palettes filter synchronously on every keystroke with a cheap, memoized scorer and don't debounce. Throttling and debouncing are kept for I/O-bound sources (VS Code's 200 ms on cold file search, kbar's 100 ms). Large lists need virtualization or a cap (VS Code 512 results, Slack 24 initial rows). Data loads when the palette opens, not per keystroke.

### Cited Findings
- **cmdk:**
  - Synchronous filter and sort on each search change.
  - Memoized recursion, with lowercasing hoisted out of the hot path.
  - No virtualization; good up to 2–3k items.
  - `shouldFilter={false}` plus your own virtualization beyond that.
  - Sources: [command-score.ts](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts), [README](https://github.com/pacocoursey/cmdk/blob/main/README.md)
- **kbar:** 100 ms throttle plus TanStack virtualization. — [utils.ts](https://github.com/timc1/kbar/blob/main/src/utils.ts), [KBarResults.tsx](https://github.com/timc1/kbar/blob/main/src/KBarResults.tsx)
- **VS Code:**
  - Fixed-height virtualized rows.
  - Score cache.
  - 512-result cap.
  - Cancellation tokens on every keystroke.
  - 200 ms throttled delayer only for a cold file cache.
  - Sources: [quickInputList.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/quickInputList.ts), [fuzzyScorer.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts), [anythingQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/search/browser/anythingQuickAccess.ts)
- **Slack:**
  - Fetch on open.
  - A small initial list (24).
  - Fewer DOM nodes.
  - A 16.67 ms frame budget.
  - Measured with production timings: 7 ms open, 12 ms render.
  - Source: [Slack Engineering](https://slack.engineering/a-faster-smarter-quick-switcher/)
- **Superhuman:** a 100 ms target for every interaction. — [Antler](https://www.antler.co/blog/antler-early-days-episode-2-superhuman-with-rahul-vohra)

### Inferences
- Native budget: aim for the key-to-updated-list path within one frame (about 8 ms at 120 Hz on ProMotion, 16.7 ms at 60 Hz). Slack's 12 ms render shows a list that size is reachable.
- Use NSTableView or NSCollectionView cell reuse as the equivalent of virtualization, and diff updates keyed by item ID.

### Gaps
- None of the sources gave per-keystroke latency for cmdk or Linear.
