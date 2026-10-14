import SwiftUI

// The Brief (a prototype): Now written as prose by an agent. On top, what's for you and what's worth a look, in a few plain
// sentences; under it a paragraph per project saying where it stands. The parts that point at a session are tags the
// agent writes in the text, `<need s="…">`, `<look s="…">` and `<run s="…">`; the page draws them as highlights. Hovering
// one shows its card over the text, clicking opens the card under the paragraph and points the composer at it, so you
// answer as you do a card's. Whenever something comes in, an agent rereads the brief and rewrites what changed (not in this
// prototype: the demo's text is written by hand).

/// What the agent wrote: the lead's two parts and a paragraph per project, in the order it chose (which stays put).
struct RouterDigest: Equatable {
    struct Project: Equatable, Identifiable {
        /// The project's folder, as the canvas keys it.
        let folder: String
        let text: String
        var id: String { folder }
    }

    /// What needs you, in a few sentences.
    var forYou: String
    /// What's worth a look, in a sentence or two (empty: none).
    var worthALook: String
    var projects: [Project]
    var at: Date
}

/// The text with its tags read out.
enum DigestMarkup {
    enum Kind: String {
        case need, look, run

        var tint: Color {
            switch self {
            case .need: RouterZone.needs.tint
            case .look: CDS.Text.accent
            case .run: CDS.Text.muted
            }
        }
    }

    enum Piece: Equatable {
        case text(String)
        case span(Kind, session: String, text: String)
    }

    // swiftlint:disable:next force_try
    nonisolated(unsafe) private static let tag = try! Regex(#"<(need|look|run)\s+s="([^"]+)">(.*?)</\1>"#,
                                                            as: (Substring, Substring, Substring, Substring).self)

