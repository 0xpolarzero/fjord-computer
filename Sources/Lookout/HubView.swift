import AppKit
import Carbon
import SwiftUI

// Lookout as one bar on a screen edge that expands, on hover, into the whole app.

/// `repos` is the inbox's categories page (it was the repositories').
enum HubPage { case main, settings, categories }

/// A tab of the inbox: a category, or Done at the end.
enum InboxTab: Hashable {
    case category(UUID)
    case done
}

@Observable
@MainActor
final class HubState {
    var hovering = false
    var pinned = false {
        didSet {
            // Pinned or unpinned by hand on a page: that's what you want once back, not what it was before.
            if !navigating, page != .main { pinnedBeforePage = nil }
            // Just closed with the pointer still over the bar: no panel pops back open under it.
            if oldValue && !pinned { quiet = true }
        }
    }
    /// No hover panels until the pointer has left the bar (set when the full view closes).
    var quiet = false
    var page: HubPage = .main
    /// "i:<item id>" or "a:<session id>": the row the keys act on.
    var selection: String?
    /// The last row the keyboard (or a click on the inbox) picked: the lists scroll to it. Never set by hovering, so
    /// the pointer moving over a row doesn't move the list.
    var keyboardSelection: ScrollRequest?
    /// The inbox's tab; nil is the first category shown.
    var tab: InboxTab? {
        didSet { selection = nil; keyboardSelection = nil }
    }
    /// Asks the lists to scroll to a row, even one asked for before (a new request every time).
    func requestScroll(_ id: String) {
        keyboardSelection = ScrollRequest(id: id, seq: (keyboardSelection?.seq ?? 0) + 1)
    }
    /// The full view on the inbox, on the tab holding what just arrived: no search or earlier tab hides it.
    func showInbox(_ tab: InboxTab?) {
        go(.main)
        endSearch()
        self.tab = tab
        focus = .inbox
        pinned = true
    }
    /// Asks Settings to scroll to a section (by name), once it is open: where Check for Updates shows what it found.
    var settingsScroll: ScrollRequest?
    /// Opens Settings at its Updates section, also when Settings is open already, scrolled elsewhere.
    func showUpdates() {
        go(.settings)
        settingsScroll = ScrollRequest(id: SettingsView.updatesID, seq: (settingsScroll?.seq ?? 0) + 1)
    }
    @ObservationIgnored var sessionMemo = SessionSearchMemo()
    /// The last search's results (see `Store.hubItems`).
    @ObservationIgnored var searchMemo = SearchMemo()
    var toast: String?
    /// Typed while the hub has the keyboard: narrows the inbox and finds sessions, kept or not.
    var query = ""
    /// The search field is showing: while there is a query, and after ⌫ emptied it (Esc, or leaving the hub, ends it).
    var searchOpen = false
    /// Mirrors the field's focus, for the key handler, which leaves a focused field alone.
    var searchFocused = false
    /// Bumped to ask the field for focus.
    var focusRequest = 0
    /// The next focus is the typing's own: the caret goes after what the field holds, and the key is typed. Any other
    /// focus (a click, Tab) keeps what the field and the pointer decide.
    var caretAtEnd = false
    /// Which way the last page change went, so pages slide in from the side you're heading to.
    var forward = true
    /// The page you came from, so going back retraces your steps (the categories opened from Settings go back
    /// there; opened from the main view, back to it).
    private(set) var previous: HubPage = .main
    /// Whether the view was pinned before a page pinned it: going back to the main view restores that.
    @ObservationIgnored private var pinnedBeforePage: Bool?
    @ObservationIgnored private var navigating = false

    /// The section the pointer is on: just that one opens beside the bar.
    var section: HubSection?
    /// The bar is being carried to another edge: no panels meanwhile.
    @ObservationIgnored var dragging = false
    @ObservationIgnored private var dwell: Task<Void, Never>?

    /// The keys that started the search, for the field to take once it has the keyboard: it types them itself (a dead key,
    /// an input method's first key, a plain letter), as it would have had it been focused.
    @ObservationIgnored var pendingKeys: [NSEvent] = []

    /// Shows the search field and asks it for the keyboard; `replaying`: the key that started it, which the field gets
    /// as if typed in it (after anything already in it).
    func startSearch(replaying event: NSEvent? = nil) {
        searchOpen = true
        caretAtEnd = true
        if let event { pendingKeys.append(event) }
        focusRequest &+= 1
    }

    /// With the field editor up: the caret goes after what the field holds, then the keys that started the search are typed
    /// into it, in order. (A click into the query, or Tab back into it, keeps the selection the field made.)
    func typePendingKeys() {
        // The window the keys were typed in is the one whose field editor gets them.
        guard let editor = (pendingKeys.first?.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView,
              editor.isFieldEditor else { return }
        if caretAtEnd { editor.moveToEndOfDocument(nil) }
        caretAtEnd = false
        let keys = pendingKeys
        pendingKeys = []
        keys.forEach(editor.keyDown(with:))
    }

    /// Clears the query and takes the field away.
    func endSearch() {
        query = ""
        searchOpen = false
        searchFocused = false
        caretAtEnd = false
        pendingKeys = []
    }

    /// Picks a row from the keyboard (or none): the lists follow it.
    func pick(_ target: String?, ui: UIState) {
        selection = target
        if let target { requestScroll(target) } else { keyboardSelection = nil }
        ui.drawerSelection = target.flatMap { $0.hasPrefix("a:") ? String($0.dropFirst(2)) : nil }
    }

    /// The pointer entered a section. The first panel waits for the pointer to settle (so sweeping along the edge
    /// opens nothing); once one is open, moving to another section switches at once, with no transition.
    func enter(_ next: HubSection) {
        dwell?.cancel()
        guard !dragging else { return }
        if section != nil {
            guard section != next else { return }
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            withTransaction(instant) { section = next }
            return
        }
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled, self?.dragging == false { self?.section = next }
        }
    }

    /// The pointer left a section before it settled: nothing opens.
    func cancelDwell() { dwell?.cancel() }

    /// Where that section's panel is (in the hub's window), so the window takes the mouse there too.
    @ObservationIgnored var panelFrame: CGRect = .zero
    /// The panel's frame while one is showing. Not cleared when a panel goes: one closing (still fading out) as the
    /// next opens would clear the new one's frame, leaving the window deaf to the pointer over most of it.
    var openPanelFrame: CGRect? {
        section != nil && !quiet && !expanded && panelFrame != .zero ? panelFrame : nil
    }

    /// The whole view, every section at once: kept open (right ⌘, a page, the context menu).
    var expanded: Bool { pinned }
    /// In the full view, the section given all the room it needs; the others shrink to their header (and counts).
    var focus: HubSection?

    /// Settings and the categories page pin the view, so it stays put while you type or drag; back on the main view,
    /// the pin is what it was before.
    func go(_ next: HubPage) {
        guard next != page else { return }
        forward = next.rank > page.rank
        navigating = true
        defer { navigating = false }
        if page == .main {
            pinnedBeforePage = pinned
            pinned = true
        }
        if next == .main {
            if let before = pinnedBeforePage { pinned = before }
            pinnedBeforePage = nil
        }
        previous = page
        page = next
    }

    /// A page's own step back, set while it has one to take (the category editor's, to the list): Esc and the back
    /// button take it first, and leave the page for good only once it's gone.
    @ObservationIgnored var stepBack: (() -> Bool)?

