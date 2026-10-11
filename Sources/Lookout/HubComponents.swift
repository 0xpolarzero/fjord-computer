import AppKit
import SwiftUI

// Building blocks of the hub.

/// The bottom edges of the rows that mark themselves with `.capEdge()`, in the scrolled content's own space.
struct CapEdges: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) { value += nextValue() }
}

extension View {
    /// Marks a row of a `CappedScroll`'s content: the list may stop at its bottom edge, never through it.
    func capEdge() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: CapEdges.self, value: [proxy.frame(in: .named(CappedScrollSpace.name)).maxY])
            }
        }
    }
}

enum CappedScrollSpace {
    static let name = "capped-content"

    /// CDS `scroll-fade-y`: 28pt, alpha 1 → .85 → .70 → .50 → .30 → .15 → .05 at 0 / 13 / 25 / 40 / 55 / 70 / 85%.
    static let fade: CGFloat = 28
    static let fadeStops: [Gradient.Stop] = [(1, 0), (0.85, 0.13), (0.70, 0.25), (0.50, 0.40), (0.30, 0.55), (0.15, 0.70),
                                             (0.05, 0.85), (0.05, 1)].map { Gradient.Stop(color: .black.opacity($0.0), location: $0.1) }

    /// The tallest height up to `cap` that ends on a row's bottom edge, when the cap falls inside a measured row (a
    /// row ends past it). A lazy list only measures the rows it has laid out: with none ending past the cap, the cut
    /// is somewhere unmeasured, and the cap itself stands.
    static func fit(cap: CGFloat, edges: [CGFloat]) -> CGFloat {
        guard edges.contains(where: { $0 > cap + 0.5 }) else { return cap }
        return edges.filter { $0 <= cap + 0.5 }.max().map { min($0, cap) } ?? cap
    }

    /// `fit` for a lazy list, which only measures the rows it has realized (and may report a stray edge far past the
    /// rest while it settles): the rows beyond the last measured edge within the cap are taken to repeat the measured
    /// pitch (the gaps between consecutive edges within it, which must agree within a point), and the cap snaps down to a whole number of them.
    /// Never below the first row; with fewer than two edges within the cap there is no pitch to go by.
    static func fitLazy(cap: CGFloat, edges: [CGFloat]) -> CGFloat {
        let within = edges.filter { $0 <= cap + 0.5 }
        guard within.count >= 2, let last = within.last else { return fit(cap: cap, edges: edges) }
        let gaps = zip(within, within.dropFirst()).map { $1 - $0 }
        // Only uniform rows can be extrapolated; otherwise the unmeasured rows' heights are unknown.
        guard let pitch = gaps.max(), pitch > 1, gaps.allSatisfy({ pitch - $0 <= 1 }) else { return fit(cap: cap, edges: edges) }
        return min(last + ((cap - last + 0.5) / pitch).rounded(.down) * pitch, cap)
    }
}

/// A vertical stack that is lazy only for long lists: a list of up to 40 rows is laid out whole, so every row's edge is measured
/// (`CappedScroll` can then cut between rows, not through one). Past that, building every row at once stalls a switch of
/// filter (a Done list of 140 took most of a second); a lazy list cuts on its rows' pitch instead.
struct AdaptiveStack<Content: View>: View {
    let count: Int
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    /// Whether a list of `count` rows is laid out lazily.
    static func isLazy(_ count: Int) -> Bool { count > 40 }

    var body: some View {
        if !Self.isLazy(count) {
            VStack(alignment: alignment, spacing: spacing, content: content)
        } else {
            LazyVStack(alignment: alignment, spacing: spacing, content: content)
        }
    }
}

