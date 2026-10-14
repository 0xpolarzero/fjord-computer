# Native techniques for a fast in-app command palette on macOS 14+ (SwiftUI + AppKit)

Method note: the reference implementations below were read at source level through the GitHub API on 2026-10-14 (file paths and line-level behaviour are quoted from the files as fetched). Repo stats are from `gh api repos/<owner>/<repo>` on the same day. Web sources were used for Apple APIs, perf behaviour and IME issues. Some Apple doc pages did not render through the fetch tool; where a claim rests on that, it is flagged.

## Window/overlay: NSPanel child window vs SwiftUI overlay vs sheet; panel config, dismissal, focus return, appearance animation, Liquid Glass

### Takeaway
Two patterns hold up in shipping apps. One is a SwiftUI overlay in a `ZStack` over the main window's content (Ghostty). It's the simplest, but focus has to be grabbed and handed back by hand, and the palette is clipped to the host window. The other is an `NSPanel` subclass with `canBecomeKey = true` that closes itself in `resignKey`/`windowDidResignKey` (Maccy, CodeEdit, Sol, DSFQuickActionBar, Tinycast). It floats above the window, gets its own shadow and material, and closes on an outside click for free, but you have to restore the previous key window yourself. I found no reference app that uses a sheet. On macOS 26, `NSGlassEffectView` (contentView/cornerRadius/tintColor) replaces `NSVisualEffectView` plus a mask image. On 14/15 you fall back to `NSVisualEffectView` or SwiftUI materials.

### Cited Findings
**SwiftUI overlay (Ghostty)**
- Ghostty's palette is a SwiftUI overlay. `TerminalCommandPaletteView` puts `CommandPaletteView` in a `ZStack` → `GeometryReader` → `VStack`, with a spacer 5% down from the top and `.zIndex(1)`, on top of the terminal surface. It is not a separate window. — [ghostty macos/Sources/Features/Command Palette/TerminalCommandPalette.swift](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift)
- Focus return in Ghostty: on `onChange(of: isPresented)` going false, it runs `DispatchQueue.main.async { surfaceView.window?.makeFirstResponder(surfaceView) }`. The comment says there is "probably a better way" and that the async hop is needed because onChange runs on a user-interactive thread and Xcode complains. — [TerminalCommandPalette.swift](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift)
- Ghostty uses a `ResponderChainInjector: NSViewRepresentable`: a zero-size dummy `NSView` whose `nextResponder` is set (async) to the terminal surface. This keeps the underlying view in the responder chain while the palette's text field is first responder, so menu and action commands still reach the surface. — [TerminalCommandPalette.swift L188-200](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift)
- Ghostty dismisses on focus loss: `.onChange(of: isTextFieldFocused) { if !focused { onEvent?(.exit) } }`. It has no outside-click monitor. Losing focus is the outside-click signal. — [CommandPalette.swift L228-232](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift)
- Ghostty's chrome: `.background(ZStack { Rectangle().fill(.ultraThinMaterial); Rectangle().fill(backgroundColor).blendMode(.color) }.compositingGroup())`, then `.clipShape(RoundedRectangle(cornerRadius: 10))`, a `tertiaryLabelColor` stroke, `.shadow(radius: 32, y: 12)` and `.frame(maxWidth: 500)`. It forces the `colorScheme` from the luminance of the terminal background. — [CommandPalette.swift L154-172](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift)

**NSPanel configurations in the wild**
- Maccy `FloatingPanel<Content: View>: NSPanel`:
  - styleMask `[.nonactivatingPanel, .resizable, .closable, .fullSizeContentView]`, `isFloatingPanel = true`
  - `level = .statusBar`. A TODO notes that Chrome's autofill uses window level 999, so they may need `.screenSaver` (1000), see Maccy #1403.
  - `collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`, `animationBehavior = .none`, `backgroundColor = .clear`, hidden traffic lights, `titlebarSeparatorStyle = .none`
  - `contentView = NSHostingView(rootView:)` with `.ignoresSafeArea()`
  - Rounded corners: `layer.cornerRadius` + `cornerCurve = .continuous` + `masksToBounds` on both `contentView` and `contentView.superview`
  - Opening: `orderFrontRegardless(); makeKey()`
  - Closing: overrides `resignKey()` → `close()` unless an alert is up. `canBecomeKey` returns `true` "so text inputs inside the panel can receive focus."
  — [Maccy/FloatingPanel.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/FloatingPanel.swift)