    /// One step back (Esc, the back button): a page's own step first, then to the page you came from, the main view
    /// in the end.
    func back() {
        if let stepBack, stepBack() { return }
        go(page == .categories && previous == .settings ? .settings : .main)
    }
}

extension HubPage {
    var rank: Int {
        switch self {
        case .main: 0
        case .settings: 1
        case .categories: 2
        }
    }
}

/// The hub's keys, the same in the app and the playground.
@MainActor
final class HubKeys {
    let store: Store
    let ui: UIState
    let hub: HubState
    /// Unpinned and closed from the keyboard (Esc): the app hands focus back.
    var onClose: () -> Void = {}

    init(store: Store, ui: UIState, hub: HubState) {
        self.store = store
        self.ui = ui
        self.hub = hub
    }

    /// Router only switched (or the Router): no focus stays on the sessions that went, and no session they hid stays picked.
    func followSessionsHidden() {
        guard store.sessionsHidden else { return }
        if hub.focus == .agents { hub.focus = nil }
        if hub.section == .agents { hub.section = nil }
        if let selection = hub.selection, selection.hasPrefix("a:"), !targets().contains(selection) {
            hub.selection = nil
            hub.keyboardSelection = nil
        }
        if let id = ui.drawerSelection, !targets().contains("a:" + id) { ui.drawerSelection = nil }
    }

    /// The session switcher's key: kept open on the sessions, the first that needs you picked. In Router only, with no
    /// tiles to pick from, the search takes the keyboard instead: type to find any session, Return opens it.
    func showSessions() {
        guard store.agents.enabled else { return }
        hub.go(.main)
        hub.pinned = true
        if store.sessionsHidden {
            hub.focus = nil
            hub.startSearch()
            return
        }
        if let first = store.sessionShortcutPick { select("a:" + first.id) }
    }

    /// The keep-open key: opens (and keeps open), or closes.
    func toggleTap() {
        if HotKeys.debug { NSLog("Lookout keys: tap, pinned %d", hub.pinned ? 1 : 0) }
        if hub.pinned { close() } else { hub.pinned = true }
    }

    func close() {
        // Closing leaves any page: the hub opens on the main view next time.
        hub.go(.main)
        hub.endSearch()
        hub.keyboardSelection = nil
        hub.pinned = false
        hub.hovering = false
        onClose()
    }

    /// Returns whether the key was handled. Typing in a text field is left alone, except Esc and, in the search field, the
    /// keys that act on the results.
    func key(_ event: NSEvent) -> Bool {
        // An input method is composing in a text field: Esc, the arrows and Return are the composition's.
        if (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let flags = event.modifierFlags.intersection(Shortcut.relevant)
        let shortcut = Shortcut(event)
        if hub.searchFocused, hub.page == .main, let handled = searchKey(event, flags: flags, shortcut: shortcut) { return handled }
        let editing = event.window?.firstResponder is NSText
        // The categories page keeps its own history of edits: ⌘Z undoes, ⇧⌘Z redoes, typing in a field or not. (By the
        // character, as Done's undo is, so it is the Z key on any layout.)
        if hub.page == .categories, flags == .command || flags == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "z", let history = store.categoryHistory {
            if editing { event.window?.makeFirstResponder(nil) }
            if flags == .command { history.undo(store) } else { history.redo(store) }
            return true
        }
        if editing, event.keyCode != UInt16(kVK_Escape) { return false }
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            if editing { event.window?.makeFirstResponder(nil) }
            else if !hub.query.isEmpty || hub.searchOpen { setQuery("") }
            else if hub.page != .main { hub.back() }
            else if hub.focus != nil { withAnimation(LookoutHub.refocus.resolved(reduce: LookoutHub.reduceNow)) { hub.focus = nil } }
            else { close() }
            return true
        }
        // A control the Tab ring is on (Undo, a button, a tab) takes Return and Space itself, not the picked row.
        if flags.isEmpty, event.window?.firstResponder is NSControl,
           [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space].contains(Int(event.keyCode)) { return false }
        if flags == .command, event.charactersIgnoringModifiers == "," {
            hub.go(.settings)
            return true
        }
        if shortcut == store.shortcut(.refresh) { store.refreshNow(); return true }
        guard hub.expanded, hub.page == .main else { return false }
        if jumpToCategory(event, flags: flags) { return true }
        // Typing searches: letters and digits start it, Space and ⌫ edit it once it has started. The key is handed to the
        // field to type (not read here), so a dead key or an input method's first key works as it does in any field.
        if event.keyCode == UInt16(kVK_Delete), flags.isEmpty, !hub.query.isEmpty {
            setQuery(String(hub.query.dropLast()))
            return true
        }
        // What the user bound comes before the typing that starts a search: a letter bound to Mark read marks the picked row
        // read. With nothing picked to act on, or once a search has started, it is a letter like any other.
        if hub.query.isEmpty, isBound(shortcut), markAllRead(shortcut) || rowCommand(shortcut, targets: targets()) { return true }
        if startsSearch(event, flags: flags) {
            // Searching looks everywhere, and the field is in the inbox's header: no section stays expanded without it.
            if hub.focus != nil { withAnimation(LookoutHub.refocus.resolved(reduce: LookoutHub.reduceNow)) { hub.focus = nil } }
            hub.startSearch(replaying: event)
            return true
        }
        let targets = targets()
        if event.keyCode == 125 || event.keyCode == 126, flags.isEmpty {
            move(down: event.keyCode == 125, in: targets)
            return true
        }
        if markAllRead(shortcut) { return true }
        if rowCommand(shortcut, targets: targets) { return true }
        // What no action is bound to: ⌘Z takes back the last Done.
        return flags == .command && event.charactersIgnoringModifiers == "z" && store.undoLast()
    }

    /// Whether the key types something into a field: a printable character (not Space before the first one), or a dead key
    /// (the accent a layout waits to put on the next letter), whose event carries no characters at all.
    private func startsSearch(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        if flags.subtracting(.shift).isEmpty, let typed = Self.printable(event) { return !(typed == " " && hub.query.isEmpty) }
        return flags.isDisjoint(with: [.command, .control]) && isDeadKey(event)
    }

    /// Whether the key is a dead key of the current layout (⌥E on US, ^ on French). Replaceable, as it depends on the keyboard.
    var isDeadKey: (NSEvent) -> Bool = HubKeys.layoutHasDeadKey