/// Scrolls only once its content is taller than `cap`; otherwise exactly as tall as the content. Cut short, it stops
/// at the last row that fits whole (rows mark themselves with `.capEdge()`), its fade saying "more below". Follows
/// the keyboard selection (never the pointer's: hovering a row mustn't move the list under it).
struct CappedScroll<Content: View>: View {
    let cap: CGFloat
    /// Read here, in this view's own body, so the parent doesn't depend on it.
    var hub: HubState?
    /// The content is a lazy stack: it only measures the rows its viewport reaches, so the list starts at the
    /// cap (a full viewport) and only shrinks once content measured *at the cap* turns out shorter.
    var lazy = false
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// Lazy only: the content's height, once measured in a viewport as tall as the cap and found shorter than it.
    @State private var lazyShort: CGFloat?
    @State private var edges: [CGFloat] = []
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        // Whole rows only; with no rows marked (or none ending within the cap) the plain cap.
        let limit = lazy ?CappedScrollSpace.fitLazy(cap: cap, edges: edges) : CappedScrollSpace.fit(cap: cap, edges: edges)
        // A lazy list's measured height can lag behind the rows it has since laid out: they count too.
        let cut = lazy ? lazyShort == nil : max(height, edges.last ?? 0) > cap + 0.5
        let shown = cut ? limit : lazy ? lazyShort ?? cap : height
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                content()
                    .coordinateSpace(.named(CappedScrollSpace.name))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        // The first measure lands as is (the hub's own spring reveals it); later ones glide.
                        if height == 0 { height = h } else { withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) { height = h } }
                        settle()
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                viewport = h
                settle()
            }
            .onPreferenceChange(CapEdges.self) { new in
                let sorted = Array(Set(new.map { ($0 * 2).rounded() / 2 })).sorted()
                if sorted != edges {
                    edges = sorted
                    // Rows came or went: measure again at the cap.
                    if lazy, lazyShort != nil { lazyShort = nil }
                    // The content's height may already be known at the cap (a list that shrank): settle on it now.
                    settle()
                }
            }
            // No scroller: a legacy one ("Show scroll bars: Always") would take its width out of the rows and push
            // them off the bar's cells they line up with.
            .scrollIndicators(.never)
            .scrollDisabled(!cut)
            .frame(height: max(shown, 1))
            // Cut short: the last visible row fades out, so it reads as "more below" rather than clipped: Claude's
            // `scroll-fade-y` bottom edge (28pt, its eased alpha stops).
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(stops: cut ? CappedScrollSpace.fadeStops : [.init(color: .black, location: 0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: CappedScrollSpace.fade)
                }
            }
            .onChange(of: hub?.keyboardSelection) { _, request in
                if let id = request?.id { withAnimation(Theme.Motion.hover.resolved(reduce: reduce)) { proxy.scrollTo(id) } }
            }
        }
    }
}

extension CappedScroll {
    /// Lazy: trusts the content's height only when it was measured in a viewport as tall as the cap.
    fileprivate func settle() {
        guard lazy, height > 0 else { return }
        // A viewport snapped down to whole rows is as good as the cap when the content is shorter than it.
        let snapped = CappedScrollSpace.fitLazy(cap: cap, edges: edges)
        if viewport >= cap - 0.5 || (viewport >= snapped - 0.5 && height < snapped - 0.5) {
            let short: CGFloat? = height < cap - 0.5 ? height : nil
            if short != lazyShort { lazyShort = short }
        } else if let short = lazyShort {
            // Shrunk to its content: rows added make it overflow its viewport (measure again at the cap); rows removed
            // leave it short still.
            if height > short + 0.5 { lazyShort = nil } else if height < short - 0.5 { lazyShort = height }
        }
    }
}

/// A thing in the inbox on three short lines, as Claude's two-line rows (search-tabs-avatars.md §5.1) with a third for the
/// facts: 13/16 title over a 12/16 muted `repo#number · @author`, over the facts as compact chips; Claude's Avatar (sm, 20) in a
/// 24 slot, the unread dot cut into its corner (a workflow has its state's glyph instead); its actions (Claude's 24pt row
/// controls) show on hover or when picked with the keys.
struct EntryRow: View {
    let entry: InboxEntry
    let store: Store
    let hub: HubState
    @State private var hover = false

    private var thing: Thing { entry.thing }
    /// Compared here, in this row's own body: hovering another row doesn't rebuild the whole hub.
    private var selected: Bool { hub.selection == "i:" + entry.id }
    private var open: Bool { hover || selected }
    private var unread: Bool { entry.isUnread && !entry.isDone }
    private var tint: Color { store.categories.first { $0.id == entry.categoryID }?.color.swatch ?? Theme.tertiary }

    static let avatar: CGFloat = 20
    static let line: CGFloat = 16

