import SwiftUI

// The Router's canvas as data and geometry (docs/design/spec/router-canvas.md §3): which project frames there are, which
// groups each holds and which of Now's items stand in them, in what order; the frames' columns, the gaps between the items,
// the lines from a group's label to its cards, and the camera's maths. Pure: the views draw it and the tests read it.

/// A group of a frame, in the Router's order: whose move is next.
enum CanvasGroup: String, Hashable, CaseIterable, Identifiable {
    case needs, notes, waiting, working, done

    var id: String { rawValue }

    /// Its section of Now; Done has none (it is the history's).
    var zone: RouterZone? {
        switch self {
        case .needs: .needs
        case .notes: .notes
        case .waiting: .waiting
        case .working: .working
        case .done: nil
        }
    }

    var title: String { zone?.title ?? "Done" }
    var symbol: String { zone?.symbol ?? "checkmark" }
    var tint: Color { zone?.tint ?? CDS.Text.muted }
}

/// One of Now's items on the canvas, keyed as the list keys it, so the pick, the reply and a reveal reach it unchanged.
enum CanvasItem: Identifiable, Equatable {
    /// An open card that needs you.
    case need(RouterCard)
    /// A wait that is over, yours to continue (Needs you's too).
    case ready(RouterCard)
    /// A finished turn worth a look.
    case note(RouterCard)
    /// A session waiting on something else.
    case waiting(RouterCard)
    /// A session working.
    case working(AgentRow)
    /// A session's newest addressed card, when nothing else of it is on the canvas.
    case done(RouterCard)

    var id: String {
        switch self {
        case .need(let c), .ready(let c), .note(let c), .done(let c): c.id
        case .waiting(let c): RouterModel.workingID(c.sessionID)
        case .working(let row): RouterModel.workingID(row.id)
        }
    }

    var sessionID: String {
        switch self {
        case .need(let c), .ready(let c), .note(let c), .waiting(let c), .done(let c): c.sessionID
        case .working(let row): row.id
        }
    }
}

/// A project folder's frame: its groups, each with the items it draws and how many more it holds.
struct CanvasFolder: Identifiable, Equatable {
    struct Group: Identifiable, Equatable {
        let group: CanvasGroup
        var items: [CanvasItem]
        /// Held but not drawn: "+n more" under the items.
        var more: Int = 0
        /// Left out by the filter.
        var hidden = false

        var id: CanvasGroup { group }
    }

    /// The folder (the repository's root), "" for Scratch.
    let key: String
    let name: String
    let color: Color?
    var groups: [Group]

    var id: String { key }
    /// Only finished sessions: it folds to its header line until you open it.
    var doneOnly: Bool { !groups.isEmpty && groups.allSatisfy { $0.group == .done } }
    /// The groups drawn (none left out by the filter).
    var shown: [Group] { groups.filter { !$0.hidden } }
    /// Its sessions, each once.
    var sessions: Int { Set(groups.flatMap { $0.items.map(\.sessionID) }).count + groups.reduce(0) { $0 + $1.more } }
    /// What sorts it among the frames: what needs you, then what's worth a look, then how much it holds.
    var weight: (needs: Int, notes: Int, items: Int) {
        func count(_ g: CanvasGroup) -> Int { groups.first { $0.group == g }.map { $0.items.count + $0.more } ?? 0 }
        return (count(.needs), count(.notes), groups.reduce(0) { $0 + $1.items.count + $1.more })
    }

    /// The id of a group's "+n more" line, keyed as a node.
    func moreID(_ group: CanvasGroup) -> String { "more#\(key)#\(group.rawValue)" }
}

enum RouterCanvasModel {
    /// How many of Worth a look and of Done a frame draws before "+n more".
    static let shown = 3

