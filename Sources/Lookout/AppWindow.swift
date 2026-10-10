import AppKit
import SwiftUI

// Lookout as a window: everything the bar holds, with the bar's items as a navigation sidebar. The other mode is the bar
// docked on a screen edge; whoever switches between them calls `show` and listens to `onClose`.

/// How the app is present on the system. An accessory app has no Dock icon and no menu bar; while the app window is open
/// Lookout is a regular app (Dock icon, ⌘-Tab, menu bar).
@MainActor
enum AppPolicy {
    /// Regular while `windowOpen`, else accessory (the bar only).
    static func update(windowOpen: Bool) {
        let policy: NSApplication.ActivationPolicy = windowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
}

@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    /// The window the Go menu acts on: the last one made.
    static weak var active: AppWindowController?
    static let autosave = "LookoutApp"
    static let minSize = NSSize(width: 1000, height: 600)

    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    /// Called once the window has closed (by the user or `close()`): the place to put the bar back on its edge.
    var onClose: (() -> Void)?
    /// The screen the bar is docked on: the window opens there. Nil (or no answer) is the main screen.
    var barScreen: () -> NSScreen? = { nil }
    /// Where the bar is, to morph out of when the window opens and into when it closes. Nil: no morph.
    var bar: () -> BarMorph? = { nil }
    /// The window starts closing (its morph is under way): the bar may fade back in now. `onClose` follows.
    var onClosing: (() -> Void)?
    /// The window came to the front, or went out of sight (another app in front, minimized, covered): the bar is away
    /// while the window is in front, and back on its edge otherwise.
    var onFront: ((Bool) -> Void)?
    private var lastFront: Bool?
    private var observers: [NSObjectProtocol] = []
    /// What a morph in progress is, so a new `show` or `close` can take it over.
    private(set) var run: AppTransition.Run?
    private var generation = 0

    /// Where the window is in its morph. The bar's presence is not told of the window's comings and goings meanwhile (the
    /// window is out of sight on purpose), and is told what they came to once it is over.
    enum Phase { case idle, opening, closing }
    private(set) var phase = Phase.idle
    private(set) var window: NSWindow?
    private let checksClaudeCode: Bool
    /// The rows' picked state, Settings' scroll requests and the category editor's step back, shared by the destinations.
    let hub = HubState()
    private lazy var keys = RouterKeys(store: store, model: routerModel) { [weak self] in self?.close() }
    /// The inbox's search, and the keys of the inbox destinations (see `AppWindowKeys`).
    let search = InboxSearch()
    private(set) lazy var inboxKeys = AppWindowKeys(store: store, navigator: navigator, hub: hub, search: search) { [weak self] in
        self?.close()
    }
    private var monitor: Any?

    /// `routerModel`: the Router's chat state, shared with whatever else shows the Router. `remembers`: open on the place left
    /// last (off for shots and tests).
    init(store: Store, routerModel: RouterModel? = nil, remembers: Bool = true, checksClaudeCode: Bool = true) {
        self.store = store
        self.routerModel = routerModel ?? RouterModel()
        self.checksClaudeCode = checksClaudeCode
        navigator = AppNavigator(fallback: .category(store.tabNeedingYou.categoryID ?? UUID()),
                                 defaults: remembers ? .standard : nil)
        super.init()
        Self.active = self
        settle()
    }

    /// Open, or on its way in (its morph plays before the window itself is in); one on its way out is closed already (a
    /// toggle opens it again).
    var isOpen: Bool { phase == .opening || (phase != .closing && window?.isVisible == true) }
    /// The window's content, kept while the window is closed: out of the window it stands still (no body runs, no clock,
    /// timeline or animation ticks, its tasks are cancelled), and back in it picks up where it was, its scroll positions and
    /// the rest of its state kept, its appearing (`onAppear`, `.task`, `onChange(initial:)`) run again as on a first open.
    private var content: NSViewController?
    /// The window's picture at its last close: the next opening starts on it (see `startOpening`).
    private var closedPicture: AppTransition.Picture?
    /// An opening whose window is still to be brought in: its generation.
    private var pending: Int?
    /// A fresh picture the overlay of an opening still needs, and whether it fades in over the one shown. Taken once the
    /// window has the keyboard (its buttons as they will be when it takes over), else just before it does.
    private var owed: (generation: Int, crossFade: Bool)?
    private var keyWatch: NSObjectProtocol?
    /// Whether the window has the keyboard, or is about to (no banner for the Router then: you are looking at the cards).
    var isKey: Bool { window?.isKeyWindow == true || pending != nil }