    var body: some View {
        Button { store.open(entry) } label: {
            HStack(alignment: .top, spacing: CDS.Sidebar.rowGap) {
                lead.frame(width: CDS.Sidebar.leadingSlot, height: Self.line * 2 + 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(thing.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle((unread && !entry.isNoise) || open ? CDS.Text.primary : CDS.Text.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        // The actions take the timestamp's place; the title stops short of them.
                        Text(shortAgo(thing.updatedAt)).font(Theme.Typography.meta.monospacedDigit()).foregroundStyle(CDS.Text.muted)
                            .opacity(open ? 0 : 1)
                            .frame(width: open ? actionsWidth - 6 : nil, alignment: .trailing)
                    }
                    .frame(height: Self.line)
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(Theme.Typography.meta)
                            .foregroundStyle(CDS.Text.muted)
                            .lineLimit(1)
                        if let tag = ThingStatusTag.shows(thing.status) { ThingStatusTag(status: tag) }
                        ForEach(jevTags, id: \.self) { JevTag(kind: $0) }
                        ForEach(store.actionChips(for: entry)) { chip in ActionChipView(chip: chip, store: store) }
                    }
                    .frame(height: Self.line)
                    if !chips.isEmpty { FactChips(facts: chips, labels: entry.labels) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowHighlight(open)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(thing.kind == .workflow ? "\(thing.title), \(thing.repo)" : "\(thing.title), \(thing.repo) #\(thing.number ?? 0)")
        .accessibilityValue(([unread ? "Unread" : ""] + jevTags.map(\.words) + chips.map(\.label))
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint("Opens it on GitHub")
        .overlay(alignment: .topTrailing) {
            // Centred on the title line (5pt row padding + half its 16pt line = 13; the controls are 24 tall), 3 from the end.
            if open { actions.padding(.top, 1).padding(.trailing, CDS.RowControl.inset).transition(.opacity) }
        }
        .contextMenu { EntryMenu(entry: entry, store: store) }
        .onHover {
            hover = $0
            if $0 { hub.selection = "i:" + entry.id }
        }
        .motion(Theme.Motion.hover, value: open)
    }

    /// Jev's tags: his rating when it is high or urgent, and the label that stands out most among the facts' messages.
    private var jevTags: [JevTag.Kind] {
        (entry.importance.flatMap { $0 >= .high ? [.importance($0)] : nil } ?? []) + (entry.label.map { [.label($0)] } ?? [])
    }

    /// The facts as chips, each wording once (a thread each says "2 unresolved" twice), and, for a failing workflow, the
    /// jobs that failed.
    private var chips: [Fact] {
        var seen = Set<String>()
        var out = entry.facts.filter { seen.insert($0.label).inserted }
        if thing.kind == .workflow, let job = thing.failingJobs.first, !out.contains(where: { $0.label.contains(job) }) {
            out.append(Fact(key: "jobs", label: FailingNames.summary(thing.failingJobs), tint: .danger))
        }
        return out
    }

    /// Who acted last on it: the latest of the comments, reviews and thread replies; the author when nothing has happened.
    private var actor: Person? {
        var latest: (Person, Date)?
        func consider(_ p: Person, _ at: Date) { if latest == nil || at > latest!.1 { latest = (p, at) } }
        for c in thing.comments { consider(c.author, c.at) }
        for r in thing.reviews { consider(r.author, r.at) }
        for t in thing.threads { consider(t.lastReplyBy, t.lastReplyAt) }
        return latest?.0 ?? thing.author
    }

    private var subtitle: String {
        let name = String(thing.repo.split(separator: "/").last ?? "")
        switch thing.kind {
        case .workflow:
            return [name, thing.workflowName, thing.currentBranch].compactMap { $0 }.joined(separator: " · ")
        default:
            let by = actor.map { " · @\($0.login)" } ?? ""
            return "\(name)#\(thing.number ?? 0)\(by)"
        }
    }

    @ViewBuilder private var lead: some View {
        if thing.kind == .workflow {
            let color = switch thing.checks {
            case .failing?: Theme.red
            case .pending?: Theme.claude
            case .passing?: Theme.green
            case nil: Theme.tertiary
            }
            Image(systemName: thing.checks == .passing ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(Theme.Typography.glyph(15))
                .foregroundStyle(color)
                .frame(width: Self.avatar, height: Self.avatar)
                .overlay(alignment: .topTrailing) { if unread { Circle().fill(tint).frame(width: CDS.Dot.size, height: CDS.Dot.size).offset(x: 3, y: -1) } }
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
            avatar.frame(maxHeight: .infinity, alignment: .center)
        }
    }

    /// The author's avatar; unread, Claude's 6pt status dot at its top-right corner, cut out of it (2pt clear around), in
    /// the category's colour.
    private var avatar: some View {
        let size = Self.avatar
        let r = CDS.Dot.size / 2
        let centre = CGPoint(x: size - r + 1, y: r - 1)
        return Avatar(url: actor?.avatar, size: size, name: actor?.login)
            .mask {
                Rectangle()
                    .overlay {
                        if unread {
                            Circle().frame(width: 2 * (r + 2), height: 2 * (r + 2)).position(centre).blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .overlay {
                if unread {
                    Circle().fill(tint).frame(width: CDS.Dot.size, height: CDS.Dot.size).position(centre)
                }
            }
            .frame(width: size, height: size)
    }

    /// Room the controls take over the title line: 24pt buttons 2 apart, 3 from the end, and 4 before them.
    private var actionsWidth: CGFloat {
        let n = CGFloat(unread || entry.isDone ? 3 : 2)
        return n * IconButton.Size.row + (n - 1) * CDS.RowControl.gap + CDS.RowControl.inset + 4
    }

    private var actions: some View {
        let size = IconButton.Size.row
        return RowActions {
            if entry.isDone {
                IconButton(symbol: "arrow.uturn.backward", help: "Back to inbox", detail: store.shortcut(.discard).display,
                           size: size) { store.restore(entry) }
            } else {
                if unread {
                    IconButton(symbol: "checkmark", help: "Mark as seen", detail: store.shortcut(.toggleRead).display, size: size) {
                        store.markSeen(entry)
                    }
                } else {
                    IconButton(symbol: "circlebadge", help: "Mark as unread", detail: store.shortcut(.toggleRead).display, size: size) {
                        store.markUnread(entry)
                    }
                }
                IconButton(symbol: "xmark", help: "Done", detail: "Moves it to Done until something new happens · \(store.shortcut(.discard).display)",
                           size: size) { store.finish(entry) }
            }
            IconButton(symbol: "arrow.up.right", help: "Open on GitHub", detail: store.shortcut(.openItem).display, size: size) {
                store.open(entry)
            }
        }
    }
}

/// An entry's context menu: open, copy link, seen, done.
struct EntryMenu: View {
    let entry: InboxEntry
    let store: Store

    var body: some View {
        Button("Open on GitHub") { store.open(entry) }
        Button("Copy link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.thing.url.absoluteString, forType: .string)
        }
        Divider()
        if entry.isDone {
            Button("Back to inbox") { store.restore(entry) }
        } else {
            if entry.isUnread { Button("Mark as seen") { store.markSeen(entry) } }
            else { Button("Mark as unread") { store.markUnread(entry) } }
            Button("Done") { store.finish(entry) }
        }
    }
}

/// Jev's word on a row, as a tag beside its status (Claude's Badge, xs): his label of its messages, or his rating of what
/// it asks of you. Asks you and To do stand out (accent, warning), FYI is plain, Noise is muted; Important (high) and
/// Urgent stand out too. Emphasis only: a row is there, and notifies, by your rules alone.
struct JevTag: View {
    enum Kind: Hashable {
        case label(CommentLabel)
        case importance(Importance)

        var text: String {
            switch self {
            case .label(let label): label.tag
            case .importance(let level): level == .urgent ? "Urgent" : "Important"
            }
        }

        var words: String {
            switch self {
            case .label(let label): "Jev labels it \(label.title)"
            case .importance(let level): "Jev rates this \(level.rawValue)"
            }
        }

        var colors: (fill: Color, ink: Color) {
            switch self {
            case .label(.asks): (CDS.BadgeTint.accentFill, CDS.BadgeTint.accentText)
            case .label(.todo): (CDS.BadgeTint.warningFill, CDS.BadgeTint.warningText)
            case .label(.fyi): (CDS.Badge.fill, CDS.Badge.ink)
            case .label(.noise): (CDS.Badge.fill, CDS.Text.muted)
            case .importance(let level): level == .urgent ? (CDS.BadgeTint.dangerFill, CDS.BadgeTint.dangerText)
                : (CDS.BadgeTint.warningFill, CDS.BadgeTint.warningText)
            }
        }
    }

    let kind: Kind

    var body: some View {
        let (fill, ink) = kind.colors
        Text(kind.text)
            .font(CDS.sans(CDS.Badge.font, .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, CDS.Badge.padX)
            .frame(height: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(fill))
            .fixedSize()
            .tip(kind.words)
    }
}

/// A fact as a chip, Claude's Badge (xs, 16 tall, radius 4) in the variant of its tint.
struct FactChip: View {
    let fact: Fact

    var body: some View {
        let (fill, ink) = Self.colors(fact.tint)
        Text(fact.label)
            .font(Theme.Typography.caption)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(fill))
    }

    static func colors(_ tint: FactTint) -> (Color, Color) {
        switch tint {
        case .neutral: (CDS.Badge.fill, CDS.Badge.ink)
        case .attention: (CDS.BadgeTint.warningFill, CDS.BadgeTint.warningText)
        case .danger: (CDS.BadgeTint.dangerFill, CDS.BadgeTint.dangerText)
        case .success: (CDS.BadgeTint.successFill, CDS.BadgeTint.successText)
        }
    }
}

/// The facts on one line: as many chips as fit, then "···" for the rest (VoiceOver reads them all); a fact about a message
/// Jev labels noise is muted.
struct FactChips: View {
    let facts: [Fact]
    /// Jev's labels of the facts' messages, by fact key: one about noise is muted.
    var labels: [String: CommentLabel] = [:]

    var body: some View {
        ChipLine(spacing: 4) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                FactChip(fact: fact).opacity(labels[fact.key] == .noise ? 0.55 : 1)
            }
            Text("···").font(Theme.Typography.caption).foregroundStyle(CDS.Text.muted).fixedSize()
                .frame(height: CDS.Badge.height).accessibilityHidden(true)
        }
        .frame(height: CDS.Badge.height)
        .clipped()
    }
}

/// Chips left to right while they fit; the last child is the "more" mark, shown only when some chip didn't.
private struct ChipLine: Layout {
    var spacing: CGFloat

    private func shown(_ subviews: Subviews, width: CGFloat) -> Int {
        let chips = subviews.dropLast()
        let mark = subviews.last?.sizeThatFits(.unspecified).width ?? 0
        let widths = chips.map { $0.sizeThatFits(.unspecified).width }
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        if total <= width { return widths.count }
        var x: CGFloat = 0
        var n = 0
        for w in widths {
            if x + w + spacing + mark > width { break }
            x += w + spacing
            n += 1
        }
        return n
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = subviews.dropLast().map { $0.sizeThatFits(.unspecified).width }
        let natural = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        return CGSize(width: min(natural, proposal.width ?? natural), height: CDS.Badge.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = shown(subviews, width: bounds.width)
        var x = bounds.minX
        for (i, sub) in subviews.dropLast().enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if i < n {
                sub.place(at: CGPoint(x: x, y: bounds.minY), proposal: .unspecified)
                x += size.width + spacing
            } else {
                sub.place(at: CGPoint(x: -10_000, y: bounds.minY), proposal: .unspecified)
            }
        }
        if let mark = subviews.last {
            let hidden = n < subviews.count - 1
            mark.place(at: CGPoint(x: hidden ? x : -10_000, y: bounds.minY), proposal: .unspecified)
        }
    }
}

/// A PR or issue that isn't plainly open, as Claude's Badge: Draft (neutral), Merged (violet), Closed (red).
struct ThingStatusTag: View {
    let status: ThingStatus

    /// Open things carry no tag.
    static func shows(_ status: ThingStatus) -> ThingStatus? { status == .open ? nil : status }

    var body: some View {
        let (label, fill, ink): (String, Color, Color) = switch status {
        case .merged: ("Merged", CDS.BadgeTint.violetFill, CDS.BadgeTint.violetText)
        case .closed: ("Closed", CDS.BadgeTint.dangerFill, CDS.BadgeTint.dangerText)
        default: ("Draft", CDS.Badge.fill, CDS.Badge.ink)
        }
        Text(label)
            .font(CDS.sans(CDS.Badge.font, .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, CDS.Badge.padX)
            .frame(height: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(fill))
            .fixedSize()
    }
}


/// A row's controls on hover, the same for inbox items and sessions: Claude's row controls (sidebar §2.7), 24pt ghost
/// buttons 2 apart, laid over the row's right end (so showing them never changes the row's size). No box of their own:
/// the row's text stops short of them.
struct RowActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: CDS.RowControl.gap) { content }
    }
}

/// A request to scroll the lists to a row; `seq` makes asking for the same row again a new request.
struct ScrollRequest: Equatable {
    let id: String
    let seq: Int
}

extension Store {
    /// The categories shown in the bar and as tabs: all but the hidden ones.
    /// In the bar's order: section by section (CategorySections.swift).
    var shownCategories: [InboxCategory] { barSections.flatMap(\.categories) }

    /// The tab the inbox peek shows: the one picked while it is still there, else the first category shown, else Done.
    func hubTab(_ hub: HubState) -> InboxTab {
        switch hub.tab {
        case .done?: return .done
        case .category(let id)?: if shownCategories.contains(where: { $0.id == id }) { return .category(id) }
        case nil: break
        }
        return shownCategories.first.map { .category($0.id) } ?? .done
    }

    /// The category a tab is, if it is one.
    func category(_ tab: InboxTab) -> InboxCategory? {
        if case .category(let id) = tab { return categories.first { $0.id == id } }
        return nil
    }

    /// The tab to open the inbox on: the first category shown with something unread, else the first shown.
    var tabNeedingYou: InboxTab {
        let shown = shownCategories
        return (shown.first { unreadCount($0.id) > 0 } ?? shown.first).map { .category($0.id) } ?? .done
    }

    /// What a tab lists.
    func entries(in tab: InboxTab) -> [InboxEntry] {
        switch tab {
        case .done: doneEntries
        case .category(let id): entries(in: id)
        }
    }

    /// The number a category carries in the bar and its tab: what is unread; CI's is how many fail.
    func badge(_ category: InboxCategory) -> Int { category.isCI ? count(category.id) : unreadCount(category.id) }

    /// Opens a thing on GitHub, and it is seen; the playground reports it instead.
    func open(_ entry: InboxEntry) {
        if let interceptOpen { interceptOpen("Open on GitHub · \(entry.thing.title)") } else { Link.open(entry.thing.url) }
        if entry.isUnread { markSeen(entry) }
    }

    /// Done, with an undo for the next 30 s: it puts the thing back as it was (unread stays unread), unless something else
    /// has happened to it since, or it is gone.
    func finish(_ entry: InboxEntry) {
        guard !entry.isDone else { return }
        let before = marks[entry.id] ?? EntryMarks()
        markDone(entry)
        let after = marks[entry.id]
        undoStack.push("Moved to Done") { [self] in
            guard things[entry.id] != nil, let now = marks[entry.id], now.acked == after?.acked, now.doneAt == after?.doneAt else {
                return false
            }
            var m = now
            m.acked = before.acked
            m.seen = before.seen
            m.doneAt = before.doneAt
            m.doneIn = before.doneIn
            m.doneFacts = before.doneFacts
            marks[entry.id] = m
            return true
        }
    }

    /// Everything a tab lists, seen.
    func markAllSeen(_ tab: InboxTab) {
        for entry in entries(in: tab) where entry.isUnread { markSeen(entry) }
    }

    /// Shows or hides a category: hidden, it collects quietly and has no icon in the bar.
    func setHidden(_ id: UUID, _ hidden: Bool) {
        guard let i = categories.firstIndex(where: { $0.id == id }), categories[i].hidden != hidden else { return }
        categories[i].hidden = hidden
    }

    /// Drags `id` to where `target` is among the categories, into its section (CategorySections.swift).
    func moveCategory(_ id: UUID, onto target: UUID) {
        guard id != target, let from = categories.firstIndex(where: { $0.id == id }),
              let to = categories.firstIndex(where: { $0.id == target }) else { return }
        var list = categories
        let section = sectionID(of: list[to])
        var moving = list.remove(at: from)
        if section != nil { moving.section = section }
        // Down: after the target (now one place up); up: before it. Either way, its place.
        list.insert(moving, at: to)
        categories = treeOrdered(list)
    }

    /// One place up (-1) or down (+1) among `among` (every category by default; the bar's tabs pass the shown ones).
    /// False when it is already at that end.
    @discardableResult
    func moveCategory(_ id: UUID, by step: Int, among: [InboxCategory]? = nil) -> Bool {
        let list = among ?? categories
        guard let at = list.firstIndex(where: { $0.id == id }), list.indices.contains(at + step) else { return false }
        moveCategory(id, onto: list[at + step].id)
        return true
    }

    /// Whether `moveCategory(_:by:)` has somewhere to go.
    func canMoveCategory(_ id: UUID, by step: Int, among: [InboxCategory]? = nil) -> Bool {
        let list = among ?? categories
        guard let at = list.firstIndex(where: { $0.id == id }) else { return false }
        return list.indices.contains(at + step)
    }

}

/// The inbox in the bar: the GitHub mark. A click opens the inbox; the categories have their own cells under it (beside it
/// along the top and bottom).
struct InboxCell: View {
    let vertical: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { InboxCellLabel(vertical: vertical) }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel("Inbox")
            .accessibilityHint("Opens your GitHub inbox")
    }
}

private struct InboxCellLabel: View {
    let vertical: Bool
    @State private var hover = false

    var body: some View {
        GitHubMark()
            .fill(hover ? Theme.text : Theme.secondary)
            // Optically the weight of a 14pt symbol next to it.
            .frame(width: 15, height: 15)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: CDS.Tile.radius, style: .continuous).fill(hover ? Theme.Fill.hover : .clear))
            .frame(width: Theme.Metrics.line, height: Theme.Metrics.line)
            .padding(.vertical, vertical ? 3 : 0)
            .padding(.horizontal, vertical ? 0 : 2)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .motion(Theme.Motion.hover, value: hover)
    }
}

/// A category in the bar: its symbol in its colour, and on its corner how many things are unread (the Router's badge); a
/// click opens the inbox on it.
struct CategoryCell: View {
    let category: InboxCategory
    let badge: Int
    let vertical: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { CategoryCellLabel(category: category, badge: badge, vertical: vertical) }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel(category.title)
            .accessibilityValue(badge == 0 ? "Nothing new" : category.isCI ? "\(badge) failing" : "\(badge) unread")
            .accessibilityHint("Opens it in the inbox")
            .motion(.snappy, value: badge)
    }
}

private struct CategoryCellLabel: View {
    let category: InboxCategory
    let badge: Int
    let vertical: Bool
    @State private var hover = false

