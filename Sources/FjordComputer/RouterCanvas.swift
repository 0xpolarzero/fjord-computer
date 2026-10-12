import AppKit
import SwiftUI

// Now as a canvas (docs/design/spec/router-canvas.md): every project folder a frame, its sessions grouped under Needs you,
// Worth a look, Waiting, Working and Done, on a ground you pan with two fingers or a drag, zoom with a pinch or ⌘-scroll,
// and fit with a double-click. The frames and cards are laid out once (RouterCanvasLayout.swift); a pan or a zoom moves
// only the camera's transform, so nothing in them is drawn again.

// MARK: - State

/// What the canvas shows of its content: read only by the transform, so a pan or a zoom redraws nothing else.
@Observable
@MainActor
final class CanvasCamera {
    var transform = CanvasTransform()
    /// Moved by you (a pan, a zoom, Fit): the first look no longer follows the content as it settles.
    @ObservationIgnored var moved = false
}

/// What the canvas keeps while the window lives (its folds across launches).
@Observable
@MainActor
final class RouterCanvasState {
    let camera = CanvasCamera()
    /// The groups shown, none for all.
    var filter: Set<CanvasGroup> = []
    /// Folds of yours over a frame's own (a frame of finished sessions only folds), by folder.
    var folderFolds: [String: Bool] {
        didSet {
            guard folderFolds != oldValue else { return }
            defaults?.set(folderFolds, forKey: Self.foldsKey)
        }
    }
    /// Groups whose "+n more" was opened ("folder#group").
    var expandedMore: Set<String> = []
    /// When the first look was taken: it follows the content as it settles (the cards measured, the column sized) for a
    /// moment, unless you move it.
    @ObservationIgnored var firstFit: Date?
    /// The viewport's room for content, and the content's size, as last laid out: what Fit and a reveal go by.
    @ObservationIgnored var free: CGRect = .zero
    @ObservationIgnored var contentSize: CGSize = .zero
    /// Each session's newest addressed card, for the search's words and the history's revision (`Done`).
    @ObservationIgnored var doneMemo: (query: String, revision: Int, cards: [RouterCard])?
    @ObservationIgnored private let defaults: UserDefaults?

    static let foldsKey = "routerCanvasFolds"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        folderFolds = defaults?.dictionary(forKey: Self.foldsKey) as? [String: Bool] ?? [:]
    }

    func folded(_ folder: CanvasFolder) -> Bool { folderFolds[folder.key] ?? folder.doneOnly }

    func toggleFold(_ folder: CanvasFolder) {
        let next = !folded(folder)
        folderFolds[folder.key] = next == folder.doneOnly ? nil : next
    }

    func showAll(_ group: CanvasGroup, in folder: CanvasFolder) { expandedMore.insert("\(folder.key)#\(group.rawValue)") }

    /// Everything shown, centred.
    func fit(reduce: Bool) {
        guard contentSize.width > 0, free.width > 0 else { return }
        let next = CanvasTransform.fit(CGRect(origin: .zero, size: contentSize), in: free)
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform = next }
    }

    /// The first look: everything if it reads (at 0.6 or more), else the first column's top at full size.
    func fitFirst() {
        guard !camera.moved, contentSize.width > 0, free.width > 0 else { return }
        let now = Date()
        if let firstFit, now.timeIntervalSince(firstFit) > 1.5 { return }
        if firstFit == nil { firstFit = now }
        let all = CanvasTransform.fit(CGRect(origin: .zero, size: contentSize), in: free)
        camera.transform = all.scale >= 0.6 ? all : CanvasTransform(origin: free.origin, scale: 1)
    }

    func zoom(by factor: CGFloat, reduce: Bool) {
        let at = CGPoint(x: free.midX, y: free.midY)
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform = camera.transform.zoomed(by: factor, at: at) }
    }
}

extension RouterModel {
    /// The canvas's frames on Now's zones as the search leaves them (`page`).
    func canvasFolders(_ store: Store, page: RouterPage) -> [CanvasFolder] {
        let picked = Set([selection, highlighted, expandedNeed].compactMap { $0 })
        return RouterCanvasModel.make(page: page, done: canvasDone(store), muted: Set(store.agents.mutedFolders),
                                      name: store.folderName, color: store.projectColor, filter: canvas.filter,
                                      picked: picked, expanded: canvas.expandedMore, showsAll: searching)
    }