    /// Shows the window in front, on `destination` when one is given (else where it was left). `card`: a Router card to pick
    /// (it opens on the Router).
    func show(_ destination: AppDestination? = nil, card: String? = nil) {
        Self.active = self
        settle()
        let shown = navigator.selection
        var destination = destination
        if card != nil { destination = .router }
        if let card { routerModel.select(card, store: store) }
        if let destination { navigator.go(destination.resolved(shown: shownIDs, routerOn: store.routerOn)) }
        let window = self.window ?? makeWindow()
        self.window = window
        // A window on its way out comes back from where it is; one on its way in just goes on.
        let reversing = phase == .closing && run != nil
        let arriving = phase == .opening
        let opening = !arriving && (reversing || !window.isVisible) && !window.isMiniaturized && AppTransition.enabled
        if !window.isVisible && !reversing && !arriving { moveToBarScreen(window) }
        // The bar as it is now, before whoever called us hides it.
        let morph = opening && !reversing && !AppTransition.reduceMotion ? bar() : nil
        if opening {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            startOpening(window, bar: morph, reversing: reversing)
        } else {
            // One on its way in with its window still to come gets it then.
            if pending == nil { bringIn(window) }
            // On its way in to another place now: the overlay shows that one.
            if arriving, navigator.selection != shown { contentChanged() }
        }
        // A card picked on the way in (a close turned round included): the place may be the same, what it shows is not.
        if card != nil, reversing || arriving { contentChanged() }
        watchKeys()
        watchFront()
        reportFront()
    }

    /// What shows the window: its content (built once, kept across closes), the app regular and active, the window in front
    /// with the keyboard. The heavy part of an opening, which waits until its morph is on screen.
    private func bringIn(_ window: NSWindow) {
        if window.contentViewController == nil {
            // The window takes its content's size: kept content is given the window's as it is now (it may have been fitted
            // to a smaller screen since), new content is made at it.
            let size = window.contentRect(forFrameRect: window.frame).size
            let content = self.content ?? makeContent(size: size)
            if content.view.frame.size != size { content.view.setFrameSize(size) }
            self.content = content
            window.contentViewController = content
        }
        AppPolicy.update(windowOpen: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window opens: the overlay grows out of the bar's cell (or picks up from where a close had got to) while the real
    /// window waits at its frame, invisible; then the real window takes over under the overlay. The motion comes first: the
    /// overlay starts on the picture kept from the last close (or the window's bare surface) and is on screen before the
    /// window is built and brought in, a turn later, which gives it a fresh picture.
    private func startOpening(_ window: NSWindow, bar: BarMorph?, reversing: Bool) {
        phase = .opening
        generation += 1
        let mine = generation
        let current: AppTransition.Run?
        let kept = closedPicture.flatMap { $0.fits(window) ? $0 : nil }
        if reversing, let run {
            current = run
        } else {
            run?.end()
            current = AppTransition.makeRun(for: window, image: kept?.image, bar: bar)
        }
        run = current
        guard let current else {
            bringIn(window)
            reveal(window)
            finishOpening(mine)
            return
        }
        // No picture yet, or another place's: the fresh one fades in over it. A close turned round keeps the picture it
        // took, of the window as it still is, unless it now goes to another place.
        let place = reversing ? closedPicture?.destination : kept?.destination
        let other = place != navigator.selection
        pending = mine
        let stale = !reversing || other || !current.imageIsKey
        owed = stale ? (generation: mine, crossFade: other || (!reversing && kept == nil)) : nil
        current.open(reduced: AppTransition.reduceMotion || current.bar == nil) { [weak self, weak window] in
            guard let self, let window, self.generation == mine else { return }
            // The real window must be in, and the overlay show it as it is now, before it takes over: whatever has not
            // happened yet happens now (the picture as the window is, key or not, since that is what will be seen).
            self.bringInPending(mine)
            if self.owed != nil {
                self.owed = nil
                self.stopKeyWatch()
                current.refresh(window)
            }
            current.handoff(reveal: { self.reveal(window) }, finished: { self.finishOpening(mine) })
        }
        // The motion is on screen: the rest waits a turn.
        AppTransition.nextTurn { [weak self] in self?.bringInPending(mine) }
    }

    /// The window of the opening `mine` brought in, if it is not yet.
    private func bringInPending(_ mine: Int) {
        guard pending == mine, generation == mine, phase == .opening, let window else { return }
        pending = nil
        bringIn(window)
        payPicture(mine)
    }

    /// The fresh picture the opening `mine` needs, once its window is in and has the keyboard (the app becomes active a
    /// little after it is asked to: the picture waits for it, rather than being taken twice).
    private func payPicture(_ mine: Int) {
        guard let owed, owed.generation == mine, generation == mine, pending == nil, let window, let run else { return }
        guard AppTransition.isKey(window) else {
            guard keyWatch == nil else { return }
            keyWatch = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopKeyWatch()
                    self?.payPicture(mine)
                }
            }
            return
        }
        self.owed = nil
        stopKeyWatch()
        run.refresh(window, crossFade: owed.crossFade)
    }

