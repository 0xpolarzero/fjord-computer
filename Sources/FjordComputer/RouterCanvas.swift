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
    /// The drag that pans it: one for the canvas's life, so a redraw in the middle of a drag doesn't start it again.
    let pan: CanvasPan
    /// The frames' columns: as many as the viewport holds (`CanvasMetrics.columns(width:)`), changed only as it is resized.
    var columns = 1
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
    /// The Working or Waiting row open on the canvas (its node's id). A card of Needs you or Worth a look open is
    /// `RouterModel.expandedNeed`, a Done line `openDone` (in `RouterModel.expanded`, as the history's lines): one at a time.
    var openRow: String?
    var openDone: String?
    /// Each node's box in the content, as last laid out (its frame's columns, its open height): what a reveal goes to.
    @ObservationIgnored var nodeRects: [String: CGRect] = [:]
    /// The reveal under way, so a newer one replaces it.
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    /// When the first look was taken: it follows the content as it settles (the cards measured, the column sized) for a
    /// moment, unless you move it.
    @ObservationIgnored var firstFit: Date?
    /// The viewport's room for content, and the content's size, as last laid out: what Fit and a reveal go by.
    @ObservationIgnored var free: CGRect = .zero
    @ObservationIgnored var contentSize: CGSize = .zero
    /// Each session's newest addressed card, for the search's words and the history's revision (`Done`).
    @ObservationIgnored var doneMemo: (query: String, revision: Int, cards: [RouterCard])?
    @ObservationIgnored private let defaults: UserDefaults?

    // Your messages on their way (RouterCanvasPending.swift).
    /// Your messages seen settled, or settled when the canvas came: those that flew, or never will. Nil while it is away.
    @ObservationIgnored var settled: Set<UUID>?
    /// Each pending line's box in the Router's space (`RouterMain.space`), kept after it goes: where its flight leaves from.
    @ObservationIgnored var pendingFrames: [UUID: CGRect] = [:]
    /// The composer's box, and the canvas's viewport, in the same space: where a message with no line leaves from, and how
    /// a node's box in the content is found in the window.
    /// Read by the pending area too, which keeps over the canvas (the composer is the page's, as wide as both columns).
    var composerFrame: CGRect = .zero
    var viewportFrame: CGRect = .zero
    /// A narrow window's switch to the history for an answer of the Router's, under way.
    @ObservationIgnored var historyTask: Task<Void, Never>?
    /// The plan Esc went Back out of on the canvas: the next Esc folds it rather than going into revise again.
    @ObservationIgnored var backedOutOf: String?
    /// The messages in the air.
    var flights: [CanvasFlight] = []
    /// What landed on a node, by its id: its ripple and "You: …" under it, for a few seconds.
    var landed: [String: CanvasLanding] = [:]
    @ObservationIgnored private var landingTasks: [String: Task<Void, Never>] = [:]
    /// Shots: every flight held at this point of its arc, and what landed kept.
    @ObservationIgnored var freezeFlight: CGFloat?

    static let foldsKey = "routerCanvasFolds"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        pan = CanvasPan(camera: camera)
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

    /// The first look: everything if it reads (at 0.6 or more), else the columns' tops, as wide as the room shows them.
    func fitFirst() {
        guard !camera.moved, contentSize.width > 0, free.width > 0 else { return }
        let now = Date()
        if let firstFit, now.timeIntervalSince(firstFit) > 1.5 { return }
        if firstFit == nil { firstFit = now }
        let all = CanvasTransform.fit(CGRect(origin: .zero, size: contentSize), in: free)
        guard all.scale < 0.6 else {
            camera.transform = all
            return
        }
        let scale = CanvasTransform.clamp(min(1, free.width / contentSize.width))
        camera.transform = CanvasTransform(origin: CGPoint(x: free.midX - contentSize.width * scale / 2, y: free.minY), scale: scale)
    }

    /// What it shows changed (a search): the first look is taken again, as the content settles.
    func refit() {
        camera.moved = false
        firstFit = nil
        fitFirst()
    }

    /// A chip: only its group shown (with the others lit), or, lit, not.
    func toggleFilter(_ group: CanvasGroup) {
        if filter.contains(group) { filter.remove(group) } else { filter.insert(group) }
    }

    /// The camera moved the least that shows the node, once it is laid out (opened, its frame grown): its top at the
    /// room's top when it is taller than the room.
    func bringIntoView(_ id: String, reduce: Bool) {
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            // A few layout passes: what opened for it is measured first.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, !Task.isCancelled else { return }
                guard let rect = self.nodeRects[id], self.free.width > 0 else { continue }
                self.camera.moved = true
                guard let next = self.camera.transform.origin(toShow: rect.insetBy(dx: -8, dy: -8), in: self.free) else { return }
                withAnimation(Motion.spatial.resolved(reduce: reduce)) { self.camera.transform.origin = next }
                return
            }
        }
    }

    /// The camera moved the least that shows `rect` (content space), at once: where it goes, so a flight lands where the
    /// node will be.
    @discardableResult
    func show(_ rect: CGRect, reduce: Bool) -> CanvasTransform {
        revealTask?.cancel()
        guard free.width > 0, let next = camera.transform.origin(toShow: rect.insetBy(dx: -8, dy: -8), in: free) else {
            return camera.transform
        }
        camera.moved = true
        withAnimation(Motion.spatial.resolved(reduce: reduce)) { camera.transform.origin = next }
        return camera.transform
    }

    /// Lands a message on a node: its ripple and "You: …" for `CanvasLanding.shown`, then gone (kept in shots).
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
        historyTask?.cancel()
        historyTask = nil
        if freezeFlight == nil {
            flights = []
            landed = [:]
        }
        settled = nil
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
        // Not Jev's highlight: it moves as you type, and the group would widen and narrow under you.
        let picked = Set([selection, expandedNeed].compactMap { $0 })
        return RouterCanvasModel.make(page: page, done: canvasDone(store), muted: Set(store.agents.mutedFolders),
                                      name: store.folderName, color: store.projectColor, filter: canvas.filter,
                                      picked: picked, expanded: canvas.expandedMore, showsAll: searching)
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
                                                  name: { $0 }, color: { _ in nil }, picked: [node], showsAll: true)
            .first(where: { $0.groups.contains { $0.items.contains { $0.id == node } } }),
              let group = folder.groups.first(where: { $0.items.contains { $0.id == node } })?.group else { return }
        // The chips light the groups shown: its own lit with them.
        if !canvas.filter.isEmpty, !canvas.filter.contains(group) { canvas.filter.insert(group) }
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