    private static func layoutHasDeadKey(_ event: NSEvent) -> Bool {
        guard event.characters?.isEmpty ?? true,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return false }
        let layout = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
        var state: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let modifiers = (Shortcut(event).carbonModifiers >> 8) & 0xFF
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, event.keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                           0, &state, chars.count, &length, &chars)
        }
        return status == noErr && state != 0
    }

    /// What a key types, when it is printable text (not a control character or a function key).
    private static func printable(_ event: NSEvent) -> String? {
        guard let typed = event.characters, !typed.isEmpty,
              typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) else { return nil }
        return typed
    }

    private func move(down: Bool, in targets: [String]) {
        let i = targets.firstIndex(of: hub.selection ?? "") ?? (down ? -1 : targets.count)
        let next = min(max(i + (down ? 1 : -1), 0), targets.count - 1)
        if targets.indices.contains(next) { select(targets[next]) }
    }

    /// The digit row's keys, by key code (the layout's own digits need a modifier on some, AZERTY's among them).
    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                                    kVK_ANSI_9]

    /// ⌃1 to ⌃9: the inbox on the Nth category shown, in the bar's order (Done has no number).
    fileprivate func jumpToCategory(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags == .control, let n = Self.digitKeys.firstIndex(of: Int(event.keyCode)) else { return false }
        let shown = store.shownCategories
        guard shown.indices.contains(n) else { return false }
        withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) {
            hub.endSearch()
            if hub.focus == .agents { hub.focus = nil }
            hub.tab = .category(shown[n].id)
        }
        return true
    }

    private func markAllRead(_ shortcut: Shortcut) -> Bool {
        guard shortcut == store.shortcut(.markAllRead) else { return false }
        withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) { store.markAllSeen(store.hubTab(hub)) }
        return true
    }

    /// What the bound actions do to the row that is picked. False when `shortcut` is none of them, or no row is picked.
    private func rowCommand(_ shortcut: Shortcut, targets: [String]) -> Bool {
        // Only a row that is listed now: one a filter, a search or Router only hides is left alone.
        guard let selection = hub.selection, targets.contains(selection) else { return false }
        let id = String(selection.dropFirst(2))
        if selection.hasPrefix("i:"), let entry = store.entries.first(where: { $0.id == id }) {
            if shortcut == store.shortcut(.openItem) { store.open(entry) }
            else if shortcut == store.shortcut(.toggleRead) { if entry.isUnread { store.markSeen(entry) } }
            else if shortcut == store.shortcut(.discard) {
                let i = targets.firstIndex(of: selection) ?? 0
                if targets.indices.contains(i + 1) { select(targets[i + 1]) }
                withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) { entry.isDone ? store.restore(entry) : store.finish(entry) }
            } else { return false }
            return true
        }
        if selection.hasPrefix("a:") {
            if shortcut == store.shortcut(.openItem) { store.openAgent(id) }
            else if shortcut == store.shortcut(.toggleRead) { store.toggleAgentRead(id) }
            else if shortcut == store.shortcut(.keepSession) { withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) { store.togglePin(id) } }
            else if shortcut == store.shortcut(.removeSession) { withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) { store.dismissAgent(id) } }
            else { return false }
            return true
        }
        return false
    }

    /// Every row the arrows walk through, top to bottom: inbox items, then sessions.
    func targets() -> [String] { store.hubTargets(hub) }

    /// A new search picks its first result, so ↩ opens it straight away.
    private func setQuery(_ query: String) {
        withAnimation(Theme.Motion.fade.resolved(reduce: LookoutHub.reduceNow)) {
            hub.query = query
            // Searching looks everywhere, and what you type shows in the inbox's header: nothing stays shrunk.
            if !query.isEmpty { hub.focus = nil }
            if query.isEmpty { hub.endSearch() }
        }
        // The field takes the keyboard (so the next keys are its own), the caret after what is in it.
        if !query.isEmpty { hub.startSearch() }
        hub.pick(targets().first, ui: ui)
    }

    /// Picks a row from the keyboard: the lists follow it.
    func select(_ target: String) { hub.pick(target, ui: ui) }
}

// MARK: Search field