    /// Each session's newest addressed card among the history's lines the search leaves (not the Unread filter: it is
    /// History's), newest first; worked out again only as the words or the history change.
    func canvasDone(_ store: Store) -> [RouterCard] {
        let query = searching ? search.query : "", revision = store.routerSearchRevision
        if let memo = canvas.doneMemo, memo.query == query, memo.revision == revision { return memo.cards }
        let cards = RouterCanvasModel.done(history: searchedHistory(store))
        canvas.doneMemo = (query, revision, cards)
        return cards
    }
}

// MARK: - Canvas

struct RouterCanvas: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let canvas = model.canvas
        VStack(alignment: .leading, spacing: 0) {
            CanvasNotices(store: store, model: model, page: page)
            if #available(macOS 26, *) {
                // Under the composer, which floats over it: the room for content ends where the composer starts.
                viewport(canvas).ignoresSafeArea(.container, edges: .bottom)
            } else {
                viewport(canvas)
            }
        }
    }

    private func viewport(_ canvas: RouterCanvasState) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bottom = proxy.safeAreaInsets.bottom
            let free = CGRect(x: CanvasMetrics.pad, y: CanvasMetrics.pad, width: max(0, size.width - 2 * CanvasMetrics.pad),
                              height: max(0, size.height - bottom - 2 * CanvasMetrics.pad))
            ZStack(alignment: .topLeading) {
                CanvasGround(canvas: canvas, pan: CanvasPan(camera: canvas.camera))
                Color.clear
                    .overlay(alignment: .topLeading) {
                        CanvasContent(store: store, model: model, page: page, pan: CanvasPan(camera: canvas.camera))
                            .fixedSize()
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                canvas.contentSize = size
                                canvas.fitFirst()
                            }
                            .modifier(CameraTransform(camera: canvas.camera))
                    }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .background(CanvasEvents(camera: canvas.camera, bottomInset: bottom))
            .onChange(of: free, initial: true) { _, free in
                canvas.free = free
                canvas.fitFirst()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Router canvas")
        .accessibilityAction(named: "Fit everything") { canvas.fit(reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom in") { canvas.zoom(by: 1.25, reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom out") { canvas.zoom(by: 0.8, reduce: reduceMotion) }
    }
}

/// The frames, in their columns; read again only as what they show changes, never as the camera moves.
private struct CanvasContent: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let pan: CanvasPan

    var body: some View {
        let folders = model.canvasFolders(store, page: page)
        let columns = CanvasMetrics.columns(closed: folders.map { CanvasMetrics.closedHeight($0, folded: model.canvas.folded($0)) })
        let column = Dictionary(zip(folders.map(\.id), columns), uniquingKeysWith: { a, _ in a })
        CanvasMasonry {
            ForEach(folders) { folder in
                CanvasFolderFrame(folder: folder, store: store, model: model, page: page, pan: pan)
                    .canvasColumn(column[folder.id] ?? 0)
            }
        }
    }
}

/// The camera's transform: the only view that reads it.
private struct CameraTransform: ViewModifier {
    let camera: CanvasCamera

    func body(content: Content) -> some View {
        let t = camera.transform
        content
            .scaleEffect(t.scale, anchor: .topLeading)
            .offset(x: t.origin.x, y: t.origin.y)
    }
}

/// The canvas's ground: a drag pans, a double-click fits.
private struct CanvasGround: View {
    let canvas: RouterCanvasState
    let pan: CanvasPan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CDS.Surface.s1
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { canvas.fit(reduce: reduceMotion) }
            .canvasPannable(pan)
            .accessibilityHidden(true)
    }
}

/// A drag that pans the canvas, from its ground or a frame's: in the window's points, whatever the zoom.
@MainActor
final class CanvasPan {
    let camera: CanvasCamera
    private var start: CGPoint?

    init(camera: CanvasCamera) { self.camera = camera }