    /// The frames on Now's zones (as the search leaves them) and the sessions done. `done`: each session's newest addressed
    /// card, newest first (`done(history:)`), those with an item in another group left out here. `expanded`: the groups
    /// ("folder#group") whose "+n more" was opened; `picked`: what is picked or marked, always drawn; `showsAll`: a search
    /// is on, every match drawn.
    static func make(page: RouterPage, done: [RouterCard], muted: Set<String> = [], name: (String) -> String,
                     color: (String) -> Color?, filter: Set<CanvasGroup> = [], picked: Set<String> = [],
                     expanded: Set<String> = [], showsAll: Bool = false) -> [CanvasFolder] {
        var items: [String: [CanvasGroup: [CanvasItem]]] = [:]
        var order: [String] = []
        func add(_ item: CanvasItem, _ folder: String, _ group: CanvasGroup) {
            guard !muted.contains(folder) else { return }
            if items[folder] == nil { order.append(folder) }
            items[folder, default: [:]][group, default: []].append(item)
        }
        for card in page.needs { add(.need(card), card.folder ?? "", .needs) }
        for card in page.ready { add(.ready(card), card.folder ?? "", .needs) }
        for card in page.notes { add(.note(card), card.folder ?? "", .notes) }
        for card in page.waiting { add(.waiting(card), card.folder ?? "", .waiting) }
        for row in page.working { add(.working(row), row.session.folderKey, .working) }
        let live = Set(page.needs.map(\.sessionID) + page.ready.map(\.sessionID) + page.notes.map(\.sessionID)
                       + page.waiting.map(\.sessionID) + page.working.map(\.id))
        for card in done where !live.contains(card.sessionID) { add(.done(card), card.folder ?? "", .done) }

        let folders = order.map { key -> CanvasFolder in
            let byGroup = items[key] ?? [:]
            let groups = CanvasGroup.allCases.compactMap { group -> CanvasFolder.Group? in
                guard let all = byGroup[group], !all.isEmpty else { return nil }
                var drawn = all
                // Worth a look and Done draw a few, unless one picked is past them; a single extra is drawn rather than
                // said ("+1 more" takes the room of the card).
                if group == .notes || group == .done, !showsAll, !expanded.contains("\(key)#\(group.rawValue)"),
                   all.count > shown + 1, !all.dropFirst(shown).contains(where: { picked.contains($0.id) }) {
                    drawn = Array(all.prefix(shown))
                }
                return .init(group: group, items: drawn, more: all.count - drawn.count,
                             hidden: !filter.isEmpty && !filter.contains(group))
            }
            return CanvasFolder(key: key, name: name(key), color: key.isEmpty ? nil : color(key), groups: groups)
        }
        return folders.enumerated().sorted { a, b in
            // A frame of finished sessions only folds: under every frame with something live.
            if a.element.doneOnly != b.element.doneOnly { return !a.element.doneOnly }
            let x = a.element.weight, y = b.element.weight
            if x.needs != y.needs { return x.needs > y.needs }
            if x.notes != y.notes { return x.notes > y.notes }
            if x.items != y.items { return x.items > y.items }
            let byName = a.element.name.localizedStandardCompare(b.element.name)
            return byName != .orderedSame ? byName == .orderedAscending : a.offset < b.offset
        }.map(\.element)
    }

    /// Each session's newest addressed card in the history (oldest first, as the store keeps it), newest first.
    static func done(history: [RouterPage.Entry]) -> [RouterCard] {
        var seen = Set<String>()
        var out: [RouterCard] = []
        for entry in history.reversed() {
            guard case .card(let card) = entry, !card.isOpen, seen.insert(card.sessionID).inserted else { continue }
            out.append(card)
        }
        return out
    }

    /// The node a reveal goes to: an item drawn (a card's id, a row's `working#…`), or for a section of Now (its zone's
    /// raw value) the first item of that group, frame by frame. Nil for what the canvas doesn't draw: the history's end, a
    /// section's fold, an item folded away or past "+n more".
    static func target(forReveal id: String, in folders: [CanvasFolder], folded: (CanvasFolder) -> Bool = { _ in false }) -> String? {
        let drawn = folders.filter { !folded($0) }
        if drawn.contains(where: { $0.shown.contains { $0.items.contains { $0.id == id } } }) { return id }
        guard let zone = RouterZone(rawValue: id), let group = CanvasGroup.allCases.first(where: { $0.zone == zone }) else { return nil }
        return drawn.lazy.compactMap { $0.shown.first { $0.group == group }?.items.first?.id }.first
    }

