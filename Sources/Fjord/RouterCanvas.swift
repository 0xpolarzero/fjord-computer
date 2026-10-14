import AppKit
import SwiftUI

// Now as a canvas (docs/design/spec/router-canvas.md): every project folder a frame, its sessions grouped under Needs you,
// Worth a look, Waiting, Working and Done, on a ground you pan with two fingers or a drag, zoom with a pinch or ⌘-scroll,
// and fit with a double-click. The frames and cards are laid out once (RouterCanvasLayout.swift); a pan or a zoom moves
// only the camera's transform, so nothing in them is drawn again.

// MARK: - State

/// What the canvas shows of its content: read only by the transform, so a pan or a zoom redraws nothing else. Kept across
/// launches: it moves only when you move it.
@Observable
@MainActor
final class CanvasCamera {
    var transform: CanvasTransform {
        didSet {
            guard transform != oldValue, let defaults else { return }
            defaults.set([Double(transform.origin.x), Double(transform.origin.y), Double(transform.scale)], forKey: Self.key)
        }
    }
    /// Set by you (a pan, a zoom, Fit) or kept from before: no first look is taken.
    @ObservationIgnored var moved = false
    @ObservationIgnored private let defaults: UserDefaults?

    static let key = "routerCanvasCamera"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let kept = defaults?.array(forKey: Self.key) as? [Double], kept.count == 3 {
            transform = CanvasTransform(origin: CGPoint(x: kept[0], y: kept[1]), scale: CanvasTransform.clamp(kept[2]))
            moved = true
        } else {
            transform = CanvasTransform()
        }
    }
}

/// A frame being dragged or resized: which, and how far (in the content's points, whatever the zoom). Read only by the
/// frames' lift and the frame resized, so a drag redraws nothing else.
@Observable
@MainActor
final class CanvasFrameDrag {
    var key: String?
    var offset: CGSize = .zero
    /// The frame's top left in the content as the drag started, and the drag's own start (a new drag, a new start).
    @ObservationIgnored var start: (at: CGPoint, origin: CGPoint)?
    /// The frame being resized, its size as the pointer has it, and its size and the drag's start as it began.
    var resizing: String?
    var size: CGSize = .zero
    @ObservationIgnored var resizeStart: (at: CGPoint, size: CGSize)?
}

/// How far a frame's body is scrolled, and how far it can be: read only by the body's own offset.
@Observable
@MainActor
final class CanvasBodyScroll {
    var offset: CGFloat = 0
    /// What the body holds and what the frame shows of it.
    var body: CGFloat = 0
    var visible: CGFloat = 0

    var maxScroll: CGFloat { CanvasMetrics.maxScroll(body: body, visible: visible) }

    /// Scrolled by `delta` content points (down positive), never past either end.
    func scroll(by delta: CGFloat) {
        offset = min(maxScroll, max(0, offset + delta))
    }
}

/// Where the canvas points you to a node it doesn't show (a message landed there, a card picked by the keys): a marker on
/// the viewport's edge, towards it, that goes there when you click it.
struct CanvasMarker: Equatable {
    let node: String
    let label: String
    var id = UUID()
}

/// What the canvas keeps while the window lives (its folds, the frames' places and sizes, and its camera across launches).
@Observable
@MainActor
final class RouterCanvasState {
    let camera: CanvasCamera
    /// The drag that pans it: one for the canvas's life, so a redraw in the middle of a drag doesn't start it again.
    let pan: CanvasPan
    /// The frame being dragged or resized.
    let drag = CanvasFrameDrag()
    /// Folds of yours over a frame's own (a frame of finished sessions only folds), by folder.
    var folderFolds: [String: Bool] {
        didSet {
            guard folderFolds != oldValue else { return }
            defaults?.set(folderFolds, forKey: Self.foldsKey)
        }
    }
    /// Where you put the frames (their top left in the content), by folder; the others are packed (`CanvasMetrics.preferred`).
    var positions: [String: CGPoint] {
        didSet {
            guard positions != oldValue else { return }
            defaults?.set(positions.mapValues { [Double($0.x), Double($0.y)] }, forKey: Self.positionsKey)
        }
    }
    /// The sizes you gave the frames, by folder: a width, and a height (0: as tall as what it holds).
    var sizes: [String: CGSize] {
        didSet {
            guard sizes != oldValue else { return }
            defaults?.set(sizes.mapValues { [Double($0.width), Double($0.height)] }, forKey: Self.sizesKey)
        }
    }
    /// The frames moved, the last on top: what draws over what where they overlap.
    var stack: [String] = []
    /// Each frame's body's scroll, when you made it shorter than what it holds: one small object each, so a scroll redraws
    /// only its frame's offset.
    @ObservationIgnored private var scrolls: [String: CanvasBodyScroll] = [:]

    func scroll(_ key: String) -> CanvasBodyScroll {
        if let scroll = scrolls[key] { return scroll }
        let scroll = CanvasBodyScroll()
        scrolls[key] = scroll
        return scroll
    }

