import AppKit
import Observation
import SwiftUI

/// Where the hub sits in its window, and what the controller needs to know about it.
@Observable
@MainActor
final class HubLayout {
    /// Docked: the window spans the edge and the hub is placed along it. Floating: the window is exactly the bar
    /// (while it's dragged to another edge).
    var floating = false
    /// The bar's length along its edge: the bar keeps its start where it was whatever its peek takes.
    var restLength: CGFloat = 0
    /// The bar's size, to carry exactly that when it's dragged.
    @ObservationIgnored var restSize: CGSize = .zero
    /// The hub's frame in the window (top-left origin).
    @ObservationIgnored var frame: CGRect = .zero {
        didSet { if frame != oldValue { onFrame?() } }
    }
    @ObservationIgnored var onFrame: (() -> Void)?
}

/// A transparent window over the bar at rest. The real window lets the mouse through everywhere until the pointer
/// is on the hub; this one's tracking area is how that's noticed without a system-wide mouse monitor.
private final class HoverTrigger: FloatingPanel {
    private final class TriggerView: NSView {
        var onHover: (() -> Void)?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                                           owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onHover?() }
        override func mouseMoved(with event: NSEvent) { onHover?() }
    }

    private let trigger = TriggerView()
    var onHover: (() -> Void)? {
        get { trigger.onHover }
        set { trigger.onHover = newValue }
    }

    override init(size: NSSize) {
        super.init(size: size)
        contentView = trigger
        // It takes the mouse (a window that ignores it gets no tracking events); it only covers the hub's own frame,
        // and goes away the moment the pointer is on it.
        acceptsMouseMovedEvents = true
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Places the hub against its edge: flush with the screen, at its position along the edge, and kept on screen
/// as it grows (from the bar's top on the sides, from its left end along the top and bottom).
private struct EdgeLayout: Layout {
    let edge: DockEdge
    let position: Double
    let restLength: CGFloat
    private let inset = Theme.Metrics.inset

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let hub = subviews.first else { return }
        let size = hub.sizeThatFits(.unspecified)
        func along(_ length: CGFloat, _ own: CGFloat) -> CGFloat {
            // From where the bar starts, so the bar never moves as a peek opens.
            let start = length * position - restLength / 2
            return min(max(start, inset), length - own - inset)
        }
        let origin = switch edge {
        case .right: CGPoint(x: bounds.maxX - size.width, y: bounds.minY + along(bounds.height, size.height))
        case .left: CGPoint(x: bounds.minX, y: bounds.minY + along(bounds.height, size.height))
        case .top: CGPoint(x: bounds.minX + along(bounds.width, size.width), y: bounds.minY)
        case .bottom: CGPoint(x: bounds.minX + along(bounds.width, size.width), y: bounds.maxY - size.height)
        }
        hub.place(at: origin, proposal: .unspecified)
    }
}

struct HubRoot: View {
    let store: Store
    let ui: UIState
    let hub: HubState
    let layout: HubLayout
    var openApp: (AppDestination) -> Void = { _ in }
    var openUpdates: () -> Void = {}
    var openRouter: (String?) -> Void = { _ in }
    var openRouterMessage: (UUID) -> Void = { _ in }
    var pickRouterCard: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { _ in content }
            .coordinateSpace(.named(LookoutHub.rootSpace))
            .environment(\.openApp, openApp)
            .environment(\.openUpdates, openUpdates)
            .environment(\.openRouter, openRouter)
            .environment(\.openRouterMessage, openRouterMessage)
            .environment(\.pickRouterCard, pickRouterCard)
            // Tooltips are drawn over the whole window, outside the hub's clipped shape, so they're never cut off.
            .tipSpace()
    }

    @ViewBuilder private var content: some View {
        let view = LookoutHub(store: store, ui: ui, hub: hub)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LookoutHub.rootSpace)) } action: { frame in
                if HubController.debug { NSLog("Lookout hub frame \(frame)") }
                layout.frame = frame
                layout.restLength = ui.edge.isHorizontal ? frame.width : frame.height
                layout.restSize = frame.size
            }
        if layout.floating {
            view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EdgeLayout(edge: ui.edge, position: store.settings.centerPill == true ? 0.5 : ui.position,
                       restLength: layout.restLength) { view }
        }
    }
}