    /// The items drawn, folder by folder, group by group, as they read: what the keys and VoiceOver go by. A folded frame's
    /// items aren't drawn.
    static func order(_ folders: [CanvasFolder], folded: (CanvasFolder) -> Bool = { _ in false }) -> [String] {
        folders.filter { !folded($0) }.flatMap { $0.shown.flatMap { $0.items.map(\.id) } }
    }
}

// MARK: - Geometry

/// The canvas's measures (the prototype's, canvas2-spec.md §2): frames 560 wide spread over the ground in columns, as many
/// as give the whole a 16:10 shape, 48 apart; the groups' labels at the frame's left and the cards at 124, 420 wide.
enum CanvasMetrics {
    static let frameWidth: CGFloat = 560
    static let pad: CGFloat = 16
    /// The frame's header line, the project's name centred in it; a folded frame is as tall.
    static let header: CGFloat = 44
    static let labelX: CGFloat = 16
    static let labelMax: CGFloat = 92
    static let labelH: CGFloat = 22
    static let cardX: CGFloat = 124
    static let cardW: CGFloat = 420
    /// A folded card with a second line, and a line alone: what a frame is guessed to take before it is drawn.
    static let closedH: CGFloat = 52
    static let lineH: CGFloat = 34
    static let moreH: CGFloat = 24
    static let gap: CGFloat = 6
    static let groupGap: CGFloat = 16
    static let colGap: CGFloat = 48
    static let rowGap: CGFloat = 48
    /// The narrowest and shortest a frame is resized to: its labels and a card still read.
    static let minFrameWidth: CGFloat = 500
    static let minFrameHeight: CGFloat = 96

    /// A measured size in whole points, up: a measure that wavers by a fraction of a point gives the same size, so nothing
    /// placed by it moves.
    static func whole(_ size: CGSize) -> CGSize {
        CGSize(width: (size.width - 0.01).rounded(.up), height: (size.height - 0.01).rounded(.up))
    }

    /// The cards' width in a frame `frame` wide: all of it but the labels' gutter and the margin, so a wider frame shows
    /// more of every card.
    static func cardWidth(frame: CGFloat) -> CGFloat { max(0, max(frame, minFrameWidth) - cardX - pad) }

    /// A frame resized from `start` by `delta` (content points) on the edges dragged: never under the minimum.
    static func resized(_ start: CGSize, by delta: CGSize, width: Bool, height: Bool) -> CGSize {
        CGSize(width: width ? max(minFrameWidth, start.width + delta.width) : start.width,
               height: height ? max(minFrameHeight, start.height + delta.height) : start.height)
    }

    /// Where a line from `centre` towards `target` leaves `rect` (both in the same space), for a marker on the viewport's
    /// edge; `centre` itself when the target is at it.
    static func edgePoint(from centre: CGPoint, to target: CGPoint, in rect: CGRect) -> CGPoint {
        let dx = target.x - centre.x, dy = target.y - centre.y
        guard dx != 0 || dy != 0 else { return centre }
        var t = CGFloat.infinity
        if dx > 0 { t = min(t, (rect.maxX - centre.x) / dx) }
        if dx < 0 { t = min(t, (rect.minX - centre.x) / dx) }
        if dy > 0 { t = min(t, (rect.maxY - centre.y) / dy) }
        if dy < 0 { t = min(t, (rect.minY - centre.y) / dy) }
        t = min(1, max(0, t))
        return CGPoint(x: centre.x + dx * t, y: centre.y + dy * t)
    }
    /// The shape the frames are spread to, wide over tall: a screen's.
    static let aspect: CGFloat = 16.0 / 10.0

