# How command palettes and quick-open panels are built inside native and GPU-rendered desktop apps

Scope: Zed (GPUI), Ghostty (macOS, SwiftUI-in-AppKit), CodeEdit (SwiftUI + AppKit), Xcode Open Quickly, Sublime Text, Arc/Dia, Tower, Things 3, Nova, BBEdit, Craft. All three open-source repos were shallow-cloned and read on 2026-10-14. Permalinks pin these commits:
- Zed `c403bc6af644cd0ab60c90045ac6dc3436218809` (2026-10-14)
- Ghostty `291fd050b9e9c293c8adb6a140742649b7e42d3a` (2026-10-14)
- CodeEdit `fa2aebd86373211c78626074b53ab75010767575` (2026-08-18)

Shorthand used below: Z = `https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/`, G = `https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/`, C = `https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/`.

## Q1. UI stack, and whether the palette is a separate panel or window or an overlay inside the main window

### Takeaway
The three open-source apps take three different approaches:
- **Zed** draws the palette as an in-window overlay element in its own GPU renderer. Its `ModalLayer` is an absolutely positioned div that occludes the workspace.
- **Ghostty** puts a SwiftUI overlay in a `ZStack` over the terminal, inside the main window's hosting view.
- **CodeEdit** uses a separate `NSPanel` subclass that is added as a child window of the workspace window, with SwiftUI content inside it.

Xcode's Open Quickly is AppKit with its own window controller (`IDEAbstractOpenQuicklyWindowController`). The closed-source apps (Sublime, Arc, Tower, Things, Nova, BBEdit, Craft) publish almost nothing about their window structure.

### Cited Findings