extension HubKeys {
    /// A key while the search field has focus: Esc clears and ends the search, ↑↓ walk the results, the configured Open
    /// shortcut opens one (so does ↩ or keypad Enter, unless bound to another action), and the row actions, Mark all as read
    /// and ⌘, work as off the search. Everything else (typing, ⌫, Space, ⌘Z) is the field's own: nil leaves the key to it.
    fileprivate func searchKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, shortcut: Shortcut) -> Bool? {
        // Open is the user's to rebind, ⌘O included, which the field would otherwise swallow. A bare letter is typed.
        if shortcut == store.shortcut(.openItem), !typesText(event) { return openResult(shortcut) }
        // So are the chords of the row actions (Keep, Remove, Done, ...), which act on the picked result as they do off the
        // search; the field keeps a chord only when no action is bound to it, or nothing is picked to act on.
        if shortcut.hasCommandLikeModifier, isBound(shortcut), rowCommand(shortcut, targets: targets()) { return true }
        // As do Mark all as read, Check now and Settings, which no text has a use for.
        if !typesText(event), markAllRead(shortcut) { return true }
        if shortcut == store.shortcut(.refresh), shortcut.hasCommandLikeModifier { store.refreshNow(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "," {
            hub.go(.settings)
            return true
        }
        if jumpToCategory(event, flags: flags) { return true }
        guard flags.isEmpty else { return nil }
        switch Int(event.keyCode) {
        case kVK_Escape:
            (event.window ?? NSApp.keyWindow)?.makeFirstResponder(nil)
            setQuery("")
        case kVK_UpArrow, kVK_DownArrow:
            move(down: Int(event.keyCode) == kVK_DownArrow, in: targets())
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // A Return or Enter the user bound to another action does that action; one with no assignment submits the search.
            if shortcut == store.shortcut(.refresh) { store.refreshNow(); return true }
            return openResult(isBound(shortcut) ? shortcut : store.shortcut(.openItem))
        default:
            return nil
        }
        return true
    }

    /// Whether the key is bound to an action that is the hub's own (not a global one).
    private func isBound(_ shortcut: Shortcut) -> Bool {
        ShortcutAction.allCases.contains { !$0.isGlobal && store.shortcut($0) == shortcut }
    }

    /// Does what `shortcut` does to the pick off the search (Open for a key bound to nothing), only if the results still show
    /// it: a row the typing has since filtered out is left alone. nil leaves the key to the field.
    private func openResult(_ shortcut: Shortcut) -> Bool? {
        guard let selection = hub.selection, targets().contains(selection) else { return nil }
        return rowCommand(shortcut, targets: targets()) ? true : nil
    }

    /// Whether a field would put this key in its text: a printable character without ⌃⌥⌘.
    private func typesText(_ event: NSEvent) -> Bool {
        !Shortcut(event).hasCommandLikeModifier && Self.printable(event) != nil
    }
}

/// The bar and, when expanded, everything behind it: each cell of the bar stays beside the content it stands for.
struct LookoutHub: View {
    let store: Store
    let ui: UIState
    @Bindable var hub: HubState
    /// Room the expanded view may take along its edge.
    var maxLength: CGFloat = 700
    /// The window's width: along the top and bottom, the sessions' column takes what the screen has left.
    var maxWidth: CGFloat = .infinity
    /// Where each section's cells are in the bar, and whether the pointer is on the bar or a section's panel.
    @State var sectionFrames: [HubSection: CGRect] = [:]
    @State var overBar = false
    @State var overPanel = false
    @State var peekLeave: Task<Void, Never>?
    /// The bar's size and the open panel's natural size, to place the panel against the bar's ends.
    @State var barSize: CGSize = .zero
    /// On the sides, the open column's height without its filler: what it lacks to be as tall as the bar at rest
    /// (whose sessions take a tile each, where open the new ones share a line) is room given to the inbox.
    @State var openContent: CGFloat = 0
    /// The inbox list's own height as laid out: with the filler, what the open column has left for it.
    @State var inboxListHeight: CGFloat = 0
    @State var inboxMarkHeight: CGFloat = 0
    @State var inboxCellsHeight: CGFloat = 0
    var openFiller: CGFloat {
        // An empty inbox stays one line: no room for nothing.
        guard showsDetail, !edge.isHorizontal, !items.isEmpty, barSize.height > 0, openContent > 0 else { return 0 }
        return max(0, min(barSize.height, maxLength) - openContent)
    }
    @State var peekSizes: [HubSection: CGSize] = [:]
    /// The strip's trailing group (controls, update button) as laid out, for the sessions' segment to leave room
    /// for; a first guess until it's measured.
    @State var stripTrailingWidth: CGFloat = 140
    @Environment(\.accessibilityReduceMotion) var reduce
    /// Opens the Router's window (on a card, from a card's row).
    @Environment(\.openRouter) var openRouter
    @Environment(\.pickRouterCard) var pickRouterCard

    /// The bar's depth: a cell's width on the sides, the strip's height along the top and bottom.
    static let cell = Theme.Metrics.bar
    /// What sits beside a cell on the sides; the inbox and agents columns along the top and bottom.
    static let detail: CGFloat = 400
    /// The one outer inset. Pieces pad their own 8 inside it, so text starts 14pt from the hub's side everywhere.
    static let inset = Theme.Metrics.inset
    /// Along the top and bottom: the CI column, and the narrowest a page gets under the strip.
    static let ciWidth: CGFloat = 300
    static let pageWidth: CGFloat = 480
    /// How many pending sessions the hub lists before the rest stay hidden.
    /// The hub's one coordinate space name (the hosting root's).
    static let rootSpace = "hub-root"
    /// Animations: pass through `.motion` / `.resolved(reduce:)`, which follow Reduce Motion live.
    static let opening = Theme.Motion.spring
    static let closing = Animation.spring(duration: 0.2, bounce: 0)
    static let pageSpring = Theme.Motion.spring
    static let refocus = Animation.spring(duration: 0.34, bounce: 0.06)
    /// The system's current setting, for code with no view (key handlers).
    static var reduceNow: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var edge: DockEdge { ui.edge }
    var expanded: Bool { hub.expanded }
    /// Settings or the categories showing: the bar stays as at rest, dimmed, and the page takes the rows' place.
    var pageOpen: Bool { expanded && hub.page != .main }
    /// The rows' content beside the bar (and the strip's segments at full width).
    var showsDetail: Bool { expanded && hub.page == .main }

    var body: some View {
        let shape = barOutline
        Group {
            if edge.isHorizontal { horizontal } else { vertical }
        }
        .coordinateSpace(.named(Self.barSpace))
        // Only the bar at rest is measured (for the hover panels): nothing to redo while the full view changes.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in if !hub.expanded, barSize != size { barSize = size } }
        .onHover { overBar = $0; hoverChanged() }
        .background(shape.fill(Theme.bg))
        // Claude's panel ring (`shadow-panel`'s inset white 10%) against the desktop.
        .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
        .clipShape(shape)
        // The hovered section's panel, outside the bar's clip; the bar's own size doesn't change.
        .overlay(alignment: peekAlignment) { peekPanel }
        // Shadows come from shapes alone, in a layer under the bar and its panel (never a blurred composite of their
        // content, which would be redone on every frame of anything animating inside): the panel's can't fall
        // across the bar, which is opaque above it.
        .background(alignment: peekAlignment) { peekShadow }
        .background {
            // Claude's `shadow-panel` (its two drops) once open; at rest, only its near one, so the bar sits light.
            let open = expanded || peeking != nil
            shape.fill(Theme.bg)
                .shadow(color: open ? CDS.PanelShadow.far.color : .clear, radius: CDS.PanelShadow.far.radius,
                        y: CDS.PanelShadow.far.y)
                .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y)
        }
        .motion(Theme.Motion.fade, value: peeking != nil)
        .fixedSize()
        // Opening has a touch of bounce; closing doesn't, so it never overshoots back past the bar.
        .motion(expanded ? Self.opening : Self.closing, value: expanded)
        .motion(Self.pageSpring, value: hub.page)
        .motion(Self.refocus, value: hub.focus)
        .contextMenu {
            Toggle("Keep Open", isOn: $hub.pinned)
            if store.routerOn {
                Button("Open Router") { openRouter(nil) }
                Toggle("Router Only", isOn: Binding(get: { store.router.routerOnly }, set: { store.setRouterOnly($0) }))
            }
            Button("Settings…") { hub.go(.settings) }
            Button("Inbox Categories…") { hub.go(.categories) }
            if store.updater.isRelease {
                // Settings' update row says what the check finds (up to date, or why it failed); the bar has no room to.
                Button("Check for Updates") {
                    hub.showUpdates()
                    Task { await store.updater.update(manual: true) }
                }
            }
            Divider()
            Button("Quit Lookout") { NSApp.terminate(nil) }
        }
        .environment(\.colorScheme, .dark)
        .background(SelectionSync(ui: ui, hub: hub))
        // Router only taking the sessions away: their focus and pick go with them.
        .onChange(of: store.sessionsHidden, initial: true) { HubKeys(store: store, ui: ui, hub: hub).followSessionsHidden() }
        .background(UpdateAnnouncer(updater: store.updater))
    }

    // MARK: Data

    var items: [InboxEntry] { store.hubEntries(hub) }
    var searching: Bool { !hub.query.isEmpty }
    /// What the inbox list animates on: its entries changing, or the tab or search swapping them.
    struct ListKey: Equatable { let revision: Int; let tab: InboxTab; let query: String }
    var listKey: ListKey { ListKey(revision: store.inboxRevision, tab: store.hubTab(hub), query: hub.query) }
    /// The list's identity: a different tab or a search is a different list (it cross-fades).
    var listID: String {
        guard !searching else { return "search" }
        switch store.hubTab(hub) {
        case .done: return "done"
        case .category(let id): return id.uuidString
        }
    }
    /// The sessions by group; searching, one untitled group of the matches.
    var agentSections: [AgentSection] {
        if searching {
            let rows = store.hubSessions(hub)
            return rows.isEmpty ? [] : [AgentSection(group: .pinned, rows: rows)]
        }
        return store.agentSections
    }

    /// Over a group's sessions: its name and count (none when searching: the matches are one list).
    func groupLabel(_ section: AgentSection, twoLines: Bool) -> some View {
        IslandGroupLabel(title: section.group.title, count: section.rows.count)
            .padding(.leading, twoLines ? CDS.Sidebar.labelInset : 8)
    }

    /// Sessions that need a look get their detail under the title beside the bar, and the room for it.
    func slotHeight(_ r: AgentRow) -> CGFloat {
        r.group.rawValue < AgentGroup.pinned.rawValue && !searching ? Self.tallSlot : Theme.Metrics.row
    }
    static let tallSlot: CGFloat = Theme.Metrics.row + 14
    /// The line above a group beside the bar (the first group's sits under the asterisk).
    static let groupLine: CGFloat = 16

    // MARK: Vertical (left / right edges)

    /// The screen's side: rows line up against it, so the bar column is straight whatever is beside it.
    var side: HorizontalAlignment { edge == .right ? .trailing : .leading }
    /// A row's width: its cell, and its content beside it when that shows.
    var rowWidth: CGFloat { showsDetail ? Self.cell + Self.detail : Self.cell }

    var vertical: some View {
        // The page slides out from under the bar column, which stays where it is.
        HStack(alignment: .top, spacing: 0) {
            if edge == .right && pageOpen { verticalPage }
            barColumn.zIndex(1)
            if edge == .left && pageOpen { verticalPage }
        }
    }

    var verticalPage: some View {
        page
            .frame(width: Self.detail)
            .modifier(FitHeight(cap: maxLength))
            // (Reduce Motion: no slide, but still a short fade.)
            .transition(reduce ? .opacity.animation(Theme.Motion.fade) : .slide(from: edge == .right ? .trailing : .leading, reduce: false))
    }

    /// The rows: the bar's cells on the screen side, their content beside them. With a page open, the same cells
    /// as at rest, dimmed, and settings lit at the bottom.
    var barColumn: some View {
        VStack(alignment: side, spacing: 0) {
            VStack(alignment: side, spacing: 0) { mainRows }
                .opacity(pageOpen ? 0.5 : 1)
            // Last, the controls: a gear at rest (hover for pin, repositories, settings), settings and the
            // footer once open. In the full view, dragging the line above them sizes the sessions' list.
            sectionDivider
            VStack(alignment: side, spacing: 0) {
                row(cell: { Group { if expanded { settingsCell.padding(.vertical, 5) } else { controlsCell.padding(.vertical, 9) } } },
                    detail: { footerDetail })
            }
            .modifier(probe(.controls))
        }
        // Opaque, so the page sliding out from under it doesn't show through.
        .background(Theme.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            let content = height - openFiller
            if showsDetail, abs(openContent - content) > 0.5 { openContent = content }
        }
    }

    /// Beside the settings cell: on the left edge, the same pieces mirrored, so pin and repositories sit by
    /// the bar on either side and the sync status out by the rounded side.
    @ViewBuilder var footerDetail: some View {
        if edge == .left {
            HStack(spacing: 9) {
                reposButton
                pinButton
                Spacer(minLength: 0)
                syncStatus
            }
            .frame(height: Self.footerHeight)
        } else {
            footer
        }
    }

    /// One line of the expanded view: the bar's cell on the screen side, its content beside it. The cell always
    /// takes its width, empty or not, so content lines up whether or not its row has something in the bar.
    @ViewBuilder
    func row<Cell: View, Detail: View>(alignment: VerticalAlignment = .center, @ViewBuilder cell: () -> Cell,
                                       @ViewBuilder detail: () -> Detail) -> some View {
        let slot = ZStack {
            Color.clear.frame(width: Self.cell, height: 0)
            cell()
        }
        .frame(width: Self.cell)
        HStack(alignment: alignment, spacing: 0) {
            if edge == .left { slot }
            if showsDetail {
                detail()
                    // The one outer inset, against the rounded side; the bar's cells sit on the other.
                    .padding(edge == .right ? .leading : .trailing, Self.inset)
                    .frame(width: Self.detail, alignment: .leading)
                    .transition(.hubReveal)
            }
            if edge == .right { slot }
        }
    }

    @ViewBuilder var mainRows: some View {
        // Inbox: the GitHub mark and the tabs; under them the categories' cells in the bar, the list beside them.
        VStack(alignment: side, spacing: 0) {
            // Top-aligned, so the icon stays where it is at rest whatever the header beside it takes.
            row(alignment: .top, cell: {
                inboxIcon.padding(.top, 2).padding(.bottom, 2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inboxMarkHeight = $0 }
            },
                detail: { inboxHeader.padding(.top, 6) })
            ZStack(alignment: Alignment(horizontal: side, vertical: .top)) {
                if showsDetail && !shrunk(.inbox) {
                    VStack(alignment: side, spacing: 0) {
                        row(cell: { EmptyView() }, detail: { undoLine })
                        if items.isEmpty {
                            row(cell: { EmptyView() }, detail: { emptyInbox })
                        }
                        CappedScroll(cap: max(caps.inbox, openFiller + inboxListHeight), hub: hub, lazy: AdaptiveStack<EmptyView>.isLazy(items.count)) {
                            AdaptiveStack(count: items.count, alignment: side, spacing: 1) {
                                ForEach(items) { entry in
                                    row(cell: { EmptyView() }, detail: { itemRow(entry) }).capEdge().id("i:" + entry.id)
                                }
                            }
                            .padding(.bottom, 4)
                            .id(listID)
                            .transition(.opacity)
                            .motion(Theme.Motion.fade, value: listKey)
                        }
                        // Its own width, so a scroller can't widen it and push its rows off the bar's column.
                        .frame(width: Self.cell + Self.detail)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inboxListHeight = $0 }
                        if openFiller > 0 { Color.clear.frame(width: Self.cell + Self.detail, height: openFiller) }
                    }
                    .transition(.hubReveal)
                }
                VStack(spacing: 0) { categoryCells }.frame(width: Self.cell)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inboxCellsHeight = $0 }
            }
            .frame(width: rowWidth, alignment: Alignment(horizontal: side, vertical: .top))
        }
        // The inbox is one group: the mark and its categories share one well, apart from the Router and the sessions.
        .background(alignment: Alignment(horizontal: side, vertical: .top)) {
            if !store.shownCategories.isEmpty {
                RoundedRectangle(cornerRadius: CDS.Tile.radius + 4, style: .continuous)
                    .fill(CDS.Fill.ghostSelected)
                    .frame(width: Self.cell - 8, height: inboxMarkHeight + inboxCellsHeight + 2)
                    .frame(width: Self.cell)
                    .padding(.top, 1)
            }
        }
        .modifier(probe(.inbox))
        // The Router, just before the sessions it works on: its cell and counts; kept open, what is running too.
        if store.routerOn {
            sectionDivider.padding(.vertical, 6)
            VStack(alignment: side, spacing: 0) {
                row(cell: { routerCell }, detail: { routerHeader })
                if showsDetail && !shrunk(.router) {
                    Group {
                        // Router only: what works, where the sessions' rows would be (it says what the status line would).
                        if store.sessionsHidden {
                            row(cell: { EmptyView() }, detail: { routerWorking.padding(.bottom, 4) })
                        } else {
                            row(cell: { EmptyView() }, detail: { routerStatusRow })
                        }
                    }
                    .transition(.hubReveal)
                }
            }
            .modifier(probe(.router))
            .opacity(searching ? 0.4 : 1)
        }
        if showsSessions {
            sectionDivider
            VStack(alignment: side, spacing: 0) { agentRowsView }
                .modifier(probe(.agents))
        }
        if store.updater.showsInPill {
            row(cell: { UpdateButton(updater: store.updater, horizontal: false).padding(.vertical, 4) },
                detail: {
                    HStack(spacing: 4) {
                        Text(updateText).font(Theme.Typography.control).foregroundStyle(Theme.secondary)
                        Spacer(minLength: 0)
                        UpdateMenu(updater: store.updater)
                    }
                    .padding(.horizontal, 8)
                })
                .transition(.scaleFade(0.8, reduce: reduce))
        }
    }

    @ViewBuilder var agentRowsView: some View {
        row(cell: { claudeMark }, detail: { agentsHeader })
        if showsDetail { row(cell: { EmptyView() }, detail: { ClaudeNotice(store: store).padding(.horizontal, Theme.Space.md) }) }
        if showsDetail && shrunk(.agents) {
            EmptyView()
        } else if showsDetail {
            Group {
                // The sessions scroll with their tiles, so each stays beside its row.
                CappedScroll(cap: caps.agents, hub: hub) { sessionRows }
                    .frame(width: Self.cell + Self.detail)
                // With the Router on, it starts sessions (with their first message): no second way here.
                if !store.routerOn { row(cell: { newSessionCell }, detail: { newSessionDetail }) }
            }
            .transition(.hubReveal)
        } else {
            sessionRows
        }
    }

    @ViewBuilder var sessionRows: some View {
        let sections = agentSections
        VStack(alignment: side, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.group) { i, section in
                if !searching {
                    row(cell: { groupMark(first: i == 0) },
                        detail: { groupLabel(section, twoLines: false) })
                        .frame(height: Self.groupLine)
                }
                ForEach(section.rows) { r in
                    // Its first line level with the tile; what it did, or what it left running, under it.
                    row(alignment: .top, cell: { tile(r, size: 26).frame(height: showsDetail ? nil : slotHeight(r)) },
                        detail: { sessionBlock(r, twoLines: false) })
                        .modifier(ReorderIf(enabled: showsDetail && section.group == .pinned, row: r, store: store))
                        .capEdge()
                        .id("a:" + r.id)
                }
            }
        }
    }

    /// Between groups on the bar, a short line; over the first, nothing.
    func groupMark(first: Bool) -> some View {
        Rectangle().fill(first ? .clear : CDS.border).frame(width: 12, height: 1).frame(height: Self.groupLine)
    }

    /// Heights the two lists may scroll within: what's left once the fixed parts are laid out, inbox first.
    /// With a section focused, it takes everything the shrunk sections' headers leave.
    var caps: (inbox: CGFloat, agents: CGFloat) {
        switch hub.focus {
        case .inbox: (max(160, maxLength - 260), 0)
        case .agents: (0, max(144, maxLength - 260))
        default: sharedCaps
        }
    }

    /// No section focused: what's left once the fixed parts are laid out, inbox first.
    var sharedCaps: (inbox: CGFloat, agents: CGFloat) {
        let free = max(160, maxLength - 340)
        guard showsSessions else { return (free, 0) }
        // Whole 36pt session rows, so the last one showing is never cut through its tile.
        let agents = max(2, (free * 0.45 / 36).rounded(.down)) * 36
        return (free - agents, agents)
    }

    /// Across the whole view when expanded; a short rule centred in the bar at rest.
    var sectionDivider: some View {
        IslandRule()
            .frame(width: showsDetail ? Self.cell + Self.detail : Self.cell - 24)
            .frame(width: rowWidth)
            .padding(.vertical, 4)
    }

    // MARK: Horizontal (top / bottom edges)

    var horizontal: some View {
        // The strip and what's under it share one width, so the strip's trailing group sits at the far end.
        SharedWidthStack {
            if edge == .bottom { horizontalBody }
            HStack(alignment: .center, spacing: 0) { strip }
                .frame(height: Self.cell)
                .zIndex(1)
            if edge == .top { horizontalBody }
        }
    }

    /// The bar along the top or bottom: each segment as wide as the column under it once expanded; with a page
    /// open, back to their size at rest, dimmed.
    @ViewBuilder var strip: some View {
        let wide = showsDetail
        Group {
            HStack(spacing: wide ? 8 : 0) {
                inboxIcon
                if wide && !shrunk(.inbox) {
                    inboxHeader.transition(.hubReveal)
                } else if wide {
                    Spacer(minLength: 0)
                    focusButton(.inbox)
                } else {
                    // At rest: the categories' cells beside the mark.
                    HStack(spacing: 0) { categoryCells }
                }
            }
            .background {
                if !wide && !store.shownCategories.isEmpty {
                    RoundedRectangle(cornerRadius: CDS.Tile.radius + 4, style: .continuous).fill(CDS.Fill.ghostSelected)
                        .padding(.vertical, 5).padding(.horizontal, -3)
                }
            }
            .padding(.leading, Self.inset + 1)
            .padding(.trailing, Self.inset)
            .frame(width: wide ? columnWidth(.inbox) : nil, alignment: .leading)
            .frame(maxHeight: .infinity)
            .modifier(probe(.inbox))
            if store.routerOn {
                stripDivider.padding(.horizontal, 6)
                HStack(spacing: 8) {
                    routerCell
                    // On a narrow screen, only the cell: its column under the strip goes too (the window has the cards).
                    if wide && routerHasColumn { routerHeader.transition(.hubReveal) }
                }
                .padding(.leading, Self.inset + 1)
                .padding(.trailing, Self.inset)
                .frame(width: wide ? columnWidth(.router) : nil, alignment: .leading)
                .frame(maxHeight: .infinity)
                // The whole segment opens the window, not only its cell.
                .contentShape(Rectangle())
                .onTapGesture { openRouter(nil) }
                .modifier(probe(.router))
                .opacity(searching ? 0.4 : 1)
            }
            if showsSessions {
                stripDivider
                HStack(spacing: 8) {
                    claudeMark
                    if wide {
                        agentsHeader.transition(.hubReveal)
                    } else {
                        // (At rest: the tiles.)
                        ForEach(Array(agentSections.enumerated()), id: \.element.group) { i, section in
                            if i > 0 { Rectangle().fill(CDS.border).frame(width: 1, height: 12) }
                            ForEach(section.rows) { tile($0, size: 26) }
                        }
                    }
                }
                // The asterisk over the column's session tiles (inset, the row's 10, half a 24pt tile).
                .padding(.leading, Self.inset + 10 + 12 - 15)
                .padding(.trailing, Self.inset)
                .frame(width: wide ? columnWidth(.agents) : nil, alignment: .leading)
                .frame(maxHeight: .infinity)
                .modifier(probe(.agents))
            }
        }
        .opacity(pageOpen ? 0.5 : 1)
        if !expanded {
            stripDivider
            controlsCell
                .padding(.horizontal, Self.inset)
                .frame(maxHeight: .infinity)
                .modifier(probe(.controls))
        }
        if expanded { Spacer(minLength: 0) }
        HStack(spacing: 0) {
            if expanded {
                // The rate limit shows here whatever's focused (the sync status itself is in the controls' panel).
                RateNotice(store: store, fill: false).lineLimit(1).padding(.trailing, Self.inset)
                stripDivider
                // Claude's chrome buttons: 24 squares, 4 apart.
                HStack(spacing: 4) {
                    pinButton
                    reposButton
                    settingsCell
                }
                .padding(.horizontal, Self.inset + 2)
                .transition(.hubReveal)
            }
            if store.updater.showsInPill {
                stripDivider
                HStack(spacing: 0) {
                    UpdateButton(updater: store.updater, horizontal: true)
                    UpdateMenu(updater: store.updater)
                }
                .padding(.horizontal, 6)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if expanded, stripTrailingWidth != width { stripTrailingWidth = width }
        }
    }

    var updateText: String {
        let version = store.updater.release?.version ?? ""
        return switch store.updater.phase {
        case .ready: "Lookout \(version) is ready · click to restart into it"
        case .downloading: "Downloading Lookout \(version)…"
        case .installing: "Installing…"
        case .failed(let error): "Update failed · \(error)"
        default: "Lookout \(version) is available"
        }
    }

    var stripDivider: some View {
        IslandRule(axis: .vertical).frame(height: 16)
    }

    @ViewBuilder var horizontalBody: some View {
        if expanded {
            Group {
                if hub.page == .main {
                    // GitHub on the left (the inbox, CI under it), the sessions on the right; a focused section has
                    // the whole width to itself. The strip above keeps its segments whatever's focused.
                    VStack(spacing: 0) {
                        if let focus = hub.focus {
                            // The strip's width, never its text's.
                            focusedBody(focus).frame(minWidth: Self.ciWidth, idealWidth: Self.ciWidth, maxWidth: .infinity, alignment: .topLeading)
                        } else {
                            HStack(alignment: .top, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    inboxColumn
                                    Spacer(minLength: 0)
                                }
                                .frame(width: Self.githubWidth, alignment: .topLeading)
                                .frame(maxHeight: .infinity, alignment: .top)
                                if store.routerOn {
                                    columnDivider
                                    Group {
                                        if routerHasColumn { routerColumn } else { Color.clear }
                                    }
                                    .frame(width: columnWidth(.router), alignment: .topLeading)
                                    .opacity(searching ? 0.4 : 1)
                                }
                                if showsSessions {
                                    columnDivider
                                    // As wide as its segment (with the controls after it), whatever its text would like.
                                    agentsColumn.frame(minWidth: columnWidth(.agents), idealWidth: columnWidth(.agents),
                                                       maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                            // As tall as the taller side, so the sessions' column reaches the bottom (its new
                            // session row with it).
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity.animation(Theme.Motion.fade.delay(0.1)),
                                            removal: .opacity.animation(Theme.Motion.hover)))
                } else {
                    page
                        .modifier(FitHeight(cap: maxLength - Self.cell))
                        .frame(idealWidth: Self.pageWidth, maxWidth: .infinity)
                        // Settles toward the strip as it fades in.
                        .transition(reduce ? .opacity.animation(Theme.Motion.fade)
                                    : .opacity.combined(with: .offset(y: edge == .top ? -8 : 8)))
                }
            }
            .overlay(alignment: edge == .top ? .top : .bottom) { IslandRule() }
            .transition(.hubReveal)
        }
    }

    var columnDivider: some View {
        IslandRule(axis: .vertical, inset: 12)
    }

    /// The inbox's list along the top and bottom.
    var inboxColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            undoLine.padding(.horizontal, Self.inset - Theme.Space.md)
            inboxList
        }
    }

    private var inboxList: some View {
        CappedScroll(cap: max(160, min(maxLength - Self.cell - 60, Self.listCap)), hub: hub, lazy: AdaptiveStack<EmptyView>.isLazy(items.count)) {
            AdaptiveStack(count: items.count, spacing: 1) {
                if items.isEmpty { emptyInbox }
                ForEach(items) { itemRow($0).id("i:" + $0.id) }
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 8)
            .id(listID)
            .transition(.opacity)
            .motion(Theme.Motion.fade, value: listKey)
        }
    }

    /// The sessions along the top and bottom: one per line, read top to bottom like the inbox beside them.
    var agentsColumn: some View {
        let sections = agentSections
        let count = sections.reduce(0) { $0 + $1.rows.count }
        return VStack(alignment: .leading, spacing: 0) {
            // Directly under the Sessions header (in the strip above).
            ClaudeNotice(store: store).padding(.horizontal, Self.inset + 8)
            CappedScroll(cap: min(maxLength - Self.cell - 60, Self.listCap + 90), hub: hub, lazy: AdaptiveStack<EmptyView>.isLazy(count)) {
                // By group: what needs you first, then what's done, working, pinned; the recent ones.
                AdaptiveStack(count: count, alignment: .leading, spacing: 0) {
                    agentGroupList(sections)
                }
                .padding(.horizontal, Self.inset)
                .padding(.top, 8)
            }
            // At the bottom, whatever height the column gets; a line keeps a row the list cuts off from running into
            // the new session row.
            Spacer(minLength: 0)
            if !store.routerOn {
                IslandRule(inset: Self.inset + 10).padding(.bottom, Theme.Space.xs)
                NewSessionRow(store: store, style: .twoLines)
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, Self.newSessionBlock - Theme.Space.xs - 44)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Along the top and bottom, under the line above the new session row: the row (44) and the air around it.
    static let newSessionBlock: CGFloat = Theme.Space.xs + 44 + 8

    func twoLineRow(_ r: AgentRow) -> some View {
        sessionBlock(r, twoLines: true).capEdge().id("a:" + r.id)
    }

    /// Along the top and bottom: each group under its label, a row per session with its tile.
    @ViewBuilder func agentGroupList(_ sections: [AgentSection]) -> some View {
        ForEach(sections) { section in
            if !searching {
                // Claude's group label: 12 above (less the rows' own air), 4 below.
                groupLabel(section, twoLines: true).padding(.top, 8).padding(.bottom, 4)
            }
            ForEach(section.rows) { r in
                twoLineRow(r).modifier(ReorderIf(enabled: section.group == .pinned && !searching, row: r, store: store))
            }
        }
    }

    /// A line between one project's sessions and the next's.
    var groupDivider: some View {
        IslandRule(inset: 10).padding(.vertical, Theme.Space.xs)
    }

    // MARK: Focus

    /// Shrunk to its header because another section is focused (in the full view only).
    func shrunk(_ section: HubSection) -> Bool {
        showsDetail && hub.focus != nil && hub.focus != section
    }

    /// Along the top and bottom, the strip's segments: the inbox's spans the GitHub column under it; the sessions' (with
    /// the controls after it) spans theirs.
    func columnWidth(_ section: HubSection) -> CGFloat {
        switch section {
        case .inbox: return Self.githubWidth
        case .router:
            guard routerHasColumn else { return Self.routerCompact }
            guard !showsSessions else { return Self.routerWidth }
            // Router only: the room the sessions' column had, up to a side column's width.
            let room = maxWidth - Self.githubWidth - 1 - 1 - stripTrailingWidth - 2 * Self.inset
            return max(Self.routerWidth, min(Self.detail, room))
        default:
            // As much as the screen has left after the measured controls and update button, and the margins (and the
            // Router's segment, when it has one: next to its bare cell, the sessions make do with a little less).
            let router = store.routerOn ? columnWidth(.router) + 1 : 0
            let least = store.routerOn && !routerHasColumn ? Self.agentsMin - Self.routerCompact - 1 : Self.agentsMin
            let room = maxWidth - Self.githubWidth - 1 - router - stripTrailingWidth - 2 * Self.inset
            return max(least, min(Self.detail, room))
        }
    }

    /// Along the top and bottom, whether the screen has room for the Router's column beside the sessions' narrowest.
    var routerHasColumn: Bool {
        Self.routerColumnFits(maxWidth: maxWidth, trailing: stripTrailingWidth, sessions: showsSessions)
    }

    /// `sessions`: the sessions' column is beside it (not in Router only).
    static func routerColumnFits(maxWidth: CGFloat, trailing: CGFloat, sessions: Bool = true) -> Bool {
        maxWidth >= githubWidth + 1 + routerWidth + (sessions ? 1 + agentsMin : 0) + trailing + 2 * inset
    }

    /// The sessions' section (tiles, rows, column): there with the extension on, except in Router only, where a search
    /// still brings the sessions it finds.
    var showsSessions: Bool { store.agents.enabled && (!store.sessionsHidden || searching) }

    static let githubWidth: CGFloat = 570
    /// Along the top and bottom, the Router's segment and the column under it.
    static let routerWidth: CGFloat = 260
    /// Its segment with no column: the bare cell, padded like the others.
    static let routerCompact: CGFloat = Theme.Metrics.line + 2 * Theme.Metrics.inset + 1
    /// The narrowest the sessions' column gets.
    static let agentsMin: CGFloat = 260
    /// Along the top and bottom, the lists scroll past this, so the view stays compact.
    static let listCap: CGFloat = 300

    /// Along the top and bottom, a focused section across the whole width: the inbox in two columns.
    @ViewBuilder func focusedBody(_ section: HubSection) -> some View {
        switch section {
        case .inbox:
            VStack(alignment: .leading, spacing: 0) {
                undoLine.padding(.horizontal, Self.inset - Theme.Space.md)
                CappedScroll(cap: maxLength - Self.cell - 16, hub: hub, lazy: true) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.sm, alignment: .top), GridItem(.flexible(), spacing: Theme.Space.sm, alignment: .top)],
                              alignment: .leading, spacing: 1) {
                        ForEach(items) { itemRow($0).id("i:" + $0.id) }
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 8)
                }
                .overlay(alignment: .topLeading) { if items.isEmpty { emptyInbox.padding(Self.inset) } }
            }
        default:
            agentsColumn
        }
    }


    /// A section header's button: give this section all the room (the others shrink to their header), or back.
    func focusButton(_ section: HubSection) -> some View {
        let focused = hub.focus == section
        return IconButton(symbol: focused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          help: focused ? "Back to all sections" : "Make room for this",
                          detail: focused ? "Esc" : "The other sections shrink to their counts",
                          size: IconButton.Size.header) {
            withAnimation(Self.refocus.resolved(reduce: reduce)) { hub.focus = focused ? nil : section }
        }
    }

    /// A session in the full view (see `SessionBlock`).
    func sessionBlock(_ r: AgentRow, twoLines: Bool) -> some View {
        SessionBlock(row: r, twoLines: twoLines, store: store, ui: ui, hub: hub)
    }
}