/// The bar on its screen edge. The window spans the edge (so a peek can open without the window being resized mid-animation)
/// and lets the mouse through everywhere but the bar and its peek. While the app window is open the bar is away.
@MainActor
final class HubController {
    let store: Store
    let ui: UIState
    let hub = HubState()
    private let layout = HubLayout()
    private let window: PillPanel
    private let host: NSHostingView<HubRoot>
    private var screen: NSScreen
    /// The screen the bar is docked on.
    var dockedScreen: NSScreen { screen }
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    /// The hover state a scheduled task is about to apply, so repeated events don't reschedule it.
    private var pendingHover: Bool?
    /// Whether the hub was last reported to the store as visible beyond the bare bar.
    private var reportedOpen = false
    /// The app window is open. The bar is off the edge only while the window is also in front.
    private(set) var windowOpen = false
    /// The open window is in front of the user (else the bar is back on its edge, the window behind it).
    private(set) var windowFront = false
    /// Whether the bar is away from the edge now: the window is open and in front.
    var barAway: Bool { BarPresence(windowOpen: windowOpen, windowFront: windowFront).barAway }
    private var barApplied = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    fileprivate static let debug = ProcessInfo.processInfo.environment["LOOKOUT_DEBUG"] != nil
    private let trigger = HoverTrigger(size: NSSize(width: 10, height: 10))
    private var globalMouse: Any?
    /// Opens the app window on a place (the app's delegate owns it).
    var openApp: (AppDestination) -> Void = { _ in } {
        didSet { host.rootView.openApp = { [weak self] in self?.opened($0) } }
    }
    /// Opens the app window on Settings, scrolled to Updates: the window's own Settings is the one that scrolls.
    var openUpdates: () -> Void = {} {
        didSet { host.rootView.openUpdates = { [weak self] in self?.openedUpdates() } }
    }
    /// Picks a card in the Router, before the window opens on it.
    var pickRouterCard: (String) -> Void = { _ in } {
        didSet { host.rootView.pickRouterCard = pickRouterCard }
    }
    /// Scrolls the Router's conversation to a message, before the window opens on it.
    var pickRouterMessage: (UUID) -> Void = { _ in }

    /// The edge `--edge` names, if it names one.
    nonisolated static func edge(in arguments: [String]) -> DockEdge? {
        arguments.firstIndex(of: "--edge").flatMap { arguments.dropFirst($0 + 1).first }.flatMap(DockEdge.init(rawValue:))
    }