    var body: some View {
        let tint = badge > 0 ? category.color.swatch : hover ? Theme.text : Theme.tertiary
        Image(systemName: category.symbol)
            .symbolRenderingMode(.palette)
            .font(Theme.Typography.glyph(14))
            // Its colour only while it holds something; neutral when empty (and CI, when nothing fails).
            .foregroundStyle(tint, tint, tint)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: CDS.Tile.radius, style: .continuous).fill(hover ? Theme.Fill.hover : .clear))
            .overlay(alignment: .topTrailing) { CornerBadge(count: badge, fill: category.color.swatch, ink: category.color.ink) }
            .frame(width: Theme.Metrics.line, height: Theme.Metrics.line)
            .padding(.vertical, vertical ? 3 : 0)
            .padding(.horizontal, vertical ? 0 : 2)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .motion(Theme.Motion.hover, value: hover)
            // No tooltip: hovering it peeks its list, which says more.
    }
}

extension CategoryColor {
    /// The text on a solid fill of this colour.
    var ink: Color { self == .blue || self == .red || self == .violet || self == .magenta ? .white : CDS.Text.onPrimary }
}

/// Claude's corner count (the pending-invite badge), shared by the Router's cell and the categories': 16 tall, round, caption
/// at 460, a 2pt ring of the island's black; nothing at zero.
struct CornerBadge: View {
    let count: Int
    let fill: Color
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(Theme.Typography.badge)
                .foregroundStyle(ink)
                .contentTransition(reduce ? .opacity : .numericText(value: Double(count)))
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(fill))
                .background(Capsule().fill(Theme.bg).padding(-2))
                .offset(x: 6, y: -5)
                .transition(.scaleFade(0.6, reduce: reduce))
        }
    }
}

