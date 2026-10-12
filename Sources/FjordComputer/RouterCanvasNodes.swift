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
    let pan: CanvasPan
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folded: Bool { model.canvas.folded(folder) }

    var body: some View {
        let folded = self.folded
        VStack(alignment: .leading, spacing: 0) {
            header(folded: folded)
            if !folded {
                if folder.shown.isEmpty {
                    Text("Nothing here").cdsText((12, 16), .regular, CDS.Text.muted)
                        .frame(height: 20).padding(.leading, CanvasMetrics.pad).padding(.bottom, CanvasMetrics.pad)
                } else {
                    CanvasFolderStack {
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
                            .environment(\.cdsColumnWidth, CanvasMetrics.cardW)
                            .frame(width: CanvasMetrics.cardW, alignment: .leading)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CanvasContent.space)) } action: { rect in
                                model.canvas.nodeRects[node.id] = rect
                            }
                            .canvasGroup(node.group)
                            .transition(.scaleFade(0.97, reduce: reduceMotion))
                        }
                    }
                    .padding(.leading, CanvasMetrics.cardX)
                    .padding(.bottom, CanvasMetrics.pad)
                }
            }
        }
        .frame(width: CanvasMetrics.frameWidth, alignment: .leading)
        .motion(.spatial, value: nodes.map(\.id))
        // Where a message for a session not drawn yet lands (RouterCanvasPending.swift).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CanvasContent.space)) } action: { rect in
            model.canvas.nodeRects[CanvasFolder.frameID(folder.key)] = CGRect(origin: rect.origin,
                                                                               size: CGSize(width: rect.width, height: CanvasMetrics.header))
        }
        // The lines under the cards, on the frame's ground; the labels over it.
        .backgroundPreferenceValue(CanvasHeaders.self) { heads in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(scheme == .dark ? CDS.alpha(0.03) : CDS.Surface.s0)
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
                    .canvasPannable(pan)
                if !folded {
                    GeometryReader { proxy in lines(heads, proxy) }
                }
            }
        }
        .overlayPreferenceValue(CanvasHeaders.self) { heads in
            if !folded {
                GeometryReader { proxy in labels(heads, proxy) }
            }
        }
        // The frame's anchors stay in it.
        .transformPreference(CanvasHeaders.self) { $0 = [:] }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(folder.name), \(folder.sessions == 1 ? "1 session" : "\(folder.sessions) sessions")\(folded ? ", folded" : "")")
    }

    // MARK: Header

    @ViewBuilder private func header(folded: Bool) -> some View {
        let line = HStack(spacing: 6) {
            ProjectLabel(name: folder.name, color: folder.color)
                .cdsText((13, 18), .medium, folder.shown.isEmpty ? CDS.Text.muted : CDS.Text.primary).lineLimit(1)
            if folded {
                let done = folder.sessions
                Text("· \(done) done").cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CanvasMetrics.pad)
        .frame(height: CanvasMetrics.header)
        .contentShape(Rectangle())
        if folder.doneOnly {
            Button {
                withAnimation(Motion.spatial.resolved(reduce: reduceMotion)) { model.canvas.toggleFold(folder) }
            } label: { line }
                .buttonStyle(.plain)
                .help(folder.key.isEmpty ? (folded ? "Show what was done" : "Fold") : folder.key)
                .accessibilityLabel(folder.name)
                .accessibilityValue(folded ? "Folded, \(folder.sessions) done" : "Open")
                .accessibilityHint(folded ? "Shows what was done" : "Folds it")
        } else {
            line.help(folder.key.isEmpty ? "Chats with no project" : folder.key)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Nodes

    /// A node of the frame: an item, or a group's "+n more".
    struct Node: Identifiable {
        let id: String
        let group: CanvasGroup
        var item: CanvasItem?
        var more = 0
    }

    private var nodes: [Node] {
        folder.shown.flatMap { g in
            g.items.map { Node(id: $0.id, group: g.group, item: $0) } + (g.more > 0 ? [Node(id: folder.moreID(g.group), group: g.group, more: g.more)] : [])
        }
    }

    /// A node with what you sent it: its ripple as the message lands, then "You: …" under it for a few seconds.
    @ViewBuilder private func landed(_ id: String, @ViewBuilder node: () -> some View) -> some View {
        let landing = model.canvas.landed[id]
        VStack(alignment: .leading, spacing: 2) {
            node().overlay { if let landing { CanvasRipple(landing: landing, frozen: model.canvas.freezeFlight != nil) } }
            if let landing {
                CanvasLanded(landing: landing).transition(.opacity)
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
                .stroke(label.group == .needs ? CDS.Fill.warning.opacity(0.45) : CDS.alpha(0.14), lineWidth: 1)
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
            Image(systemName: group.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(group.tint).frame(width: 10)
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
            WaitingCard(store: store, card: card, standalone: true, open: openRow(item.id))
        case .note(let card):
            CardView(store: store, model: model, card: card, expanded: model.expandedNeed == card.id, form: nil,
                     project: store.routerProject(card), quiet: true, showsProject: false)
        case .working(let row):
            WorkingCard(store: store, model: model, row: row, summary: page.summaries[row.id],
                        unanswered: page.unanswered[row.id] ?? [], standalone: true, open: openRow(item.id))
        case .done(let card):
            MinuteTicking { now in
                HistoryCardLine(card: card, now: now, open: model.expanded.contains(card.id),
                                marked: model.selection == card.id || model.highlighted == card.id, store: store, model: model)
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
