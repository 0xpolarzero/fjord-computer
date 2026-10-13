import SwiftUI

// What the canvas draws (docs/design/spec/router-canvas.md §4): a frame for each project, its groups' labels joined by lines
// to the cards, and the cards themselves, the Router's own (`CardView`, `WaitingCard`, `WorkingCard`, `HistoryCardLine`),
// 420 wide.

// MARK: - Header anchors

private struct CanvasNodeIDKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// The canvas node a view is drawn in: its header line marks itself for the lines (`canvasHeader`). None off the canvas.
    var canvasNodeID: String? {
        get { self[CanvasNodeIDKey.self] }
        set { self[CanvasNodeIDKey.self] = newValue }
    }
}

/// Each node's header line, by its id: where its group's line meets it.
struct CanvasHeaders: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

private struct CanvasHeaderMark: ViewModifier {
    @Environment(\.canvasNodeID) private var id

    func body(content: Content) -> some View {
        if let id {
            content.anchorPreference(key: CanvasHeaders.self, value: .bounds) { [id: $0] }
        } else {
            content
        }
    }
}

extension View {
    /// A card's header line: on the canvas, where its group's line meets it; elsewhere nothing.
    func canvasHeader() -> some View { modifier(CanvasHeaderMark()) }
}

// MARK: - Frame

/// A project's frame: its name over its groups, each group's label at the left joined by a line to each of its cards. A
/// frame of finished sessions only folds to its name and how many, until you open it.
struct CanvasFolderFrame: View {
    let folder: CanvasFolder
    let store: Store
    let model: RouterModel
    let page: RouterPage
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folded: Bool { model.canvas.folded(folder) }