    /// The frame under `point` (content space) whose body scrolls there, the topmost: what a two-finger scroll over it moves.
    func scrollingFrame(at point: CGPoint) -> String? {
        let hits = frameRects.filter { key, rect in
            rect.contains(point) && point.y > rect.minY + CanvasMetrics.header && (scrolls[key]?.maxScroll ?? 0) > 0
        }.map(\.key)
        return hits.max { (stack.firstIndex(of: $0) ?? -1) < (stack.firstIndex(of: $1) ?? -1) }
    }
    /// The marker pointing to a node off the view, if any.
    var marker: CanvasMarker?
    /// Each frame's place as last worked out (yours or packed), before the push-down: what a drop keeps of the others.
    @ObservationIgnored var preferred: [String: CGPoint] = [:]
    /// Where the chips and notices floating at the canvas's top end: what Fit keeps the content under.
    var topRoom: CGFloat = 0
    /// Each frame's box in the content as drawn: what Fit takes in.
    @ObservationIgnored var frameRects: [String: CGRect] = [:]
    /// Groups whose "+n more" was opened ("folder#group").
    var expandedMore: Set<String> = []
    /// The Working or Waiting row open on the canvas (its node's id). A card of Needs you or Worth a look open is
    /// `RouterModel.expandedNeed`, a Done line `openDone` (in `RouterModel.expanded`, as the history's lines): one at a time.
    var openRow: String?
    var openDone: String?
    /// Each node's box in the content, as last laid out (its frame's place, its open height): what a marker points to.
    @ObservationIgnored var nodeRects: [String: CGRect] = [:]
    /// The marker being worked out (its node measured first), so a newer one replaces it.
    @ObservationIgnored private var pointTask: Task<Void, Never>?
    @ObservationIgnored private var markerTask: Task<Void, Never>?
    /// When the first look was taken: it follows the content as it settles (the cards measured) for a moment, unless you
    /// move it. Only when there is no camera kept from before.
    @ObservationIgnored var firstFit: Date?
    /// The viewport's room for content, and the content's size, as last laid out: what Fit and a marker go by.
    @ObservationIgnored var free: CGRect = .zero
    @ObservationIgnored var contentSize: CGSize = .zero
    /// Each session's newest addressed card, for the search's words and the history's revision (`Done`).
    @ObservationIgnored var doneMemo: (query: String, revision: Int, cards: [RouterCard])?
    @ObservationIgnored private let defaults: UserDefaults?

    struct FolderInputs: Equatable {
        var store: ObjectIdentifier
        var page: RouterPage
        var done: [RouterCard]
        var muted: [String]
        var colors: [String: Int]
        var names: [String: String]
        var named: Set<String>?
        var filter: RouterFilter
        var picked: Set<String>
        var expanded: Set<String>
        var searching: Bool
        var guestProjects: [RunsOnProject]
        var guestStarts: [PendingDesktopStart]
    }
    @ObservationIgnored var folderMemo: (inputs: FolderInputs, folders: [CanvasFolder])?

    struct PackingFrame: Equatable {
        var key: String
        var closed: CGFloat
    }
    @ObservationIgnored private var packingMemo: (frames: [PackingFrame], positions: [String: CGPoint], places: [String: CGPoint])?

    func packedPlaces(_ folders: [CanvasFolder]) -> [String: CGPoint] {
        let frames = folders.map {
            PackingFrame(key: $0.key, closed: max(CanvasMetrics.closedHeight($0, folded: folded($0)), sizes[$0.key]?.height ?? 0))
        }
        if let memo = packingMemo, memo.frames == frames, memo.positions == positions { return memo.places }
        let places = CanvasMetrics.preferred(frames.map { ($0.key, $0.closed) }, placed: positions)
        packingMemo = (frames, positions, places)
        return places
    }

    /// The canvas viewport in the shared flight space.
    var viewportFrame: CGRect = .zero
    /// The plan Esc went Back out of on the canvas: the next Esc folds it rather than going into revise again.
    @ObservationIgnored var backedOutOf: String?
    /// What landed on a node, by its id: its glow and "You: …" on it, for a few seconds.
    var landed: [String: CanvasLanding] = [:]
    @ObservationIgnored private var landingTasks: [String: Task<Void, Never>] = [:]
    /// Shots: every flight held at this point of its arc, and what landed kept.
    @ObservationIgnored var freezeFlight: CGFloat?