struct RouterCanvas: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    /// Now and History one at a time: an answer of the Router's shows the history once its message has gone.
    var narrow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let canvas = model.canvas
        VStack(alignment: .leading, spacing: 0) {
            CanvasNotices(store: store, model: model, page: page)
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
        // A card picked (the keys, a banner, the away strip), a section asked for, Jev's pick for the draft, a node opened:
        // the canvas goes there, the least that shows it.
        .onChange(of: model.revealRequest, initial: true) { _, request in
            guard let request, let taken = model.takeReveal(request, by: "canvas"),
                  let target = RouterCanvasModel.target(forReveal: taken.id, in: model.canvasFolders(store, page: page), folded: canvas.folded) else { return }
            canvas.bringIntoView(target, reduce: reduceMotion)
        }
        .onChange(of: model.zoneRequest, initial: true) { _, request in
            guard let request, let taken = model.takeReveal(request, by: "canvasZone"),
                  let target = RouterCanvasModel.target(forReveal: taken.id, in: model.canvasFolders(store, page: page), folded: canvas.folded) else { return }
            canvas.bringIntoView(target, reduce: reduceMotion)
        }
        .onChange(of: model.highlighted) { _, id in
            // A reveal marks what it goes to too: it pans once.
            guard let id, id != model.revealRequest?.id, let target = RouterCanvasModel.target(forReveal: id, in: model.canvasFolders(store, page: page), folded: canvas.folded) else { return }
            canvas.bringIntoView(target, reduce: reduceMotion)
        }
        .onChange(of: [model.expandedNeed, canvas.openRow, canvas.openDone]) { _, open in
            guard let id = open.compactMap({ $0 }).first else { return }
            canvas.bringIntoView(id, reduce: reduceMotion)
        }
        // A search changes what the frames hold: the first look is taken again, so what it found shows.
        .onChange(of: model.search.query) { canvas.refit() }
        // A message of yours settled: it flies to its card (RouterCanvasPending.swift).
        .onChange(of: store.routerRevision, initial: true) {
            canvas.depart(store: store, model: model, page: page, narrow: narrow, reduce: reduceMotion)
        }
        .onDisappear { canvas.stopFlights() }
    }

    /// `bottom`: how much of its foot the composer covers.
    private func viewport(_ canvas: RouterCanvasState, bottom: CGFloat) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let free = CGRect(x: CanvasMetrics.pad, y: CanvasMetrics.pad, width: max(0, size.width - 2 * CanvasMetrics.pad),
                              height: max(0, size.height - bottom - 2 * CanvasMetrics.pad))
            ZStack(alignment: .topLeading) {
                CanvasGround(canvas: canvas, pan: canvas.pan)
                Color.clear
                    .overlay(alignment: .topLeading) {
                        CanvasContent(store: store, model: model, page: page, pan: canvas.pan)
                            .fixedSize()
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                canvas.contentSize = size
                                canvas.fitFirst()
                            }
                            .modifier(CameraTransform(camera: canvas.camera))
                    }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // What passes under the bar over it fades in rather than being cut.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                    Color.black
                }
            }
            .clipped()
            .background(CanvasEvents(camera: canvas.camera, bottomInset: bottom))
            .onChange(of: free, initial: true) { _, free in
                canvas.free = free
                let columns = CanvasMetrics.columns(width: free.width)
                if canvas.columns != columns { canvas.columns = columns }
                canvas.fitFirst()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RouterMain.space)) } action: { canvas.viewportFrame = $0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Router canvas")
        .accessibilityAction(named: "Fit everything") { canvas.fit(reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom in") { canvas.zoom(by: 1.25, reduce: reduceMotion) }
        .accessibilityAction(named: "Zoom out") { canvas.zoom(by: 0.8, reduce: reduceMotion) }
    }
}

/// The frames, in their columns; read again only as what they show changes, never as the camera moves.
struct CanvasContent: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let pan: CanvasPan

    var body: some View {
        let folders = model.canvasFolders(store, page: page)
        let count = model.canvas.columns
        let columns = CanvasMetrics.columns(closed: folders.map { CanvasMetrics.closedHeight($0, folded: model.canvas.folded($0)) },
                                            count: count)
        let column = Dictionary(zip(folders.map(\.id), columns), uniquingKeysWith: { a, _ in a })
        CanvasMasonry(columns: count) {
            ForEach(folders) { folder in
                CanvasFolderFrame(folder: folder, store: store, model: model, page: page, pan: pan)
                    .canvasColumn(column[folder.id] ?? 0)
            }
        }
        // Inside the camera's transform: a pan or a zoom moves nothing measured in it.
        .coordinateSpace(.named(Self.space))
    }

    /// Where the nodes are measured (`RouterCanvasState.nodeRects`).
    static let space = "canvasContent"
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

/// A drag that pans the canvas, from its ground or a frame's: in the window's points, whatever the zoom. Its start is kept
/// by the drag's own start, so a drag cancelled (with no end) leaves nothing for the next.
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

// MARK: - Bar

/// The canvas's chips, over it in Now's bar: one per group with something in it, its count, lit while the canvas shows only
/// the lit groups (none lit: all); then Summarize what's running and Fit at the column's end. A chip filters, in place:
/// nothing folds or scrolls.
struct CanvasBar: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    /// Beside the switch: the groups' names go first when there's no room for them.
    var compact = false
    /// The column's margin (`routerGutter`).
    let gutter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The sessions done that aren't live on the page, as the frames' Done groups hold them.
        let live = Set(page.needs.map(\.sessionID) + page.ready.map(\.sessionID) + page.notes.map(\.sessionID)
                       + page.waiting.map(\.sessionID) + page.working.map(\.id))
        let muted = Set(store.agents.mutedFolders)
        let done = model.canvasDone(store).count { !live.contains($0.sessionID) && !muted.contains($0.folder ?? "") }
        let counts = CanvasGroup.allCases.map { ($0, $0.zone.map(page.count) ?? done) }.filter { $0.1 > 0 }
        HStack(spacing: 12) {
            if !counts.isEmpty {
                ViewThatFits(in: .horizontal) {
                    row(counts, named: true)
                    row(counts, named: false)
                }
            }
            // The list says it in its Needs you header; the canvas has none.
            if page.count(.needs) == 0, !model.searching {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").font(.system(size: 10, weight: .medium))
                    Text("Nothing needs you").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                }
                .foregroundStyle(CDS.Text.muted)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if !page.working.isEmpty {
                    let summarizer = model.summarizer
                    SparklesButton(busy: !summarizer.batch.isEmpty, done: Set(page.working.map(\.id)).isSubset(of: summarizer.busy),
                                   label: "Summarize what's running") { summarizer.requestAll(store: store) }
                }
                CanvasFitButton { model.canvas.fit(reduce: reduceMotion) }
            }
        }
        .padding(.leading, compact ? 0 : gutter)
        .padding(.trailing, gutter)
    }

    private func row(_ counts: [(CanvasGroup, Int)], named: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(counts, id: \.0) { group, count in
                CanvasChip(group: group, count: count, named: named, lit: model.canvas.filter.contains(group),
                           overview: group == .working ? overview : nil) {
                    withAnimation(Motion.spatial.resolved(reduce: reduceMotion)) { model.canvas.toggleFilter(group) }
                }
            }
        }
        .fixedSize()
    }

    /// What the Working sessions are on, as Now's folded Working line says it.
    private var overview: String? { RouterOverviewLine.text(store.overviewItems(page.working, now: Date())) }
}