    var gesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { [self] drag in
                let start = self.start ?? camera.transform.origin
                self.start = start
                camera.moved = true
                camera.transform.origin = CGPoint(x: start.x + drag.translation.width, y: start.y + drag.translation.height)
            }
            .onEnded { [self] _ in start = nil }
    }
}

extension View {
    func canvasPannable(_ pan: CanvasPan) -> some View { gesture(pan.gesture) }
}

// MARK: - Notices

/// What Now's list says over its sections, over the canvas: what came while you were away, the Router at work (before
/// macOS 26, where the column's bar doesn't hold it), the messages waiting for where they go, and a search that found
/// nothing.
private struct CanvasNotices: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage

    var body: some View {
        let empty = RouterZone.allCases.allSatisfy { page.count($0) == 0 }
        let nothing = model.searching && empty && model.canvasDone(store).isEmpty
        let away = store.routerAttention.strip?.line(store.routerShownCards) != nil
        let busy: Bool = if #unavailable(macOS 26) { store.routerDispatcher.isBusy } else { false }
        if away || busy || !page.asks.isEmpty || nothing {
            VStack(alignment: .leading, spacing: 6) {
                AwayStripView(store: store, model: model)
                if busy { RouterBusyLine(store: store) }
                ForEach(page.asks) { ask in AskBackCard(store: store, ask: ask) }
                if nothing { RouterNothingFound() }
            }
            .frame(maxWidth: CanvasMetrics.frameWidth, alignment: .leading)
            .padding(.horizontal, CanvasMetrics.pad)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Scroll and pinch

/// Two-finger scrolls and pinches over the canvas: a scroll pans, ⌘-scroll and a pinch zoom at the pointer. Each gesture is
/// the canvas's or not from its start to the end of its momentum, so a pan sliding a card under the pointer never turns
/// into a scroll of what is in the card.
private struct CanvasEvents: NSViewRepresentable {
    let camera: CanvasCamera
    /// The composer's room at the bottom: scrolls over it are its own.
    let bottomInset: CGFloat

    func makeNSView(context: Context) -> CanvasEventView {
        let view = CanvasEventView()
        view.camera = camera
        view.bottomInset = bottomInset
        return view
    }

    func updateNSView(_ view: CanvasEventView, context: Context) {
        view.camera = camera
        view.bottomInset = bottomInset
    }
}

final class CanvasEventView: NSView {
    var camera: CanvasCamera?
    var bottomInset: CGFloat = 0
    private var monitor: Any?
    /// Whether the scroll under way is the canvas's.
    private var claimed = false

    override var isFlipped: Bool { true }
    /// Never in the way of a click: it only watches.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handle(event) }
            return consumed ? nil : event
        }
    }

    /// Where the event is in the canvas, if it is over its room.
    private func point(_ event: NSEvent) -> CGPoint? {
        guard event.window === window, !isHidden else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p), p.y < bounds.height - bottomInset else { return nil }
        return p
    }

    /// Whether the event is the canvas's (it pans or zooms): consumed.
    @MainActor private func handle(_ event: NSEvent) -> Bool {
        guard let camera else { return false }
        switch event.type {
        case .magnify:
            if event.phase == .began || event.phase == [] { claimed = point(event) != nil }
            guard claimed else { return false }
            camera.moved = true
            camera.transform = camera.transform.zoomed(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
            if event.phase == .ended || event.phase == .cancelled { claimed = false }
            return true
        case .scrollWheel:
            if event.phase == .began || (event.phase == [] && event.momentumPhase == []) { claimed = point(event) != nil }
            guard claimed else { return false }
            camera.moved = true
            let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            let dx = event.scrollingDeltaX * k, dy = event.scrollingDeltaY * k
            if event.modifierFlags.contains(.command) {
                camera.transform = camera.transform.zoomed(by: exp(-dy * 0.01), at: convert(event.locationInWindow, from: nil))
            } else {
                camera.transform.origin = CGPoint(x: camera.transform.origin.x + dx, y: camera.transform.origin.y + dy)
            }
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled { claimed = false }
            return true
        default:
            return false
        }
    }
}