    static let foldsKey = "routerCanvasFolds"
    static let positionsKey = "routerCanvasPositions"
    static let sizesKey = "routerCanvasSizes"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        camera = CanvasCamera(defaults: defaults)
        pan = CanvasPan(camera: camera)
        folderFolds = defaults?.dictionary(forKey: Self.foldsKey) as? [String: Bool] ?? [:]
        let kept = defaults?.dictionary(forKey: Self.positionsKey) as? [String: [Double]] ?? [:]
        positions = kept.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        let sized = defaults?.dictionary(forKey: Self.sizesKey) as? [String: [Double]] ?? [:]
        sizes = sized.compactMapValues { $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil }
    }

    // MARK: Moving and resizing frames

    /// A frame's width: as it is being resized, else yours, else the default.
    func width(_ key: String) -> CGFloat {
        if drag.resizing == key { return drag.size.width }
        return sizes[key].map { max(CanvasMetrics.minFrameWidth, $0.width) } ?? CanvasMetrics.frameWidth
    }

    /// The height you gave a frame, 0 for none (it fits what it holds). Yours wins: what it holds scrolls inside it.
    func height(_ key: String) -> CGFloat {
        if drag.resizing == key { return drag.size.height }
        return sizes[key]?.height ?? 0
    }

    /// Every frame drawn kept where it is drawn, so none re-flows once one leaves the packing; `key` at `at`.
    private func placeAll(_ key: String, at: CGPoint) -> [String: CGPoint] {
        var next = positions
        for (other, at) in preferred where next[other] == nil && other != key { next[other] = frameRects[other]?.origin ?? at }
        next[key] = at
        return next
    }

    /// Changed at once, with nothing to animate: a frame stays exactly where the pointer left it.
    private func still(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// A frame dropped `offset` (content points) from where it was drawn: it stays exactly there, over the others, and
    /// every other frame keeps the place it had. Nothing is nudged: frames may overlap, the last moved on top.
    func drop(_ key: String, offset: CGSize) {
        let from = drag.start?.origin ?? frameRects[key]?.origin ?? preferred[key] ?? .zero
        let next = placeAll(key, at: CGPoint(x: from.x + offset.width, y: from.y + offset.height))
        still {
            positions = next
            raise(key)
            drag.start = nil
            drag.key = nil
            drag.offset = .zero
        }
    }

    /// A drag that ended without a drop (cancelled): the frame goes back to its place.
    func cancelDrag(_ key: String) {
        if drag.key == key {
            drag.start = nil
            drag.key = nil
            drag.offset = .zero
        }
        if drag.resizing == key {
            drag.resizeStart = nil
            drag.resizing = nil
        }
    }

    /// A frame being resized to `size`.
    func resize(_ key: String, to size: CGSize) {
        if drag.resizing != key { drag.resizing = key }
        drag.size = size
    }

    /// A resize let go: the frame keeps its size, where it is, and every other frame where it was.
    func endResize(_ key: String) {
        guard drag.resizing == key else { return }
        let size = drag.size
        let next = placeAll(key, at: positions[key] ?? frameRects[key]?.origin ?? preferred[key] ?? .zero)
        still {
            sizes[key] = size
            positions = next
            raise(key)
            drag.resizeStart = nil
            drag.resizing = nil
        }
    }

    private func raise(_ key: String) {
        stack.removeAll { $0 == key }
        stack.append(key)
    }

    /// The frames packed again, at their sizes, as on a first look.
    func resetLayout(reduce: Bool) {
        withAnimation(Motion.spatial.resolved(reduce: reduce)) {
            positions = [:]
            sizes = [:]
            stack = []
        }
        for scroll in scrolls.values { scroll.offset = 0 }
    }

    /// What there is to show: every frame drawn, or the content as laid out before any is.
    var contentBounds: CGRect {
        let rects = frameRects.values
        guard let first = rects.first else { return CGRect(origin: .zero, size: contentSize) }
        return rects.reduce(first) { $0.union($1) }
    }

    func folded(_ folder: CanvasFolder) -> Bool { folderFolds[folder.key] ?? folder.doneOnly }

    func toggleFold(_ folder: CanvasFolder) {
        let next = !folded(folder)
        folderFolds[folder.key] = next == folder.doneOnly ? nil : next
    }

    func showAll(_ group: CanvasGroup, in folder: CanvasFolder) { expandedMore.insert("\(folder.key)#\(group.rawValue)") }

    /// "Show less": the group back to its first few.
    func showLess(_ group: CanvasGroup, in folder: CanvasFolder) { expandedMore.remove("\(folder.key)#\(group.rawValue)") }

    // MARK: Camera: only you move it

    /// Everything shown, centred (Fit, a double-click).
    func fit(reduce: Bool) {
        let bounds = contentBounds
        guard bounds.width > 0, free.width > 0 else { return }
        let next = CanvasTransform.fit(bounds, in: free)
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform = next }
    }

    /// The very first look, when no camera is kept from before: everything, following the content as it settles (the
    /// cards measured) for a moment. Never again after that.
    func fitFirst() {
        let bounds = contentBounds
        guard !camera.moved, bounds.width > 0, free.width > 0 else { return }
        let now = Date()
        if let firstFit, now.timeIntervalSince(firstFit) > 1.5 {
            camera.moved = true
            return
        }
        if firstFit == nil { firstFit = now }
        camera.transform = CanvasTransform.fit(bounds, in: free)
    }

    /// A frame at full size, its top left at the room's (shots).
    func look(at key: String) {
        guard let rect = frameRects[key] else { return }
        camera.moved = true
        camera.transform = CanvasTransform(origin: CGPoint(x: free.minX - rect.minX, y: free.minY - rect.minY), scale: 1)
    }

    /// Whether `rect` (content space) shows in the viewport's room, at least in part.
    func shows(_ rect: CGRect) -> Bool {
        let t = camera.transform
        let shown = CGRect(x: t.origin.x + rect.minX * t.scale, y: t.origin.y + rect.minY * t.scale,
                           width: rect.width * t.scale, height: rect.height * t.scale)
        return free.width > 0 && shown.intersects(free)
    }

    /// A node picked (the keys, a banner, a search) or written to: the camera stays; if the node is off the view, a marker on
    /// the viewport's edge points to it, once it is laid out.
    func point(to id: String, label: String) {
        pointTask?.cancel()
        pointTask = Task { [weak self] in
            // A few layout passes: what opened for it is measured first.
            for attempt in 0..<20 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(40)) }
                guard let self, !Task.isCancelled else { return }
                guard let rect = self.nodeRects[id], self.free.width > 0 else { continue }
                self.mark(rect, id: id, label: label)
                return
            }
        }
    }

    /// The marker for the node at `rect`, or none when it shows.
    func mark(_ rect: CGRect, id: String, label: String) {
        guard !shows(rect) else {
            if marker?.node == id { marker = nil }
            return
        }
        marker = CanvasMarker(node: id, label: label)
        markerTask?.cancel()
        guard freezeFlight == nil else { return }
        markerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.marker?.node == id else { return }
            self.marker = nil
        }
    }

    /// The marker clicked: the camera goes to its node (you asked), the least that shows it.
    func goToMarker(reduce: Bool) {
        guard let marker else { return }
        self.marker = nil
        guard let rect = nodeRects[marker.node] ?? frameRects[marker.node], free.width > 0,
              let next = camera.transform.origin(toShow: rect.insetBy(dx: -8, dy: -8), in: free) else { return }
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform.origin = next }
    }

    /// Lands a message on a node: "You: …" for `CanvasLanding.shown`, then gone (kept in shots).
    func land(_ text: String, on node: String) {
        landed[node] = CanvasLanding(text: text)
        landingTasks[node]?.cancel()
        guard freezeFlight == nil else { return }
        landingTasks[node] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CanvasLanding.shown))
            guard let self, !Task.isCancelled else { return }
            self.landed[node] = nil
            self.landingTasks[node] = nil
        }
    }

    /// The canvas goes away: nothing in the air, nothing left to clear, and what comes meanwhile doesn't fly.
    func stopFlights() {
        for task in landingTasks.values { task.cancel() }
        landingTasks = [:]
        if freezeFlight == nil {
            landed = [:]
        }
    }

    func zoom(by factor: CGFloat, reduce: Bool) {
        let at = CGPoint(x: free.midX, y: free.midY)
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform = camera.transform.zoomed(by: factor, at: at) }
    }
}