    /// What an opening's window shows changed after its overlay's picture was taken (another place, a card, a row or a
    /// section asked for): a fresh one fades in over it, a turn later (once the change has been drawn), at the latest as
    /// the real window takes over.
    private func contentChanged() {
        guard phase == .opening, run != nil else { return }
        let mine = generation
        owed = (mine, crossFade: true)
        AppTransition.nextTurn { [weak self] in self?.payPicture(mine) }
    }

    private func stopKeyWatch() {
        if let keyWatch { NotificationCenter.default.removeObserver(keyWatch) }
        keyWatch = nil
    }

    /// The real window, shown (under the overlay), with the keyboard.
    private func reveal(_ window: NSWindow) {
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }

    private func finishOpening(_ mine: Int) {
        guard generation == mine else { return }
        stopKeyWatch()
        run = nil
        phase = .idle
        // Used: the next close takes another.
        closedPicture = nil
        reportFront()
    }

    func close() {
        // An opening whose window is not in yet: in now, so there is a window to close.
        if let pending { bringInPending(pending) }
        window?.performClose(nil)
    }

    /// Closing morphs the window into the bar: an overlay takes the window's place first, then the real window goes and the
    /// overlay shrinks into the bar's cell, then it really closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AppTransition.enabled, phase != .closing, phase == .opening || isFront else { return phase != .closing }
        // An opening whose overlay has let go of its picture shows the real window already: it closes as an open one does.
        let interrupting = phase == .opening && run?.handedOver != true
        phase = .closing
        generation += 1
        let mine = generation
        pending = nil
        owed = nil
        stopKeyWatch()
        sender.ignoresMouseEvents = true
        let existing = interrupting ? run : nil
        let current: AppTransition.Run?
        if let existing {
            current = existing
        } else {
            run?.end()
            current = AppTransition.makeRun(for: sender, bar: AppTransition.reduceMotion ? nil : bar())
        }
        guard let current else {
            finishClosing(sender, mine)
            return false
        }
        run = current
        // Kept for the next opening to start on, when it was taken with the window key.
        if let image = current.image, current.imageIsKey {
            closedPicture = AppTransition.Picture(image: image, frame: sender.frame, scale: sender.backingScaleFactor,
                                                  destination: navigator.selection)
        }
        let start = { [weak self, weak sender] in
            guard let self, let sender, self.generation == mine else { return }
            sender.orderOut(nil)
            self.onClosing?()
            current.close(reduced: AppTransition.reduceMotion || current.bar == nil) { [weak self, weak sender] in
                guard let self, let sender, self.generation == mine else { return }
                self.finishClosing(sender, mine)
            }
        }
        if interrupting {
            start()
        } else {
            // The overlay shows the window before the real one goes: no frame without either.
            current.present()
            AppTransition.nextFrame(sender.screen, start)
        }
        return false
    }

    private func finishClosing(_ window: NSWindow, _ mine: Int) {
        guard generation == mine else { return }
        run?.end()
        run = nil
        phase = .idle
        window.orderOut(nil)
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.close()
    }

    /// Whether the window is in front of the user: the app is active and the window is on screen and not covered.
    var isFront: Bool { isFront(active: NSApp.isActive) }

    func isFront(active: Bool) -> Bool {
        guard active, let window, window.isVisible, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }

    /// Tells `onFront` when that changes. `active` is passed by the notifications that know it before `NSApp` does.
    func reportFront(active: Bool = NSApp.isActive) {
        guard phase == .idle else { return }
        let front = isFront(active: active)
        guard front != lastFront else { return }
        lastFront = front
        onFront?(front)
    }

    private func watchFront() {
        guard observers.isEmpty, let window else { return }
        let center = NotificationCenter.default
        func watch(_ name: Notification.Name, object: AnyObject?, active: Bool? = nil) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let active { self?.reportFront(active: active) } else { self?.reportFront() }
                }
            })
        }
        watch(NSApplication.didResignActiveNotification, object: nil, active: false)
        watch(NSApplication.didBecomeActiveNotification, object: nil, active: true)
        watch(NSWindow.didChangeOcclusionStateNotification, object: window)
        watch(NSWindow.didMiniaturizeNotification, object: window)
        watch(NSWindow.didDeminiaturizeNotification, object: window)
    }

    /// Opening puts the window on the bar's screen, where it was left if that is the one, else at the same place relative
    /// to the screen it was on.
    private func moveToBarScreen(_ window: NSWindow) {
        guard let target = barScreen() ?? NSScreen.main else { return }
        let screens = NSScreen.screens
        let previous = screens.max { overlap(window.frame, $0.visibleFrame) < overlap(window.frame, $1.visibleFrame) }
        let from = previous.flatMap { overlap(window.frame, $0.visibleFrame) > 0 ? $0.visibleFrame : nil }
        let frame = AppWindowPlacement.frame(window.frame, from: from, in: target.visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: false) }
    }

    private func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Settings, scrolled to Updates: where Check for Updates shows what it found. The request is the window's own, so it
    /// reaches the Settings page shown here whether it opens now or was open already.
    func showUpdates() {
        show(.settings)
        hub.showUpdates()
        contentChanged()
    }

    /// An inbox entry picked and scrolled to, on its category (Done if it was done since): where a banner's click lands.
    func show(entry: InboxEntry) {
        show(entry.isDone ? .done : .category(entry.categoryID))
        hub.selection = "i:" + entry.id
        hub.requestScroll("i:" + entry.id)
        contentChanged()
    }

    /// The Go menu's destinations with their titles, in the sidebar's order.
    var goItems: [GoMenuModel.Item] {
        GoMenuModel.items(AppDestination.all(shown: shownIDs, routerOn: store.routerOn)) { title(for: $0) }
    }

    func title(for destination: AppDestination) -> String {
        switch destination {
        case .category(let id): store.categories.first { $0.id == id }?.title ?? "Inbox"
        case .done: "Done"
        case .router: "Router"
        case .settings: "Settings"
        case .categories: "Inbox categories"
        }
    }

    private var shownIDs: [UUID] { store.shownCategories.map(\.id) }

    /// Keeps the selection on a place that exists.
    private func settle() { navigator.settle(shown: shownIDs, routerOn: store.routerOn) }

    /// `size`: the window's content size, so that setting the content keeps the window as it is (left alone, the content
    /// would size it to its own minimum, too small to see).
    private func makeContent(size: NSSize) -> NSViewController {
        let root = AppRootView(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                               checksClaudeCode: checksClaudeCode)
        let controller = NSHostingController(rootView: root)
        // The window sizes the content, not the other way round.
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: size)
        return controller
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 1180, height: 760)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        Self.style(window)
        window.delegate = self
        if !window.setFrameUsingName(Self.autosave) { window.center() }
        window.setFrameAutosaveName(Self.autosave)
        return window
    }

    /// The window's look: dark like the bar's panels, the content running up under a transparent unified title bar.
    static func style(_ window: NSWindow) {
        window.title = "Lookout"
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(CDS.Surface.s1)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.allowsToolTipsWhenApplicationIsInactive = true
    }

    /// The Router's keys (see `RouterKeys`) while the window is key and shows the Router; Esc dismisses a tooltip first.
    private func watchKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                guard let window = self.window, window.isKeyWindow, event.window === window,
                      !self.store.isRecordingShortcut else { return false }
                if TipCenter.dismissVisible(for: event) { return true }
                return self.navigator.selection == .router ? self.keys.key(event) : self.inboxKeys.key(event)
            }
            return consumed ? nil : event
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        lastFront = nil
        routerModel.composerFocused = false
        // The content leaves the window, which stops it: nothing ticking behind a closed window. It is kept for the next open.
        // Not if the window was opened again meanwhile (on its way in, it is not visible yet): it stays open, and the bar
        // is not told otherwise.
        let closed = generation
        AppTransition.nextTurn { [weak self] in
            guard let self, self.generation == closed, self.phase == .idle, self.pending == nil,
                  self.window?.isVisible != true else { return }
            self.window?.contentViewController = nil
            AppPolicy.update(windowOpen: false)
            self.onClose?()
        }
    }
}