    var body: some View {
        let folded = self.folded
        let canvas = model.canvas
        let width = canvas.width(folder.key)
        let cardWidth = CanvasMetrics.cardWidth(frame: width)
        VStack(alignment: .leading, spacing: 0) {
            header(folded: folded)
            if !folded {
                if folder.groups.isEmpty {
                    Text("Nothing here").cdsText((12, 16), .regular, CDS.Text.muted)
                        .frame(height: 20).padding(.leading, CanvasMetrics.pad).padding(.bottom, CanvasMetrics.pad)
                } else {
                    CanvasFolderStack(width: cardWidth) {
                        ForEach(nodes) { node in
                            Group {
                                if let item = node.item {
                                    landed(node.id) {
                                        CanvasNode(item: item, store: store, model: model, page: page)
                                    }
                                } else {
                                    more(node)
                                }
                            }
                            .environment(\.canvasNodeID, node.id)
                            .environment(\.cdsColumnWidth, cardWidth)
                            .frame(width: cardWidth, alignment: .leading)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CanvasContent.space)) } action: { rect in
                                model.canvas.nodeRects[node.id] = rect
                            }
                            .canvasGroup(node.group)
                            // Left out by the chips: gone in place, its room kept, so nothing else moves.
                            .opacity(node.hidden ? 0 : 1)
                            .allowsHitTesting(!node.hidden)
                            .accessibilityHidden(node.hidden)
                            // Gone from the canvas: a reveal or a flight no longer goes where it was.
                            .onDisappear { model.canvas.nodeRects[node.id] = nil }
                            .transition(.scaleFade(0.97, reduce: reduceMotion))
                        }
                    }
                    .padding(.leading, CanvasMetrics.cardX)
                    .padding(.bottom, CanvasMetrics.pad)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        // As tall as you made it, or taller when what it holds is.
        .frame(minHeight: max(0, canvas.minHeight(folder.key)), alignment: .top)
        .motion(.spatial, value: nodes.map(\.id))
        .motion(.spatial, value: nodes.map(\.hidden))
        // Where a message for a session not drawn yet lands (RouterCanvasPending.swift).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CanvasContent.space)) } action: { rect in
            model.canvas.nodeRects[CanvasFolder.frameID(folder.key)] = CGRect(origin: rect.origin,
                                                                               size: CGSize(width: rect.width, height: CanvasMetrics.header))
            model.canvas.frameRects[folder.key] = rect
            model.canvas.fitFirst()
        }
        .onDisappear {
            model.canvas.nodeRects[CanvasFolder.frameID(folder.key)] = nil
            model.canvas.frameRects[folder.key] = nil
        }
        // The lines under the cards, on the frame's ground; the labels over it.
        .backgroundPreferenceValue(CanvasHeaders.self) { heads in
            ZStack(alignment: .topLeading) {
                let lifted = model.canvas.drag.key == folder.key
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // On the ground's dots, the frame's own ground: opaque, so the dots stop at its edge.
                    .fill(scheme == .dark ? CDS.Surface.s1 : CDS.Surface.s0)
                    .overlay { if scheme == .dark { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CDS.alpha(0.03)) } }
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
                    .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 18 : 0, y: lifted ? 10 : 0)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .gesture(moveGesture)
                if !folded {
                    GeometryReader { proxy in lines(heads, proxy) }.allowsHitTesting(false)
                }
            }
        }
        .overlayPreferenceValue(CanvasHeaders.self) { heads in
            if !folded {
                GeometryReader { proxy in labels(heads, proxy) }
            }
        }
        // The edges you resize it by: the right, the bottom, and their corner.
        .overlay { resizeHandles }
        // The frame's anchors stay in it.
        .transformPreference(CanvasHeaders.self) { $0 = [:] }
        .onChange(of: dragging) { _, now in
            // A drag the system cancelled (no end): the frame goes back, nothing stays lifted.
            guard !now else { return }
            DispatchQueue.main.async { model.canvas.cancelDrag(folder.key) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(folder.name), \(folder.sessions == 1 ? "1 session" : "\(folder.sessions) sessions")\(folded ? ", folded" : "")")
    }

    // MARK: Header

    /// The project's name, and at the end the fold's own button, the only way to fold or open the frame: a drag on the
    /// header moves the frame and never folds it.
    private func header(folded: Bool) -> some View {
        HStack(spacing: 6) {
            ProjectLabel(name: folder.name, color: folder.color)
                .cdsText((13, 18), .medium, folder.shown.isEmpty ? CDS.Text.muted : CDS.Text.primary).lineLimit(1)
                .help(folder.key.isEmpty ? "Chats with no project" : folder.key)
            if folded {
                Text("· \(folder.sessions) done").cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
            }
            Spacer(minLength: 0)
            IconButton(symbol: folded ? "chevron.right" : "chevron.down", help: folded ? "Unfold" : "Fold",
                       label: folded ? "Unfold \(folder.name)" : "Fold \(folder.name)", size: 22) {
                withAnimation(Motion.spatial.resolved(reduce: reduceMotion)) { model.canvas.toggleFold(folder) }
            }
        }
        .padding(.leading, CanvasMetrics.pad)
        .padding(.trailing, 10)
        .frame(height: CanvasMetrics.header)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Moving and resizing

    /// Whether a move or resize of this frame is under way (reset when the system ends it, dropped or cancelled).
    @GestureState private var dragging = false

    /// A drag from the frame's header or its own ground (never a card's): the frame follows the pointer 1:1 in the
    /// content's points, whatever the zoom, over the others, and stays exactly where it is dropped.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { drag in
                let canvas = model.canvas
                if canvas.drag.start?.at != drag.startLocation {
                    canvas.drag.start = (drag.startLocation, canvas.frameRects[folder.key]?.origin ?? .zero)
                }
                let scale = canvas.camera.transform.scale
                if canvas.drag.key != folder.key { canvas.drag.key = folder.key }
                canvas.drag.offset = CGSize(width: drag.translation.width / scale, height: drag.translation.height / scale)
            }
            .onEnded { drag in
                let scale = model.canvas.camera.transform.scale
                model.canvas.drop(folder.key, offset: CGSize(width: drag.translation.width / scale, height: drag.translation.height / scale))
            }
    }

    /// A drag on an edge: the frame's width (`width`), height (`height`) or both follow the pointer 1:1.
    private func resizeGesture(width: Bool, height: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { drag in
                let canvas = model.canvas
                if canvas.drag.resizeStart?.at != drag.startLocation {
                    let drawn = canvas.frameRects[folder.key]?.size ?? CGSize(width: canvas.width(folder.key), height: 0)
                    canvas.drag.resizeStart = (drag.startLocation, CGSize(width: drawn.width,
                                                                          height: height ? drawn.height : canvas.minHeight(folder.key)))
                }
                guard let start = canvas.drag.resizeStart?.size else { return }
                let scale = canvas.camera.transform.scale
                canvas.resize(folder.key, to: CanvasMetrics.resized(start, by: CGSize(width: drag.translation.width / scale,
                                                                                    height: drag.translation.height / scale),
                                                                    width: width, height: height))
            }
            .onEnded { _ in model.canvas.endResize(folder.key) }
    }

    private var resizeHandles: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            // The right edge.
            CanvasResizeEdge(cursor: .resizeLeftRight)
                .frame(width: 8)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 14)
                .offset(x: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .gesture(resizeGesture(width: true, height: false))
            // The bottom edge.
            CanvasResizeEdge(cursor: .resizeUpDown)
                .frame(height: 8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .offset(y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .gesture(resizeGesture(width: false, height: true))
            // The corner.
            CanvasResizeEdge(cursor: CanvasResizeEdge.corner)
                .frame(width: 16, height: 16)
                .offset(x: 4, y: 4)
                .gesture(resizeGesture(width: true, height: true))
        }
        .accessibilityHidden(true)
    }

    // MARK: Nodes

    /// A node of the frame: an item, or a group's "+n more"; hidden while the chips leave its group out.
    struct Node: Identifiable {
        let id: String
        let group: CanvasGroup
        var item: CanvasItem?
        var more = 0
        var hidden = false
    }

    private var nodes: [Node] {
        folder.groups.flatMap { g in
            g.items.map { Node(id: $0.id, group: g.group, item: $0, hidden: g.hidden) }
                + (g.more > 0 ? [Node(id: folder.moreID(g.group), group: g.group, more: g.more, hidden: g.hidden)] : [])
        }
    }

    /// A node with what you sent it: its ripple as the message lands, then "You: …" on its bottom edge for a few seconds,
    /// over the card rather than under it, so nothing below moves.
    @ViewBuilder private func landed(_ id: String, @ViewBuilder node: () -> some View) -> some View {
        let landing = model.canvas.landed[id]
        node()
            .overlay { if let landing { CanvasRipple(landing: landing, frozen: model.canvas.freezeFlight != nil) } }
            .overlay(alignment: .bottomTrailing) {
                if let landing {
                    // Astride the card's bottom edge, at its end: clear of its text and of the card under it.
                    CanvasLanded(landing: landing)
                        .offset(x: -12, y: 12)
                        .transition(.opacity)
                }
            }
            .motion(.spatial, value: landing)
    }

    private func more(_ node: Node) -> some View {
        CanvasMoreLine(count: node.more) {
            withAnimation(Motion.spatial.resolved(reduce: reduceMotion)) { model.canvas.showAll(node.group, in: folder) }
        }
        .canvasHeader()
    }

    /// Each group's label's box, centred on its nodes' header lines (in the frame's space).
    private func labelBoxes(_ heads: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> [(group: CanvasGroup, box: CGRect, heads: [CGRect])] {
        let byGroup = Dictionary(grouping: nodes, by: \.group)
        return folder.shown.compactMap { g in
            let rects = (byGroup[g.group] ?? []).compactMap { heads[$0.id].map { proxy[$0] } }
            guard !rects.isEmpty else { return nil }
            let mids = rects.map(\.midY)
            let centre = ((mids.min() ?? 0) + (mids.max() ?? 0)) / 2
            let width = CanvasGroupLabel.width(g.group)
            return (g.group, CGRect(x: CanvasMetrics.labelX, y: centre - CanvasMetrics.labelH / 2, width: width, height: CanvasMetrics.labelH),
                    rects)
        }
    }

    private func labels(_ heads: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(labelBoxes(heads, proxy), id: \.group) { label in
                CanvasGroupLabel(group: label.group, overview: label.group == .working ? overview : nil)
                    .frame(width: label.box.width, height: label.box.height, alignment: .leading)
                    .offset(x: label.box.minX, y: label.box.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lines(_ heads: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        let boxes = labelBoxes(heads, proxy)
        return ZStack(alignment: .topLeading) {
            ForEach(boxes, id: \.group) { label in
                Path { path in
                    for head in label.heads {
                        let line = CanvasMetrics.connector(label: label.box, header: CGRect(x: CanvasMetrics.cardX, y: head.minY,
                                                                                            width: head.width, height: head.height))
                        path.move(to: line.from)
                        path.addCurve(to: line.to, control1: line.c1, control2: line.c2)
                    }
                }
                .stroke(label.group == .needs ? CDS.Fill.warning.opacity(0.45) : CDS.alpha(scheme == .dark ? 0.14 : 0.22), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// What the Working group's sessions are on, as Now's folded Working line says it: its label's tip.
    private var overview: String? {
        let rows = folder.groups.first { $0.group == .working }?.items.compactMap { item -> AgentRow? in
            if case .working(let row) = item { return row } else { return nil }
        } ?? []
        let items = store.overviewItems(rows, now: Date())
        return RouterOverviewLine.text(items)
    }
}

// MARK: - Labels, lines

/// A group's name at the frame's left, its glyph in its tint; Needs you's warm and heavier. No count: its cards are.
struct CanvasGroupLabel: View {
    let group: CanvasGroup
    var overview: String? = nil

    /// Its width, shrunk to its name (at most `labelMax`): where its lines leave from.
    static func width(_ group: CanvasGroup) -> CGFloat {
        let font = CDS.nsSans(12, group == .needs ? .semibold : .medium)
        let text = (group.title as NSString).size(withAttributes: [.font: font]).width
        return min(CanvasMetrics.labelMax, ceil(16 + text + (group == .needs ? 2 : 0)))
    }

    var body: some View {
        HStack(spacing: 6) {
            CanvasGroupGlyph(group: group).frame(width: 11)
            Text(group.title)
                .cdsText((12, 16), group == .needs ? .semibold : .medium, group == .needs ? CDS.Text.warning : CDS.Text.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .help(overview ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An edge of a frame you resize it by: nothing drawn, the resize cursor while the pointer is on it.
struct CanvasResizeEdge: View {
    let cursor: NSCursor
    @State private var pushed = false

    /// The corner's: the system's diagonal one where there is one.
    static var corner: NSCursor {
        if #available(macOS 15, *) { return NSCursor.frameResize(position: .bottomRight, directions: .all) }
        return .crosshair
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, !pushed { cursor.push(); pushed = true }
                if !inside, pushed { NSCursor.pop(); pushed = false }
            }
            .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
    }
}

/// A group's glyph on the canvas: Working's is the app's animated logo (still with Reduce Motion), the others their
/// symbol.
struct CanvasGroupGlyph: View {
    let group: CanvasGroup
    var size: CGFloat = 10

    var body: some View {
        if group == .working {
            FjordLoader(color: group.tint, label: "Working").frame(width: size + 1, height: size + 1)
        } else {
            Image(systemName: group.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(group.tint)
        }
    }
}

/// "+n more" under a group: a click draws them all.
struct CanvasMoreLine: View {
    let count: Int
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("+\(count) more").cdsText((12, 16), .regular, hovered ? CDS.Text.secondary : CDS.Text.muted).monospacedDigit()
                .padding(.leading, 8)
                .frame(height: CanvasMetrics.moreH)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverMotion(hovered)
        .accessibilityLabel("\(count) more")
        .accessibilityHint("Shows them all")
    }
}

// MARK: - Nodes

/// One item, as Now's list draws it, at the card's width; the frame names the project.
struct CanvasNode: View {
    let item: CanvasItem
    let store: Store
    let model: RouterModel
    let page: RouterPage

    var body: some View {
        switch item {
        case .need(let card):
            CardView(store: store, model: model, card: card, expanded: model.expandedNeed == card.id,
                     form: store.pendingForm(for: card), project: store.routerProject(card), formCap: Self.formCap, showsProject: false)
        case .ready(let card), .waiting(let card):
            WaitingCard(store: store, card: card, standalone: true, open: openRow(item.id),
                        marked: model.selection == card.id || [card.id, item.id].contains(model.highlighted))
        case .note(let card):
            CardView(store: store, model: model, card: card, expanded: model.expandedNeed == card.id, form: nil,
                     project: store.routerProject(card), quiet: true, showsProject: false)
        case .working(let row):
            WorkingCard(store: store, model: model, row: row, summary: page.summaries[row.id],
                        unanswered: page.unanswered[row.id] ?? [], standalone: true, open: openRow(item.id))
        case .done(let card):
            // Open only as the canvas opened it: the history's line for the same card opens on its own.
            MinuteTicking { now in
                HistoryCardLine(card: card, now: now, open: model.canvas.openDone == card.id && model.expanded.contains(card.id),
                                marked: model.selection == card.id || model.highlighted == card.id, store: store, model: model)
            }
            // A box as the Working cards have, so its group's line meets an edge.
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CDS.alpha(0.03))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.border.opacity(0.7), lineWidth: 1) }
            }
        }
    }

    /// A Working or Waiting row's opening, the canvas's one open node (`RouterModel.canvasOpen`).
    private func openRow(_ id: String) -> Binding<Bool> {
        let model = model
        return Binding {
            model.canvas.openRow == id
        } set: { on in
            if on {
                model.canvasOpen(id)
                model.canvas.openRow = id
            } else if model.canvas.openRow == id {
                model.canvas.openRow = nil
            }
        }
    }

    /// The tallest an open form or plan gets on the canvas before it scrolls inside.
    static let formCap: CGFloat = 360
}