extension RouterModel {
    /// What a node of the canvas is called: its card's title, or its session's.
    func canvasTitle(_ id: String, store: Store, page: RouterPage) -> String {
        if let card = store.router.cards.first(where: { $0.id == id }) { return card.title }
        if let row = page.working.first(where: { Self.workingID($0.id) == id }) { return row.session.title }
        if let card = page.waiting.first(where: { Self.workingID($0.sessionID) == id }) { return card.title }
        return "Card"
    }

    /// The canvas's frames on Now's zones as the search leaves them (`page`).
    func canvasFolders(_ store: Store, page: RouterPage) -> [CanvasFolder] {
        // Not Jev's highlight: it moves as you type, and the group would widen and narrow under you.
        let inputs = RouterCanvasState.FolderInputs(store: ObjectIdentifier(store), page: page, done: canvasDone(store),
            muted: store.agents.mutedFolders, colors: store.agents.folderColors, names: store.folderNames,
            named: store.namedFoldersSeen, filter: filter, picked: Set([selection, expandedNeed].compactMap { $0 }),
            expanded: canvas.expandedMore, searching: searching, guestProjects: store.router.runsOnProjects,
            guestStarts: store.router.pendingDesktopStarts)
        if let memo = canvas.folderMemo, memo.inputs == inputs { return memo.folders }
        let folders = RouterCanvasModel.make(page: page, done: inputs.done, muted: Set(inputs.muted),
            name: store.routerProjectGroupName, color: store.routerProjectGroupColor, filter: inputs.filter,
            picked: inputs.picked, expanded: inputs.expanded, showsAll: inputs.searching,
            projectKey: { store.routerProjectGroupKey(sessionID: $0, folder: $1) },
            projectSource: store.routerProjectGroupSource)
        canvas.folderMemo = (inputs, folders)
        return folders
    }