    /// How many columns the frames take (their heights with every card folded, in their order): the count whose packing is
    /// nearest 16:10. The frames alone decide it, never the window, so a resize moves none of them.
    static func columnCount(closed: [CGFloat]) -> Int {
        guard closed.count > 1 else { return 1 }
        var best = (count: 1, miss: CGFloat.infinity)
        for count in 1...closed.count {
            let columns = Self.columns(closed: closed, count: count)
            var heights = Array(repeating: CGFloat(0), count: count)
            for (h, c) in zip(closed, columns) { heights[c] += h + rowGap }
            let used = Set(columns).count
            let width = CGFloat(used) * (frameWidth + colGap) - colGap
            let height = max(1, (heights.max() ?? 0) - rowGap)
            let miss = abs(log(width / height / aspect))
            if miss < best.miss - 0.0001 { best = (count, miss) }
        }
        return best.count
    }

    /// Where each frame would be (its top left in the content), by its key, in the frames' order, with the heights they take
    /// with every card folded. A frame you placed is where you put it; the others are packed as masonry, each under the
    /// shortest column (`columns(closed:count:)`), in as many columns as `columnCount` gives them, under every frame you
    /// placed, so none of them lands on one.
    static func preferred(_ frames: [(key: String, closed: CGFloat)], placed: [String: CGPoint]) -> [String: CGPoint] {
        var out: [String: CGPoint] = [:]
        var bottom: CGFloat?
        var left: CGFloat?
        for frame in frames {
            guard let at = placed[frame.key] else { continue }
            out[frame.key] = at
            bottom = max(bottom ?? -.infinity, at.y + frame.closed)
            left = min(left ?? .infinity, at.x)
        }
        let rest = frames.filter { placed[$0.key] == nil }
        let count = columnCount(closed: rest.map(\.closed))
        let columns = Self.columns(closed: rest.map(\.closed), count: count)
        let top = bottom.map { $0 + rowGap } ?? 0
        var heights = Array(repeating: top, count: max(1, count))
        for (frame, c) in zip(rest, columns) {
            out[frame.key] = CGPoint(x: (left ?? 0) + CGFloat(c) * (frameWidth + colGap), y: heights[c])
            heights[c] += frame.closed + rowGap
        }
        return out
    }

    /// The frames where they are drawn. A frame you placed (`placed`) is exactly where you put it, always, whatever it
    /// overlaps and however tall it grows. One packed is at its place unless that overlaps a frame above it or one you
    /// placed (with the gaps), then pushed down under it; taken top to bottom, so a card opening in a packed frame pushes
    /// down only the packed frames under it.
    static func resolve(_ frames: [(origin: CGPoint, size: CGSize, placed: Bool)]) -> [CGPoint] {
        var out = frames.map(\.origin)
        var done = frames.filter(\.placed).map { CGRect(origin: $0.origin, size: $0.size) }
        let order = frames.indices.filter { !frames[$0].placed }.sorted { a, b in
            let p = frames[a].origin, q = frames[b].origin
            return p.y != q.y ? p.y < q.y : p.x != q.x ? p.x < q.x : a < b
        }
        for i in order {
            var rect = CGRect(origin: frames[i].origin, size: frames[i].size)
            var moved = true
            while moved {
                moved = false
                for other in done where rect.minX < other.maxX + pad && other.minX < rect.maxX + pad
                    && rect.minY < other.maxY + rowGap && other.minY < rect.maxY + rowGap {
                    rect.origin.y = other.maxY + rowGap
                    moved = true
                }
            }
            out[i] = rect.origin
            done.append(rect)
        }
        return out
    }