    /// `demo`: on the right edge (or the one `--edge` names) and nothing saved, so trying it never moves your real bar.
    init(store: Store, demo: Bool = false, arguments: [String] = CommandLine.arguments) {
        self.store = store
        ui = demo ? UIState(persists: false, edge: Self.edge(in: arguments) ?? .right) : UIState()
        // The screen you're looking at: the one with the mouse.
        screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        window = PillPanel(size: NSSize(width: 100, height: 100))
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = true
        host = NSHostingView(rootView: HubRoot(store: store, ui: ui, hub: hub, layout: layout))
        host.sizingOptions = []
        window.contentView = host
        trigger.onHover = { [weak self] in self?.mouseMoved() }
        layout.onFrame = { [weak self] in self?.syncTrigger() }
        window.canDrag = { [weak self] p in self?.isOnBar(p) ?? false }
        window.onDragChanged = { [weak self] in self?.dragChanged(to: $0) }
        window.onDragEnded = { [weak self] in self?.dragEnded(at: $0) }
        dock()
        window.orderFrontRegardless()
        watchMouse()
        syncTrigger()
        observe()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !NSScreen.screens.contains(self.screen) { self.screen = NSScreen.main ?? NSScreen.screens[0] }
                self.dock()
            }
        }
    }

    // MARK: Window

    /// The window along the edge, deep enough for the bar's peek and its shadow.
    private func dockFrame() -> NSRect {
        let vf = screen.visibleFrame
        switch ui.edge {
        case .right, .left:
            let depth = LookoutHub.cell + LookoutHub.detail + 40
            let x = ui.edge == .right ? vf.maxX - depth : vf.minX
            return NSRect(x: x, y: vf.minY, width: depth, height: vf.height)
        case .top, .bottom:
            let depth = min(vf.height, 780)
            let y = ui.edge == .top ? vf.maxY - depth : vf.minY
            return NSRect(x: vf.minX, y: y, width: vf.width, height: depth)
        }
    }

    private func dock() {
        layout.floating = false
        host.rootView = HubRoot(store: store, ui: ui, hub: hub, layout: layout,
                                openApp: { [weak self] in self?.opened($0) },
                                openUpdates: { [weak self] in self?.openedUpdates() },
                                openRouter: { [weak self] in self?.opened(.router, card: $0) },
                                openRouterMessage: { [weak self] in self?.pickRouterMessage($0); self?.opened(.router) },
                                pickRouterCard: pickRouterCard)
        window.setFrame(dockFrame(), display: true)
        syncTrigger()
    }

    /// The hub's frame on screen (AppKit coordinates).
    private var hubScreenFrame: NSRect { screenFrame(layout.frame) }

    /// A frame in the window (top-left origin) on screen.
    private func screenFrame(_ f: CGRect) -> NSRect {
        let w = window.frame
        return NSRect(x: w.minX + f.minX, y: w.maxY - f.maxY, width: f.width, height: f.height)
    }

    /// The bar itself (where a drag can start), in window coordinates (bottom-left origin).
    private func isOnBar(_ p: NSPoint) -> Bool {
        let f = layout.frame
        let h = window.frame.height
        let hubRect = NSRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height)
        return hubRect.contains(p)
    }

    // MARK: Mouse

    /// The window only takes the mouse over the hub; hovering it opens it after a beat, leaving closes it.
    /// At rest nothing watches the mouse system-wide: a tracking area over the bar (`HoverTrigger`) notices the
    /// pointer arriving. The global monitor, to notice it leaving, runs only while the window takes the mouse.
    private func watchMouse() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { monitors.append(local) }
    }

    /// Whether the window takes the mouse (the pointer is on the hub). A window-server call, so only on change.
    private func setAcceptsMouse(_ accepts: Bool) {
        if window.ignoresMouseEvents == accepts { window.ignoresMouseEvents = !accepts }
        syncTrigger()
    }

    /// While the window takes the mouse: the global monitor runs (to notice the pointer leaving) and the arming
    /// window is away. Otherwise the arming window sits over the hub and nothing else watches.
    private func syncTrigger() {
        guard !barAway else { return }
        if !window.ignoresMouseEvents {
            if globalMouse == nil {
                globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mouseMoved() }
                }
            }
            if trigger.isVisible { trigger.orderOut(nil) }
            return
        }
        if let global = globalMouse {
            NSEvent.removeMonitor(global)
            globalMouse = nil
        }
        guard layout.frame != .zero, dragStart == nil else { return }
        let frame = hubScreenFrame.insetBy(dx: -1, dy: -1)
        if trigger.frame != frame { trigger.setFrame(frame, display: false) }
        if !trigger.isVisible { trigger.orderFrontRegardless() }
        // The hub may have grown or moved under a still pointer.
        if frame.contains(NSEvent.mouseLocation) { mouseMoved() }
    }

    private func mouseMoved() {
        guard dragStart == nil, !barAway else { return }
        let mouse = NSEvent.mouseLocation
        let inside = hubScreenFrame.insetBy(dx: -1, dy: -1).contains(mouse)
            || hub.openPanelFrame.map { screenFrame($0).insetBy(dx: -2, dy: -2).contains(mouse) } == true
        // A window-server call, so only when it changes.
        setAcceptsMouse(inside)
        if inside == hub.hovering {
            // Closed from the keyboard with the pointer outside: the next entry may show a panel again.
            if !inside, hub.quiet { hub.quiet = false }
            if pendingHover != nil { hoverTask?.cancel(); pendingHover = nil }
            return
        }
        if pendingHover == inside { return }
        hoverTask?.cancel()
        // Passing over the bar on the way somewhere else shouldn't open it; nor should a drag from elsewhere.
        guard !inside || NSEvent.pressedMouseButtons == 0 else { pendingHover = nil; return }
        pendingHover = inside
        let delay: Duration = inside ? .zero : .milliseconds(120)
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.pendingHover = nil
            self.hub.hovering = inside
            if !inside {
                self.hub.cancelDwell()
                self.hub.section = nil
                self.hub.quiet = false
                self.closedByLeaving()
            }
        }
    }

    /// The pointer left the bar and its peek.
    private func closedByLeaving() {
        hub.selection = nil
        hub.tab = nil
    }

    // MARK: The app window

    /// A click on an item of the bar (or one of its peek's): the app window opens on it.
    private func opened(_ destination: AppDestination, card: String? = nil) {
        hub.section = nil
        hub.cancelDwell()
        if let card { pickRouterCard(card) }
        openApp(destination)
    }

    /// Check for Updates, from the bar's menu: the app window opens on Settings, scrolled to Updates.
    private func openedUpdates() {
        hub.section = nil
        hub.cancelDwell()
        openUpdates()
    }

    /// The app window is open (or closed): the bar leaves the edge, and comes back where it was. The pointer may be over it
    /// when it does, which shows no peek until it has left. Opening is also bringing it to the front.
    func setWindowOpen(_ open: Bool) {
        guard open != windowOpen || (open && !windowFront) else { return }
        windowOpen = open
        windowFront = open
        applyBar()
    }

    /// The open window came to the front or went out of sight (another app, minimized, covered): the bar is away in the first
    /// case and back on its edge in the second, the window staying open.
    func setWindowFront(_ front: Bool) {
        guard windowOpen, front != windowFront else { return }
        windowFront = front
        applyBar()
    }

    /// The bar's picture and place, and the cell it grows out of (the one under the pointer, else the one last used, else the
    /// GitHub mark's), for the window to grow out of or shrink into.
    var morph: BarMorph? {
        guard layout.frame != .zero else { return nil }
        let frame = hubScreenFrame
        var image: NSImage?
        if window.isVisible, !barApplied, let rep = host.bitmapImageRepForCachingDisplay(in: layout.frame) {
            host.cacheDisplay(in: layout.frame, to: rep)
            image = NSImage(size: layout.frame.size)
            image?.addRepresentation(rep)
        }
        let tile = CDS.Tile.size + 4
        let mouse = NSEvent.mouseLocation
        var along: CGFloat?
        if frame.insetBy(dx: -2, dy: -2).contains(mouse) {
            along = ui.edge.isHorizontal ? mouse.x : mouse.y
        } else if let last = lastCellAlong, (ui.edge.isHorizontal ? frame.minX...frame.maxX : frame.minY...frame.maxY).contains(last) {
            along = last
        }
        lastCellAlong = along
        let cell: NSRect
        if ui.edge.isHorizontal {
            let x = min(max(along ?? frame.minX + LookoutHub.inset + 1 + LookoutHub.cell / 2, frame.minX + tile / 2), frame.maxX - tile / 2)
            cell = NSRect(x: x - tile / 2, y: frame.midY - tile / 2, width: tile, height: tile)
        } else {
            let y = min(max(along ?? frame.maxY - LookoutHub.cell / 2 - 2, frame.minY + tile / 2), frame.maxY - tile / 2)
            cell = NSRect(x: frame.midX - tile / 2, y: y - tile / 2, width: tile, height: tile)
        }
        return BarMorph(frame: frame, snapshot: image, cell: cell)
    }

    /// Where along the bar the window last opened from, for it to close back into.
    private var lastCellAlong: CGFloat?

    /// Puts the bar where `barAway` says: off the edge (faded out) or on it (faded in).
    private func applyBar() {
        let away = barAway
        if away != barApplied {
            barApplied = away
            hub.barHidden = away
            hoverTask?.cancel()
            pendingHover = nil
            hub.cancelDwell()
            hub.section = nil
            hub.hovering = false
            hub.selection = nil
            if away {
                setAcceptsMouse(false)
                trigger.orderOut(nil)
                if let global = globalMouse { NSEvent.removeMonitor(global); globalMouse = nil }
                fadeOut()
            } else {
                hub.quiet = true
                fadeIn()
                syncTrigger()
            }
        }
        reportOpen()
    }

    private func fadeOut() {
        guard AppTransition.enabled else { window.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.barApplied else { return }
                self.window.orderOut(nil)
            }
        })
    }

    private func fadeIn() {
        guard AppTransition.enabled else { window.alphaValue = 1; window.orderFrontRegardless(); return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppTransition.reduceMotion ? AppTransition.reducedDuration : AppTransition.duration
            context.timingFunction = AppTransition.curve
            window.animator().alphaValue = 1
        }
    }

    /// Re-evaluates the pointer and what the store is told when the bar's state changes under a still pointer.
    private func observe() {
        withObservationTracking {
            _ = ui.edge
            _ = hub.section
            _ = hub.quiet
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.mouseMoved()
                self.reportOpen()
                self.observe()
            }
        }
    }

    /// Tells the store when the hub is more than the bare bar (a peek or the app window), so it refreshes stale
    /// data and polls faster meanwhile; warms the avatars the inbox is about to show.
    private func reportOpen() {
        let open = windowOpen || (hub.section != nil && !hub.quiet)
        guard open != reportedOpen else { return }
        reportedOpen = open
        store.setHubOpen(open)
        if open {
            // Every author in the inbox (not just the newest items: the view may list another filter), and the
            // account's own picture in Settings.
            var urls = Array(Set(store.things.values.compactMap { $0.author?.avatar })).prefix(60)
                .compactMap { Avatar.sizedURL($0, size: 22) }
            if let me = Avatar.sizedURL(store.me?.avatarUrl, size: 30) { urls.append(me) }
            ImageCache.shared.prefetch(urls)
        }
    }

    // MARK: Dragging to another edge

    private func dragChanged(to mouse: NSPoint) {
        if dragStart == nil {
            hoverTask?.cancel()
            pendingHover = nil
            hub.cancelDwell()
            hub.section = nil
            // Back to the bar at once (no closing animation), and carry just the bar, under the cursor where you
            // grabbed it.
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            withTransaction(instant) {
                hub.hovering = false
                layout.floating = true
            }
            let rest = layout.restSize == .zero ? hubScreenFrame.size : layout.restSize
            let resting = restFrame(size: rest, in: screen.visibleFrame)
            let grip = NSPoint(x: min(max(mouse.x - resting.minX, 10), rest.width - 10),
                               y: min(max(mouse.y - resting.minY, 10), rest.height - 10))
            let bar = NSRect(origin: NSPoint(x: mouse.x - grip.x, y: mouse.y - grip.y), size: rest)
            window.setFrame(bar, display: true)
            dragStart = (mouse, bar.origin)
            hub.dragging = true
        }
        guard let start = dragStart else { return }
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    private func dragEnded(at mouse: NSPoint) {
        screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? screen
        let vf = screen.visibleFrame
        (ui.edge, ui.position) = EdgeSnap.snap(window.frame, in: vf)
        // Let SwiftUI lay the bar out for its new edge (it may turn), then glide it into place and dock.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            let size = self.host.fittingSize
            let target = self.restFrame(size: size, in: vf)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.window.animator().setFrame(target, display: true)
            }, completionHandler: {
                MainActor.assumeIsolated {
                    self.dragStart = nil
                    self.hub.dragging = false
                    self.dock()
                    self.mouseMoved()
                }
            })
        }
    }

    /// Where the bar rests on its edge: the same place `EdgeLayout` puts it once docked.
    private func restFrame(size: NSSize, in vf: NSRect) -> NSRect {
        let position = store.settings.centerPill == true ? 0.5 : ui.position
        let dock = dockFrame()
        let inset: CGFloat = 6
        switch ui.edge {
        case .right, .left:
            let top = min(max(dock.height * position - size.height / 2, inset), dock.height - size.height - inset)
            let x = ui.edge == .right ? vf.maxX - size.width : vf.minX
            return NSRect(x: x, y: dock.maxY - top - size.height, width: size.width, height: size.height)
        case .top, .bottom:
            let left = min(max(dock.width * position - size.width / 2, inset), dock.width - size.width - inset)
            let y = ui.edge == .top ? vf.maxY - size.height : vf.minY
            return NSRect(x: dock.minX + left, y: y, width: size.width, height: size.height)
        }
    }
}

/// Whether the bar is on its edge: it is, unless the app window is open and in front of the user.
struct BarPresence: Equatable {
    var windowOpen = false
    var windowFront = false
    var barAway: Bool { windowOpen && windowFront }

    /// The window opened (and so came to the front), or closed.
    mutating func opened(_ open: Bool) { windowOpen = open; windowFront = open }
    /// The open window came to the front or went out of sight.
    mutating func front(_ front: Bool) { if windowOpen { windowFront = front } }
}