**Zed (GPUI, custom GPU renderer, Rust)**
- The command palette is a `Picker` built with `Picker::uniform_list(delegate, window, cx).initial_width(rems(38.0))` and registered as a `ModalView` (`impl ModalView for CommandPalette {}`). — [Z crates/command_palette/src/command_palette.rs L44, L147-148](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L147)
- Modals render inside the workspace window. `ModalLayer::render` returns `div().absolute().size_full().inset_0().occlude()`, which can fade the background (`elevated_surface_background` faded 0.2). A left mouse-down on the scrim calls `hide_modal`. The modal sits in a `v_flex().h(px(0.0)).top_20().items_center()` and `track_focus(&active_modal.focus_handle)`, and the inner `h_flex().occlude()` stops mouse-down propagation. So the overlay is an element in the same window, not an OS window. — [Z crates/workspace/src/modal_layer.rs L289-333](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/workspace/src/modal_layer.rs#L289-L333)
- `ModalView` has `on_before_dismiss` returning `DismissDecision`, plus `fade_out_background` and `render_bare`. If closing the current modal fails, the new modal isn't shown. — [Z crates/workspace/src/modal_layer.rs L8-L160](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/workspace/src/modal_layer.rs)
- The file finder is the same `Picker` machinery, using `Picker::uniform_list_with_preview(delegate, preview, window, cx)`, and is also a `ModalView`. — [Z crates/file_finder/src/file_finder.rs L64, L225](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L225)

**Ghostty (macOS: AppKit window controller hosting SwiftUI)**
- The palette is a SwiftUI overlay inside the terminal window. `TerminalView` adds `TerminalCommandPaletteView(surfaceView:isPresented: $viewModel.commandPaletteIsShowing, ...)` as a sibling layer above the split tree, before the `UpdateOverlay`. — [G macos/Sources/Features/Terminal/TerminalView.swift L110-118](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Terminal/TerminalView.swift#L110-L118)
- `TerminalCommandPaletteView` is a `ZStack { if isPresented { GeometryReader { VStack { Spacer().frame(height: geometry.size.height * 0.05); ResponderChainInjector(...); CommandPaletteView(...).zIndex(1); Spacer() } } } }`. The palette sits 5% down from the top of the window. — [G macos/Sources/Features/Command Palette/TerminalCommandPalette.swift L36-71](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift#L36-L71)
- Styling:
  - The view is capped at `.frame(maxWidth: 500)`.
  - The background is `.ultraThinMaterial` with the terminal background color blended in using `.blendMode(.color)` inside a `.compositingGroup()`.
  - It has a 10 pt rounded clip, a `tertiaryLabelColor` stroke and `.shadow(radius: 32, x: 0, y: 12)`.
  - The color scheme is chosen from the terminal background's luminance (`NSColor(backgroundColor).isLightColor`).
  - Source: [G .../Command Palette/CommandPalette.swift L92-181](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L92-L181)
- History: the macOS command palette arrived in PR #7153 (2025-04-21, Mitchell Hashimoto). It is in the View menu and bound to `toggle_command_palette`, default `cmd+shift+p`. Every entry must map to a bindable action. — [ghostty PR #7153](https://github.com/ghostty-org/ghostty/pull/7153)
- The appear and disappear animation was removed in PR #9964: "Lots of people complained about this and I don't see value in it." — [ghostty PR #9964](https://github.com/ghostty-org/ghostty/pull/9964)
- PR #7283 moved window-title handling "fully to AppKit" to fix the palette overwriting the window title. Mitchell said the earlier `focusedValue`-based code "was a relic of when Ghostty was a full SwiftUI app." — [ghostty PR #7283](https://github.com/ghostty-org/ghostty/pull/7283); issue [#7236](https://github.com/ghostty-org/ghostty/issues/7236)

**CodeEdit (SwiftUI views inside an AppKit NSPanel child window)**
- `final class SearchPanel: NSPanel, NSWindowDelegate`:
  - styleMask `[.fullSizeContentView, .titled, .resizable]`, 500x48 content rect, `center()`.
  - `titlebarAppearsTransparent = true` and `isMovableByWindowBackground = true`.
  - Overrides `standardWindowButton` to hide the traffic lights.
  - Closes itself in `windowDidResignKey`.
  - Source: [C CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift)
- Presentation: `panel.contentView = NSHostingView(rootView: SettingsInjector { contentView })`, then `window?.addChildWindow(panel, ordered: .above)` and `panel.makeKeyAndOrderFront(self)`. The same shortcut closes the panel if it is already key. Both `openQuickly` (Open Quickly) and the command palette ("Quick Actions") work this way. — [C CodeEdit/Features/Documents/Controllers/CodeEditWindowController.swift ~L115-187](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Documents/Controllers/CodeEditWindowController.swift)
- Shared SwiftUI content: `SearchPanelView<RowView, PreviewView, Option>` has a `TextField` at 20 pt light, an `EffectView(.sidebar, blendingMode: .behindWindow)` background and `minWidth: 680`. Its height collapses to 19 pt when the query is empty, unless `alwaysShowOptions` is set, and grows to min 400 otherwise. Open Quickly adds a preview pane at 272 pt list width. — [C CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift)
- Palette views: `OpenQuicklyView.swift` ([C .../OpenQuickly/Views/OpenQuicklyView.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/OpenQuicklyView.swift)) and `QuickActionsView.swift`, which is the command palette, with its file header still saying `CommandPaletteView.swift` ([C .../Commands/Views/QuickActionsView.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Commands/Views/QuickActionsView.swift)).

**Xcode Open Quickly (AppKit, closed source)**
- Reverse engineering of Xcode 9.3 IDEKit names `-[IDEAbstractOpenQuicklyWindowController prepareToShowWindow]` and `inDarkMode`. `prepareToShowWindow` picks `NSAppearanceNameVibrantDark` or `NSAppearanceNameVibrantLight` based on the theme's `isDark`, so it is a dedicated window controller with a vibrant window. The post doesn't say whether it is an NSPanel. — [ndersson.me, "Byte patching Xcode 9.3"](https://ndersson.me/post/byte_patching_xcode/)

**Sublime Text (custom C++ cross-platform UI toolkit, OpenGL or software rendering)**
- Sublime HQ: "Sublime Text is built from custom components ... a powerful, custom cross-platform UI toolkit". ST4 added an OpenGL renderer, which is the default on Mac. The `hardware_acceleration` setting switches between `"none"` (software) and `"opengl"`. — [Sublime Text GPU rendering docs](https://www.sublimetext.com/docs/gpu_rendering.html) (from search snippet, not fetched); [Sublime Text 4 announcement](https://www.sublimetext.com/blog/articles/sublime-text-4)
- The ST4 changelog lists a Mac fix for "slow Goto Anything in conjunction with OpenGL rendering in some circumstances". — [ST4 changelog gist](https://gist.github.com/jfcherng/7bf4103ea486d1f67b7970e846b3a619) (from search snippet)

**Arc / Dia (The Browser Company)**
- Josh Miller on Dia's architecture: "We use a modified version of MVVM that retains many ideas from unidirectional data flow architectures, but avoids state diffing for performance reasons." Also: "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance." — [Josh Miller on X](https://x.com/joshm/status/1927466374781079799), via [Michael Tsai, "Arc and Dia" (2025-05-30)](https://mjtsai.com/blog/2025/05/30/arc-and-dia/)

**Tower (Quick Actions)**
- Heiko Witte, a senior Mac developer, conceived Quick Actions, inspired by Spotlight, LaunchBar and Alfred. Implementation started 2017-03-13 and it shipped in Tower 3.0 for Mac. The article says nothing about the UI framework or window type. — [Tower blog, "Inside Quick Actions" (Bruno Brito, updated April 2024)](https://www.git-tower.com/blog/inside-quick-actions)

**Nova (Panic)**
- Nova's Theme settings say the Command Palette and Open Quickly use an inverted appearance by default (dark with a light theme and light with a dark theme) so they stand out. This can be turned off. — [Nova Library: Theme](https://help.nova.app/settings/theme/) (from search snippet)

### Inferences
- The overlay-in-window approach (Zed, Ghostty) avoids key-window churn. The main window stays key, the titlebar doesn't dim, and the palette moves and resizes with the window.
- The child-NSPanel approach (CodeEdit, and probably Xcode) gets real window vibrancy (`.behindWindow`) and can extend past the parent window. The cost is resign-key handling: CodeEdit closes on `windowDidResignKey`, and menu shortcuts like ⌘W can leak through (see Q2).
- Ghostty's history shows a trend in SwiftUI-on-Mac apps: focus and title state move back to AppKit controllers over time. Dia's AppKit-only rewrite is the extreme version of that.

### Gaps
- No public source says whether Xcode's Open Quickly window is an `NSPanel`, borderless `NSWindow` or child window. Only the window controller class name is known.
- Arc's Command Bar: I found no engineering post or talk from The Browser Company on how it was built (SwiftUI vs AppKit, window type) or how fast it is. The only first-party performance statement is the Dia "AppKit exclusively" quote above. Claims that "Arc is SwiftUI" circulate, but I found no primary source to cite.
- Things 3 Quick Find, Craft, BBEdit (Go ‣ Command…, ⌘⇧U, per [Michael Tsai](https://mjtsai.com/blog/2022/11/16/command-bars/)) and Nova: I found no public engineering detail on stack or window structure.

## Q2. Keyboard handling: routing arrows, Enter and Escape while the text field keeps focus, and IME / marked text

### Takeaway
- **Zed** handles keys through its action system and key contexts: a keymap entry scoped to `"Picker > Editor"` maps `up`/`down`/`escape` to `menu::SelectPrevious`/`SelectNext`/`Cancel`. These beat the editor's own bindings because the context is more specific. The query field is a full Zed `Editor`, so IME goes through GPUI's NSTextInputClient-mirroring `InputHandler`.
- **Ghostty** combines SwiftUI `.onMoveCommand`, `.onExitCommand` and `.onSubmit` on a `TextField`, plus invisible zero-size `Button`s with `.keyboardShortcut(.upArrow/.downArrow)` and Ctrl-P/Ctrl-N.
- **CodeEdit** uses the same hidden-`Button` trick for ↑/↓/Esc, `.onSubmit` for Enter, and an `NSTableView` subclass that refuses first responder.

Both SwiftUI apps hit focus bugs (see below), and neither uses `control:textView:doCommandBySelector:`.

### Cited Findings

**Zed**
- Default macOS keymap: `"context": "Picker > Editor"` binds `"escape": "menu::Cancel"`, `"up": "menu::SelectPrevious"`, `"down": "menu::SelectNext"`, `"tab": "picker::ConfirmCompletion"`, `"alt-enter": ["picker::ConfirmInput", ...]`. A comment notes that preview and actions-menu bindings live in `specific-overrides-macos.json`, which loads after the base keymap "so they win over conflicting base-keymap Editor bindings." — [Z assets/keymaps/default-macos.json L1275-1288](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/assets/keymaps/default-macos.json#L1275-L1288)
- The Picker root sets `key_context("Picker")` (plus `"with_preview"`) and registers `.on_action(cx.listener(Self::select_next))`, `select_previous`, `editor_move_down/up`, `select_first/last`, `cancel`, `confirm`, `secondary_confirm`, `confirm_completion`, `confirm_input`, preview toggles, and multi-select. — [Z crates/picker/src/render.rs L159-208](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/render.rs#L159-L208)
- The head is an `ErasedEditor` (Zed's editor behind a factory). The picker subscribes to its events: `BufferEdited` triggers `update_matches(query)`, and `Blurred` triggers `cancel` when the picker draws its own container, the window is active, and no footer or actions menu is focused. That is dismiss-on-blur with an exception for its own popover menus. — [Z crates/picker/src/head.rs](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/head.rs); [Z crates/picker/src/picker.rs L1177-1199](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/picker.rs#L1177-L1199)
- On confirm, the command palette restores focus with `window.focus(&self.previous_focus_handle, cx)`, emits `DismissEvent`, and then calls `window.dispatch_action(action, cx)`, so the action runs against the previously focused view. — [Z command_palette.rs L714-760](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L714-L760)
- In the command palette, ↑ at index 0 (or while already navigating) walks the **query history** instead of the list. This is the `QueryHistory` struct with `history: VecDeque<String>`, `cursor` and `prefix`, plus prefix-filtered recall. — [Z command_palette.rs L224-232, L530-560](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L530-L560)
- IME: GPUI's `InputHandler` trait is documented as "Zed's interface for handling text input from the platform's IME system. This is currently a 1:1 exposure of the NSTextInputClient API". — [zed crates/gpui/src/platform.rs (main) L2236-2240](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/platform.rs)
- Recent IME fixes:
  - PR #64541 ends a pending marked range when the cursor is moved with the mouse. A stale marked range "always won" when resolving edit targets.
  - Issue #64389 reports that `gpui/examples/input.rs` misplaces the composition selection, and that apps copy that example for text fields.
  - Sources: [zed PR #64541](https://github.com/zed-industries/zed/pull/64541); [zed issue #64389](https://github.com/zed-industries/zed/issues/64389)

**Ghostty** — [G .../Command Palette/CommandPalette.swift L186-249](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L186-L249)
- `CommandPaletteQuery` is a `ZStack`. It holds a `Group` of four `Button { onEvent?(.move(...)) } label: { Color.clear }`, each `.buttonStyle(PlainButtonStyle())` with `.keyboardShortcut(.upArrow, modifiers: [])`, `.downArrow`, `"p"+.control` and `"n"+.control`. They are framed `0x0` and `.accessibilityHidden(true)`. The `TextField("Execute a command…")` sits on top of them.
- On the `TextField`: `.onExitCommand { .exit }`, `.onMoveCommand { .move($0) }`, `.onSubmit { .submit }`, `.focused($isTextFieldFocused)`, and `.onChange(of: isTextFieldFocused) { if !focused { onEvent?(.exit) } }`. Losing focus closes the palette.
- Focus grab: `.onAppear { DispatchQueue.main.async { isTextFieldFocused = true } }`, with the comment: "Debug and Release build using Xcode 26.4, has same issue again. Fixes #8497 ... SearchOverlay works magically as expected, I don't know why it's different here, but dispatching to next loop fixes it".
- Issue #8497: on macOS 26 Beta 9, "the command palette doesn't gain initial focus". It was fixed by PR #8591, "grab text field focus of command palette after tick", which says the next-tick dispatch "works at least on Sequoia and Tahoe". It regressed again with Xcode 26.4 SDK builds and was re-fixed in PR #11978 (2026-03-30): "Command palette is not focused when built with Xcode 26.4 (26.3 works fine) ... dispatching it to the next loop works as previously." — [issue #8497](https://github.com/ghostty-org/ghostty/issues/8497); [PR #8591](https://github.com/ghostty-org/ghostty/pull/8591); [PR #11978](https://github.com/ghostty-org/ghostty/pull/11978)
- Responder chain: `ResponderChainInjector`, an `NSViewRepresentable`, creates a dummy `NSView` and sets `dummy.nextResponder = surfaceView` on the next runloop tick. This keeps the terminal surface in the responder chain while the palette has focus, so menu actions still reach it. — [G TerminalCommandPalette.swift L188-200](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift#L188-L200)
- On dismiss, `.onChange(of: isPresented)` calls `DispatchQueue.main.async { surfaceView.window?.makeFirstResponder(surfaceView) }`. The code comment says: "There's probably a better way to handle the first responder state here but I don't know it." — [G TerminalCommandPalette.swift L59-70](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift#L59-L70)
- Selection semantics:
  - `selectedIndex: UInt?` starts `nil`, meaning no selection by default.
  - Typing sets it to 0.
  - Clearing the query while at 0 resets it to `nil`.
  - ↑/↓ wrap around. PR #7175: "This matches both VSCode and Zed."
  - Enter sets `isPresented = false` and then runs `selectedOption?.action()`.
  - Sources: [G CommandPalette.swift L100-141](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L100-L141); [PR #7175](https://github.com/ghostty-org/ghostty/pull/7175)
- Bug: with `focus-follows-mouse = true`, moving the mouse over the palette closed it, because the terminal surface grabbed focus and the text field's focus loss triggered `.exit`. — [issue #9533](https://github.com/ghostty-org/ghostty/issues/9533)
- Bug: GTK users asked for Ctrl-N/Ctrl-P navigation, and macOS already had it through the hidden buttons. — [issue #7918](https://github.com/ghostty-org/ghostty/issues/7918)

**CodeEdit** — [C SearchPanelView.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift)
- `keyHandlers` is a set of `.overlay` buttons with `.opacity(0)`: Escape runs `onClose()`, and ↑/↓ step `selection` through `options.firstIndex(of:)` with no wrap. Each has an `accessibilityLabel` ("Close Overlay", "Select Up", "Select Down").
- Enter is `TextField.onSubmit`. It calls `onRowClick(selection)`, or `NSSound.beep()` when nothing is selected.
- `.task(id: options)` resets the selection to `options.first` whenever results change.
- The table can't take focus: `NonRespondingScrollView` and `NonRespondingTableView` override `acceptsFirstResponder` to return `false`, so the text field keeps focus. `AlwaysActiveTableRowView` overrides `isEmphasized` to always return `true`, so the selection highlight stays accent-colored even though the table isn't first responder. — [C .../OpenQuickly/Views/NSTableViewWrapper.swift L20-26, L78-87](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift)
- Bugs:
  - [#1796](https://github.com/CodeEditApp/CodeEdit/issues/1796): ⌘W still closes the editor tab while Open Quickly or Quick Actions is open, ⌘W also closes the panel, and the tab bar doesn't dim. The workaround is a `panelOpen` flag checked in `closeCurrentTab`.
  - [#1821](https://github.com/CodeEditApp/CodeEdit/issues/1821): Open Quickly doesn't really close, so results and previews stay in memory.
  - [#1792](https://github.com/CodeEditApp/CodeEdit/issues/1792): unselecting an item caused a fatal error.
  - [#1810](https://github.com/CodeEditApp/CodeEdit/issues/1810): the command palette didn't show.

### Inferences
- The invisible `.keyboardShortcut` button trick in Ghostty and CodeEdit works because SwiftUI key equivalents fire through `performKeyEquivalent` before the field editor sees the key. It is also fragile: it depends on the button being in the window's view hierarchy, and on macOS 26 focus timing has needed next-runloop hacks twice.
- An AppKit implementation would normally use `NSTextFieldDelegate.control(_:textView:doCommandBy:)` to intercept `moveUp:`/`moveDown:`/`insertNewline:`/`cancelOperation:`. None of the open-source palettes studied do this. On macOS 14+, `onKeyPress` is the SwiftUI equivalent, and Ghostty doesn't use it either.
- Zed's model scales because bindings are data (keymap JSON with context predicates). Users can rebind palette navigation, and the editor and picker don't fight over keys.

### Gaps
- IME behavior of Ghostty's and CodeEdit's palette fields: I found no issues or code that handles marked text explicitly. They rely on `NSTextField`'s field editor, so composition should work. Whether ↑/↓ or Enter during composition reach the hidden buttons before the input method is untested and undocumented.
- Xcode, Sublime, Nova and Tower keyboard routing internals aren't public. Tower documents → to open an item's action list and ← to go back ([Tower blog](https://www.git-tower.com/blog/inside-quick-actions)).
- Things 3 "Type Travel" opens Quick Find on any printable keystroke, with no ⌘F needed ([Things support](https://culturedcode.com/things/support/articles/2803584/)). How the keystroke is captured isn't documented.

## Q3. List rendering for speed: virtualization, item counts, measured latency

### Takeaway
- **Zed** virtualizes with `gpui::uniform_list`. It measures one item and renders only the visible range, with matches capped at 10,000 for the palette and 100 for the file finder.
- **Ghostty** renders every command eagerly: a plain `ScrollView { VStack { ForEach } }`, not lazy, capped at 200 pt tall. That is fine for about 100 commands.
- **CodeEdit** wraps an `NSTableView` for real row virtualization, but it calls `reloadData()` on every SwiftUI update and creates a fresh `NSHostingView` per row with no reuse.

### Cited Findings
- GPUI `uniform_list` doc: "Rather than use the full taffy layout system, uniform_list simply measures the first element and then lays out all remaining elements in a line based on that measurement. This is much faster than the full layout system, but only works for elements with uniform height." It "will only render the visible subset of items." — [Z crates/gpui/src/elements/uniform_list.rs L1-20](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/gpui/src/elements/uniform_list.rs#L1-L20)
- The Picker passes a closure that is called only with `visible_range: Range<usize>`: `uniform_list("candidates", self.delegate.match_count(), cx.processor(move |picker, visible_range, ...| visible_range.map(|ix| picker.render_element(...)).collect()))`. A variable-height `list(ListState)` exists as an alternative, and docs steer callers to `uniform_list` when rows are uniform. — [Z crates/picker/src/picker.rs L1526-1546, L457-575](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/picker.rs#L1526-L1546)
- Caps: the command palette requests up to `10000` results from `fuzzy_nucleo::match_strings_async`, and the file finder requests `100` from `match_path_sets`. The file finder's history merge also stops at `self.matches.len() == 100`. — [Z command_palette.rs L618-626](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L618-L626); [Z file_finder.rs L664, L1129-1137](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L1129-L1137)
- No empty flash on open: the Picker constructor calls `update_matches("")` and then `finalize_update_matches("", Duration::from_millis(4))`, which blocks the foreground for up to 4 ms waiting for background results. On Enter during a pending search it waits up to `Duration::from_millis(16)`. If that times out, it sets `confirm_on_update` and confirms when the results land. The trait comment says this "avoids a flash of an empty command-palette on cmd-shift-p, and lets workspace::SendKeystrokes mostly work when dismissing a palette." — [Z picker.rs L233-245, L655-658, L1034-1046](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/picker.rs#L233-L245); the command palette implements it with `cx.foreground_executor().block_with_timeout(duration, rx.recv())` ([Z command_palette.rs L669-706](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L669-L706))
- Ghostty `CommandTable` is `ScrollViewReader { ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(Array(options.enumerated()), id: \.1.id) { CommandRow(...) } } } .frame(maxHeight: 200) }`. It scrolls with `proxy.scrollTo(options[selectedIndex].id)` on selection change. Each row is a `Button` with `.onHover` to track hover and `.help()` tooltips. Matched characters are highlighted by building an `AttributedString` per row on every render. — [G CommandPalette.swift L251-414](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L251-L414)
- `CommandOption` gets `let id = UUID()` at creation. `commandOptions` is a computed property in `TerminalCommandPaletteView` that rebuilds every option on each body evaluation, so IDs change every time the view re-evaluates. — [G CommandPalette.swift L3-58](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L3-L58); [G TerminalCommandPalette.swift L73-84](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift#L73-L84)
- CodeEdit `NSTableViewWrapper`:
  - `updateNSView` calls `view.reloadData()` every time, then `selectRowIndexes` and `scrollRowToVisible`.
  - `tableView(_:viewFor:row:)` builds `NSHostingView(rootView: parent.itemView(...))` inside a new `NSTableCellView` each time. It never calls `makeView(withIdentifier:owner:)`, so cells aren't reused.
  - Row heights are fixed: 40 for Open Quickly, 30 for commands.
  - Source: [C NSTableViewWrapper.swift L48-131](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift#L48-L131)
- CodeEdit's `SearchResult` has a custom `==`/`hash` on `fileURL` only. A comment explains: "This custom Hashable implementation prevents the highlighted selection from flickering when searching in 'Open Quickly'", which references PR #1790. — [C OpenQuicklyViewModel.swift L26-42](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/ViewModels/OpenQuicklyViewModel.swift#L26-L42); [PR #1790](https://github.com/CodeEditApp/CodeEdit/pull/1790)
- CodeEdit issue [#1823](https://github.com/CodeEditApp/CodeEdit/issues/1823): "After opening a large monorepo, I thought the Open Quickly feature was broken because it took several seconds to perform a search, and there was no indication that a search was being performed".
- Latency figures from others:
  - Sublime HQ says ST4 stays inside a 16 ms render budget at 60 Hz even at 4K/8K with a low-end GPU ([Sublime Text 4 announcement](https://www.sublimetext.com/blog/articles/sublime-text-4), from search snippet).
  - Nova 7.4 release notes say Open Quickly is "up to 7x faster for large projects" ([Nova 7.4 release notes](https://nova.app/releases/7.4/), from search snippet).
  - Things fixed a bug "that made Quick Find slow to return results" ([9to5Mac, 2019](https://9to5mac.com/2019/12/16/things-quick-find-update/), from search snippet).

### Inferences
- Ghostty's eager `VStack` plus a fresh UUID per option means SwiftUI can't diff rows. Each keystroke rebuilds the whole list. At about 100 to 200 commands this is cheap, but it won't scale to file lists. That is fine for its use case, since session search adds only a few open terminals.
- CodeEdit has the right primitive (`NSTableView`) but defeats it: `reloadData` per update plus a new `NSHostingView` per row costs several hundred microseconds each. Combined with re-enumerating the file system on each query (Q4/Q5), that explains the "several seconds" report.
- Zed's design hits a frame budget because three things combine: uniform-height virtualization, capped result counts, and a short bounded synchronous wait on open and confirm.

### Gaps
- No published end-to-end keystroke-to-pixel latency for Zed's palette, Ghostty's or CodeEdit's. Only matcher microbenchmarks exist (Q4).
- No public numbers for Xcode Open Quickly, Arc's Command Bar, Tower, Craft or BBEdit.

## Q4. Matching and ranking

### Takeaway
- **Zed** has two matchers.
  - The legacy `fuzzy` crate is a memoized recursive DP with a 64-bit `CharBag` prefilter, boundary bonuses (`/`=0.9, `-_ ` digit or camel=0.8, `.`=0.7) and a distance penalty (0.6 base, -0.05 per gap char, floor 0.2).
  - Since March to May 2026, the command palette and file finder use `fuzzy_nucleo`, which wraps Helix's `nucleo` with order-independent multi-word atoms. It keeps the `CharBag` prefilter and turns smart case into a scoring penalty instead of a filter.
  - The command palette ranks previously used commands first, by last-invoked time then invocation count.
- **Ghostty** has no fuzzy matching. It uses a case-insensitive substring match with a fallback to word initials, and ranks by color name match, then title, subtitle and description.
- **CodeEdit** uses a simple sequential-run scorer with ASCII-folding normalization. Its command palette is plain `localizedCaseInsensitiveContains`.
- **Sublime**'s algorithm is known only through Forrest Smith's reverse engineering.
- **Xcode**'s matcher (`IDEOpenQuicklyPattern`) is private, and users reported a quality regression in Xcode 15.

### Cited Findings

**Zed legacy `fuzzy` crate**
- Constants: `BASE_DISTANCE_PENALTY = 0.6`, `ADDITIONAL_DISTANCE_PENALTY = 0.05`, `MIN_DISTANCE_PENALTY = 0.2`. — [Z crates/fuzzy/src/matcher.rs L8-10](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/matcher.rs#L8-L10)
- Per-match char score in `recursive_score_match`:
  - 1.0 when the match is contiguous.
  - After `/` it is 0.9.
  - After `- _ space`, a digit, or at a lower-to-upper camel transition it is 0.8.
  - After `.` it is 0.7.
  - For the first query char otherwise it is 0.6.
  - Otherwise it is `max(0.2, 0.6 - (gap-1)*0.05)`.
  - A case mismatch under smart case, or on `/`, multiplies by `0.001`.
  - With `penalize_length`, the first char's multiplier is divided by the length after the last slash.
  - Results are memoized in `score_matrix[query_idx * path_len + path_idx]`, and best positions are kept for highlight reconstruction.
  - Early exit at score 1.0, and branch-and-bound against `min_score`.
  - Source: [Z matcher.rs L185-320](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/matcher.rs#L185-L320)
- Prefilters:
  - `CharBag(u64)` stores 2-bit saturating counts for a–z, bits 52–61 for digits and bit 62 for `-`, and `is_superset` is a single AND. Candidates whose bag isn't a superset of the query's bag are skipped before any DP.
  - `find_last_positions` then scans right-to-left for each query char's last possible position, which bounds the DP and rejects non-subsequences.
  - Sources: [Z crates/fuzzy/src/char_bag.rs](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/char_bag.rs); [Z matcher.rs L72-133](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/matcher.rs#L72-L133)
- Ordering: `StringMatch` orders by score, then `candidate_id`. Top-N comes from `truncate_to_bottom_n_sorted_by` (partial sort). — [Z crates/fuzzy/src/strings.rs L108-205](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/strings.rs#L108-L205)

**Zed `fuzzy_nucleo` (current matcher for the palette and file finder)**
- Cargo deps: `fuzzy` (for `CharBag`), `nucleo`, `gpui`. — [Z crates/fuzzy_nucleo/Cargo.toml](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy_nucleo/Cargo.toml)
- `Query::build`:
  - Normalizes whitespace and builds `Pattern::new(&normalized, CaseMatching::Ignore, Normalization::Smart, AtomKind::Fuzzy)`. Each whitespace-separated word is a separate atom, which gives order independence.
  - A code comment explains that `CaseMatching::Smart` would "*reject* candidates whose capitalization doesn't match the query, breaking pickers like the command palette (`"Editor: Backspace"` against the action named `"editor: backspace"`)". Smart case is instead applied as a scoring hint, with `SMART_CASE_PENALTY_PER_MISMATCH = 0.9` raised to the power of the number of mismatches.
  - The score is then reduced by a length penalty (`s.len() * LENGTH_PENALTY`).
  - Sources: [Z crates/fuzzy_nucleo/src/fuzzy_nucleo.rs L51-128](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy_nucleo/src/fuzzy_nucleo.rs#L51-L128); [Z crates/fuzzy_nucleo/src/strings.rs L254-290](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy_nucleo/src/strings.rs#L254-L290)
- History:
  - [PR #51164](https://github.com/zed-industries/zed/pull/51164) (merged March 2026) added `fuzzy_nucleo` "for order independent file finder search" and closed #14428.
  - [PR #54112](https://github.com/zed-industries/zed/pull/54112) added the CharBag prefilter.
  - [PR #54123](https://github.com/zed-industries/zed/pull/54123) moved the command palette, tab switcher, branch picker and recent projects to nucleo. Its author said the earlier attempt ([#37123](https://github.com/zed-industries/zed/pull/37123), closed) regressed because of how nucleo filters on case.
- Benchmarks from the PRs:
  - #54112, path matching, nucleo vs legacy fuzzy: 1-word at 10,000 paths takes 1.13 ms vs 1.28 ms. 2-word at 10,000 takes 271 µs vs 53.4 µs, so nucleo is about 5x slower for multi-word, which is the cost of order independence.
  - #54123: string matching for a 1-word query at 1,000 strings takes 150 µs (nucleo) vs 207 µs (fuzzy). The case-penalty workaround adds a roughly constant cost: "a query takes 35 µs instead of 25 µs, but a query that takes 800 µs will only take 820 µs."
  - Sources: [PR #54112](https://github.com/zed-industries/zed/pull/54112); [PR #54123](https://github.com/zed-industries/zed/pull/54123)

**Zed command palette ranking (history)**
- `struct CommandUsage { last_invoked: i64, invocations: u16 }`. It derives `Ord`, so it compares recency first, then count.
- `command_usage()` reads `CommandPaletteDB::list_commands_used()` (SQLite persistence) when the `use_command_history` setting is on. The doc comment: "We only account for commands triggered directly via command palette and not by e.g. keystrokes because if a user already knows a keystroke for a command, they are unlikely to use a command palette to look for it."
- Sources: [Z command_palette.rs L211-222, L390-418](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L390-L418); [Z crates/command_palette/src/persistence.rs](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/persistence.rs)
- In `update_matches`:
  - Commands are sorted by `(Reverse(usage), name)`.
  - Fuzzy matching runs.
  - Then `matches.sort_by_key(|m| if m.candidate_id < used_commands { m.candidate_id } else { usize::MAX })`. This stable sort puts every matching previously used command first, ordered by usage, ahead of all others, and leaves the rest in fuzzy-score order.
  - Command aliases (`settings.command_aliases`) rewrite the query first.
  - Names are humanized (`editor::GoToDefinition` becomes `editor: go to definition`).
  - On confirm, the invocation and query are written in the background with `db.write_command_invocation(command_name, latest_query)`.
  - Sources: [Z command_palette.rs L580-667, L714-760, L867](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L580-L667)
- File finder ranking: recent navigation history (`recent_navigation_history(Some(MAX_RECENT_SELECTIONS))`) and the currently open path are matched separately through `matching_history_items`. `cmp_matches` puts the currently open file last, and history matches are merged with search matches capped at 100. — [Z file_finder.rs L121-165, L574-730](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L574-L730)

**Ghostty** — [G CommandPalette.swift L430-528](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L430-L528)
- `String.matchedIndices(for:)` first tries a substring match with `range(of: query, options: .caseInsensitive)`. Failing that, it matches word initials in order: each query char against the first letter of successive whitespace-split words.
- `CommandOptionMatch` scores two things:
  - `colorScore` (0–1): if the query contains a system color name (`NSColor.colorNames`), the option's tab color is scored by weighted-RGB distance, normalized against a max of 1.5. This supports typing "red" to find red-tagged terminals.
  - `textScore`: 3 for title, 2 for subtitle, 1 for description.
- Results sort by the `(colorScore, textScore)` tuple, which preserves base alphabetical order.
- Base order: update actions first, then `sortedTerminalPaletteOptions`, which sorts with `localizedCaseInsensitiveCompare` after replacing `:` with `\t` "so that "Foo:" sorts before "Foo Bar:"". `sortKey: ObjectIdentifier` breaks ties. — [G TerminalCommandPalette.swift L4-17, L73-84](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift#L4-L17)
- Mitchell in PR #9945 (Session Search, 2025-12): "we don't have fuzzy search capabilities yet ... We should add fuzzy searching in the future." PR #7175: "If and when we introduce most recently used commands, defaulting to that would make sense." No MRU exists today. — [PR #9945](https://github.com/ghostty-org/ghostty/pull/9945); [PR #7175](https://github.com/ghostty-org/ghostty/pull/7175)

**CodeEdit** — [C CodeEdit/Features/Search/FuzzySearch/](https://github.com/CodeEditApp/CodeEdit/tree/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Search/FuzzySearch)
- `FuzzySearchable.fuzzyMatch` walks the candidate's characters, which are lowercased and ASCII-folded through `data(using: .ascii, allowLossyConversion: true)`:
  - On each match the pattern index advances, and a running `currentScore` grows by 1 per consecutive match and is added to `totalScore`. The score is therefore quadratic in run length, which rewards contiguous runs.
  - On a miss, `currentScore` resets to 0.
  - The result counts only if the total matched length equals the query length.
  - There is no separator or camel bonus and no backtracking.
- `Collection.fuzzySearch` uses `concurrentMap` (CollectionConcurrencyKit), filters `weight > 0` and sorts descending.
- Quick Actions (commands) uses `commands.filter { $0.title.localizedCaseInsensitiveContains(val) }`. — [C QuickActionsViewModel.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Commands/ViewModels/QuickActionsViewModel.swift)
- Issue [#1811](https://github.com/CodeEditApp/CodeEdit/issues/1811): "In Xcode, Quick Actions (aka command palette) reflects the menu items. Currently our commands are separate from our menu items."

**Sublime Text (Forrest Smith's reverse engineering)**
- Original 2016 weights: unmatched letter -1, consecutive match +5, separator bonus (after space or underscore) +10, camel bonus +10, unmatched leading letter -3 each with a cap of -9. — [Forrest Smith, "Reverse Engineering Sublime Text's Fuzzy Match"](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)
- The 2017-02-18 update, following feedback from Sublime's Jon Skinner, switched to exhaustive search for the best-scoring alignment. The motivating example is "LLL" against `SVisualLoggerLogsList.h`. — same source
- The current `fts_fuzzy_match.h` "Performs exhaustive search via recursion" with `recursionLimit = 10`. Weights: `sequential_bonus = 15`, `separator_bonus = 30`, `camel_bonus = 30`, `first_letter_bonus = 15`, `leading_letter_penalty = -5`, `max_leading_letter_penalty = -15`, `unmatched_letter_penalty = -1`. — [lib_fts/code/fts_fuzzy_match.h](https://github.com/forrestthewoods/lib_fts/blob/master/code/fts_fuzzy_match.h)
- Performance: 13,164 UE4 filenames in about 5 ms single-threaded on an i5-4670, and 355k words in about 50 ms. Smith says there is no single correct weighting: "I believe there isn't a single correct answer." — [forrestthewoods.com](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)

**objc.io Swift Talk "Quick Open" (Swift reference implementation)**
- Six episodes (S01E211–216, July–August 2020) go from simple fuzzy matching through scoring, complete recursive matching, a recursion-to-matrix (Smith-Waterman-style DP) rewrite, and two performance passes. The last pass runs matching concurrently "to reach 60 frames per second". — [Swift Talk Quick Open collection](https://talk.objc.io/collections/quick-open)
- Blog numbers, about 20k files from the Swift repo:
  - naive: ~400 ms
  - `UTF8View`: ~100 ms
  - byte arrays: ~80 ms
  - cached first-match index: ~45 ms
  - integer indices: ~37 ms
  - parallel chunks (one per core): ~11 ms while screen recording, ~6 ms without
  - about 70k Linux-kernel files: under 16 ms
  - Cited prior art: Forrest Smith, fzf `algo.go`, TextMate `ranker.cc`.
  - Source: [objc.io, "A Fast Fuzzy Search Implementation" (2020-08-18)](https://www.objc.io/blog/2020/08/18/fuzzy-search/)

**Xcode Open Quickly**
- Matching lives in a private IDEKit class, `IDEOpenQuicklyPattern`. Chendo found it with dtrace and reused it in FuzzyAutocompletePlugin for Xcode 5–8. — [chendo, "Reverse engineering Xcode with dtrace"](https://chen.do/reverse-engineering-xcode-with-dtrace/); [FuzzyAutocompletePlugin](https://github.com/FuzzyAutocomplete/FuzzyAutocompletePlugin) (from search snippets)
- Xcode 15 regression reports: queries such as `artidevico` for `XXXArticleDetailViewController` and `XXXUsrMgr` for `XXXUserManager` returned results in Xcode 14 and nothing in 15. No Apple reply is visible. — [Apple Developer Forums thread 733567](https://developer.apple.com/forums/thread/733567)
- Users noticed in Xcode 7.3 that local results no longer rose to the top, which implies ranking weights where a symbol comes from, not just text match quality. — [Apple Developer Forums thread 43550](https://developer.apple.com/forums/thread/43550) (from search snippet)

**Tower, Things**
- Tower Quick Actions "supports fuzzy matching". With an empty input, Quick Open sorts repositories by last opened. The architecture is a general item-type/action description with contextual validation, and supports both "synchronous and asynchronous loading of items". — [Tower, "Inside Quick Actions"](https://www.git-tower.com/blog/inside-quick-actions)
- Things Quick Find searches titles of to-dos, projects, areas, tags and headings first, with "Continue Search" for full text. Version 3.11 (2019) added recents and headings. — [Things support](https://culturedcode.com/things/support/articles/2803584/); [9to5Mac](https://9to5mac.com/2019/12/16/things-quick-find-update/) (from search snippets)

### Inferences
- There are two families. One is subsequence DP with positional bonuses: Sublime/FTS, Zed `fuzzy`, objc.io, fzf. The other is atom-based multi-word matchers like nucleo, which give order independence. Zed's move to nucleo shows users want "vaguely gesture at the command" behavior (PR #54123 author) even at about 5x the cost for multi-word queries.
- Usage-based boosting is the main ranking lever on top of match quality. Zed's version is blunt: any previously used matching command beats any unused one. Tower and Things use recency for empty-query states.
- Ghostty's "substring, then initials" approach is enough for a short command list, and its color-name matching is a domain-specific trick for session search.

### Gaps
- Xcode's actual scoring (IDEOpenQuicklyPattern) has never been publicly reverse-engineered in detail.
- Sublime HQ has never published its algorithm. Smith's is a behavioral reconstruction.
- No information on Arc's Command Bar ranking. It mixes tabs, history and commands, but no source explains how they're ranked. Same for Craft, BBEdit and Nova.

## Q5. Async: background matching, cancellation, debounce

### Takeaway
- **Zed**:
  - Matching runs on GPUI's `BackgroundExecutor`, split into one segment per CPU with `executor.scoped`, and each worker checks a shared `AtomicBool` cancel flag per candidate.
  - The file finder replaces the flag on every search (store `true` into the old flag, allocate a new one), tags searches with a monotonically increasing `search_id`, and drops stale results.
  - It debounces 100 ms only when a search is already in flight.
  - The picker drops the delegate's task synchronously so superseded work stops quickly.
- **CodeEdit**:
  - Open Quickly debounces 200 ms through Combine, then runs a `Task.detached(priority: .userInitiated)` with `runningTask?.cancel()` and `Task.isCancelled` checks.
  - It re-enumerates the whole workspace directory on every query.
- **Ghostty** filters synchronously in the SwiftUI `body`.

### Cited Findings
- `fuzzy::match_strings`:
  - `num_cpus = executor.num_cpus().min(candidates.len())`, `segment_size = div_ceil`, and `executor.scoped(|scope| for each segment scope.spawn(async move { Matcher::new(...).match_candidates(..., cancel_flag, ...) }))`.
  - Afterwards: `if cancel_flag.load(Acquire) { return Vec::new() }`, then concatenate and partial-sort to `max_results`.
  - Inside `match_candidates`, the flag is checked every candidate: `if cancel_flag.load(atomic::Ordering::Acquire) { break; }`.
  - Sources: [Z crates/fuzzy/src/strings.rs L117-200](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/strings.rs#L117-L200); [Z matcher.rs L72-80](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy/src/matcher.rs#L72-L80)
- `fuzzy_nucleo::match_strings_async` has the same structure. It keeps per-CPU `nucleo::Matcher`s (`matcher::get_matchers(num_cpus, config)`) and checks the cancel flag with `Relaxed` ordering in the loop. — [Z crates/fuzzy_nucleo/src/strings.rs L100-160, L242](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/fuzzy_nucleo/src/strings.rs#L100-L160)
- Command palette `update_matches`:
  - Clones `all_commands` and the usage map into `cx.background_spawn`, which sorts, matches and runs interceptors (e.g. `zed://` links, vim `:` commands via `GlobalCommandPaletteInterceptor`).
  - Sends the result over a `postage::dispatch::channel(1)`.
  - A foreground `cx.spawn_in(window, ...)` receives it and calls `matches_updated`.
  - The channel receiver is also stored, so `finalize_update_matches` can block on it with a timeout.
  - Source: [Z command_palette.rs L580-706](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/command_palette/src/command_palette.rs#L580-L706)
- Picker-level cancellation: `PendingUpdateMatches` holds the delegate's task in an `Option` so it "can synchronously drop the task returned by the delegate's `update_matches` method". The comment explains: "If we simply capture the delegate's task into the picker's task, when the picker's task gets synchronously dropped, the delegate's task would keep running until the picker's task has a chance of being scheduled, because dropping a task happens asynchronously." — [Z picker.rs L1230-1270](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/picker/src/picker.rs#L1230-L1270)
- File finder:
  - `spawn_search` does `let search_id = util::post_inc(&mut self.search_count); self.cancel_flag.store(true, Release); self.cancel_flag = Arc::new(AtomicBool::new(false));` and then `fuzzy_nucleo::match_path_sets(..., 100, &cancel_flag, cx.background_executor().clone())`.
  - `set_search_matches` ignores results unless `search_id >= self.latest_search_id`.
  - If the previous search was cancelled and the path query hasn't changed, it extends the old matches instead of replacing them (`extend_old_matches`).
  - Sources: [Z file_finder.rs L1093-1180](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L1093-L1180)
- File finder debounce: `SEARCH_DEBOUNCE = 100 ms` and `WORKTREE_UPDATE_REFRESH_DEBOUNCE = 200 ms`. The timer runs only `if was_in_flight` (`search_in_flight.swap(true)`), so the first keystroke searches immediately. — [Z file_finder.rs L898-899, L1999-2009](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L1999-L2009)
- The file finder works against in-memory worktree snapshots (`worktree.snapshot()` per `PathMatchCandidateSet`), not a fresh disk walk. — [Z file_finder.rs L1106-1122](https://github.com/zed-industries/zed/blob/c403bc6af644cd0ab60c90045ac6dc3436218809/crates/file_finder/src/file_finder.rs#L1106-L1122)
- CodeEdit Open Quickly:
  - `.onReceive(openQuicklyViewModel.$query.debounce(for: 0.2, scheduler: DispatchQueue.main)) { fetchResults() }`.
  - `fetchResults` cancels `runningTask` and starts `Task.detached(priority: .userInitiated)`, which builds `FileManager.default.enumerator(at: fileURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants])` and `allObjects` on every query.
  - It filters `isRegularFile` through `resourceValues`, then runs `fuzzySearch`, `concurrentMap` and `MainActor.run { searchResults = ... }`, with `Task.isCancelled` checks between stages.
  - A leftover `print("Duration: ...")` is still in the code.
  - Sources: [C OpenQuicklyView.swift L57-59](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/OpenQuicklyView.swift#L57-L59); [C OpenQuicklyViewModel.swift L44-90](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/ViewModels/OpenQuicklyViewModel.swift#L44-L90)
- Newer CodeEdit `FuzzySearchUIModel` (2025-08, @MainActor): an `AsyncStream<String>` with `.debounce(for: .milliseconds(50))` feeding `performSearch`. Cancellation is tied to `deinit`. — [C CodeEdit/Features/Search/FuzzySearch/FuzzySearchUIModel.swift](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Search/FuzzySearch/FuzzySearchUIModel.swift)
- CodeEdit Quick Actions also debounces 0.2 s, but its `TextField` binding sets `commandQuery` directly. — [C QuickActionsView.swift L64-66](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Commands/Views/QuickActionsView.swift#L64-L66)
- Ghostty: `filteredOptions` is a computed property evaluated in `body`. There is no debounce, background work or caching. — [G CommandPalette.swift L75-81](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift#L75-L81)

### Inferences
- Zed's async recipe has five parts that transfer to any native palette:
  1. Snapshot candidates on the main thread, and keep them in memory, not on disk.
  2. Fan out across cores with a per-candidate cancel check.
  3. Version results with a monotonic ID.
  4. Debounce only when a search is already running.
  5. Allow a short bounded synchronous wait (4 ms on open, 16 ms on Enter) so the first frame and Enter-before-results behave as if matching were synchronous.
- CodeEdit's fixed 200 ms debounce adds latency to every query. Its per-query filesystem enumeration (instead of a cached index) is probably the main cause of the multi-second searches on monorepos in issue #1823.

### Gaps
- No public detail on async strategy for Xcode, Sublime, Nova (beyond "7x faster" in 7.4), Arc, Things, Tower ("synchronous and asynchronous loading of items", no mechanism given), BBEdit or Craft.

## Q6. Ghostty and CodeEdit: exact source files and known bugs (summary index)

### Takeaway
Ghostty keeps its whole macOS palette in two SwiftUI files mounted in `TerminalView`. CodeEdit splits its palette across an NSPanel class, a shared SwiftUI `SearchPanelView`, an `NSTableView` wrapper, per-feature views and view models, and the controller that presents them. Both projects' issue trackers are dominated by focus and lifecycle bugs, not rendering speed. CodeEdit is the exception: issue #1823 reports slow search on large repos.

### Cited Findings

**Ghostty (`ghostty-org/ghostty`)**
- Palette view, query field, keyboard handling, list and matching: [`macos/Sources/Features/Command Palette/CommandPalette.swift`](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/CommandPalette.swift)
- Overlay wrapper, option assembly, responder-chain injection and focus restore: [`macos/Sources/Features/Command Palette/TerminalCommandPalette.swift`](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Command%20Palette/TerminalCommandPalette.swift)
- Mount point (in-window overlay, no separate panel): [`macos/Sources/Features/Terminal/TerminalView.swift` L110-118](https://github.com/ghostty-org/ghostty/blob/291fd050b9e9c293c8adb6a140742649b7e42d3a/macos/Sources/Features/Terminal/TerminalView.swift#L110-L118)
- Issues and PRs:
  - [#8497](https://github.com/ghostty-org/ghostty/issues/8497), [#8591](https://github.com/ghostty-org/ghostty/pull/8591), [#11978](https://github.com/ghostty-org/ghostty/pull/11978): the field doesn't get initial focus on macOS 26 or with the Xcode 26.4 SDK. Fixed by setting focus on the next runloop tick.
  - [#9533](https://github.com/ghostty-org/ghostty/issues/9533): the palette closed on mouse move with focus-follows-mouse.
  - [#7236](https://github.com/ghostty-org/ghostty/issues/7236) and [#7283](https://github.com/ghostty-org/ghostty/pull/7283): the window title changed while the palette was open. Fixed by moving title logic to AppKit.
  - [#9964](https://github.com/ghostty-org/ghostty/pull/9964): animation removed.
  - [#7175](https://github.com/ghostty-org/ghostty/pull/7175): no default selection, wrapping.
  - [#9945](https://github.com/ghostty-org/ghostty/pull/9945): session search and better sorting, no fuzzy matching yet.
  - [#7174](https://github.com/ghostty-org/ghostty/issues/7174): some binding keys (e.g. arrows) didn't show properly in the palette.

**CodeEdit (`CodeEditApp/CodeEdit`)**
- Window/panel: [`CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/CodeEditUI/Views/SearchPanel.swift)
- Shared palette UI and keyboard handling: [`CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/CodeEditUI/Views/SearchPanelView.swift)
- List: [`CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/NSTableViewWrapper.swift)
- Open Quickly: [`OpenQuicklyView.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/Views/OpenQuicklyView.swift), [`OpenQuicklyViewModel.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/OpenQuickly/ViewModels/OpenQuicklyViewModel.swift), `OpenQuicklyListItemView.swift`, `OpenQuicklyPreviewView.swift`
- Command palette ("Quick Actions"): [`Commands/Views/QuickActionsView.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Commands/Views/QuickActionsView.swift), [`Commands/ViewModels/QuickActionsViewModel.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Commands/ViewModels/QuickActionsViewModel.swift)
- Presentation: `CodeEditWindowController.openQuickly(_:)` and the command-palette toggle in [`Features/Documents/Controllers/CodeEditWindowController.swift`](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Documents/Controllers/CodeEditWindowController.swift)
- Matching: [`Features/Search/FuzzySearch/`](https://github.com/CodeEditApp/CodeEdit/tree/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Search/FuzzySearch) (`FuzzySearchable.swift`, `Collection+FuzzySearch.swift`, `String+Normalise.swift`, `String+LengthOfMatchingPrefix.swift`, `FuzzySearchUIModel.swift`)
- Issues:
  - [#1823](https://github.com/CodeEditApp/CodeEdit/issues/1823): searches take several seconds on a large monorepo, with no progress indicator.
  - [#1821](https://github.com/CodeEditApp/CodeEdit/issues/1821): the panel isn't torn down on close.
  - [#1796](https://github.com/CodeEditApp/CodeEdit/issues/1796): ⌘W leaks through to the editor.
  - [#1792](https://github.com/CodeEditApp/CodeEdit/issues/1792): crash on unselect.
  - [#1810](https://github.com/CodeEditApp/CodeEdit/issues/1810): the palette doesn't show.
  - [#1789](https://github.com/CodeEditApp/CodeEdit/issues/1789) and [PR #1790](https://github.com/CodeEditApp/CodeEdit/pull/1790): highlighting, and selection flicker fixed by a custom Hashable.
  - [#1395](https://github.com/CodeEditApp/CodeEdit/issues/1395): the preview broke after toggling.
  - [#1836](https://github.com/CodeEditApp/CodeEdit/issues/1836): .gitignore not respected.
  - [#1811](https://github.com/CodeEditApp/CodeEdit/issues/1811): commands are separate from menu items.

### Inferences
- In both SwiftUI palettes, most bugs come from the seam between SwiftUI focus state and AppKit's first responder, key window and menu key equivalents, not from SwiftUI rendering. Zed avoids that whole class of bugs by owning the full focus and key-dispatch stack in GPUI.

### Gaps
- Neither project has published latency measurements for its palette.

## Q7. What Arc's team said about building in SwiftUI, and command bar performance

### Takeaway
The only first-party engineering statement I found is about Dia, Arc's successor. In May 2025 Josh Miller said that on Mac they now use AppKit exclusively because any SwiftUI use "consistently regressed performance", and that they avoid state diffing. I found no first-party post about how Arc's Command Bar was built or how it performs.

### Cited Findings
- "We use a modified version of MVVM that retains many ideas from unidirectional data flow architectures, but avoids state diffing for performance reasons." / "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance." / "This new architecture is optimized for cross-platform code sharing". — [Josh Miller on X, May 2025](https://x.com/joshm/status/1927466374781079799), quoted in [Michael Tsai, "Arc and Dia"](https://mjtsai.com/blog/2025/05/30/arc-and-dia/)
- Arc's Command Bar (⌘T) doubles as the URL bar and searches open and archived tabs, extensions and menu commands. — [Michael Tsai, "Command Bars" (comment by Adrian B)](https://mjtsai.com/blog/2022/11/16/command-bars/); feature description from search results, not first-party.
- Arc was sunset in 2025 in favor of Dia, and The Browser Company is now owned by Atlassian. — [Wikipedia: Arc (web browser)](https://en.wikipedia.org/wiki/Arc_(web_browser)) (from search snippet)

### Inferences
- Taken with Ghostty's move of title and focus handling to AppKit (PR #7283) and its next-tick focus hacks, the Dia statement points one way. On macOS, keep the palette's hot path (text field, list, key routing) in AppKit, or in a custom renderer like Zed's. Use SwiftUI, if at all, only for row content, where its cost is bounded.

### Gaps
- No Browser Company blog post, talk or podcast transcript describing the Arc Command Bar's implementation (SwiftUI vs AppKit, window type, matching) turned up in searches. Statements that "Arc is built in SwiftUI" are widely repeated, but I couldn't confirm a primary source within this research budget.
- No Craft engineering detail on its palette was found.