/// GitHub's mark (Octicons' `mark-github`, 16 × 16), drawn from its path so it is crisp at any size.
struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 16
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        return SVGPath.parse(Self.data).applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale))
    }

    static let data = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
}

/// SVG path data (M L H V C S A Z, absolute and relative) as a SwiftUI path.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var scanner = Scanner(d)
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"
        while let next = scanner.command(or: command) {
            command = next
            let relative = next.isLowercase
            let origin = relative ? current : .zero
            switch Character(next.uppercased()) {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                start = current
                path.move(to: current)
                // More pairs after a move are lines.
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: origin.y + y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let a = scanner.number(), let b = scanner.number(), let c = scanner.number(), let e = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = CGPoint(x: origin.x + a, y: origin.y + b), c2 = CGPoint(x: origin.x + c, y: origin.y + e)
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "S":
                guard let c = scanner.number(), let e = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = CGPoint(x: origin.x + c, y: origin.y + e)
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let x = scanner.number(), let y = scanner.number()
                else { return path }
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// An elliptical arc as cubic curves (SVG's endpoint form, appendix F.6).
    private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                            rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coefficient = (large == sweep ? -1 : 1) * (max(0, numerator / denominator)).squareRoot()
        let cx1 = coefficient * rx * y1 / ry, cy1 = -coefficient * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }
        let segments = Int((abs(delta) / (.pi / 2)).rounded(.up))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func point(_ t: CGFloat, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> CGPoint {
            let x = rx * cos(t) + dx, y = ry * sin(t) + dy
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        var t = theta
        for _ in 0..<segments {
            let t2 = t + step
            let c1 = point(t, -k * rx * sin(t), k * ry * cos(t))
            let c2 = point(t2, k * rx * sin(t2), -k * ry * cos(t2))
            path.addCurve(to: point(t2), control1: c1, control2: c2)
            t = t2
        }
    }

    private struct Scanner {
        let chars: [Character]
        var i = 0
        init(_ s: String) { chars = Array(s) }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 }
        }

        /// The next command letter, or `repeating` when numbers follow the last command.
        mutating func command(or repeating: Character) -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            if chars[i].isLetter { i += 1; return chars[i - 1] }
            return repeating
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var s = ""
            var dot = false
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c) } else if c == ".", !dot { dot = true; s.append(c) } else { break }
                i += 1
            }
            return Double(s).map { CGFloat($0) }
        }

        /// An arc flag: a single 0 or 1, which may be followed directly by the next number.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
            i += 1
            return chars[i - 1] == "1"
        }
    }
}