/// Where the window goes when it opens on a screen.
enum AppWindowPlacement {
    /// `frame` on the screen whose usable area is `visible`. Kept (inside the screen) when its centre is already there;
    /// else the same relative place as on `from` (the area of the screen it was on), centred when that is unknown. Never
    /// larger than the screen.
    static func frame(_ frame: NSRect, from: NSRect?, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        var center = NSPoint(x: frame.midX, y: frame.midY)
        if !visible.contains(center) {
            if let from, from.width > 0, from.height > 0 {
                center = NSPoint(x: visible.minX + (center.x - from.minX) / from.width * visible.width,
                                 y: visible.minY + (center.y - from.minY) / from.height * visible.height)
            } else {
                center = NSPoint(x: visible.midX, y: visible.midY)
            }
        }
        let x = min(max(center.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

private extension InboxTab {
    var categoryID: UUID? {
        if case .category(let id) = self { return id }
        return nil
    }
}

/// The window's root: the sidebar and the destination side by side, as Claude's Code tab lays them out (a split view
/// would draw the system's floating sidebar). The window's buttons sit over the sidebar's top; the sidebar toggle, back and
/// forward over the content's.
struct AppRootView: View {
    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    let hub: HubState
    var search = InboxSearch()
    var checksClaudeCode = true
    var sidebar: SidebarState = .shared

    static let sidebarWidth: CGFloat = 240

    var body: some View {
        let collapsed = sidebar.collapsed
        // The rail is narrower than the window's three buttons; the content starts after what sticks out. It follows the
        // sidebar's width on the same spring (an implicit animation here would end up fighting the explicit one).
        let railInset = collapsed ? max(0, AppNavButtons.trafficLights - AppSidebar.railWidth) : 0
        HStack(spacing: 0) {
            AppSidebar(store: store, navigator: navigator, hub: hub, collapsed: collapsed)
                .padding(.top, CDS.Sidebar.titleRow)
                .frame(width: collapsed ? AppSidebar.railWidth : Self.sidebarWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .clipped()
                .background(CDS.Surface.sidebar)
                .overlay(alignment: .trailing) { Rectangle().fill(CDS.border).frame(width: CDS.Sidebar.edge) }
            AppContent(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                       checksClaudeCode: checksClaudeCode, leadingInset: railInset)
                .overlay(alignment: .topLeading) {
                    AppNavButtons(navigator: navigator,
                                  sidebarShown: Binding(get: { !sidebar.collapsed }, set: { sidebar.set(collapsed: !$0) }))
                        .padding(.leading, 12 + railInset)
                        .frame(height: CDS.TitleBar.header)
                }
        }
        .frame(minWidth: 640, minHeight: 600)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .tipSpace()
        .ignoresSafeArea(.container, edges: .top)
        .background(CDS.Surface.s1)
        .onChange(of: store.shownCategories.map(\.id)) { _, shown in navigator.settle(shown: shown, routerOn: store.routerOn) }
        // Another place has its own pick and search; a row asked for there (a banner's click) stays.
        .onChange(of: navigator.selection) { _, place in
            search.end()
            if let pick = hub.selection, let tab = place.tab, store.entries(in: tab).contains(where: { "i:" + $0.id == pick }) { return }
            hub.selection = nil
            hub.keyboardSelection = nil
        }
        .onChange(of: store.routerOn) { _, on in navigator.settle(shown: store.shownCategories.map(\.id), routerOn: on) }
        .environment(\.openRouter) { card in
            if let card { routerModel.select(card, store: store) }
            navigator.go(.router)
        }
        .environment(\.pickRouterCard) { card in routerModel.select(card, store: store) }
        // Chips in the window's own lists: a place, or the Router on the message an action left in its conversation.
        .environment(\.openApp) { navigator.go($0.resolved(shown: store.shownCategories.map(\.id), routerOn: store.routerOn)) }
        .environment(\.openRouterMessage) { message in
            routerModel.show(message: message)
            navigator.go(.router)
        }
        .environment(\.openChange) { change in
            switch change.target(in: store) {
            case .category(let id): navigator.go(.categories); hub.openCategory(id)
            case .group(let id): navigator.go(.categories); hub.openGroup(id)
            case .categories: navigator.go(.categories)
            case .settings(let section):
                navigator.go(.settings)
                hub.settingsScroll = ScrollRequest(id: section, seq: (hub.settingsScroll?.seq ?? 0) + 1)
            case .entry(let thing, let category, let isDone):
                navigator.go(isDone ? .done : (category.map { .category($0) } ?? .done))
                hub.selection = "i:" + thing
                hub.requestScroll("i:" + thing)
            }
        }
    }
}

/// Sidebar toggle, back and forward: Claude's 26pt ghost icon buttons, 4 apart.
struct AppNavButtons: View {
    let navigator: AppNavigator
    @Binding var sidebarShown: Bool
    /// Room the window's three buttons take at the content's start when the sidebar is away.
    static let trafficLights: CGFloat = 70
    /// What the three buttons take, with the gaps.
    static let width: CGFloat = 3 * CDS.TitleBar.button + 2 * CDS.TitleBar.buttonGap

    var body: some View {
        HStack(spacing: CDS.TitleBar.buttonGap) {
            AppIconButton(symbol: "sidebar.left", help: sidebarShown ? "Hide sidebar" : "Show sidebar", enabled: true) {
                withAnimation(.easeOut(duration: 0.18)) { sidebarShown.toggle() }
            }
            AppIconButton(symbol: "chevron.left", help: "Back · ⌘[", enabled: navigator.canGoBack) { navigator.back() }
            AppIconButton(symbol: "chevron.right", help: "Forward · ⌘]", enabled: navigator.canGoForward) { navigator.forward() }
        }
    }
}

struct AppIconButton: View {
    let symbol: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(!enabled ? CDS.Text.disabled : hovered ? Color.white : CDS.Text.secondary)
                .frame(width: CDS.TitleBar.button, height: CDS.TitleBar.button)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered && enabled ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityLabel(help)
        .help(help)
    }
}
