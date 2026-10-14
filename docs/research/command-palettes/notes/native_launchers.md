# How the best-known macOS launchers build their search/command window (Raycast, Alfred, Spotlight, LaunchBar, 1Password Quick Access, Sol, Spotter, Script Kit)

Research date: 2026-10-14. Sources are primary where possible: vendor blogs and docs, engineers' own words, and open-source code. Some findings come from **local binary inspection** on this machine (macOS 26.5, build 25F71): `otool -L` and `strings` on `/System/Library/CoreServices/Spotlight.app` (CFBundleVersion 181.4.6) and `/Applications/Raycast.app` (2.8.0). These are labeled "[local inspection]" and have no URL. Treat what they show as strong evidence of which classes and APIs exist, not as proof of how they are used.

---

## 1. UI stack for each product

### Takeaway
The best-known launchers all run in a native AppKit shell. Raycast v1 rendered everything with custom AppKit components, and its React extensions were turned into native views by a custom reconciler. Raycast v2 (May 2026) moved the UI into a WKWebView inside a thin Swift/AppKit host to ship on Windows too. Apple's Tahoe Spotlight mixes AppKit (panel, NSSearchField, NSTableView, view controllers) with SwiftUI hosting views. 1Password Quick Access runs on Electron. Script Kit is moving from Electron to Rust/GPUI, and Sol is React Native macOS inside an NSPanel.

### Cited findings