    /// The card of Needs you shown in full: on the canvas only the one you opened (nothing opens by itself there), in the
    /// list the one asked for or the first (`RouterPage.openNeed`). What Esc's Revise… and the form keys act on.
    func openNeed(_ store: Store) -> String? {
        let page = zones(store)
        guard layout == .canvas else { return page.openNeed(preferred: expandedNeed) }
        guard let id = expandedNeed, page.needs.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The node open on the canvas, if one is: a card in full, a row, a Done line.
    func canvasOpenNode(_ store: Store) -> String? {
        let page = zones(store)
        if let id = expandedNeed, (page.needs + page.notes).contains(where: { $0.id == id }) { return id }
        if let id = canvas.openRow { return id }
        if let id = canvas.openDone, expanded.contains(id) { return id }
        return nil
    }

    /// One node open on the canvas at a time: every other folds as `id` opens (none: all fold).
    func canvasOpen(_ id: String?) {
        canvas.backedOutOf = nil
        if expandedNeed != nil, expandedNeed != id { expandedNeed = nil }
        if canvas.openRow != nil, canvas.openRow != id { canvas.openRow = nil }
        if let done = canvas.openDone, done != id {
            expanded.remove(done)
            canvas.openDone = nil
        }
    }

    /// Esc on the canvas: the node open on it folds. Whether one was.
    func foldCanvasNode(_ store: Store) -> Bool {
        guard canvasOpenNode(store) != nil else { return false }
        canvasOpen(nil)
        return true
    }

    /// A pick on the canvas: Now shows (in a narrow window) unless the card is only the history's, its node opens, and the
    /// canvas goes there if `shows`. A session waiting is its row's node (`workingID`), one ready to continue its card's.
    func showOnCanvas(_ id: String, store: Store, reveal shows: Bool, expand: Bool) {
        var node = id
        if let card = store.router.cards.first(where: { $0.id == id }) {
            if card.isOpen {
                uncover(card.kind == .waiting && store.routerTier(card) != .needsYou ? Self.workingID(card.sessionID) : id, store: store)
            }
            if card.isOpen && card.kind == .waiting {
                node = store.routerTier(card) == .needsYou ? id : Self.workingID(card.sessionID)
                show(.now)
                canvasOpen(node)
                canvas.openRow = node
            } else if card.isOpen {
                show(.now)
                canvasOpen(id)
                expandedNeed = id
            } else {
                let drawn = RouterCanvasModel.order(canvasFolders(store, page: zones(store)), folded: canvas.folded).contains(id)
                if !drawn { show(.history) }
                if expand {
                    // The history's line opens; the canvas's node only when it is drawn.
                    if drawn { canvasOpen(id) }
                    expanded.insert(id)
                    if drawn { canvas.openDone = id }
                }
            }
        }
        if shows { reveal(node) }
    }

    /// A node picked from elsewhere (a banner, the away strip, Jev) drawn: its group shown if the chips left it out, its
    /// frame opened if folded, so what opens for it is seen and Esc folds what you see.
    private func uncover(_ node: String, store: Store) {
        let page = zones(store)
        guard let folder = RouterCanvasModel.make(page: page, done: canvasDone(store), muted: Set(store.agents.mutedFolders),
                                                  name: { $0 }, color: { _ in nil }, picked: [node], showsAll: true,
                                                  projectKey: { store.routerProjectGroupKey(sessionID: $0, folder: $1) },
                                                  projectSource: store.routerProjectGroupSource)
            .first(where: { $0.groups.contains { $0.items.contains { $0.id == node } } }),
              let group = folder.groups.first(where: { $0.items.contains { $0.id == node } })?.group else { return }
        // The chips say which groups show: its own does too.
        if !filter.shows(group) { filter.reveal(group) }
        if canvas.folded(folder) { canvas.folderFolds[folder.key] = folder.doneOnly ? false : nil }
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

/// The canvas over the whole Router page under its top bar: an infinite ground of dots you pan and zoom, the frames on it,
/// your messages and the composer floating at its foot.
struct RouterCanvas: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room over the content for the chips and buttons floating at the canvas's top.
    static let top: CGFloat = 56

    var body: some View {
        let canvas = model.canvas
        Group {
            if #available(macOS 26, *) {
                // Under the composer, which floats over it: the room for content ends where the composer starts (the
                // inset read before the canvas runs under it).
                GeometryReader { outer in
                    viewport(canvas, bottom: outer.safeAreaInsets.bottom).ignoresSafeArea(.container, edges: .bottom)
                }
            } else {
                viewport(canvas, bottom: 0)
            }
        }
        // A card picked (the keys, a banner, the away strip), a section asked for: the camera stays where you left it; a
        // marker on the viewport's edge points to the card if it is off the view. Opening a card, Jev's pick and a search
        // move nothing either.
        .onChange(of: model.revealRequest, initial: true) { _, request in
            guard let request, let taken = model.takeReveal(request, by: "canvas"),
                  let target = RouterCanvasModel.target(forReveal: taken.id, in: model.canvasFolders(store, page: page), folded: canvas.folded) else { return }
            canvas.point(to: target, label: model.canvasTitle(target, store: store, page: page))
        }
        .onChange(of: model.zoneRequest, initial: true) { _, request in
            guard let request, let taken = model.takeReveal(request, by: "canvasZone"),
                  let target = RouterCanvasModel.target(forReveal: taken.id, in: model.canvasFolders(store, page: page), folded: canvas.folded) else { return }
            canvas.point(to: target, label: model.canvasTitle(target, store: store, page: page))
        }
        .onDisappear { canvas.stopFlights() }
    }

    /// `bottom`: how much of its foot the composer covers.
    private func viewport(_ canvas: RouterCanvasState, bottom: CGFloat) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let top = max(Self.top, canvas.topRoom + 8)
            let free = CGRect(x: CanvasMetrics.pad, y: top, width: max(0, size.width - 2 * CanvasMetrics.pad),
                              height: max(0, size.height - bottom - top - CanvasMetrics.pad))
            ZStack(alignment: .topLeading) {
                CanvasGround(canvas: canvas, pan: canvas.pan)
                Color.clear
                    .overlay(alignment: .topLeading) {
                        CanvasContent(store: store, model: model, page: page)
                            .fixedSize()
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                canvas.contentSize = size
                                canvas.fitFirst()
                            }
                            .modifier(CameraTransform(camera: canvas.camera))
                    }
                CanvasEdgeMarker(canvas: canvas)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .background(CanvasEvents(canvas: canvas, bottomInset: bottom))
            .onChange(of: free, initial: true) { _, free in
                canvas.free = free
                canvas.fitFirst()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FlightSpace.name)) } action: { canvas.viewportFrame = $0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Router canvas")
        .accessibilityAction(named: "Fit everything") { canvas.fit(reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom in") { canvas.zoom(by: 1.25, reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom out") { canvas.zoom(by: 0.8, reduce: reduceMotion) }
    }
}