    /// What a frame takes with every card folded (Done's lines and the "+n more" lines shorter than the cards), whatever
    /// the chips leave out (they hide a group in place), whatever "+n more" or a pick drew past the first few: what its
    /// column is chosen by, so none of them moves a frame sideways.
    static func closedHeight(_ folder: CanvasFolder, folded: Bool) -> CGFloat {
        let groups = folder.groups
        guard !folded, !groups.isEmpty else { return header }
        var h = header + pad
        for (i, g) in groups.enumerated() {
            if i > 0 { h += groupGap }
            let one = g.group == .done ? lineH : closedH
            let all = g.items.count + g.more
            let capped = (g.group == .notes || g.group == .done) && all > RouterCanvasModel.shown + 1
            let drawn = capped ? RouterCanvasModel.shown : all
            h += CGFloat(drawn) * one + CGFloat(max(0, drawn - 1)) * gap
            if capped { h += gap + moreH }
        }
        return h
    }

    /// Each frame's column: under the shortest so far (the first of equals), by the heights with every card folded, so
    /// opening one only pushes its own column down and no frame moves sideways.
    static func columns(closed: [CGFloat], count: Int) -> [Int] {
        var heights = Array(repeating: CGFloat(0), count: max(1, count))
        return closed.map { h in
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            heights[c] += h + rowGap
            return c
        }
    }

    /// Each node's top, and each group's label's centre, in a frame's body (its top at 0): the nodes stacked `gap` apart,
    /// `groupGap` between groups; a label centred on its nodes' header lines (`heads`: each node's header's middle, from
    /// its top).
    static func folderPlacement(rows: [(group: CanvasGroup, height: CGFloat, head: CGFloat)]) -> (tops: [CGFloat], labels: [CanvasGroup: CGFloat]) {
        var tops: [CGFloat] = []
        var mids: [CanvasGroup: (lo: CGFloat, hi: CGFloat)] = [:]
        var y: CGFloat = 0
        var last: CanvasGroup?
        for row in rows {
            if let last { y += last == row.group ? gap : groupGap }
            tops.append(y)
            let mid = y + row.head
            let span = mids[row.group]
            mids[row.group] = (min(span?.lo ?? mid, mid), max(span?.hi ?? mid, mid))
            y += row.height
            last = row.group
        }
        return (tops, mids.mapValues { ($0.lo + $0.hi) / 2 })
    }

    /// A line from a group's label to a node's header: from just past the label's end at its middle, to the card's left at
    /// its header's middle, leaving and arriving level.
    static func connector(label: CGRect, header: CGRect) -> (from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint) {
        let from = CGPoint(x: label.maxX + 6, y: label.midY)
        let to = CGPoint(x: header.minX, y: header.midY)
        let mid = (from.x + to.x) / 2
        return (from, CGPoint(x: mid, y: from.y), CGPoint(x: mid, y: to.y), to)
    }
}

/// What the canvas shows: content at `origin` (in the viewport) and `scale`. Pure.
struct CanvasTransform: Equatable {
    var origin: CGPoint = .zero
    var scale: CGFloat = 1

    /// Out far enough to see every frame at once; in no further than 1, as above it `scaleEffect` scales the drawn layers
    /// and text and forms blur.
    static let range: ClosedRange<CGFloat> = 0.25...1.0

    static func clamp(_ scale: CGFloat) -> CGFloat { min(range.upperBound, max(range.lowerBound, scale)) }

    /// Zoomed by `factor`, the point under `point` (in the viewport) staying where it is.
    func zoomed(by factor: CGFloat, at point: CGPoint) -> CanvasTransform {
        let next = Self.clamp(scale * factor)
        let k = next / scale
        return CanvasTransform(origin: CGPoint(x: point.x - (point.x - origin.x) * k, y: point.y - (point.y - origin.y) * k),
                               scale: next)
    }

    /// Everything in `bounds` (content space) shown in `free` (the viewport's room), centred, never above 1.
    static func fit(_ bounds: CGRect, in free: CGRect) -> CanvasTransform {
        guard bounds.width > 0, bounds.height > 0 else { return CanvasTransform(origin: free.origin, scale: 1) }
        let scale = clamp(min(1, free.width / bounds.width, free.height / bounds.height))
        return CanvasTransform(origin: CGPoint(x: free.midX - bounds.midX * scale, y: free.midY - bounds.midY * scale), scale: scale)
    }