**Raycast v1 (2020 to mid-2026): native AppKit, custom components, little SwiftUI**
- Raycast v1 was "a native macOS app built with Swift on top of AppKit." The team "almost never reached for standard UI components" because they didn't suit keyboard-first, power-user workflows, so every list row, shortcut and default behavior was custom. SwiftUI "never quite cleared our bar for performance and control." The yearly Wrapped feature is the only SwiftUI code. — [Raycast blog, "A Technical Deep Dive Into the New Raycast", 2026-05-14](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Why not SwiftUI (2023): "We chose not to use SwiftUI as we weren't confident in it not increasing our crash rate or degrading performance." AppKit, "with its lifecycle methods and imperative UI code", became the native base. — [Felix Raab, "How the Raycast API and extensions work", Raycast blog, 2023-05-31](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- Extension rendering in v1, a **custom React reconciler targeting AppKit**:
  - Extensions declare UI with React components.
  - The reconciler serializes each component to JSON and composes the results into a "render tree".
  - Each new tree is diffed against the previous one with **JSON Patch**. "If there are no patches, it means there are no changes", so native code does nothing.
  - Large trees are gzip-compressed only above a size threshold where compression pays for itself.
  - On the native side, Swift builds "lightweight Swift view models" and translates patches into bitset types. This shields the AppKit components from changes in the render-tree format.
  - Source: [Raycast blog, 2023-05-31](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- Process model in v1:
  - Extensions run in **Node worker threads** ("essentially v8 isolates", with per-extension heap limits) under a Node parent process.
  - They talk to the Swift app with **JSON-RPC over stdio file descriptors**, which Raycast calls "easy to debug due to its plain text nature".
  - Session IDs allow parallel extension instances. Swift uses serial queues and buffered streams to keep messages ordered.
  - A first prototype used an XPC extension host with JavaScriptCore engines. It was dropped because developers wanted npm packages and easier UI/state handling.
  - Raycast downloaded and managed its own Node runtime, so a Node crash usually doesn't take down Raycast.
  - Source: [Raycast blog, 2023-05-31](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- Extension docs: "Raycast uses React for its user interface declaration and renders the supported elements to our native UI." — [developers.raycast.com, User Interface](https://developers.raycast.com/api-reference/user-interface)
- Thomas Paul Mann (co-founder, April 2024): "being a native application gives us all the advantages, being close to the operating system, giving us the performance, but also giving us the look and feel of a native application." He called being faster than Spotlight "table stakes": "We have like a more reliable search for apps. We made it faster than Spotlight, and that is like sort of the table stakes." — [Changelog Interviews #587 transcript, 2024-04-17](https://github.com/thechangelog/transcripts/blob/master/podcast/the-changelog-587.md)

**Raycast v2 (public beta 2026-05-14, out of beta 2026-08-25): native host plus a WebView UI**
- Architecture has four parts:
  1. A **host app** per platform, Swift/AppKit on macOS and C#/.NET 8/WPF on Windows. It owns windows, global hotkeys and the menu bar/tray, loads the UI in **WKWebView / WebView2**, and supervises Node.
  2. One shared **React + TypeScript frontend**, with separate entry points per window (Launcher, AI Chat, Notes, Settings).
  3. One long-lived **Node backend** for the database, extension runtime and services.
  4. A **Rust core** for the data layer, sync and the file indexer.
  - Interfaces are declared once and typed clients are generated for every side. Transport uses platform message handlers plus stdio.
  - Source: [Raycast deep dive, 2026-05-14](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Why they rewrote:
  - Compile times kept rising, "AppKit was getting in our way more often", and deep native-macOS hires were hard to find.
  - Native Windows UI was rejected because of WPF/UWP/WinUI 3 churn.
  - Electron was rejected because they needed deep OS hooks ("global hotkeys, accessibility APIs, floating panels that don't steal focus") and wanted the system WebKit rather than a bundled Chromium.
  - Tauri was rejected as "less native control" and too young.
  - Source: [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Costs they admit:
  - Memory went up. v1 sat at "200–300 MB after some usage", v2 at "350–450 MB". With the window hidden, v2 breaks down as WebContent ~120–200 MB, Node ~150–200 MB, Swift shell ~40 MB.
  - Accessibility, drag-and-drop edge cases and **IME** "take explicit work in a WebView".
  - A gain: "Hot reloading means UI changes show up in under a second."
  - Source: [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Wes Bos on Raycast 2: "noticeably very snappy… Light native wrapper. Rust where it matters. No electron of[sic] Tauri." — [Wes Bos on X, May 2026](https://x.com/wesbos/status/2054929458746867817?lang=en)
- [local inspection] Raycast 2.8.0 bundle:
  - `LSUIElement = true`, `LSMinimumSystemVersion = 26.0`.
  - The main binary links AppKit, SwiftUI, WebKit and Carbon, plus `@rpath/libraycast_host.dylib`.
  - `Resources/macos-app_RaycastDesktopApp.bundle` (181 MB) contains `frontend/`, `backend/`, `node/`, `api/` and `audio/`. A `ripgrep` binary is also bundled.
  - Swift type names include `ActionPanelWindow`, `AiContextCapturePanel`, `CaretInspectorPanel`, `FocusNotificationToastPanel` and a `HyperKey+CapsLockCGEventTapKeyImplementation`.

**Spotlight (macOS 26 Tahoe redesign)**
- Feature changes:
  - Actions come from App Intents and Shortcuts, with **Quick Keys** (short letter strings like "sm" for send message, auto-generated from usage or user-set).
  - Clipboard history.
  - "Browse modes" on ⌘1–⌘4 (Apps/Files/Actions/Clipboard).
  - It replaces Launchpad.
  - Sources: [9to5Mac, 2025-06-10](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/); [MacRumors](https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/)
- Developer side:
  - Make entities `IndexedEntity` and donate them to Spotlight (`indexingKey` links properties to Spotlight keys).
  - Annotate on-screen content with entities so they get priority while visible.
  - Adopt `PredictableIntent` so "the system can learn from past user behavior".
  - Interactive snippets (SwiftUI) render in Spotlight.
  - Sources: [WWDC25-275](https://developer.apple.com/videos/play/wwdc2025/275/); [WWDC25-260](https://developer.apple.com/videos/play/wwdc2025/260/); [WWDC25-281](https://developer.apple.com/videos/play/wwdc2025/281/)
- [local inspection] The Spotlight.app binary (UI process, `LSUIElement = true`, principal class `SPApplication`):
  - Links **both AppKit and SwiftUI**, plus private SearchUI, SearchFoundation, SpotlightUIShared and SpotlightUIServices.
  - AppKit-side names include `SPSpotlightPanel`, `SPSpotlightWindowNoDismissOnLostKeyFocus`, `MainWindowController`, `SearchViewController`, `SearchResultsViewController`, `SpotlightSearchField`/`SearchField`/`SearchFieldCell` (NSSearchField subclasses), `NSSearchFieldDelegate`, `WindowAnimationCoordinator`, and many `NSTableView` delegate/data-source selector signatures.
  - SwiftUI-side names include `MainWindowView`, `queryFilterBarHostingView` and `hostingView`.
  - Conclusion: AppKit panel, search field and view controllers, with SwiftUI hosted for parts of the UI (at least the filter bar). The binary alone can't show what draws the results rows.
- Paulo Andrade (2026): Spotlight's "keep typing in the search field while using up/down to move through results" is "currently not possible in pure SwiftUI". — [Paulo's Blog, "Using SwiftUI to Build a Mac-assed App in 2026"](https://pfandrade.me/blog/mac-assed-swiftui-app/)

**Alfred**
- Andrew Pepperrell built Alfred as his first Objective-C/Cocoa project, starting around 2010. He said his enterprise background "helped him get Alfred's architecture and performance right from the start." The test machine was an old G4 Mac mini on 10.5. — [Mac.AppStorm interview](https://mac.appstorm.net/general/interviews/meet-the-developers-andrew-pepperrell-of-alfred-app/); [Wikipedia](https://en.wikipedia.org/wiki/Alfred_(software))
- Alfred 5.0 shipped 2022-07-13 with native Apple Silicon support. The latest release is 5.7.2 (2025-12-09). — [Wikipedia](https://en.wikipedia.org/wiki/Alfred_(software))

**LaunchBar (Objective Development)**
- Its search is "Ultra fast, adaptive abbreviation search (AASv5)". — [LaunchBar features](https://www.obdev.at/products/launchbar/features.html)
- No published statements about its UI framework were found.

**1Password Quick Access (1Password 8)**
- 1Password 8 for Mac uses Electron for the UI: "1Password 8 uses Electron only to render the app's UI. Processing is handled in Rust and Swift for performance and security." — [1Password on X, Aug 2021](https://twitter.com/1Password/status/1428336271689191431?lang=en)
- A moderator described the frontend as TypeScript + React in Electron with a Rust core. A native SwiftUI Mac app was started and abandoned. A 1Password developer (Fey) explained that even with SwiftUI they ended up building "separate implementations of certain components and sometimes whole features to have them feel at home." — [Michael Tsai blog, 2021-08-11](https://mjtsai.com/blog/2021/08/11/1password-8-for-mac-early-access/); [Six Colors](https://sixcolors.com/post/2021/08/not-important-enough-1password-abandons-its-native-mac-app/)
- Quick Access is "built into the desktop versions of 1Password 8". Its shortcut is ⇧⌘Space on Mac and Ctrl+Shift+Space on Windows/Linux. — [1Password support, Quick Access](https://support.1password.com/quick-access/)

**Sol (ospfranco, open source, MIT)**
- Stack:
  - **React Native macOS** 0.81.7 with TypeScript, NativeWind/Tailwind and MobX.
  - `@legendapp/list` for the virtualized list.
  - `minisearch` and `fuse.js` for search, and `react-native-reanimated`.
  - Swift native modules under `macos/sol-macOS/` (`PanelManager`, `HotKeyManager`, `ApplicationSearcher`, a SQLite-backed `FileSearchIndex`).
  - Source: [Sol package.json](https://github.com/ospfranco/sol/blob/main/package.json); [repo](https://github.com/ospfranco/sol)
- Franco's description of his setup: the RN root view "is not the entry point of the app, but rather I manually create it an load it into an NSPanel" (brownfield, via `RCTRootViewFactory`). — [ospfranco.com, RCTRootViewFactory](https://ospfranco.com/react-native-rctrootviewfactory/)

**Spotter**
- It is **Flutter/Dart** with C++ and a small amount of Swift (GitHub languages: Dart 38.6k, C++ 23.3k, Swift 2.9k bytes). The last push was 2023-12-18, so it is effectively dormant. — [spotter-application/spotter](https://github.com/spotter-application/spotter) (GitHub API languages endpoint)

**Script Kit**
- The original app is Electron and TypeScript (e.g. "Electron 22, node 16.17.1" in the Dec 2022 release). — [kit discussion #970](https://github.com/johnlindquist/kit/discussions/970)
- **script-kit-next** is a full rewrite in **Rust on GPUI** (Zed's GPU-rendered UI framework):
  - Scripts run in a **Bun** child process and drive the native shell over JSONL messages.
  - SQLite holds clipboard and notes.
  - It uses `nucleo-matcher` ("High-performance fuzzy matching (10-100x faster than bespoke)" per Cargo.toml comment), `global-hotkey`, and `cocoa`/`objc` for AppKit calls.
  - Sources: [script-kit-next repo](https://github.com/johnlindquist/script-kit-next); [Cargo.toml](https://github.com/johnlindquist/script-kit-next/blob/main/Cargo.toml); [DeepWiki summary](https://deepwiki.com/johnlindquist/script-kit-next)

### Inferences
- For a native Swift palette, the most relevant model is **Raycast v1**: AppKit, custom row views, very little SwiftUI. That was the stack that won "faster than Spotlight". Raycast moved off it for cross-platform and hiring reasons, not because the launcher was slow.
- Apple's own redesigned Spotlight is a hybrid: AppKit panel, search field and table/view controllers, with SwiftUI hosting views embedded. That suggests the same split for a Swift app. Keep the panel, the text field (first responder, arrow-key routing) and probably the list in AppKit, and use SwiftUI for row content, filter chips and detail panes.
- Every app that went off-native (1Password 8, Raycast v2) took on documented costs: memory, IME, accessibility, and flicker workarounds.

### Gaps
- No primary source on Alfred's or LaunchBar's current view stack (Objective-C vs Swift, NSTableView vs custom). Alfred is not installed on this machine, so it couldn't be inspected.
- No primary source on how the 1Password Quick Access window itself is implemented (a separate Electron BrowserWindow vs a native panel). The Electron conclusion is inferred from the whole-app architecture.
- No Raycast talk or post found that names NSTableView vs NSCollectionView vs custom views for the v1 root list.

---

## 2. Window handling: panels, focus, dismissal, Spaces, hotkeys

### Takeaway
The common pattern is an **`NSPanel` with `.nonactivatingPanel`**, `canBecomeKey = true`, a high window level, and Spaces/full-screen collection behaviors. The panel hides on `windowDidResignKey`, and the global hotkey is registered through Carbon `RegisterEventHotKey` (via a wrapper). The two best-documented apps disagree on Spaces: Sol uses `canJoinAllSpaces`, while Script Kit asserts `moveToActiveSpace` and forbids `canJoinAllSpaces`. Raycast documents warm-start tricks: pre-render with alpha 0, and wait for the next presentation update before showing.

### Cited findings
- **Sol's panel:**
  - Settings: `NSPanel` subclass with `styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel]`, `level = .floating`, `collectionBehavior` gets `.fullScreenAuxiliary` and `.canJoinAllSpaces`, hidden transparent titlebar, `isMovableByWindowBackground`, `isReleasedWhenClosed = false`, non-opaque, `NSVisualEffectView` (`.headerView` material, `.behindWindow`) as content view.
  - Overrides `canBecomeKey` and `canBecomeMain` to return `true`.
  - **Dismissal:** `windowDidResignKey` → `DispatchQueue.main.async { PanelManager.shared.hideWindow() }`.
  - Source: [Sol Panel.swift](https://github.com/ospfranco/sol/blob/main/macos/sol-macOS/views/Panel.swift)
- **Sol's show/hide:**
  - Picks either the screen of the frontmost app's window (found via Accessibility) or the screen under the mouse.
  - Positions the panel horizontally centered with a 30% upward offset from the vertical middle.
  - Shows with `setIsVisible(true)` then `makeKeyAndOrderFront`. Hiding is `setIsVisible(false)`, not close.
  - Pauses its in-panel ⌘, hotkey while hidden.
  - Grows the window height from JS via a `setHeight` bridge.
  - Source: [Sol PanelManager.swift](https://github.com/ospfranco/sol/blob/main/macos/sol-macOS/managers/PanelManager.swift)
- **Sol's hotkeys** use the `HotKey` Swift package (Carbon-based); the default main hotkey is ⌘Space. It adds `NSEvent.addLocalMonitorForEvents` for keyDown and flagsChanged, and a `CGEvent` tap. — [Sol HotKeyManager.swift](https://github.com/ospfranco/sol/blob/main/macos/sol-macOS/managers/HotKeyManager.swift)
- **Script Kit Next's panel invariants** (a runtime-checked contract):
  - The main window is "an NSPanel with NonactivatingPanel style, the GPUI `WindowKind::PopUp` level, accessory app activation policy, a specific collection-behavior shape, and a three-layer cursor-in-background system".
  - Level is **101** (`NSPopUpMenuWindowLevel`), "not `NSFloatingWindowLevel = 3`".
  - "`MoveToActiveSpace` is required, `CanJoinAllSpaces` is rejected."
  - Activation policy is Accessory (=1) and `NSWindowAnimationBehaviorNone`.
  - Checks run on every show path. Debug builds panic on mismatch, and release builds log.
  - Source: [script-kit-next src/platform/panel_invariants.rs](https://github.com/johnlindquist/script-kit-next/blob/main/src/platform/panel_invariants.rs)
- **Raycast v2 window tricks on macOS** (documented):
  - To avoid WebKit throttling, the window is ordered front with `alphaValue = 0`, WebKit occlusion detection is disabled, and rendering is triggered in `requestAnimationFrame` before showing.
  - To avoid blank frames on expand, the WKWebView frame stays at the expanded size.
  - `NSWindow.setFrame` is overridden to animate with implicit Core Animation so resizes don't stutter.
  - The private `_doAfterNextPresentationUpdate` makes sure the WebView has drawn before the window appears ("flash on open").
  - The emoji font is prewarmed at startup.
  - Runtime flags lift the 60 FPS cap and enable `requestIdleCallback`.
  - In v1, secondary windows (AI Chat, Notes) were kept warm. v2 tears inactive windows down more aggressively, causing a cold-open delay, and plans "grace periods" to keep recently used windows warm.
  - Source: [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Raycast lists "floating panels that don't steal focus" among the OS hooks that ruled out Electron. — [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- [local inspection] The Raycast 2.8.0 binary links **Carbon** and contains `EventHotKeyID` (the Carbon `RegisterEventHotKey` path), `CGSSymbolicHotKey`/`AppleSymbolicHotKeys` and `HotkeyDisableSymbolicHotkeyHandler`/`HotkeyCommandSpaceAvailabilityHandler`. This is consistent with Raycast turning off Spotlight's ⌘Space symbolic hotkey so it can take it. It also contains `moveToActiveSpace`, `windowOcclusionDetectionEnabled`, `_doAfterNextPresentationUpdate:` and `setAlphaValue:`, which match the blog's description.
- [local inspection] Tahoe Spotlight.app contains:
  - `SPSpotlightPanel` and `SPSpotlightWindowNoDismissOnLostKeyFocus`, which suggests that by default the panel dismisses on lost key focus, with a debug or default override.
  - `_lostKeyFocusTimeout:` (a grace timeout before dismissing on focus loss), `windowDidResignKey:`, `canBecomeKeyWindow`, `setCollectionBehavior:`, custom full-screen animation delegate methods, `SearchFieldClearTimeoutSeconds` (query cleared after a timeout rather than on every close), and `WindowAnimationCoordinator`.
- Raycast 2.0's headline features included "reliable hotkey recording". — [Raycast 2.0 changelog](https://www.raycast.com/changelog/macos/2-0); [Threads announcement](https://www.threads.com/@raycastapp/post/DYUQVgCmuNB/raycast-beta-is-now-publicly-available-for-download)

### Inferences
- The recipe: `NSPanel` + `.nonactivatingPanel` + `canBecomeKey` override. Show with `makeKeyAndOrderFront` without `NSApp.activate`, so the previous app stays frontmost and paste/insert targets keep working. Hide on `windowDidResignKey`. Use an accessory activation policy (`LSUIElement`).
- Spaces: `canJoinAllSpaces` (Sol) means the panel is everywhere. `moveToActiveSpace` (Script Kit, and present in the Raycast binary) moves it to the current Space on show. Both add `.fullScreenAuxiliary` (Sol) or an equivalent to appear over full-screen apps.
- Spotlight's `_lostKeyFocusTimeout` and `SearchFieldClearTimeoutSeconds` suggest two refinements: a short grace period before dismissing on focus loss (to survive transient key-window changes such as a popover), and keeping the last query for N seconds so a quick re-summon restores it.
- Open with a pre-rendered, laid-out window: order it in at alpha 0 or wait for a presentation update, and avoid resizing on first frame. This applies in spirit to AppKit too.

### Gaps
- No vendor has published hotkey-to-visible latency in ms. Raycast's deep dive says nothing on startup or summon time.
- Spotlight's actual collection behavior and window level were not determined; that would need a runtime check, not `strings`.
- Alfred's and LaunchBar's window and focus handling are undocumented publicly.

---

## 3. List rendering and keeping typing-to-results under one frame

### Takeaway
Hard numbers are scarce. Raycast v1 used custom AppKit components. Raycast's extension API pushes filtering to the native side ("Use built-in filtering for best performance") and re-sends only JSON-Patch diffs. Spotlight uses NSTableView data-source/delegate machinery. Sol uses a virtualized RN list. Script Kit tunes opt-level for GPUI because dev builds miss frame deadlines.

### Cited findings
- Raycast docs:
  - "Use built-in filtering for best performance."
  - Native filtering fuzzy-matches each item's `title` and `keywords`.
  - Supplying `onSearchTextChange` implicitly sets `filtering = false`.
  - `throttle` makes `onSearchTextChange` fire "with a delay" instead of on every keypress and is "Recommended… with asynchronous operations (e.g. network requests)".
  - `filtering: { keepSectionOrder }` controls whether ranking may reorder sections.
  - Pagination exists (API ≥1.69), but extensions have limited memory.
  - Source: [developers.raycast.com, List](https://developers.raycast.com/api-reference/user-interface/list)
- In Raycast v1, a re-render whose JSON Patch is empty triggers no native update. Native code keeps lightweight view models separate from AppKit views. — [Raycast blog, 2023](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- [local inspection] Spotlight.app contains many `NSTableView` data-source/delegate selector signatures (row views, drag-and-drop pasteboard writing, `NSTableRowView`) and `NSScrollView`. It also contains `Size invalidation requested with debounce`, `windowSizingDebouncer` and `expansionDebouncer`, meaning window-size changes as results arrive are debounced.
- Sol uses `@legendapp/list` 3.0 beta (virtualized) with MobX state. — [Sol package.json](https://github.com/ospfranco/sol/blob/main/package.json)
- Script Kit Next's Cargo.toml comment: "Scroll/animation frame cost is dominated by layout+paint code in gpui, gpui-component, and taffy; at opt-level 0 a dev build misses the frame", so those crates get optimized even in dev. — [script-kit-next Cargo.toml](https://github.com/johnlindquist/script-kit-next/blob/main/Cargo.toml)
- Third-party claim (not from Raycast) that Raycast v1 extension UIs looked native, "hit 60 fps", and respected accessibility. — [huakun.tech notes on Raycast](https://huakun.tech/Code-Chronicles/raycast) (secondary; treat with care)

### Inferences
- Patterns to copy:
  - Keep the result model separate from views (view models plus a cheap diff).
  - Filter and rank in-process on the native side, not across an IPC boundary per keystroke.
  - Use a recycling list (NSTableView/NSCollectionView view reuse, or a virtualized list).
  - Debounce window-height changes separately from result updates, as Spotlight's debouncers suggest. That avoids resize thrash while results stream.
- Neither Raycast nor Apple publishes a frame budget. The "under one frame" target is a team goal, not something a vendor documented.

### Gaps
- No published typing-to-results latency, result-count caps, or row-reuse details from Raycast, Alfred, LaunchBar or Apple.
- It is unclear whether Spotlight's result rows are AppKit or SwiftUI. The binary has both NSTableView machinery and SwiftUI hosting views.

---

## 4. Search and ranking

### Takeaway
Everyone fuzzy- or abbreviation-matches on titles, then personalizes. Alfred and LaunchBar **latch the exact typed query to the chosen result**. Raycast ranks by a documented priority: alias, then fuzzy title, then subtitle/keywords, then frecency. Learned results are tied to the query typed and its prefixes. Open-source launchers implement frecency explicitly: Script Kit uses exponential decay with a 7-day half-life, and Sol puts usage *below* match-quality tiers.

### Cited findings
- **Alfred:**
  - Keeps a "heuristic fingerprint of your usage, maintained on a 4 week rolling window".
  - By default "Alfred latches the typed query phrase to the selected result". Example: open Calendar 100×/day and Calculator 10×/day, but pick Calculator after typing "c" 2–3 times and Alfred "will very quickly re-learn your intention". Learning is per exact query, so "c" can map to Calculator while "ca" maps to Calendar.
  - With no usage knowledge, files fall back to the macOS metadata "Last Used" and "Last Modified" fields.
  - Source: [Alfred Help, Understanding Result Ordering](https://www.alfredapp.com/help/kb/understanding-result-ordering/)
  - Script Filter results get usage ranking only if they carry a UID; items without one stay unsorted. — [Alfred Forum](https://www.alfredforum.com/topic/22175-how-to-rank-script-filter-results/)
- **LaunchBar** ("adaptive abbreviation search", AASv4 in help, AASv5 on the features page):
  - Matches any characters in order ("SPF > System Preferences"), ignoring spaces and case.
  - If you type T and pick Terminal over TextEdit, "the next time you type T it suggests Terminal right away".
  - One- or two-character abbreviations may need extra training.
  - **Instant Open:** hold the last letter to open the selection.
  - Source: [LaunchBar Help, Abbreviation Search](https://www.obdev.at/resources/launchbar/help/AbbreviationSearch.html); [features](https://www.obdev.at/products/launchbar/features.html)
- **Raycast:**
  - Fuzzy search became the Root Search algorithm in v1.40.0 (2022-09-28), e.g. "ftime" → FaceTime and "msg" → Messages.
  - "Ranking of elements automatically accounts for how often you open every element and whether you have written a previously triggered search term (or a prefix of it)."
  - "Search index is partially rebuilt after each triggered search result."
  - A Root Search Sensitivity setting controls match strictness.
  - Source: [Raycast changelog 1.40.0](https://www.raycast.com/changelog/1-40-0)
- Raycast manual ranking order: 1. exact alias match, 2. alias prefix match, 3. title fuzzy match score, 4. subtitle and keyword matches, 5. **frecency** ("a blend of frequency and recency"). "The more often, and the more recently, you pick a result for a given query" the higher it ranks. "Reset Ranking" clears frecency for a command. — [Raycast Manual, Search Bar](https://manual.raycast.com/search-bar)
- A recent Raycast changelog entry (about early Oct 2026, per search snippet): Root Search "now has improved ranking to favor complete words and exact title matches while preserving results learned from your previous searches". — [Raycast changelog](https://www.raycast.com/changelog) (exact entry and date not verified)
- v2 file search:
  - v1 relied on Spotlight metadata.
  - v2 has its own **Rust indexer** in a separate process that scans the filesystem and updates via FS events. On Windows it reads the NTFS Master File Table directly to "index an entire drive in seconds rather than minutes".
  - Rust was chosen for predictable memory and no GC pauses.
  - Root Search now includes full file search.
  - Source: [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- **Spotlight (Tahoe):**
  - Quick Keys are "generated automatically based on how you use your Mac" or set by the user. — [9to5Mac](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/); [MacRumors](https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/)
  - Apps contribute ranking signals via `PredictableIntent` and on-screen entity annotation. — [WWDC25-275](https://developer.apple.com/videos/play/wwdc2025/275/)
  - [local inspection] Metric names `TimeToTopHit`/`timeToTopHit` and `TimeToWindowExpansion` show Apple measures time-to-first-best-result and time-to-expand as key metrics.
- **Sol's ranking code:**
  - MiniSearch over `name`, `localizedName`, `alias` and `type`, with `prefix: true`, `fuzzy: true` and `boost: {name: 2}`.
  - Results are re-sorted by: (1) a **match tier** (exact > prefix > word-prefix > substring > fuzzy), so "usage history can only reorder items of comparable match quality"; (2) ever-selected before never-selected; (3) MiniSearch score; (4) last-selection timestamp; (5) selection count; (6) name.
  - Selection counts are keyed by item id and persisted.
  - Source: [Sol ui.store.tsx](https://github.com/ospfranco/sol/blob/main/src/stores/ui.store.tsx)
- **Script Kit Next:**
  - `nucleo-matcher` for fuzzy matching. — [Cargo.toml](https://github.com/johnlindquist/script-kit-next/blob/main/Cargo.toml)
  - A frecency module combines count and last-used timestamp with "exponential decay with a configurable half-life": `2^(-days/hl)`, default `DEFAULT_SUGGESTED_HALF_LIFE_DAYS = 7.0`. — [src/frecency/mod.rs](https://github.com/johnlindquist/script-kit-next/blob/main/src/frecency/mod.rs); [src/config/defaults.rs](https://github.com/johnlindquist/script-kit-next/blob/main/src/config/defaults.rs)

### Inferences
- A layered ranker is the consensus design:
  - Explicit aliases or exact matches win.
  - Match-quality tiers come next, and usage must not lift a fuzzy match over a prefix match (Sol's rule; Raycast's order implies the same).
  - **Query-specific learning** comes next: map typed string and its prefixes to the chosen item, as Alfred, LaunchBar and Raycast all do.
  - Decayed global frecency breaks ties (Script Kit's 7-day half-life; Alfred's 4-week window).
- The "query latching" behavior that Alfred and LaunchBar both document is the main UX feature. Two or three picks re-teach a one-letter query.

### Gaps
- Raycast hasn't published its fuzzy scoring function or frecency decay constants. Alfred and LaunchBar haven't published their algorithms beyond help text.
- No source details Spotlight's ranking model.

---

## 5. Async results from slow sources

### Takeaway
Little is published. Raycast exposes an `isLoading` progress bar and a `throttle` flag for async filtering, and tells developers to prefer native filtering. Apple's Spotlight binary shows result debouncing, a "results after timeout" path, and debounced window resizing. These point to a design where fast local results show at once and late results are either merged in or deferred to avoid reordering.

### Cited findings
- Raycast: `isLoading` "Indicates whether a loading bar should be shown or hidden below the search bar". The EmptyView is never shown while `isLoading` is true and the search bar is empty. `throttle` is recommended for async custom filtering. — [Raycast List docs](https://developers.raycast.com/api-reference/user-interface/list)
- Raycast v1's IPC serializes extension messages through serial queues and buffered streams to preserve order, and race conditions between the two processes are "handled with custom logic". — [Raycast blog, 2023](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- [local inspection] Spotlight.app strings include:
  - `shouldDebounceResults`, `debouncer`.
  - `didReceiveResultsAfterTimeout:` and `SFResultsReceivedAfterTimeoutFeedback`: results that arrive after a deadline are handled and logged separately.
  - `goToAppsCompletionTimeoutTimer`, `windowSizingDebouncer`, `expansionDebouncer`.
- Third-party open-source example: DSFQuickActionBar's "Faux Spotlight" demo shows asynchronous search with `MDItemQuery`. — [dagronf/DSFQuickActionBar](https://github.com/dagronf/DSFQuickActionBar)

### Inferences
- Apple's pattern, read from symbol names: render local and top-hit results immediately and track time-to-top-hit. Debounce result updates and window expansion. Treat results that arrive after a timeout specially (append, or record without reshuffling), so the top hit doesn't jump under the user's cursor. Speculative, from names alone.
- Raycast's guidance: keep filtering native and synchronous, and throttle plus show a progress bar for network-backed sources.

### Gaps
- No vendor documents a cancellation strategy, stable-ordering rules for late results, or debounce intervals in ms.

---

## 6. What they've said about what makes it feel fast or great

### Takeaway
Raycast's public line is consistent. Speed versus Spotlight is "table stakes". Native feel is judged by whether "someone… would think it's a regular Mac app". Quality means behavior ("behave right"), not just looks. Concretely: no flicker on open, transitions or resize; pre-rendered windows; and platform conventions (no pointer cursor or hover highlights, native popovers and tooltips).

### Cited findings
- "We made it faster than Spotlight, and that is like sort of the table stakes." Users use it "hundreds of times a day". — Thomas Paul Mann, [Changelog #587, 2024-04-17](https://github.com/thechangelog/transcripts/blob/master/podcast/the-changelog-587.md)
- Raycast v2 feel bar:
  - The test is "if someone used Raycast without knowing what it's built with, would they think it's a regular Mac app?"
  - Conventions: no `cursor: pointer`, no hover highlights on most controls, settings in a separate native window, popovers and tooltips as native windows that can extend past window bounds, and eliminating flicker on view transitions.
  - "we won't ship something if it doesn't feel right."
  - Source: [Raycast deep dive](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)
- Pepperrell (Alfred) developed and tested on deliberately old hardware (a G4 Mac mini, a 4-year-old MacBook). — [Mac.AppStorm interview](https://mac.appstorm.net/general/interviews/meet-the-developers-andrew-pepperrell-of-alfred-app/)
- LaunchBar markets "Ultra fast" adaptive abbreviation search and Instant Open (hold the last key). — [LaunchBar features](https://www.obdev.at/products/launchbar/features.html)
- Spotlight on Tahoe: some users reported Spotlight regressions (clipboard indexing, "completely broken"). — [Apple Community thread](https://discussions.apple.com/thread/256238046); [9to5Mac](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/)
- Tuple's *Distributed* podcast with Mann (2025-06-12) covers using nightly builds internally to polish UX. — [Tuple Distributed](https://tuple.app/distributed/raycast-founder-on-ios-community-and-quality)

### Inferences
- The things to copy are mostly invisible:
  - A pre-rendered panel with no first-frame flash.
  - No layout jump while results stream.
  - Selection that stays on the same item when late results arrive.
  - Learned rankings that make one- or two-letter queries hit.
  - Platform-correct chrome.
- Apple's own metric names (`TimeToTopHit`, `TimeToWindowExpansion`) are a good instrumentation template.

### Gaps
- No vendor published latency budgets, frame-time targets, or benchmark numbers for summon or typing. Raycast's deep dive gives only memory numbers.