/// A group's chip on the canvas: the look of Now's section chips (`ZoneChip`), lit while the canvas shows only it (and the
/// others lit).
struct CanvasChip: View {
    let group: CanvasGroup
    let count: Int
    let named: Bool
    let lit: Bool
    var overview: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: group.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(group.tint)
                if named { Text(group.title).cdsText((12, 16), .regular, hovered || lit ? CDS.Text.primary : CDS.Text.secondary) }
                Text("\(count)").cdsText((12, 16), .medium, group == .needs ? CDS.Fill.warning : CDS.Text.muted).monospacedDigit()
            }
            .padding(.horizontal, 7)
            .frame(height: ZoneChip.height)
            .background(Capsule().fill(lit ? CDS.Fill.secondary : hovered ? CDS.Fill.ghostHover : CDS.alpha(0.04)))
            .overlay { if lit { Capsule().strokeBorder(CDS.border, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(overview ?? (lit ? "Show it with the rest" : "Show only \(group.title)"))
        .accessibilityLabel("\(group.title), \(count)")
        .accessibilityValue(lit ? "Shown only" : "")
        .accessibilityAddTraits(lit ? .isSelected : [])
        .accessibilityHint(lit ? "Shows everything again" : "Shows only it on the canvas")
    }
}

/// Fit: everything on the canvas in view, as a double-click on its ground does.
struct CanvasFitButton: View {
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovered ? CDS.Text.secondary : CDS.Text.muted)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovered = $0 }
        .tip("Fit everything", "Double-click the canvas", focused: focused)
        .accessibilityLabel("Fit everything")
    }
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
        // The chips left nothing to show (a search that did is said above).
        let filtered = !nothing && !model.canvas.filter.isEmpty && model.canvasFolders(store, page: page).allSatisfy { $0.shown.isEmpty }
        // The questions the Router asks back are over the composer, with the messages they hold (`RouterPendingStack`).
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
            if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
                claimed = point(event) != nil && !scrollsItself(event)
            }
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