- CodeEdit `SearchPanel: NSPanel`: styleMask `[.fullSizeContentView, .titled, .resizable]`, `titlebarAppearsTransparent`, `isMovableByWindowBackground`, `standardWindowButton` overridden to hide the buttons, `windowDidResignKey` → `panel.close()`. It is not non-activating, because it lives inside the app. — [CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift](https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift)
- Sol `Panel: NSPanel`: `[.titled, .fullSizeContentView, .nonactivatingPanel]`, `level = .floating`, `.fullScreenAuxiliary` + `.canJoinAllSpaces`, `isReleasedWhenClosed = false`. `contentView` is an `NSVisualEffectView` (`.headerView`, `.behindWindow`, `.active`). `canBecomeKey`/`canBecomeMain` return true, and `windowDidResignKey` → async `hideWindow()`. — [sol macos/sol-macOS/views/Panel.swift](https://github.com/ospfranco/sol/blob/main/macos/sol-macOS/views/Panel.swift)
- DSFQuickActionBar window:
  - `canBecomeKey`/`canBecomeMain` true
  - styleMask `[.titled, .fullSizeContentView, .borderless]`. The comment says `titled` plus `borderless` "seems to give us a bolder drop shadow than just 'borderless'".
  - `backgroundColor = .clear`, `isOpaque = false`, `level = .floating`, `order(.above, relativeTo: parent.windowNumber)` when a parent is given, `invalidateShadow()` after layout
  - `cancelOperation` (Esc) → `resignMain()`, which closes the window
  — [DSFQuickActionBar+Window.swift](https://github.com/dagronf/DSFQuickActionBar/blob/main/Sources/DSFQuickActionBar/private/DSFQuickActionBar%2BWindow.swift)
- Tinycast `PalettePanel: NSPanel` overrides `canBecomeKey`/`canBecomeMain` to true and `resignKey()`. Its `PaletteWindowController`:
  - records `previousApp` (`NSWorkspace.shared.frontmostApplication`) and `previousOwnWindow` (the app's own key window) when summoned
  - on dismissal, refocuses with `own.makeKeyAndOrderFront(nil)` if that window is still visible, else `previousApp?.activate()`
  - presents with `makeKeyAndOrderFront` + `orderFrontRegardless`, and re-asserts key because "a never-activated login item can drop the first key request"
  - drops `panel.level` to `.normal` while a file panel is open, so it sinks rather than dismisses
  — [Tinycast/Palette/PaletteWindowController.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/PaletteWindowController.swift), [PalettePanel.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/PalettePanel.swift)
- Tutorials: whid.eu's Spotlight-like panel uses `[.nonactivatingPanel, .titled, .fullSizeContentView]`, `.floating`, `.fullScreenAuxiliary` and `isReleasedWhenClosed = false`. A 2026 Fazm guide adds `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded = true` and `[.canJoinAllSpaces, .fullScreenAuxiliary]`. — [whid.eu ch. 6](https://whid.eu/2022/06/03/chapter-6-creating-a-spotlight-like-floating-panel-in-swift/), [Fazm blog](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices), [Cindori floating panel](https://cindori.com/developer/floating-panel), [Markus Bodner](https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/)
- Cindori describes NSPanel's traits: it floats above other windows, stays in memory after closing, and hides when the app isn't active (the `hidesOnDeactivate` default). It injects the panel into the SwiftUI environment so child views can close it. — [Cindori](https://cindori.com/developer/floating-panel)
- `becomesKeyOnlyIfNeeded`: the panel becomes key only when a view that needs keyboard input is clicked. The Apple doc page didn't render through the fetch tool. This is the long-standing AppKit header semantics; verify on [Apple docs](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded).
- Apple Forums: when a floating NSPanel has rounded corners and shows a sheet, the corners are not masked. That's a known pitfall of layer-masked panels. — [Apple Forums 741628](https://developer.apple.com/forums/thread/741628)

**Appearance animation**
- Tinycast `PanelTransition.swift` sets `alphaValue = 0`, orders the window front, then runs `NSAnimationContext.runAnimationGroup` (easeOut) to `animator().alphaValue = 1`. The completion handler calls `invalidateShadow()` because "the shadow is cached from the frame it was first drawn at, scaled down". Fade-out is interruptible (the completion checks `alphaValue == 0` before `orderOut`). Content gets a SwiftUI `scaleEffect(0.94 → 1)` with `.easeOut` on appear. — [Tinycast/DesignSystem/Interaction/PanelTransition.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/DesignSystem/Interaction/PanelTransition.swift)
- Maccy sets `animationBehavior = .none` (no system zoom or fade) and animates only vertical resizes with `animator().setFrame` over 0.2 s. — [FloatingPanel.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/FloatingPanel.swift)

**Liquid Glass (macOS 26) vs NSVisualEffectView**
- WWDC25 "Build an AppKit app with the new design":
  - use `NSGlassEffectView` to put content on glass, and set `contentView` rather than adding subviews
  - customise it with `cornerRadius` and `tintColor`
  - group nearby glass shapes with `NSGlassEffectContainerView`
  - sample: `glass.contentView = view; glass.cornerRadius = 999`
  — [WWDC25 session 310](https://developer.apple.com/videos/play/wwdc2025/310/), [WWDC Notes](https://wwdcnotes.com/documentation/wwdc25-310-build-an-appkit-app-with-the-new-design/)
- `NSGlassEffectView` has a `style` (`.regular`/`.clear`). Its direct `cornerRadius` replaces the mask-image technique `NSVisualEffectView` needs for rounded corners. Third-party code also reaches private `_variant` properties through the runtime, which is not App Store safe. — [artemnovichkov Xcode docs mirror](https://github.com/artemnovichkov/xcode-27-system-prompts/blob/main/AdditionalDocumentation/AppKit-Implementing-Liquid-Glass-Design.md), [LiquidGlassEffects](https://github.com/HoYeonPark1221/LiquidGlassEffects), [onmyway133 #1025](https://github.com/onmyway133/blog/issues/1025)
- Pre-26 fallbacks in the reference apps: Sol uses `NSVisualEffectView` as contentView ([Panel.swift](https://github.com/ospfranco/sol/blob/main/macos/sol-macOS/views/Panel.swift)). CodeEdit uses `EffectView(.sidebar, blendingMode: .behindWindow)` behind the search field ([SearchPanelView.swift](https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift)). Ghostty uses SwiftUI `.ultraThinMaterial` ([CommandPalette.swift](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift)).

### Inferences
- For an *in-app* palette (not a global launcher), `.nonactivatingPanel` isn't needed, since the app is already active. What you do need is a child or attached window (`parent.addChildWindow(panel, ordered: .above)`, or DSF's `order(.above, relativeTo:)`), so the panel moves with its parent and stays above it. Pair it with `hidesOnDeactivate = true` (the NSPanel default) so it disappears with the app.
- The overlay approach avoids a second window, key-window churn and shadow caching, and it shows the host window's glass. Its costs are manual focus restoration (Ghostty's async `makeFirstResponder`) and clipping to the host window. A panel is the better choice when the palette must exceed the window bounds or float over other windows.
- Focus-return recipe, from the Ghostty and Tinycast patterns combined: record `window.firstResponder` (or the previous key window) at presentation time; on dismissal, `DispatchQueue.main.async { previousWindow.makeKeyAndOrderFront(nil); previousWindow.makeFirstResponder(savedResponder) }`, checking that the responder is still in the window.
- Liquid Glass fallback: use `if #available(macOS 26, *) { NSGlassEffectView } else { NSVisualEffectView(material: .popover/.hudWindow, blendingMode: .behindWindow, state: .active) }`. NSVisualEffectView needs `maskImage` for rounded corners, and the rest of the window must stay clear (`backgroundColor = .clear`, `isOpaque = false`).

### Gaps
- None of the examined apps uses a SwiftUI `.sheet`, and I found no source comparing the sheet approach. Sheets are modal and attach under the title bar, which is presumably why they go unused (this is inference).
- I couldn't get the exact Apple doc text for `becomesKeyOnlyIfNeeded`, `hidesOnDeactivate` or `NSWindow.StyleMask.nonactivatingPanel`, because the pages didn't render.
- I don't know whether `NSGlassEffectView` behaves correctly inside a borderless child panel with a custom shadow. No source covered that case.

## Text input: NSTextField delegate commands, marked text / IME / dead keys, SwiftUI TextField + onKeyPress limits, field editor

### Takeaway
The robust AppKit path is `control(_:textView:doCommandBy:)`, used by DSFQuickActionBar. Keys reach it only after the input context (`interpretKeyEvents`) has had them, so IME and dead-key compositions keep their keys for free. SwiftUI's `.onKeyPress` runs before the field editor when attached to an ancestor, so every handler must check the field editor's `hasMarkedText()` and return `.ignored` while composing (Maccy and Tinycast both had to). `onChange(of: text)` does not fire during composition, and marked-text changes show up only as selection-change notifications.

### Cited Findings
- Editing in an `NSTextField` happens in the window's shared field editor (an `NSTextView`). The input context sends either `insertText:replacementRange:` or `doCommandBySelector:`. Arrow keys become `moveUp:`/`moveDown:`, Return becomes `insertNewline:`. The delegate's `textView:doCommandBySelector:` returning YES stops default handling. — [Apple Cocoa Text Architecture: Text Fields, Text Views, and the Field Editor](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextFieldsAndViews/TextFieldsAndViews.html), [Text Editing](https://developer.apple.com/LIBRARY/mac/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html)
- Overriding `keyDown` on the NSTextField doesn't see the arrow keys. Use `control(_:textView:doCommandBy:)`, which is declared on NSControl (QA1454). Subclassing the field editor is "a world of pain". A custom field editor can be supplied via `NSWindow.fieldEditor(_:for:)` or the delegate's `windowWillReturnFieldEditor`. — [Apple Forums 43856](https://developer.apple.com/forums/thread/43856), [QA1454](https://developer.apple.com/library/archive/qa/qa1454/_index.html), [Using the Window's Field Editor](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/WinPanel/Tasks/UsingWindowFieldEditor.html)
- DSFQuickActionBar's delegate handles `moveDown(_:)` → `selectNextSelectableRow()`, `moveUp(_:)` → previous, and `insertNewline(_:)` → `rowAction()` (only when a row is selected). It also maps ⌘+digit via `currentEvent` to shortcut actions. `controlTextDidChange` is debounced 0.2 s. Esc is handled by the window's `cancelOperation(_:)`. — [DSFQuickActionBar+Window.swift L251-356](https://github.com/dagronf/DSFQuickActionBar/blob/main/Sources/DSFQuickActionBar/private/DSFQuickActionBar%2BWindow.swift)
- Dead keys use marked text. On ⌥E (and on AZERTY `^`), AppKit sends `setMarkedText '´'` and then `insertText` on commit, and `hasMarkedText` is YES while the accent is pending. Apps that treat the marked text as committed produce `´e` instead of `é`. The press-and-hold accent popup differs: `setMarkedText` arrives with a real `replacementRange`. — [warp PR #14891](https://github.com/warpdotdev/warp/pull/14891), [docxy #1072](https://github.com/yeroo/docxy/issues/1072)
- `.onKeyPress` on an ancestor runs *before* the focused TextField's field editor. Returning `.handled` means `interpretKeyEvents` never runs and `NSTextInputContext` never sees the key. Concrete bug: with Japanese Kotoeri composing `にほんご`, ↑ didn't step back through candidates and Esc closed the palette instead of cancelling the composition. Return was already correctly left to the IME. — [Tinycast issue #990 (closed)](https://github.com/abue-ammar/tinycast/issues/990)
- Maccy's `KeyHandlingView` guards its `.onKeyPress` with `if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient, inputClient.hasMarkedText() { return .ignored }`, and ignores arrows while `NSApp.characterPickerWindow != nil` (the emoji or accent picker). Its comment: `onKeyPress` doesn't expose the key code and "don't properly work with multiple inputs", so ⌘, fails on non-English layouts. Maccy decodes `NSApp.currentEvent` with Sauce (layout-aware key codes) instead. — [Maccy/Views/KeyHandlingView.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Views/KeyHandlingView.swift)
- Tinycast's composition tracking:
  - `PalettePanel` reaches the field editor as `firstResponder as? NSTextView` ("SwiftUI's text fields all edit through the window's one shared field editor")
  - it mirrors `editor.hasMarkedText()` into `paletteState.isComposing` by observing `NSTextView.didChangeSelectionNotification`, because "selection is the only notification a marked-text change posts; `didChange` waits for commit"
  - Return in `.onKeyPress` checks `guard !vm.isComposing else { return .ignored }`
  - it overrides `sendEvent` to catch keys the field editor swallows before `onKeyPress` sees them: bare Backspace (skipped when `hasMarkedText`), Escape and command chords
  — [Tinycast/Palette/PalettePanel.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/PalettePanel.swift), [RootPaletteView.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/RootPaletteView.swift)
- Related Tinycast issue #769: with Chinese Pinyin, results don't update during composition, because the bound query stays empty until commit. The requested behaviour was to filter on the marked text provisionally without acting on Return. — [Tinycast #769](https://github.com/abue-ammar/tinycast/issues/769)
- Ghostty's SwiftUI key wiring:
  - `TextField` + `.focused($isTextFieldFocused)` + `.onExitCommand` (Esc) + `.onMoveCommand` (arrows) + `.onSubmit` (Return)
  - invisible zero-size `Button`s with `.keyboardShortcut(.upArrow/.downArrow, modifiers: [])` and ⌃P/⌃N, marked `.accessibilityHidden(true)`
  - initial focus is set in `onAppear` via `DispatchQueue.main.async { isTextFieldFocused = true }`, which fixes "Command Palette doesn't have focus" on macOS 26 beta 9 (#8497); the comment says the issue came back with Xcode 26.4
  — [CommandPalette.swift L185-249](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift), [ghostty #8497](https://github.com/ghostty-org/ghostty/issues/8497)
- `onKeyPress` (macOS 14+) fires only when the view (or a descendant) has focus. `.handled` stops propagation and `.ignored` passes the key to the parent. Phases (`.down`, `.repeat`, `.up`) can be filtered; Tinycast uses `phases: [.down, .repeat]` for arrow auto-repeat. — [SwiftLee](https://www.avanderlee.com/swiftui/key-press-events-detection/), [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-and-respond-to-key-press-events), [RootPaletteView.swift L493-530](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/RootPaletteView.swift)
- CodeEdit's palette uses a plain SwiftUI `TextField` with `.onSubmit` (it beeps if nothing is selected) and resets the selection to the first option in `.task(id: options)`. — [SearchPanelView.swift](https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift)
- Apple Forums report: a SwiftUI TextField in a menu-bar app lost focus and stopped taking input in Japanese Romaji mode under some conditions. — [Apple Forums 729920](https://developer.apple.com/forums/thread/729920)

### Inferences
- With an AppKit `NSTextField` and `doCommandBy`, composition safety comes from the architecture. While marked text exists, the input method consumes ↑/↓/Return/Esc and never sends `moveUp:`/`insertNewline:`/`cancelOperation:`. In SwiftUI you rebuild that guarantee by hand with a `hasMarkedText()` check in every key handler. That argues for hosting an `NSTextField` (via `NSViewRepresentable`) for the query field in a palette that must work on AZERTY with dead keys.
- Filter on `controlTextDidChange`/`onChange(of: text)`, which fire on committed text only. A pending `^` (marked) then never triggers a filter pass, which suits dead keys. For CJK, optionally filter on `editor.string` (marked text included) while `hasMarkedText()`, as Tinycast #769 requests.
- Restore the saved first responder asynchronously: both Ghostty and Tinycast hop to the next run-loop turn for focus changes.

### Gaps
- I found no Apple documentation saying `onSubmit` is or isn't suppressed during marked-text commit on macOS 14. The reference apps imply Return is left to the IME when a plain `TextField` is focused (Tinycast #990 says "the same way it already keeps ↵"), but I found no official confirmation.
- I didn't find Christian Tietze's or Mark Malstrom's posts on field-editor customisation.

## List rendering: NSTableView vs SwiftUI List/LazyVStack per keystroke; NSHostingView-in-cell; scroll-into-view; hover suppression under a still pointer

### Takeaway
For per-keystroke re-filtering of hundreds to thousands of rows, a view-based `NSTableView` with fixed `rowHeight`, reused cells (`makeView(withIdentifier:owner:)`) and `reloadData()` (or a non-animated diffable apply) is the predictable choice. SwiftUI `List` on macOS evaluates every row's body up front. For small, capped result sets (≤ ~50 rows), `ScrollView` + `LazyVStack` + `ScrollViewReader.scrollTo` is fine and is what Ghostty, Maccy and Tinycast do. Hover-highlight-while-scrolling is solved by "arming" hover only on real pointer movement (Tinycast).

### Cited Findings
- SwiftUI `List` on macOS calls init and body for every row, even off-screen ones. On a 10,000-row List, one report measured about 2 s to appear (M1 Max) and another 100% CPU for 50+ s (M3, 10k rows), with selection and scrolling slowdowns. Making the row view `Equatable` cut startup to under 0.1 s on Sequoia. `ScrollView` + `LazyVStack` only runs body for rows near the viewport but loses List selection. — [TrozWare 2024](https://troz.net/post/2024/swiftui_lists/), [HWS forum](https://www.hackingwithswift.com/forums/swiftui/swiftui-list-performance-with-row-count-2000/14259), [Apple Forums 704778](https://developer.apple.com/forums/thread/704778)
- SwiftUI `Table` hangs: 13+ s for a selection in a 1,219-row table, and minutes when updating a 5,000-row table. An Apple engineer suggested Instruments' SwiftUI tracks and checking `@Observable` invalidations caused by selection. — [Apple Forums 739849](https://developer.apple.com/forums/thread/739849), [765653](https://developer.apple.com/forums/thread/765653)
- Kean (Pulse) moved from List to `NSTableView` and suspects List has no cell reuse on macOS. — [kean/articles "not list"](https://github.com/kean/articles/blob/main/2021-03-01-not-list.markdown)
- WWDC23 "Demystify SwiftUI performance" covers dependencies, faster view updates and "Identity in List and Table" (row count must be cheap to compute; avoid `ForEach` with filtering inside it). — [WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/)
- Ghostty renders rows with a non-lazy `VStack` inside `ScrollView`, inside `ScrollViewReader` with `.frame(maxHeight: 200)`, and calls `proxy.scrollTo(options[i].id)` in `onChange(of: selectedIndex)`. Hover is a separate `hoveredOptionID` set from `.onHover` and drawn in a different colour from the selection. `filteredOptions` is a computed property on the view, re-filtered on every body evaluation. `CommandOption.id` is `let id = UUID()`, created at init. — [CommandPalette.swift L251-413](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift)
- Maccy (SwiftUI since its 2.x rewrite) uses `ScrollView { ScrollViewReader { MultipleSelectionListView(...) } }` with `.task(id: appState.navigator.scrollTarget) { proxy.scrollTo(selection) }`. Fuzzy search uses Fuse with threshold 0.7 and a 5,000-character cap per item. — [HistoryListView.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Views/HistoryListView.swift), [Search.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Search.swift)
- CodeEdit's `NSTableViewWrapper: NSViewRepresentable`:
  - calls `reloadData()` on every `updateNSView`, then `selectRowIndexes` + `scrollRowToVisible(item)`
  - fixed `heightOfRow` (default 50)
  - builds a **new `NSHostingView(rootView:)` per row in `viewFor`**, with no `makeView(withIdentifier:)` reuse
  — [CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift](https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift)
- DSFQuickActionBar's table:
  - `NSTableView` with `usesAutomaticRowHeights = true` (fixed `rowHeight` on 10.11/10.12)
  - `intercellSpacing (0,5)`
  - a custom `NSTableRowView.drawSelection` that fills an accent-coloured rounded rect inset (4,2)
  - `scrollRowToVisible` on selection change, `reloadData()` per result set
  - a `ResultsTableView.keyDown` subclass for Return, ← (back to the field) and ⌘+digit
  - cell options: XIB, DSFAppKitBuilder or SwiftUI cells (demos)
  — [DSFQuickActionBar+ResultsView.swift](https://github.com/dagronf/DSFQuickActionBar/blob/main/Sources/DSFQuickActionBar/private/DSFQuickActionBar%2BResultsView.swift)
- NSTableViewDiffableDataSource:
  - for initial loads and large changes, use non-animated applies; animated applies create extra cells used only during the animation (Apple engineer, UIKit analogue)
  - macOS 15 betas: the `cellProvider` was not called for changed visible cells on animated apply; non-animated apply worked around it (FB13943853)
  - a diffable source over 8,000+ items was much slower than a direct data source in one report
  — [Apple Forums 706349](https://developer.apple.com/forums/thread/706349), [759384](https://developer.apple.com/forums/thread/759384), [651975](https://developer.apple.com/forums/thread/651975)
- Hover suppression under a stationary pointer (Tinycast):
  - `PalettePanel.sendEvent` is "the one place both event streams pass through". `.mouseMoved` → `notePointerMoved(to:)`; `.keyDown`/`.scrollWheel` → `disarmHoverHighlight(pointerAt:)`.
  - `HoverArming.isDeliberate` re-arms only when the pointer moves more than **3 pt** from the anchor ("a wheel click nudges the mouse a point or two, and a gesture ends with no displacement")
  - rows use `.onContinuousHover` and set `hovered = palette.hoverHighlightArmed`; a `hoverDisarmToken` clears hover on disarm because "disarming under a still pointer fires no hover phase"
  — [PalettePanel.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/PalettePanel.swift), [HoverArming.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/HoverArming.swift), [ArmedHover.swift](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/ArmedHover.swift)

### Inferences
- CodeEdit's per-row `NSHostingView` allocation without reuse, combined with `reloadData()` on every SwiftUI update, is the anti-pattern to avoid. If you host SwiftUI in cells, register a reusable `NSTableCellView` subclass that owns one `NSHostingView` and swap its `rootView`, or draw cells in AppKit (`NSTextField` + `NSImageView`). Fixed `rowHeight` with `usesAutomaticRowHeights = false` skips per-row height measurement.
- Ghostty's model is identity-unstable: `UUID()` per `CommandOption`, and options rebuilt in a computed property, so new IDs on every rebuild. It's acceptable for a non-lazy list of about 50 commands, but it defeats SwiftUI diffing and `scrollTo` targeting if options change while the palette is open. Use stable IDs (the command identifier).
- For keyboard selection, `scrollRowToVisible(row)` (AppKit) or `proxy.scrollTo(id)` with no anchor (scroll only when needed) avoids jumpy recentering. Wrap the scroll in a non-animated transaction while a key is auto-repeating.
- For an AppKit table, the same hover-arming idea maps to `NSTrackingArea` with `.mouseMoved`. Ignore `mouseMoved` whose delta from the last anchor is ≤ ~3 pt after a keyDown or scroll event.

### Gaps
- I found no published benchmark comparing NSTableView `reloadData()` with diffable apply per keystroke for a palette-sized list (100–5,000 rows).
- I didn't find Maccy maintainers' perf notes on the 2.0 SwiftUI rewrite (not searched in their issues because of time). Worth checking their issue tracker for "slow" and "lag" if needed.

## Async: search-as-you-type with Swift concurrency, cancellation, debounce, @MainActor application, Observation granularity

### Takeaway
Keep one `Task` handle per palette. On every keystroke, cancel it *immediately* and start a new one. Debounce (`Task.sleep`) only when the source is slow (filesystem, network). In-memory command filtering should run synchronously on the main actor within the same frame. Check `Task.isCancelled`/`checkCancellation()` after each await and before writing results. Tag results with the query they answer. With `@Observable`, views re-render only for the properties they read, but reading a whole array still invalidates every reader.

### Cited Findings
- CodeEdit Open Quickly: `runningTask?.cancel()` then `Task.detached(priority: .userInitiated)` to enumerate files. It checks `Task.isCancelled` before and after `fuzzySearch`, then assigns `searchResults` on the main actor. The model is `ObservableObject` with `@Published query/searchResults`. — [OpenQuicklyViewModel.swift](https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/OpenQuickly/ViewModels/OpenQuicklyViewModel.swift)
- DSFQuickActionBar: debounce 0.2 s on text change. The async `SearchTask` object carries `searchTerm` and an `NSLock`-guarded completion; `cancel()` completes with nil and `isCancelled` is "completion == nil", so stale completions are dropped. — [DSFQuickActionBar+SearchTask.swift](https://github.com/dagronf/DSFQuickActionBar/blob/main/Sources/DSFQuickActionBar/DSFQuickActionBar%2BSearchTask.swift), [Window.swift](https://github.com/dagronf/DSFQuickActionBar/blob/main/Sources/DSFQuickActionBar/private/DSFQuickActionBar%2BWindow.swift)
- Ghostty filters synchronously in the view body (`options.filteredAndSorted(query:)`: substring first, then word-initials fallback; ranks colour > title > subtitle > description). — [CommandPalette.swift L430-529](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift)
- Cancellation is cooperative. `Task.sleep` throws `CancellationError` when cancelled, but an in-flight API may still return, so check after the await. Cancel the prior search *immediately* on a new keystroke and use debounce only to decide when to *start* the next. `.task(id: query)` gives cancel-and-restart per value for free. — [SwiftLee Task.sleep](https://www.avanderlee.com/concurrency/task-sleep-vs-yield-differences/), [Swift with Majid](https://swiftwithmajid.com/2025/02/18/yielding-and-debouncing-in-swift-concurrency/), [Swift Forums: throttling/debouncing async sequences](https://forums.swift.org/t/throttling-or-debouncing-async-sequences/49751), [Side Effect "Regulate"](https://sideeffect.io/posts/2023-01-11-regulate/)
- Observation: SwiftUI records the `@Observable` property getters accessed in `body` and invalidates only on those. WWDC25 "Optimize SwiftUI performance with Instruments" shows that reading a shared collection creates a dependency on the whole collection for every row. The fix is per-item `@Observable` models with the container marked `@ObservationIgnored`. — [WWDC23 Discover Observation](https://developer.apple.com/videos/play/wwdc2023/10149/), [WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/)
- `Self._printChanges()` inside `body` logs why a view re-evaluated (debug only). — [WWDC23 10160 notes](https://michaelrowe01.com/index.php/blog/demystify-swiftui-performance/)

### Inferences
- Recommended shape:
  - `@MainActor @Observable final class PaletteModel { var query; private(set) var results: [Row]; var selection: Row.ID? ; private var task: Task<Void,Never>? }`
  - for in-memory sources, compute results synchronously in `didSet` of `query` (sub-millisecond for hundreds of commands)
  - for slow sources, `task?.cancel(); task = Task { try? await Task.sleep(for: .milliseconds(80)); let r = await source.search(q); guard !Task.isCancelled, q == self.query else { return }; results = r }`
  - the `q == self.query` guard defends against an uncancelled API delivering late
- Keep `selection` separate from `results`, so moving the highlight doesn't invalidate row bodies. Rows should read only their own item plus a per-row `isSelected: Bool` passed as a value (an Equatable row view), not the whole selection.
- `AsyncStream` of query strings is useful when several sources merge. For a single source, a cancel-on-keystroke `Task` is simpler and has lower latency.

### Gaps
- I didn't fetch Matt Massicotte's concurrency posts directly. The findings above rely on SwiftLee, Swift with Majid, Swift Forums and Side Effect.

## Accessibility: VoiceOver for a listbox palette

### Takeaway
Expose the palette as a text field plus a list/table that reports its rows and selected row. An `NSTableView` does this natively. Post selected-rows-changed on keyboard moves while focus stays in the text field. Use `announcementRequested` only for things VoiceOver can't infer, such as the result count.

### Cited Findings
- `NSAccessibilityList` and `NSAccessibilityOutline` inherit from `NSAccessibilityTable` (`accessibilityRows`, `accessibilitySelectedRows`, `setAccessibilitySelectedRows:`). Posting `NSAccessibilitySelectedRowsChangedNotification` on selection change lets VoiceOver speak it. — [Avalonia #22390](https://github.com/AvaloniaUI/Avalonia/issues/22390)
- Announcements:
  - `NSAccessibility.post(element: NSApp (or window), notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])`
  - the text is not spoken unless it is under the `.announcement` key
  - on macOS 14+, `AccessibilityNotification.Announcement(text).post()` is available, though one review found it wasn't heard while the AppKit route worked
  - medium-priority announcements can be cut off by the next one, and macOS has no "did finish" notification to queue on
  — [Apple Forums 761728](https://developer.apple.com/forums/thread/761728), [Apple Forums 709501](https://developer.apple.com/forums/thread/709501), [appandflow/stim PR #2155](https://github.com/appandflow/stim/pull/2155)
- Reused NSTableView row views make labels set once go stale. Set accessibility labels in `viewFor` and configure them on reuse. — [Rabbit PR #29](https://github.com/Timtam/rabbit/pull/29)
- Ghostty hides its keyboard-shortcut helper buttons from accessibility with `.accessibilityHidden(true)`. Tinycast sets an `.accessibilityLabel` on the search field from its prompt. — [CommandPalette.swift L220](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift), [RootPaletteView.swift L875](https://github.com/abue-ammar/tinycast/blob/main/Tinycast/Palette/RootPaletteView.swift)
- Apple's AccessibilityUIExamples include custom row elements for outline and table views (a starting point for custom AX rows). — [Apple sample](https://developer.apple.com/library/archive/samplecode/AccessibilityUIExamples/Listings/AccessibilityUIExamples_Outline_CustomOutlineViewAccessibilityRowElement_swift.html)

### Inferences
- Keyboard focus stays in the text field while arrows move the table selection, so VoiceOver won't follow the table on its own. Post `.selectedRowsChanged` on the table and a short low- or medium-priority announcement of the row title. Use high priority only when the result count changes to zero ("No matches").
- In SwiftUI rows, use `.accessibilityAddTraits(.isSelected)` on the highlighted row, plus `.accessibilityElement(children: .combine)` so a row reads as one element. I found no source specific to macOS palettes for this.

### Gaps
- I found no published guidance from Apple specific to combobox/listbox palettes on macOS, and no open-source Swift palette that I verified posts accessibility notifications on arrow-key selection.

## Open-source Swift reference implementations

### Takeaway
The most instructive sources are:
- **Tinycast**: SwiftUI in NSPanel, with the most complete handling of IME, hover arming, focus return and fades; AGPL, so study it, don't copy it.
- **Ghostty**: a minimal SwiftUI overlay palette, MIT.
- **DSFQuickActionBar**: a classic AppKit NSTextField + NSTableView palette, MIT, dormant since 2024.
- **Maccy**: SwiftUI in NSPanel with IME-guarded `onKeyPress`, MIT.
- **CodeEdit**: SwiftUI + `NSTableView` wrapper, MIT; it has instructive anti-patterns.

Loop and Ice are not command palettes.

### Cited Findings
Stats via `gh api` on 2026-10-14:

| Project | Stack | Key files | License | Stars / last push |
|---|---|---|---|---|
| [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) | SwiftUI overlay in the terminal window; TextField + onMoveCommand/onExitCommand/onSubmit; non-lazy VStack in ScrollView; `.ultraThinMaterial` | `macos/Sources/Features/Command Palette/CommandPalette.swift` (529 lines), `TerminalCommandPalette.swift` (200) | MIT | 62.2k / 2026-10-14 |
| [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) ("a tiny, fully native macOS launcher, hotkeys, and clipboard history") | SwiftUI in an NSPanel subclass; `sendEvent` choke point; `onKeyPress` with composition guards; hover arming; NSAnimationContext fades; tests such as `Tests/palette-navigation-test.swift`, `palette-escape-test.swift` | `Tinycast/Palette/PalettePanel.swift`, `PaletteWindowController.swift`, `RootPaletteView.swift` (1,554 lines), `HoverArming.swift`, `ArmedHover.swift`, `DesignSystem/Interaction/PanelTransition.swift` | AGPL-3.0 (LICENSE file; GitHub reports NOASSERTION) | 8.5k / 2026-10-13 |
| [p0deje/Maccy](https://github.com/p0deje/Maccy) | SwiftUI in an NSPanel (`FloatingPanel`), `@Observable` AppState, Fuse fuzzy search, Sauce key codes | `Maccy/FloatingPanel.swift`, `Views/KeyHandlingView.swift`, `Views/HistoryListView.swift`, `Search.swift` | MIT | 21.9k / 2026-10-14 (v2.7.1, 2026-08-10) |
| [CodeEditApp/CodeEdit](https://github.com/CodeEditApp/CodeEdit) | SwiftUI TextField + `NSTableViewWrapper` (NSViewRepresentable) in an NSPanel; detached Task search | `CodeEdit/Features/OpenQuickly/*`, `CodeEditUI/Views/SearchPanel.swift`, `SearchPanelView.swift` | MIT | 23.1k / 2026-08-18 |
| [dagronf/DSFQuickActionBar](https://github.com/dagronf/DSFQuickActionBar) | Pure AppKit: NSTextField delegate `doCommandBy` + NSTableView; SwiftUI wrapper `QuickActionBar.swift`; XIB, AppKitBuilder and SwiftUI cell demos; FauxSpotlight demo | `Sources/DSFQuickActionBar/private/DSFQuickActionBar+Window.swift`, `+ResultsView.swift`, `DSFQuickActionBar+SearchTask.swift` | MIT | 151 / 2024-07-20 |
| [ospfranco/sol](https://github.com/ospfranco/sol) | Native NSPanel shell (`macos/sol-macOS/views/Panel.swift`, `managers/PanelManager.swift`); UI not native Swift (the repo's main UI layer is outside `sol-macOS`) | `Panel.swift` | MIT | 3.2k / 2026-10-07 |
| [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | Menu bar manager, not a palette | n/a | GPL-3.0 | 29.8k / 2026-10-06 |
| [MrKai77/Loop](https://github.com/MrKai77/Loop) | Window manager (radial menu), not a palette | n/a | GPL-3.0 | 11.8k / 2026-10-14 |
| [adamtheturtle/CommandPaletteKit](https://github.com/adamtheturtle/CommandPaletteKit) | Not examined | n/a | MIT | 0 / 2026-10-12 |
| [astzweig/swiftui-launcher-window](https://github.com/astzweig/swiftui-launcher-window) | Not examined | n/a | EUPL-1.2 | 3 / 2024-07-11 |

- The repo `tinycast/tinycast` is an unrelated empty account (0 stars, last push 2020). The real Tinycast is `abue-ammar/tinycast`. — `gh api` results above.
- Ghostty's palette regression #8497 ("macOS 26 Beta 9: Command Palette Doesn't Have Focus", closed) shows that SwiftUI focus timing in overlays is fragile across OS betas. — [ghostty #8497](https://github.com/ghostty-org/ghostty/issues/8497)

### Inferences
- Licensing: Tinycast (AGPL-3.0), Ice and Loop (GPL-3.0) are reference-only for a closed or differently licensed app. Ghostty, Maccy, CodeEdit, DSFQuickActionBar and Sol are MIT and can be adapted with attribution.
- Maturity: Ghostty, Maccy and Tinycast are under active, daily development. DSFQuickActionBar is stable but dormant (last push July 2024); its AppKit techniques are timeless. CommandPaletteKit and swiftui-launcher-window are too new or small to rely on.

### Gaps
- I could not identify the "Corta PR" mentioned in the brief. Searches turned up no Swift repo or PR by that name.
- I didn't read Sol's UI layer. The "React Native" characterisation of Sol is from general knowledge, not verified in this session.
- I didn't verify whether Maccy's issue tracker has documented perf regressions from the SwiftUI rewrite.
- `antonyshakirov/hop` (133 stars, MIT, pushed 2026-10-10) came up in a "command palette swift macos" search but wasn't examined.