/// The frames on the ground, each where you put it or packed; read again only as what they show or where they are changes,
/// never as the camera moves or a frame is dragged.
struct CanvasContent: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage

    var body: some View {
        let canvas = model.canvas
        let folders = model.canvasFolders(store, page: page)
        let places = canvas.packedPlaces(folders)
        let order = Dictionary(canvas.stack.enumerated().map { ($0.element, Double($0.offset + 1)) }, uniquingKeysWith: max)
        CanvasBoard(places: folders.map { .init(origin: places[$0.key] ?? .zero, placed: canvas.positions[$0.key] != nil) }) {
            ForEach(folders) { folder in
                CanvasFolderFrame(folder: folder, store: store, model: model, page: page)
                    .modifier(CanvasLift(drag: canvas.drag, key: folder.key,
                                         order: order[folder.key] ?? 0))
            }
        }
        // Inside the camera's transform: a pan or a zoom moves nothing measured in it.
        .coordinateSpace(.named(Self.space))
        .onChange(of: places, initial: true) { _, places in canvas.preferred = places }
    }

    /// Where the nodes are measured (`RouterCanvasState.nodeRects`).
    static let space = "canvasContent"
}

/// A frame being dragged: lifted a little, over the others, where the pointer has taken it.
private struct CanvasLift: ViewModifier {
    let drag: CanvasFrameDrag
    let key: String
    /// Its place among the frames moved (0: never moved), the last moved on top.
    let order: Double

    func body(content: Content) -> some View {
        let lifted = drag.key == key
        content
            .offset(lifted ? drag.offset : .zero)
            .zIndex(lifted ? 100_000 : order)
    }
}

/// The camera's transform: the only view that reads it, with the ground's dots.
private struct CameraTransform: ViewModifier {
    let camera: CanvasCamera

    func body(content: Content) -> some View {
        let t = camera.transform
        content
            .scaleEffect(t.scale, anchor: .topLeading)
            .offset(x: t.origin.x, y: t.origin.y)
    }
}

/// On the viewport's edge, towards a node off the view: an arrow and its name; a click takes the camera there. Gone once the
/// node shows.
private struct CanvasEdgeMarker: View {
    let canvas: RouterCanvasState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let marker = canvas.marker, let rect = canvas.nodeRects[marker.node] ?? canvas.frameRects[marker.node] {
            let t = canvas.camera.transform
            let free = canvas.free
            let target = CGPoint(x: t.origin.x + rect.midX * t.scale, y: t.origin.y + rect.midY * t.scale)
            if !canvas.shows(rect), free.width > 80, free.height > 60 {
                let room = free.insetBy(dx: min(110, free.width / 4), dy: min(18, free.height / 4))
                let centre = CGPoint(x: free.midX, y: free.midY)
                let at = CanvasMetrics.edgePoint(from: centre, to: target, in: room)
                let angle = Angle(radians: atan2(target.y - centre.y, target.x - centre.x))
                Button { canvas.goToMarker(reduce: reduceMotion) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CDS.Fill.accent)
                            .rotationEffect(angle)
                        Text(marker.label).cdsText((12, 16), .regular, CDS.Text.primary).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 180, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .canvasFloat(radius: 13)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tip("Go to it", marker.label)
                .accessibilityLabel("Go to \(marker.label)")
                .position(at)
                .transition(.opacity)
            }
        }
    }
}

/// The canvas's ground: dots that go with the camera; a drag pans, a double-click fits, a right-click offers Fit and the
/// frames packed again.
private struct CanvasGround: View {
    let canvas: RouterCanvasState
    let pan: CanvasPan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CDS.Surface.s1
            CanvasDots(camera: canvas.camera)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { canvas.fit(reduce: reduceMotion) }
        .canvasPannable(pan)
        .contextMenu {
            Button("Fit Everything") { canvas.fit(reduce: reduceMotion) }
            Button("Reset Layout") { canvas.resetLayout(reduce: reduceMotion) }
                .disabled(canvas.positions.isEmpty)
        }
        .accessibilityHidden(true)
    }
}

/// The ground's dots, 24 apart in the content, as the camera shows them: further apart in the content as you zoom out, so
/// they never crowd.
private struct CanvasDots: View {
    let camera: CanvasCamera
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = camera.transform
        CanvasDotGrid(origin: t.origin, scale: t.scale)
            .fill(CDS.alpha(scheme == .dark ? 0.10 : 0.13))
            .allowsHitTesting(false)
    }
}

/// A dot every `step` points, in line with the content's origin: one path (shots draw it, as they draw no `Canvas`).
struct CanvasDotGrid: Shape {
    var origin: CGPoint
    var scale: CGFloat

    /// The dots' spacing in the content.
    static let spacing: CGFloat = 24
    /// The closest they come on screen.
    static let closest: CGFloat = 14

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(origin.x, origin.y), scale) }
        set {
            origin = CGPoint(x: newValue.first.first, y: newValue.first.second)
            scale = newValue.second
        }
    }

    /// The spacing on screen at `scale`: the content's 24, doubled until it is `closest` or more.
    static func step(_ scale: CGFloat) -> CGFloat {
        var step = spacing * max(0.01, scale)
        while step < closest { step *= 2 }
        return step
    }

    func path(in rect: CGRect) -> Path {
        let step = Self.step(scale)
        let r: CGFloat = 1
        func first(_ o: CGFloat, _ lo: CGFloat) -> CGFloat {
            let m = (o - lo).truncatingRemainder(dividingBy: step)
            return lo + (m < 0 ? m + step : m)
        }
        var path = Path()
        var y = first(origin.y, rect.minY)
        while y <= rect.maxY + r {
            var x = first(origin.x, rect.minX)
            while x <= rect.maxX + r {
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                x += step
            }
            y += step
        }
        return path
    }
}