/// Names of failing jobs as a fact's chip.
enum FailingNames {
    /// The first few, cut short, and how many more ("build, lint +3").
    static func summary(_ names: [String], shown: Int = 3, width: Int = 24) -> String {
        func cut(_ name: String) -> String { name.count > width ? name.prefix(width - 1).trimmingCharacters(in: .whitespaces) + "…" : name }
        let head = names.prefix(shown).map(cut).joined(separator: ", ")
        return names.count > shown ? "\(head) +\(names.count - shown)" : head
    }
}

/// Says a failed update check, download or restart to VoiceOver, wherever it was asked for (Settings' row is not always
/// on screen), from a view of its own: only this body reads the updater's failures.
struct UpdateAnnouncer: View {
    let updater: Updater

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: updater.failures) {
                guard let error = updater.shownError, NSWorkspace.shared.isVoiceOverEnabled else { return }
                AccessibilityNotification.Announcement(error).post()
            }
    }
}

/// The Router in the bar: its symbol, and on its corner how many cards are open, amber while one needs you (a question, a
/// plan, a stuck turn), blue when they are only finished turns, nothing at zero. A click opens the Router in the app window.
struct RouterCell: View {
    let needsYou: Int
    let done: Int
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { RouterCellLabel(needsYou: needsYou, done: done) }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel("Router")
            .accessibilityValue([needsYou > 0 ? "\(needsYou) need you" : nil, done > 0 ? "\(done) done" : nil]
                .compactMap { $0 }.joined(separator: ", ").nonEmpty ?? "Nothing open")
            .accessibilityHint("Opens the Router")
            .motion(.snappy, value: needsYou + done)
    }
}