    /// Where the origin goes for `rect` (content space) to show in `free`: nil when it shows already; moved the least that
    /// brings it in, its top at the room's top when it is taller than the room (its left when wider).
    func origin(toShow rect: CGRect, in free: CGRect) -> CGPoint? {
        let shown = CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
                           width: rect.width * scale, height: rect.height * scale)
        func shift(_ lo: CGFloat, _ hi: CGFloat, _ freeLo: CGFloat, _ freeHi: CGFloat) -> CGFloat {
            if hi - lo > freeHi - freeLo || lo < freeLo { return freeLo - lo }
            if hi > freeHi { return freeHi - hi }
            return 0
        }
        let dx = shift(shown.minX, shown.maxX, free.minX, free.maxX)
        let dy = shift(shown.minY, shown.maxY, free.minY, free.maxY)
        guard dx != 0 || dy != 0 else { return nil }
        return CGPoint(x: origin.x + dx, y: origin.y + dy)
    }
}

// MARK: - Layouts

private struct CanvasPlaceKey: LayoutValueKey { static let defaultValue = CGPoint.zero }
private struct CanvasPlacedKey: LayoutValueKey { static let defaultValue = false }
private struct CanvasGroupKey: LayoutValueKey { static let defaultValue: CanvasGroup = .needs }

extension View {
    /// A frame's place on the canvas (`CanvasMetrics.preferred`), and whether you put it there (then it never moves).
    func canvasPlace(_ point: CGPoint, placed: Bool) -> some View {
        layoutValue(key: CanvasPlaceKey.self, value: point).layoutValue(key: CanvasPlacedKey.self, value: placed)
    }
    /// A node's group in its frame.
    func canvasGroup(_ group: CanvasGroup) -> some View { layoutValue(key: CanvasGroupKey.self, value: group) }
}

/// The frames on the ground (`CanvasMetrics.resolve`): one you placed exactly where you put it, a packed one pushed down
/// under one it would overlap. A place may be left of or above the content's origin (a frame dragged there): it is drawn
/// there, the content's size counted from the origin.
struct CanvasBoard: Layout {
    private func place(_ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        // Each frame as wide and tall as it makes itself (its width yours or the default, its height its content's or
        // yours if taller).
        // Whole points, so a measure that wavers by a fraction (text laid out again) moves nothing.
        let sizes = subviews.map { CanvasMetrics.whole($0.sizeThatFits(.unspecified)) }
        let points = CanvasMetrics.resolve(zip(subviews, sizes).map { ($0[CanvasPlaceKey.self], $1, $0[CanvasPlacedKey.self]) })
        let maxX = zip(points, sizes).map { $0.x + $1.width }.max() ?? 0
        let maxY = zip(points, sizes).map { $0.y + $1.height }.max() ?? 0
        return (points, CGSize(width: max(0, maxX), height: max(0, maxY)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { place(subviews).size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = place(subviews).points
        for (view, point) in zip(subviews, points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// A frame's nodes, one flat list, `gap` apart inside a group and `groupGap` between groups: a node that changes group in
/// the frame stays the same view and moves.
struct CanvasFolderStack: Layout {
    /// The cards' width: the frame's less the labels' gutter (`CanvasMetrics.cardWidth`).
    var width = CanvasMetrics.cardW

    private func rows(_ subviews: Subviews) -> [(group: CanvasGroup, height: CGFloat, head: CGFloat)] {
        subviews.map { ($0[CanvasGroupKey.self], CanvasMetrics.whole($0.sizeThatFits(.init(width: width, height: nil))).height, 0) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews)
        let tops = CanvasMetrics.folderPlacement(rows: rows).tops
        return CGSize(width: width, height: zip(tops, rows).map { $0 + $1.height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let tops = CanvasMetrics.folderPlacement(rows: rows(subviews)).tops
        for (view, top) in zip(subviews, tops) {
            view.place(at: CGPoint(x: bounds.minX, y: bounds.minY + top), anchor: .topLeading,
                       proposal: .init(width: width, height: nil))
        }
    }
}