/// Stacks its views top to bottom, all as wide as the widest: along the top and bottom, the strip spans whatever
/// is under it (columns or a page) and the columns span the strip.
struct SharedWidthStack: Layout {
    /// What's been measured this pass: the widest's width, and every subview's height at one width.
    struct Cache {
        var width: CGFloat?
        var heightsAt: CGFloat?
        var heights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func width(_ subviews: Subviews, _ cache: inout Cache) -> CGFloat {
        if let width = cache.width { return width }
        let width = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        cache.width = width
        return width
    }

    private func heights(_ subviews: Subviews, at width: CGFloat, _ cache: inout Cache) -> [CGFloat] {
        if cache.heightsAt == width { return cache.heights }
        cache.heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        cache.heightsAt = width
        return cache.heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = width(subviews, &cache)
        return CGSize(width: width, height: heights(subviews, at: width, &cache).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for (sub, height) in zip(subviews, heights(subviews, at: bounds.width, &cache)) {
            sub.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height
        }
    }
}

/// As tall as its content, up to `cap`; a scroll view inside scrolls past that.
struct FitHeight: ViewModifier {
    let cap: CGFloat

    func body(content: Content) -> some View {
        CapHeightLayout(cap: cap) { content }
    }
}

private struct CapHeightLayout: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sub = subviews.first else { return .zero }
        let width = proposal.width ?? sub.sizeThatFits(.unspecified).width
        let height = sub.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: min(height, cap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}


/// Your sessions in the hub can be dragged onto one another to reorder them (pending ones can't).
struct AgentReorder: ViewModifier {
    let row: AgentRow
    let store: Store
    @State private var target = false