    /// The pieces in order; a tag it doesn't know, or one left open, is read as its text.
    static func parse(_ markup: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(markup)
        while let match = rest.firstMatch(of: tag) {
            let before = rest[rest.startIndex..<match.range.lowerBound]
            if !before.isEmpty { pieces.append(.text(String(before))) }
            if let kind = Kind(rawValue: String(match.output.1)) {
                pieces.append(.span(kind, session: String(match.output.2), text: String(match.output.3)))
            } else {
                pieces.append(.text(String(match.output.3)))
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { pieces.append(.text(String(rest))) }
        return pieces
    }
}

/// What the Brief keeps while the window lives: the highlight under the pointer and the card opened.
@Observable final class RouterDigestState {
    /// "paragraph#session" under the pointer.
    var hovered: String?
    /// "paragraph#session" opened under its paragraph.
    var open: String?
    /// With the margin: the session whose highlight or card is under the pointer (both light up).
    var hoverSession: String?
    /// Where each highlight ("paragraph#session") sits down the page, which its card in the margin lines up with.
    var anchors: [String: CGFloat] = [:]
}

// MARK: - Page

struct DigestPage: View {
    let store: Store
    let model: RouterModel

    static let column: CGFloat = 720
    /// With the margin: the text's width, the gap, and the cards' column.
    static let text: CGFloat = 600
    static let gap: CGFloat = 32
    static let marginWidth: CGFloat = 500
    static let space = "digest"

    var body: some View {
        let page = model.zones(store)
        let folders = model.canvasFolders(store, page: page)
        let items = Self.items(folders)
        GeometryReader { geometry in
            // The cards in a margin beside the text, as a document's comments, when there's room; else each opens under
            // its paragraph.
            let margin = geometry.size.width >= Self.text + Self.gap + Self.marginWidth + 64
            Scrolling {
                if let digest = store.routerDigest {
                    HStack(alignment: .top, spacing: Self.gap) {
                        text(digest, folders: folders, items: items, page: page, margin: margin)
                            .frame(width: margin ? Self.text : nil)
                            .frame(maxWidth: margin ? Self.text : Self.column, alignment: .leading)
                        if margin {
                            DigestMargin(store: store, model: model, page: page, items: items, digest: digest)
                                .frame(width: Self.marginWidth, alignment: .topLeading)
                        }
                    }
                    .coordinateSpace(.named(Self.space))
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, LaneMetrics.bottom)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func text(_ digest: RouterDigest, folders: [CanvasFolder], items: [String: CanvasItem], page: RouterPage,
                      margin: Bool) -> some View {
                VStack(alignment: .leading, spacing: 28) {
                    lead(digest, items: items, page: page, margin: margin)
                    ForEach(digest.projects) { project in
                        let folder = folders.first { $0.key == project.folder }
                        DigestParagraph(store: store, model: model, page: page, items: items, key: project.folder,
                                        markup: project.text, margin: margin) {
                            HStack(spacing: 7) {
                                Circle().fill(folder?.color ?? CDS.Text.muted).frame(width: 8, height: 8)
                                Text(folder?.name ?? (project.folder as NSString).lastPathComponent)
                                    .font(CDS.sans(13, .semibold)).foregroundStyle(CDS.Text.primary)
                            }
                        }
                        .zIndex(model.digest.hovered?.hasPrefix(project.folder + "#") == true ? 1 : 0)
                    }
                }
    }

    /// The lead: what's for you, then what's worth a look, each under its name in its colour.
    private func lead(_ digest: RouterDigest, items: [String: CanvasItem], page: RouterPage, margin: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Brief").font(CDS.sans(20, .semibold)).foregroundStyle(CDS.Text.primary)
                Spacer()
                Text("updated " + agoPhrase(digest.at)).font(CDS.sans(12)).foregroundStyle(CDS.Text.muted)
            }
            DigestParagraph(store: store, model: model, page: page, items: items, key: "lead-you", markup: digest.forYou,
                            size: 16, margin: margin) {
                Label("For you", systemImage: RouterZone.needs.symbol)
                    .font(CDS.sans(12, .semibold)).foregroundStyle(RouterZone.needs.tint)
            }
            .zIndex(model.digest.hovered?.hasPrefix("lead-you#") == true ? 2 : 1)
            if !digest.worthALook.isEmpty {
                DigestParagraph(store: store, model: model, page: page, items: items, key: "lead-look",
                                markup: digest.worthALook, size: 16, margin: margin) {
                    Label("Worth a look", systemImage: RouterZone.notes.symbol)
                        .font(CDS.sans(12, .semibold)).foregroundStyle(CDS.Text.accent)
                }
                .zIndex(model.digest.hovered?.hasPrefix("lead-look#") == true ? 2 : 0)
            }
            Rectangle().fill(CDS.border).frame(height: CDS.hairline).padding(.top, 4)
        }
        .zIndex(model.digest.hovered?.hasPrefix("lead-") == true ? 2 : 0)
    }

    /// Each session's item on the page: what it is waiting on you for first, else what it is doing.
    static func items(_ folders: [CanvasFolder]) -> [String: CanvasItem] {
        var out: [String: CanvasItem] = [:]
        func rank(_ item: CanvasItem) -> Int {
            switch item {
            case .need, .ready: 0
            case .note: 1
            case .waiting: 2
            case .working: 3
            case .done: 4
            }
        }
        for item in folders.flatMap({ $0.groups.flatMap(\.items) }) {
            if let had = out[item.sessionID], rank(had) <= rank(item) { continue }
            out[item.sessionID] = item
        }
        return out
    }
}

/// A paragraph of the brief: its name over it, the text with its highlights, and the card opened from it under it.
private struct DigestParagraph<Title: View>: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let items: [String: CanvasItem]
    let key: String
    let markup: String
    var size: CGFloat = 15
    /// The cards are in the margin: none opens under the paragraph.
    var margin = false
    @ViewBuilder let title: Title

    var body: some View {
        let state = model.digest
        let opened = state.open.flatMap { $0.hasPrefix(key + "#") ? String($0.dropFirst(key.count + 1)) : nil }
        VStack(alignment: .leading, spacing: 8) {
            title
            DigestFlow(spacing: size * 0.27, lineSpacing: 5) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    switch token {
                    case .word(let word, let tight):
                        Text(word).font(CDS.sans(size)).foregroundStyle(CDS.Text.secondary)
                            .layoutValue(key: TightKey.self, value: tight)
                    case .span(let kind, let session, let text, let tight):
                        DigestSpan(store: store, model: model, page: page, item: items[session], kind: kind,
                                   id: key + "#" + session, session: session, text: text, size: size, margin: margin)
                            .layoutValue(key: TightKey.self, value: tight)
                            .zIndex(state.hovered == key + "#" + session ? 1 : 0)
                    }
                }
            }
            if !margin, let opened, let item = items[opened] {
                HStack(alignment: .top, spacing: 8) {
                    CanvasNode(item: item, store: store, model: model, page: page)
                        .frame(maxWidth: 560, alignment: .leading)
                    Button {
                        withAnimation(Motion.spatial.resolved(reduce: false)) { state.open = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(CDS.Text.muted)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(CDS.alpha(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close the card")
                    .padding(.top, 6)
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private enum Token {
        case word(String, tight: Bool)
        case span(DigestMarkup.Kind, session: String, text: String, tight: Bool)
    }

    /// The text cut into words and highlights; a word that follows a highlight without a space (its comma) sits against it.
    private var tokens: [Token] {
        var out: [Token] = []
        var glued = false
        for piece in DigestMarkup.parse(markup) {
            switch piece {
            case .text(let text):
                let startsTight = !(text.first?.isWhitespace ?? true)
                let words = text.split(whereSeparator: \.isWhitespace)
                for (i, word) in words.enumerated() {
                    out.append(.word(String(word), tight: i == 0 && startsTight && glued))
                }
                glued = !(text.last?.isWhitespace ?? true)
            case .span(let kind, let session, let text):
                out.append(.span(kind, session: session, text: text, tight: glued))
                glued = true
            }
        }
        return out
    }
}


/// A highlight: its words in its colour on a soft ground. With the margin, its card is beside it: hovering either lights
/// both, clicking opens the card there. Without, its card floats under it while hovered and opens under the paragraph.
/// Clicked, the composer answers it.
private struct DigestSpan: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let item: CanvasItem?
    let kind: DigestMarkup.Kind
    let id: String
    let session: String
    let text: String
    let size: CGFloat
    let margin: Bool

    var body: some View {
        let state = model.digest
        let hovered = margin ? state.hoverSession == session : state.hovered == id
        let open = margin ? item.flatMap(DigestMargin.cardID) == model.selection && model.selection != nil : state.open == id
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button {
            withAnimation(Motion.spatial.resolved(reduce: false)) {
                if margin {
                    DigestMargin.toggle(item, model: model, store: store)
                } else {
                    state.open = open ? nil : id
                    state.hovered = nil
                    if !open, let card = item.flatMap(DigestMargin.cardID) { model.select(card, store: store, reveal: false) }
                }
            }
        } label: {
            Text(text)
                .font(CDS.sans(size, kind == .run ? .regular : .medium))
                .foregroundStyle(kind == .run ? CDS.Text.primary : kind.tint)
                .padding(.horizontal, kind == .run ? 0 : 4)
                .padding(.vertical, 1)
                .background {
                    if kind != .run {
                        shape.fill(kind.tint.opacity(hovered || open ? 0.28 : 0.13))
                    }
                }
                .overlay(alignment: .bottom) {
                    if kind == .run {
                        Rectangle().fill(CDS.Text.muted.opacity(hovered ? 0.9 : 0.45)).frame(height: 1).offset(y: 1)
                    }
                }
                .overlay { if open { shape.strokeBorder(kind.tint.opacity(0.75), lineWidth: 1) } }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if margin {
                if inside { state.hoverSession = session } else if state.hoverSession == session { state.hoverSession = nil }
            }
            // The peek: always for a running session (it has no card in the margin), else only without the margin.
            if !margin || kind == .run {
                if inside { state.hovered = id } else if state.hovered == id { state.hovered = nil }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(DigestPage.space)).minY } action: { y in
            if state.anchors[id] != y { state.anchors[id] = y }
        }
        .overlay(alignment: .topLeading) {
            if state.hovered == id, !open, let item {
                DigestPeek(item: item, page: page)
                    .frame(width: 400, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: size + 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(text)
        .accessibilityHint(item == nil ? "" : "Opens its card")
    }
}

/// The cards the text points at, beside it as a document's comments: each at the height of its highlight in its project's
/// paragraph (the lead's only when the project's has none), pushed down so none overlaps. The one opened sits exactly at its
/// highlight, those before it moving up to make room, as comments do.
private struct DigestMargin: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let items: [String: CanvasItem]
    let digest: RouterDigest

    var body: some View {
        let state = model.digest
        let entries = entries(state.anchors)
        let active = entries.firstIndex { Self.cardID($0.item) == model.selection }
        DigestMarginLayout(active: active, gap: 10) {
            ForEach(entries, id: \.session) { entry in
                let lit = state.hoverSession == entry.session
                let isActive = Self.cardID(entry.item) == model.selection
                CanvasNode(item: entry.item, store: store, model: model, page: page)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(lit && !isActive ? CDS.Text.accent.opacity(0.8) : .clear, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                    .opacity(active == nil || isActive || lit ? 1 : 0.72)
                    .offset(x: isActive ? -10 : 0)
                    .onHover { inside in
                        if inside { state.hoverSession = entry.session } else if state.hoverSession == entry.session { state.hoverSession = nil }
                    }
                    .layoutValue(key: MarginAnchor.self, value: entry.y)
            }
        }
        .animation(Motion.spatial.resolved(reduce: false), value: model.selection)
        .animation(Motion.spatial.resolved(reduce: false), value: model.expandedNeed)
    }

    private struct Entry {
        let session: String
        let item: CanvasItem
        let y: CGFloat
    }

    /// The sessions with a card the text points at, top to bottom, each at its highlight.
    private func entries(_ anchors: [String: CGFloat]) -> [Entry] {
        var best: [String: (y: CGFloat, lead: Bool)] = [:]
        let paragraphs = [("lead-you", digest.forYou), ("lead-look", digest.worthALook)] + digest.projects.map { ($0.folder, $0.text) }
        for (key, text) in paragraphs {
            let lead = key.hasPrefix("lead-")
            for case .span(let kind, let session, _) in DigestMarkup.parse(text) where kind != .run {
                guard let y = anchors[key + "#" + session] else { continue }
                if let had = best[session], !had.lead || lead { continue }
                best[session] = (y, lead)
            }
        }
        return best.compactMap { session, at in
            guard let item = items[session], Self.cardID(item) != nil else { return nil }
            return Entry(session: session, item: item, y: at.y)
        }
        .sorted { $0.y < $1.y }
    }

    /// The open card an item is, if it has one the margin shows.
    static func cardID(_ item: CanvasItem) -> String? {
        switch item {
        case .need(let c), .ready(let c), .note(let c): c.id
        default: nil
        }
    }

    /// A highlight or card clicked: its card opens (and the composer answers it), or, open already, folds.
    static func toggle(_ item: CanvasItem?, model: RouterModel, store: Store) {
        guard let item, let id = cardID(item) else { return }
        if model.selection == id {
            model.expandedNeed = nil
            model.selection = nil
            model.replyTo = nil
        } else {
            model.select(id, store: store, reveal: false)
        }
    }
}

private struct MarginAnchor: LayoutValueKey { static let defaultValue: CGFloat = 0 }

/// The margin's cards, each at its anchor or as close under it as the cards above allow; the active one exactly at its
/// anchor, the ones above it moved up as far as needed (never above the top).
private struct DigestMarginLayout: Layout {
    let active: Int?
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? DigestPage.marginWidth
        let frames = frames(subviews, width: width)
        return CGSize(width: width, height: frames.map { $0.maxY }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, frame) in frames(subviews, width: bounds.width).enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX, y: bounds.minY + frame.minY),
                              proposal: ProposedViewSize(width: bounds.width, height: frame.height))
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let anchors = subviews.map { $0[MarginAnchor.self] }
        var ys = anchors
        let pivot = active ?? 0
        guard !ys.isEmpty else { return [] }
        // From the pivot down: each under the one above.
        for i in pivot..<ys.count where i > pivot {
            ys[i] = max(anchors[i], ys[i - 1] + heights[i - 1] + gap)
        }
        // From the pivot up: each over the one below, at its anchor if it fits.
        if pivot > 0 {
            for i in stride(from: pivot - 1, through: 0, by: -1) {
                ys[i] = min(anchors[i], ys[i + 1] - heights[i] - gap)
            }
        }
        // Nothing above the top: push everything down from the first, as a last resort.
        if let first = ys.first, first < 0 {
            ys[0] = 0
            for i in 1..<ys.count { ys[i] = max(ys[i], ys[i - 1] + heights[i - 1] + gap) }
        }
        if active == nil {
            for i in 1..<max(1, ys.count) { ys[i] = max(anchors[i], ys[i - 1] + heights[i - 1] + gap) }
        }
        return zip(ys, heights).map { CGRect(x: 0, y: $0, width: width, height: $1) }
    }
}

/// What a highlight points at, floating over the text while hovered: the session, what kind of thing it is, what it says
/// and what it asks. Click to open the card itself.
private struct DigestPeek: View {
    let item: CanvasItem
    let page: RouterPage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(CDS.sans(13, .semibold)).foregroundStyle(CDS.Text.primary).lineLimit(1)
                if let card { KindTag(kind: card.kind) }
                Spacer(minLength: 4)
                Text(shortAgo(at)).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
            }
            if !text.isEmpty {
                Text(LocalizedStringKey(text)).font(CDS.sans(12.5)).foregroundStyle(CDS.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let asks = card?.asks, !asks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(asks, id: \.question) { ask in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(CDS.Text.muted)
                            Text(LocalizedStringKey(ask.question)).foregroundStyle(CDS.Text.primary)
                        }
                        .font(CDS.sans(12.5))
                    }
                }
            }
            Text("Click to open and answer").font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
        }
        .padding(12)
        .background(shape.fill(CDS.Surface.s3))
        .overlay(shape.strokeBorder(CDS.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }

    private var card: RouterCard? {
        switch item {
        case .need(let c), .ready(let c), .note(let c), .waiting(let c), .done(let c): c
        case .working: nil
        }
    }

    private var title: String {
        switch item {
        case .working(let row): row.session.title
        default: card?.title ?? ""
        }
    }

    private var text: String {
        switch item {
        case .working(let row): row.activity?.text ?? page.summaries[row.id]?.text ?? ""
        default: card.map { $0.brief ?? $0.text } ?? ""
        }
    }

    private var at: Date {
        switch item {
        case .working(let row): row.activity?.since ?? row.session.lastActivity
        default: card?.createdAt ?? Date()
        }
    }
}

// MARK: - Flow

private struct TightKey: LayoutValueKey { static let defaultValue = false }

/// Words and highlights laid out as text is: left to right, onto the next line when the line is full, each line's items on
/// a shared middle. A tight item sits against the one before it.
struct DigestFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            for (index, x, size) in line.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(Int, CGFloat, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let gap = view[TightKey.self] || lines[lines.count - 1].items.isEmpty ? 0 : spacing
            if !lines[lines.count - 1].items.isEmpty, lines[lines.count - 1].width + gap + size.width > width {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            let x = line.items.isEmpty ? 0 : line.width + gap
            line.items.append((index, x, size))
            line.width = x + size.width
            line.height = max(line.height, size.height)
            lines[lines.count - 1] = line
        }
        return lines
    }
}