/// A drag that pans the canvas, from its ground: in the window's points, whatever the zoom. Its start is kept by the drag's
/// own start, so a drag cancelled (with no end) leaves nothing for the next.
@MainActor
final class CanvasPan {
    let camera: CanvasCamera
    private var start: (at: CGPoint, origin: CGPoint)?

    init(camera: CanvasCamera) { self.camera = camera }

    var gesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { [self] drag in
                if self.start?.at != drag.startLocation { self.start = (drag.startLocation, camera.transform.origin) }
                let start = self.start?.origin ?? camera.transform.origin
                camera.moved = true
                camera.transform.origin = CGPoint(x: start.x + drag.translation.width, y: start.y + drag.translation.height)
            }
            .onEnded { [self] _ in start = nil }
    }
}

extension View {
    func canvasPannable(_ pan: CanvasPan) -> some View { gesture(pan.gesture) }
}

// MARK: - Floating controls

/// The canvas's chips, floating at its top left: one per group with something in it, its count, with Solo and Mute on each
/// and Clear after them (`RouterFilterRow`). A chip filters, in place: nothing folds or scrolls.
struct CanvasChips: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage

    var body: some View {
        // The sessions done that aren't live on the page, as the frames' Done groups hold them.
        let live = Set(page.needs.map(\.sessionID) + page.ready.map(\.sessionID) + page.notes.map(\.sessionID)
                       + page.waiting.map(\.sessionID) + page.working.map(\.id))
        let muted = Set(store.agents.mutedFolders)
        let done = model.canvasDone(store).count {
            !live.contains($0.sessionID) && !muted.contains($0.folder ?? "")
                && !muted.contains(store.routerProjectGroupKey(sessionID: $0.sessionID, folder: $0.folder ?? ""))
        }
        let counts = CanvasGroup.allCases.map { ($0, $0.zone.map(page.count) ?? done) }.filter { $0.1 > 0 }
        let calm = page.count(.needs) == 0 && !model.searching
        if !counts.isEmpty || calm {
            HStack(spacing: 8) {
                if !counts.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        RouterFilterRow(model: model, counts: counts, named: true, overview: overview)
                        RouterFilterRow(model: model, counts: counts, named: false, overview: overview)
                    }
                }
                // The list says it in its Needs you header; the canvas has none.
                if calm {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").font(.system(size: 10, weight: .medium))
                        Text("Nothing needs you").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                    }
                    .foregroundStyle(CDS.Text.muted)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(4)
            .canvasFloat()
        }
    }

    /// What the Working sessions are on, as Now's folded Working line says it.
    private var overview: String? { RouterOverviewLine.text(store.overviewItems(page.working, now: Date())) }
}

/// The canvas's buttons, floating at its top right: Summarize what's running, zoom out and in, Fit, Reset layout once a frame
/// was moved, and the history's panel with its unread.
struct CanvasControls: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 26

    var body: some View {
        let canvas = model.canvas
        let historyOpen = model.pane == .history
        HStack(spacing: 2) {
            if !page.working.isEmpty {
                let summarizer = model.summarizer
                SparklesButton(busy: !summarizer.batch.isEmpty, done: Set(page.working.map(\.id)).isSubset(of: summarizer.busy),
                               label: "Summarize what's running") { summarizer.requestAll(store: store) }
                divider
            }
            IconButton(symbol: "minus.magnifyingglass", help: "Zoom out", detail: "Pinch or ⌘-scroll", size: Self.size) {
                canvas.zoom(by: 0.8, reduce: reduceMotion)
            }
            IconButton(symbol: "plus.magnifyingglass", help: "Zoom in", detail: "Pinch or ⌘-scroll", size: Self.size) {
                canvas.zoom(by: 1.25, reduce: reduceMotion)
            }
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Fit everything", detail: "Double-click the canvas",
                       size: Self.size) {
                canvas.fit(reduce: reduceMotion)
            }
            if !canvas.positions.isEmpty {
                IconButton(symbol: "rectangle.3.group", help: "Reset layout", detail: "Packs the projects' frames again",
                           size: Self.size) {
                    canvas.resetLayout(reduce: reduceMotion)
                }
            }
            divider
            let unread = store.routerUnread.count
            IconButton(symbol: "clock.arrow.circlepath", help: historyOpen ? "Hide history" : "History",
                       label: unread > 0 ? "History, \(unread) unread" : "History", detail: "Esc closes it",
                       size: Self.size, active: historyOpen) {
                withAnimation(Motion.spatial.resolved(reduce: reduceMotion)) { model.show(historyOpen ? .now : .history) }
            }
            .flightTarget("pane:history")
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(CDS.sans(10, .semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(CDS.Fill.accent))
                        .offset(x: 5, y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(3)
        .canvasFloat()
    }

    private var divider: some View {
        Rectangle().fill(CDS.border).frame(width: CDS.hairline, height: 16).padding(.horizontal, 3)
    }
}

/// What floats over the canvas: the composer's ground (Regular glass on macOS 26 with glass chrome, else its raised
/// surface) in a rounded box, ringed, with the panels' shadow.
private struct CanvasFloat: ViewModifier {
    var radius: CGFloat = 10
    @Environment(Chrome.self) private var chrome: Chrome?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let glass: Bool = if #available(macOS 26, *) { chrome?.mode == .glass } else { false }
        content
            .modifier(ComposerMaterial(shape: shape, glass: glass, fill: CDS.Surface.s3))
            .overlay(shape.strokeBorder(glass ? .clear : CDS.border, lineWidth: 1))
            .shadow(color: glass ? .clear : CDS.PanelShadow.near.color.opacity(0.5), radius: CDS.PanelShadow.near.radius,
                    y: CDS.PanelShadow.near.y)
            .shadow(color: glass ? .clear : CDS.PanelShadow.far.color.opacity(0.35), radius: CDS.PanelShadow.far.radius,
                    y: CDS.PanelShadow.far.y)
    }
}