    func body(content: Content) -> some View {
        content
            .modifier(Reorderable(row: row, store: store, dropTarget: $target))
            .overlay(Theme.Radius.shape(Theme.Radius.md).strokeBorder(target ? Theme.accent : .clear, lineWidth: 1.5))
    }
}

/// Under the Sessions header: Claude's session files missing or unreadable (nothing when all is well).
struct ClaudeNotice: View {
    let store: Store

    var body: some View {
        switch store.claudeLink {
        case .missing, .unreadable:
            HStack(spacing: 6) { ClaudeLinkStatus(store: store) }
                // One element for VoiceOver: what is wrong, said as shown.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(store.claudeLink == .missing ? "Claude's sessions not found" : "Can't read Claude's sessions")
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.xs)
        default:
            EmptyView()
        }
    }
}

/// Beside the sync status, on every edge: the GitHub rate limit running low (nothing otherwise).
struct RateNotice: View {
    let store: Store
    /// Takes the whole line (its text at the leading edge); off, only the room it needs.
    var fill = true

    var body: some View {
        RateLimitWarning(store: store)
            .font(Theme.Typography.meta)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
    }
}

// MARK: Island pieces (Claude's frame: dots, dividers, group labels)

/// Claude's sidebar status dot (spec §1.7): 6pt; needs you amber, done blue, working muted and blinking, quiet a hollow
/// ring. CI's states use the same dot: failing danger, running clay, passing git green.
struct IslandDot: View {
    enum Kind: Equatable {
        case awaiting, ready, running, idle
        case custom(Color)