private struct RouterCellLabel: View {
    let needsYou: Int
    let done: Int
    @State private var hover = false

    var body: some View {
        let open = needsYou + done
        Image(systemName: "arrow.triangle.branch")
            .font(Theme.Typography.glyph(14))
            .foregroundStyle(hover ? Theme.text : Theme.secondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: CDS.Tile.radius, style: .continuous)
                .fill(hover ? Theme.Fill.hover : Theme.Fill.rest))
            // Awaiting yellow while one needs you, accent blue for finished turns.
            .overlay(alignment: .topTrailing) {
                CornerBadge(count: open, fill: needsYou > 0 ? CDS.Fill.warning : CDS.Fill.accent,
                            ink: needsYou > 0 ? CDS.Text.onPrimary : Color.white)
            }
            .frame(width: Theme.Metrics.line, height: Theme.Metrics.line)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .motion(Theme.Motion.hover, value: hover)
    }
}

extension String {
    /// nil for an empty string, for `??` defaults.
    var nonEmpty: String? { isEmpty ? nil : self }
}


/// What an action did for a thing, or that it waits: a small ⚡ chip; the session or the comment opens when it has one.
struct ActionChipView: View {
    let chip: InboxActions.Chip
    let store: Store
    @Environment(\.openApp) private var openApp
    @Environment(\.openRouterMessage) private var openRouterMessage

    var body: some View {
        let (fill, ink) = FactChip.colors(chip.tint)
        let face = HStack(spacing: 3) {
            Image(systemName: "bolt.fill").font(.system(size: 8))
            Text(chip.label).lineLimit(1)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(height: CDS.Badge.height)
        .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(fill))
        if let target = chip.target {
            Button {
                if target == .router {
                    if let message = chip.message { openRouterMessage(message) } else { openApp(.router) }
                } else {
                    store.openActionTarget(target)
                }
            } label: { face }
                .buttonStyle(.plain)
                .help(chip.help)
                .accessibilityLabel("Action: \(chip.label)")
                .accessibilityHint(chip.help)
        } else {
            face.help(chip.help).accessibilityLabel("Action: \(chip.label)")
        }
    }
}
