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

    var isOpen: Bool { window?.isVisible == true }
    /// Whether the window has the keyboard (no banner for the Router then: you are looking at the cards).
    var isKey: Bool { window?.isKeyWindow == true }

    /// Shows the window in front, on `destination` when one is given (else where it was left). `card`: a Router card to pick
    /// (it opens on the Router); `search`: the Router's sidebar search has the keyboard, to find any session.
    func show(_ destination: AppDestination? = nil, card: String? = nil, search: Bool = false) {
        Self.active = self
        settle()
        var destination = destination
        if card != nil || search { destination = .router }
        if let card { routerModel.select(card, store: store) }
        if search { routerModel.searchWanted = true }
        if let destination { navigator.go(destination.resolved(shown: shownIDs, routerOn: store.routerOn)) }
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentViewController == nil { window.contentViewController = makeContent() }
        if !window.isVisible { moveToBarScreen(window) }
        AppPolicy.update(windowOpen: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        watchKeys()
    }

    func close() { window?.performClose(nil) }

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

    /// Opens the window, or closes it when it is open (the keep-open shortcut's job now).
    func toggle(_ destination: AppDestination? = nil) {
        if isOpen { close() } else { show(destination) }
    }

    /// An inbox entry picked and scrolled to, on its category (Done if it was done since): where a banner's click lands.
    func show(entry: InboxEntry) {
        show(entry.isDone ? .done : .category(entry.categoryID))
        hub.selection = "i:" + entry.id
        hub.requestScroll("i:" + entry.id)
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

    private func makeContent() -> NSViewController {
        let root = AppRootView(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                               checksClaudeCode: checksClaudeCode)
        let controller = NSHostingController(rootView: root)
        // The window sizes the content, not the other way round.
        controller.sizingOptions = []
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
        routerModel.composerFocused = false
        // The content goes with the window: no view, nothing ticking behind a closed window.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible != true else { return }
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
    @State private var sidebarShown = true

    static let sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown {
                AppSidebar(store: store, navigator: navigator)
                    .padding(.top, CDS.Sidebar.titleRow)
                    .frame(width: Self.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(CDS.Surface.sidebar)
                    .overlay(alignment: .trailing) { Rectangle().fill(CDS.border).frame(width: CDS.Sidebar.edge) }
                    .transition(.move(edge: .leading))
            }
            AppContent(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                       checksClaudeCode: checksClaudeCode, leadingInset: sidebarShown ? 0 : AppNavButtons.trafficLights)
                .overlay(alignment: .topLeading) {
                    AppNavButtons(navigator: navigator, sidebarShown: $sidebarShown)
                        .padding(.leading, sidebarShown ? 12 : 12 + AppNavButtons.trafficLights)
                        .frame(height: CDS.TitleBar.header)
                }
        }
        .frame(minWidth: 1000, minHeight: 600)
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