        static func ci(_ state: CIState) -> Kind {
            switch state {
            case .failure: .custom(CDS.Text.danger)
            case .pending: .custom(CDS.clay)
            case .success: .custom(CDS.Git.added)
            case .none: .idle
            }
        }
    }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var low = false

    var body: some View {
        Group {
            switch kind {
            case .awaiting: Circle().fill(CDS.Dot.awaiting)
            case .ready: Circle().fill(CDS.Dot.ready)
            case .custom(let color): Circle().fill(color)
            case .idle:
                Circle().strokeBorder(CDS.Dot.running, lineWidth: CDS.Dot.ringWidth).opacity(CDS.Dot.ringOpacity)
            case .running:
                Circle().fill(CDS.Dot.running)
                    .opacity(reduce ? CDS.Dot.still : low ? CDS.Dot.blinkLow : 1)
                    .onAppear { blink() }
                    .onChange(of: reduce) { blink() }
            }
        }
        .frame(width: CDS.Dot.size, height: CDS.Dot.size)
        .accessibilityHidden(true)
    }

    /// `dframe-dot-blink`: .3 → 1 → .3, ease-in-out, 1.2 s a cycle.
    private func blink() {
        guard !reduce else { low = false; return }
        low = false
        withAnimation(.easeInOut(duration: CDS.Dot.blink / 2).repeatForever(autoreverses: true)) { low = true }
    }
}

/// Claude's divider: `--cds-border` (white 10%) at 0.5pt. `inset` trims both ends.
struct IslandRule: View {
    var axis: Axis = .horizontal
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CDS.border)
            .frame(width: axis == .vertical ? CDS.hairline : nil, height: axis == .horizontal ? CDS.hairline : nil)
            .padding(axis == .horizontal ? .horizontal : .vertical, inset)
    }
}

/// Claude's sidebar group label (spec §2.6): 12/16 in muted, as written (no capitals), then its count in the neutral xs
/// Badge (§2.5).
struct IslandGroupLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: CDS.Sidebar.rowGap) {
            Text(title)
                .font(CDS.sans(CDS.Sidebar.groupFont))
                .foregroundStyle(CDS.Text.muted)
                .lineLimit(1)
            if let count { IslandCountPill(count: count) }
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .combine)
    }
}

/// The CDS Badge, neutral, xs: a count beside a label.
struct IslandCountPill: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Text("\(count)")
            .font(CDS.sans(CDS.Badge.font, .medium))
            .monospacedDigit()
            .foregroundStyle(CDS.Badge.ink)
            .padding(.horizontal, CDS.Badge.padX)
            .frame(minWidth: CDS.Badge.height, minHeight: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(CDS.Badge.fill))
            .contentTransition(reduce ? .opacity : .numericText(value: Double(count)))
    }
}