extension View {
    /// Floating over the canvas (`CanvasFloat`).
    func canvasFloat(radius: CGFloat = 10) -> some View { modifier(CanvasFloat(radius: radius)) }
}

// MARK: - Notices

/// What Now's list says over its sections, floating over the canvas under its chips: what came while you were away, the
/// Router at work, a search that found nothing, and chips that left nothing.
struct CanvasNotices: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage

    var body: some View {
        let empty = RouterZone.allCases.allSatisfy { page.count($0) == 0 }
        let nothing = model.searching && empty && model.canvasDone(store).isEmpty
        let away = store.routerAttention.strip?.line(store.routerShownCards) != nil
        let busy = store.routerDispatcher.isBusy
        // The chips left nothing to show (a search that did is said above).
        let filtered = !nothing && !model.filter.isClear && model.canvasFolders(store, page: page).allSatisfy { $0.shown.isEmpty }
        // The questions the Router asks back are over the composer, with the messages they hold (`FlightStack`).
        if away || busy || nothing || filtered {
            VStack(alignment: .leading, spacing: 6) {
                AwayStripView(store: store, model: model)
                if busy { RouterBusyLine(store: store) }
                if nothing { RouterNothingFound() }
                if filtered {
                    Text("Nothing matches · Esc to clear").cdsText((13, 18), .regular, CDS.Text.muted)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // As wide as what it says, a frame's width at most.
            .frame(maxWidth: away || nothing ? CanvasMetrics.frameWidth : nil, alignment: .leading)
            .fixedSize(horizontal: !(away || nothing), vertical: true)
            .canvasFloat()
        }
    }
}

// MARK: - Scroll and pinch

/// Two-finger scrolls and pinches over the canvas: a scroll pans, ⌘-scroll and a pinch zoom at the pointer. Each gesture is
/// the canvas's or not from its start to the end of its momentum, so a pan sliding a card under the pointer never turns
/// into a scroll of what is in the card.
private struct CanvasEvents: NSViewRepresentable {
    let canvas: RouterCanvasState
    /// The composer's room at the bottom: scrolls over it are its own.
    let bottomInset: CGFloat

    func makeNSView(context: Context) -> CanvasEventView {
        let view = CanvasEventView()
        view.canvas = canvas
        view.camera = canvas.camera
        view.bottomInset = bottomInset
        return view
    }

    func updateNSView(_ view: CanvasEventView, context: Context) {
        view.canvas = canvas
        view.camera = canvas.camera
        view.bottomInset = bottomInset
    }
}

final class CanvasEventView: NSView {
    var canvas: RouterCanvasState?
    var camera: CanvasCamera?
    /// The frame whose body the scroll under way moves, if it is one's.
    private var scrollingFrame: String?
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

    /// Whether what is under the event scrolls on its own: a scroll view inside the canvas with more than it shows.
    private func scrollsItself(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        return Self.scrolls(hit, inside: convert(bounds, to: nil))
    }

    /// Whether `view` or one of its enclosing views is a scroll view inside `area` (window coordinates) with more content
    /// than it shows. One as large as the area or larger is the page's, not a card's.
    static func scrolls(_ view: NSView?, inside area: NSRect) -> Bool {
        var view = view
        while let v = view {
            if let scroll = v as? NSScrollView, let document = scroll.documentView {
                let frame = scroll.convert(scroll.bounds, to: nil)
                if frame.width < area.width, frame.height < area.height, area.intersects(frame),
                   document.frame.height > scroll.contentView.bounds.height + 1 { return true }
            }
            view = v.superview
        }
        return false
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
            // Over something that scrolls itself (an open form or plan taller than its cap), the scroll is its own.
            // Over a frame you made shorter than what it holds, the scroll is its body's. Decided once per gesture.
            if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
                let at = point(event)
                claimed = at != nil && !scrollsItself(event)
                scrollingFrame = nil
                if claimed, let at, let canvas, !event.modifierFlags.contains(.command) {
                    let t = camera.transform
                    scrollingFrame = canvas.scrollingFrame(at: CGPoint(x: (at.x - t.origin.x) / t.scale, y: (at.y - t.origin.y) / t.scale))
                }
            }
            guard claimed else { return false }
            let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            let dx = event.scrollingDeltaX * k, dy = event.scrollingDeltaY * k
            if let frame = scrollingFrame, let canvas {
                canvas.scroll(frame).scroll(by: -dy / camera.transform.scale)
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled { claimed = false }
                return true
            }
            camera.moved = true
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
