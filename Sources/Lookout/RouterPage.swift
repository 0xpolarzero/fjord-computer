import SwiftUI

// The Router's main page: one bottom-anchored page, newest nearest the composer. Scrolling up is the history (the
// conversation with the Router and the items already addressed, one timeline); pinned above the composer are what runs on
// its own (Working: calm, live) and what needs you (Needs you: warm, the loudest thing on the page).

// MARK: - Model

/// Which items stand in which zone, and in what order. Pure: the views draw it and the tests read it.
struct RouterPage: Equatable {
    /// One line of the history.
    enum Entry: Identifiable, Equatable {
        /// An addressed card, at the time it was addressed.
        case card(RouterCard)
        /// A run of the Router, from the decision log.
        case decision(RouterDecision)
        /// A summary you asked for.
        case summary(RouterSummary)

        var id: String {
            switch self {
            case .summary(let s): "summary-" + s.id.uuidString
            case .decision(let d): d.id.uuidString
            case .card(let c): c.id
            }
        }

        var date: Date {
            switch self {
            case .card(let c): c.addressedAt ?? c.createdAt
            case .decision(let d): d.at
            case .summary(let s): s.at
            }
        }
    }

    /// Open cards as the page shows them (the arrow keys walk the same order, see `ranked`): an OK asked first, then what
    /// stops a session on you, stuck turns, then the finished ones.
    var needs: [RouterCard] = []
    /// Sessions whose turn ended waiting on something (CI, another session…), with the working ones; newest first.
    var waiting: [RouterCard] = []
    /// Messages waiting for you to say where they go (nothing is sent until you do), above the cards.
    var asks: [RouterAskBack] = []
    /// Sessions working on their own, the longest running first.
    var working: [AgentRow] = []
    /// Each working session's newest summary, by session: shown under its row until the next one.
    var summaries: [String: RouterSummary] = [:]
    /// Oldest first: the Router's runs, the summaries and the addressed cards by time.
    var history: [Entry] = []

    /// The card shown in full: the one asked for while it is still waiting, else the newest.
    func openNeed(preferred: String?) -> String? {
        if let preferred, needs.contains(where: { $0.id == preferred }) { return preferred }
        return needs.first?.id
    }

    static func make(cards: [RouterCard], working: [AgentRow],
                     decisions: [RouterDecision] = [], summaries: [RouterSummary] = [], asks: [RouterAskBack] = []) -> RouterPage {
        make(cards: cards, working: working, asks: asks, history: history(cards: cards, decisions: decisions, summaries: summaries),
             summaries: summaries)
    }

    /// The zones on the cards and sessions, around a history worked out already (`Store.routerHistory`). `tasks`: what
    /// sessions whose turn is over still run (`Store.routerTasks`, the map the keys and the counts go by too, a muted
    /// project's sessions with the rest); without it, the Working rows'.
    static func make(cards: [RouterCard], working: [AgentRow], asks: [RouterAskBack], history: [Entry],
                     summaries: [RouterSummary] = [], tasks: [String: [ClaudeTask]]? = nil) -> RouterPage {
        let open = cards.filter(\.isOpen)
        var page = RouterPage()
        let tasks = tasks ?? Dictionary(working.map { ($0.id, $0.tasks) }, uniquingKeysWith: +)
        page.needs = open.filter { $0.kind != .waiting && shows($0, tasks: tasks) }.sorted(by: ranked)
        // A session that is working again shows as working.
        let busy = Set(working.map(\.id))
        page.waiting = open.filter { $0.kind == .waiting && !busy.contains($0.sessionID) }.sorted(by: newestFirst)
        page.working = working
        page.asks = asks
        page.history = history
        page.summaries = latest(summaries, working: working)
        return page
    }

    /// Whether a card is on the page (and so the keys, the pick and the away strip have it): a turn isn't done while its
    /// session still has subagents or commands running (`tasks`, by session, as the Working rows have them), it shows as
    /// working until they end.
    static func shows(_ card: RouterCard, tasks: [String: [ClaudeTask]]) -> Bool {
        !(card.isOpen && card.kind == .done && !(tasks[card.sessionID] ?? []).isEmpty)
    }

    /// Under each working session's row: its newest summary (the last of those at the same time). A session no longer working
    /// has none shown; the history keeps them all.
    static func latest(_ summaries: [RouterSummary], working: [AgentRow]) -> [String: RouterSummary] {
        let ids = Set(working.map(\.id))
        var out: [String: RouterSummary] = [:]
        for summary in summaries {
            guard let id = summary.sessionID, ids.contains(id) else { continue }
            if let kept = out[id], kept.at > summary.at { continue }
            out[id] = summary
        }
        return out
    }

    /// The history, oldest first (ties keep the runs, then the summaries, then the cards, in their order); one line per id.
    static func history(cards: [RouterCard], decisions: [RouterDecision], summaries: [RouterSummary]) -> [Entry] {
        let entries = decisions.map(Entry.decision) + summaries.map(Entry.summary) + cards.filter { !$0.isOpen }.map(Entry.card)
        var seen = Set<String>()
        return entries.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }.map(\.element).filter { seen.insert($0.id).inserted }
    }

    private static func newestFirst(_ a: RouterCard, _ b: RouterCard) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
    }

    /// Needs you's order: by kind (`Kind.rank`), then the most urgent (Jev's score; a session stopped mid-turn on a question
    /// or plan counts as blocking now, a turn he didn't score as today), then the newest.
    static func ranked(_ a: RouterCard, _ b: RouterCard) -> Bool {
        if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
        let ua = urgency(a), ub = urgency(b)
        if ua != ub { return ua > ub }
        return newestFirst(a, b)
    }

    static func urgency(_ card: RouterCard) -> Double {
        card.triage?.urgency ?? (card.kind.isTurn ? 2 : 4)
    }
}

extension Store {
    /// The Router's page on what is stored and what runs now.
    var routerPage: RouterPage {
        .make(cards: router.cards, working: routerWorkingRows, asks: routerDispatcher.askBacks, history: routerHistory,
              summaries: router.summaries, tasks: routerTasks)
    }

    /// What sessions whose turn is over still have running, as the Working rows have it (a running session's row has none).
    var routerTasks: [String: [ClaudeTask]] { claudeTasks.filter { claudeSessions[$0.key]?.running != true } }

    /// The Router's cards less those the page doesn't show (`RouterPage.shows`): what the keys and the away strip go by.
    var routerShownCards: [RouterCard] {
        let tasks = routerTasks
        return router.cards.filter { RouterPage.shows($0, tasks: tasks) }
    }

    /// The open cards the page shows, newest first: what Jev offers and a send goes to, and where a superseded card's pick
    /// moves. An addressed card is still replied to from the history.
    var routerShownOpenCards: [RouterCard] {
        let tasks = routerTasks
        return openRouterCards.filter { RouterPage.shows($0, tasks: tasks) }
    }

    /// The page's zones alone: what the live part of the page redraws on, without the history.
    var routerZones: RouterPage {
        .make(cards: router.cards, working: routerWorkingRows, asks: routerDispatcher.askBacks, history: [],
              summaries: router.summaries, tasks: routerTasks)
    }
}

// MARK: - Page

private struct GutterKey: EnvironmentKey { static let defaultValue = CDS.Transcript.gutter }
private extension EnvironmentValues {
    /// The page's side margin: 32, 16 in a narrow column.
    var routerGutter: CGFloat {
        get { self[GutterKey.self] }
        set { self[GutterKey.self] = newValue }
    }
}

struct RouterPageView: View {
    let store: Store
    @Bindable var model: RouterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    @State private var height: CGFloat = 700
    @State private var width = CDS.Transcript.measure
    /// The Router's working line over the zones, when it shows.
    @State private var statusHeight: CGFloat = 0
    /// The zones' height as shown (the Router's line with them).
    @State private var zonesShown: CGFloat = 0
    /// While the line between the history and the zones is dragged: the zones' height when it began, and the share it is at.
    @State private var dragBase: CGFloat?
    @State private var dragShare: CGFloat?

    private var spring: Animation? { Theme.Motion.spring.resolved(reduce: reduceMotion) }

    /// The zones' share of the page: the line being dragged, else as last set.
    private var share: CGFloat { dragShare ?? store.router.zonesShare.map { CGFloat($0) } ?? RouterSplit.initial }

    var body: some View {
        let page = store.routerZones
        // A session moving between the zones is the same card travelling, unless it has one in both.
        let once = Dictionary(grouping: page.needs.map(\.sessionID), by: { $0 }).filter { $0.value.count == 1 }.keys
        let bothZones = Set(page.working.map(\.id))
        let travelling = Set(once).subtracting(bothZones)
        let room = RouterSplit.room(page: height, share: share)
        VStack(spacing: 0) {
            RouterHistory(store: store, model: model)
            divider
                .frame(maxWidth: CDS.Transcript.measure + 2 * CDS.Transcript.gutter)
                .frame(maxWidth: .infinity)
                .zIndex(1)
            VStack(spacing: 0) {
                VStack(spacing: 0) { routerStatus }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statusHeight = $0 }
                RouterZones(store: store, model: model, page: page, room: room - statusHeight, ns: ns, travelling: travelling,
                            travellingWorking: Set(page.working.map(\.id)).subtracting(Set(page.needs.map(\.sessionID))))
            }
            .frame(maxWidth: CDS.Transcript.measure + 2 * CDS.Transcript.gutter)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { zonesShown = $0 }
        }
        .motion(Theme.Motion.spring, value: page.needs.map(\.id) + page.working.map(\.id))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { height = $0.height; width = $0.width }
        .environment(\.routerGutter, gutter)
        .environment(\.cdsColumnWidth, min(CDS.Transcript.measure, max(0, width - 2 * gutter)))
    }

    private var divider: some View {
        RouterDivider(zonesBig: RouterSplit.zonesAreBig(share: share),
                      share: height > 0 ? zonesShown / height : share, trailing: max(4, gutter - 22),
                      drag: { dy in
                          let base = dragBase ?? zonesShown
                          dragBase = base
                          dragShare = RouterSplit.dragged(from: base, by: dy, page: height)
                      },
                      dragEnded: {
                          if let dragShare { store.setZonesShare(dragShare) }
                          dragBase = nil
                          dragShare = nil
                      },
                      toggle: {
                          let next = RouterSplit.toggled(share: share)
                          withAnimation(spring) { store.setZonesShare(next) }
                      },
                      adjust: { up in store.setZonesShare(RouterSplit.adjusted(shown: zonesShown, page: height, up: up)) })
    }

    private var gutter: CGFloat { width < 560 ? CDS.Transcript.narrowGutter : CDS.Transcript.gutter }

    /// While the Router itself works: one slim line over the zones.
    @ViewBuilder private var routerStatus: some View {
        if store.routerDispatcher.isBusy {
            WorkingStatus(label: "The Router is working")
                .padding(.horizontal, gutter + CDS.Transcript.textInset)
                .padding(.bottom, 6)
                .transition(.opacity)
        }
    }
}

// MARK: - History

/// The timeline above the zones: opens at the bottom and follows what arrives while you are there; scrolled up, nothing
/// moves what you read. Only the newest lines are drawn, Show earlier draws more. A line is drawn from its own values (what
/// it shows, whether it is open or picked, the minute), so it redraws only when one of them changes; what it shows of a
/// session is in small views of their own, which redraw as the sessions do.
private struct RouterHistory: View {
    let store: Store
    let model: RouterModel
    @Environment(\.routerGutter) private var gutter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The oldest line drawn, once you scroll up or ask for earlier ones (so nothing drops off the top while you read); at the
    /// bottom, the newest `page` lines.
    @State private var oldest: HistoryWindow.Boundary?
    /// At the bottom: what arrives, and the zones growing under it, keep it there. Scrolled up, the top holds.
    @State private var pinned = true
    /// The content has been laid out: a scroll asked for before that waits for it.
    @State private var laidOut = false
    @State private var pending: HistoryScroll?

    /// Lines drawn at first, and more each time Show earlier is clicked.
    static let page = 100

    var body: some View {
        let all = store.routerHistory
        let entries = HistoryWindow.drawn(all, from: oldest, page: Self.page)
        let expanded = model.expanded, picked = model.selection, highlighted = model.highlighted
        // One clock for every age in the history, on the minute.
        MinuteTicking { now in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if entries.count < all.count {
                            ClaudeButton("Show earlier", variant: .ghost, size: .sm, icon: "arrow.up") {
                                let first = entries.startIndex
                                oldest = .init(all[max(0, first - Self.page)])
                                pending = HistoryScroll(id: all[first].id, anchor: .top, animated: false)
                            }
                            .padding(.bottom, 6)
                        }
                        if !all.isEmpty {
                            Text("History").cdsText((12, 16), .medium, CDS.Text.muted)
                                .padding(.leading, CDS.Transcript.textInset)
                                .padding(.bottom, 12)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(entries) { entry in
                            row(entry, now: now, open: expanded.contains(entry.id), marked: entry.id == picked || entry.id == highlighted)
                        }
                        // The bottom's margin: scrolling to it is scrolling to the very bottom.
                        Color.clear.frame(height: 18).id(RouterModel.endID)
                    }
                    // Lines arrive, leave and change without moving; only a line opened or closed by its click animates.
                    .transaction { if !$0.historyToggle { $0.animation = nil } }
                    // macOS 14 has no scroll phases to read: the scroll view itself says when you scroll up, so the lines you
                    // read stay drawn as new ones arrive.
                    .background {
                        if #available(macOS 15, *) { EmptyView() } else {
                            HistoryScrollWatch(pinned: pinned) { step in
                                switch step {
                                case .stay: break
                                case .pin(let on): if pinned != on { pinned = on }
                                case .stick: pending = HistoryScroll(id: RouterModel.endID, anchor: .bottom, animated: false)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: CDS.Transcript.measure, alignment: .leading)
                    .padding(.horizontal, gutter)
                    .frame(maxWidth: .infinity)
                    .padding(.top, CDS.Transcript.fade)
                }
                .cdsTopFade()
                .modifier(HistoryAnchoring(pinned: $pinned, laidOut: $laidOut) {
                    pending = HistoryScroll(id: RouterModel.endID, anchor: .bottom, animated: false)
                })
                // A card picked (clicked, or with the keys): as little scrolling as shows it whole; the Router picked: the bottom.
                .onChange(of: model.revealRequest) { _, request in
                    guard let request else { return }
                    scroll(to: request.id, anchor: request.id == RouterModel.endID ? .bottom : nil, in: all, drawn: entries)
                }
                // A message asked for (an action's chip), the page opening on it or not.
                .onChange(of: model.messageRequest, initial: true) { _, request in
                    guard let request else { return }
                    scroll(to: request.id, anchor: .center, in: all, drawn: entries)
                }
                // Scrolled up, the lines drawn stay; back at the bottom, only the newest are.
                .onChange(of: pinned) { _, pinned in
                    if pinned { oldest = nil } else if oldest == nil { oldest = entries.first.map(HistoryWindow.Boundary.init) }
                }
                // A line opened by its click is on screen: at the bottom it opens upwards and stays whole; scrolled up it opens
                // downwards, and as little scrolling as shows it whole follows.
                .onChange(of: expanded) { old, new in
                    guard !pinned, let id = new.subtracting(old).first, entries.contains(where: { $0.id == id }) else { return }
                    pending = HistoryScroll(id: id, anchor: nil, animated: true)
                }
                .onChange(of: pending) { perform(proxy) }
                .onChange(of: laidOut) { perform(proxy) }
            }
        }
    }

    /// Draws enough lines for the one asked for, then scrolls to it once it is drawn and laid out.
    private func scroll(to id: String, anchor: UnitPoint?, in all: [RouterPage.Entry], drawn: ArraySlice<RouterPage.Entry>) {
        if id != RouterModel.endID {
            guard let i = all.firstIndex(where: { $0.id == id }) else { return }
            // Off the bottom before the lines above are drawn: else their arrival reads as the pinned history falling short
            // of its bottom, and it is stuck back there instead of going to the line.
            pinned = false
            if i < drawn.startIndex { oldest = .init(all[i]) }
        }
        pending = HistoryScroll(id: id, anchor: anchor, animated: true)
    }

    private func perform(_ proxy: ScrollViewProxy) {
        guard laidOut, let scroll = pending else { return }
        pending = nil
        // Going to a line leaves the bottom (until the scroll, once done, finds it there after all); going to the bottom pins.
        pinned = scroll.id == RouterModel.endID
        if scroll.animated, let motion = Theme.Motion.hover.resolved(reduce: reduceMotion) {
            withAnimation(motion) { proxy.scrollTo(scroll.id, anchor: scroll.anchor) }
        } else {
            proxy.scrollTo(scroll.id, anchor: scroll.anchor)
        }
    }

    @ViewBuilder private func row(_ entry: RouterPage.Entry, now: Date, open: Bool, marked: Bool) -> some View {
        switch entry {
        case .card(let card):
            HistoryCardLine(card: card, now: now, open: open, marked: marked, store: store, model: model).equatable()
        case .decision(let decision):
            HistoryDecisionLine(decision: decision, now: now, open: open, store: store, model: model).equatable()
        case .summary(let summary):
            HistorySummaryLine(summary: summary, now: now, open: open, model: model).equatable()
        }
    }
}

/// A scroll the history was asked for; each one is new, even to the same line.
private struct HistoryScroll: Equatable {
    var id: String
    var anchor: UnitPoint?
    var animated: Bool
    private let token = UUID()

    init(id: String, anchor: UnitPoint?, animated: Bool) {
        self.id = id
        self.anchor = anchor
        self.animated = animated
    }
}

/// Opens the history at its bottom and keeps it there while you are (new lines, a line opening, the zones or the composer
/// under it growing); scrolled up, the top holds, so nothing moves what you read. Only a scroll takes it off the bottom: yours,
/// or one to a line asked for.
private struct HistoryAnchoring: ViewModifier {
    @Binding var pinned: Bool
    @Binding var laidOut: Bool
    /// Back to the bottom, after something other than a scroll left it short of it.
    let stick: () -> Void
    /// Whether a scroll is under way (yours, or an animated one asked for); kept out of the view's state, as it changes
    /// mid-scroll and draws nothing.
    @State private var scrolling = HistoryPin.Scrolling()

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                // Every role at the bottom (opening there, the alignment), but changes of size only while pinned.
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(pinned ? .bottom : .top, for: .sizeChanges)
                .onScrollPhaseChange { _, phase, context in
                    scrolling.on = phase != .idle
                    if phase == .idle { apply(.pin(HistoryPin.atBottom(context.geometry.contentSize.height,
                                                                       visibleBottom: context.geometry.visibleRect.maxY))) }
                }
                .onScrollGeometryChange(for: HistoryPin.Geometry.self) {
                    HistoryPin.Geometry(content: $0.contentSize.height, visibleBottom: $0.visibleRect.maxY)
                } action: { _, new in
                    if !laidOut, new.content > 0 { laidOut = true }
                    apply(HistoryPin.next(pinned: pinned, scrolling: scrolling.on, new))
                }
        } else {
            content
                .defaultScrollAnchor(.bottom)
                .onAppear { DispatchQueue.main.async { laidOut = true } }
        }
    }

    private func apply(_ step: HistoryPin.Step) {
        switch step {
        case .stay: break
        case .pin(let on): if pinned != on { pinned = on }
        case .stick: stick()
        }
    }
}

/// When the history counts as at its bottom, and what keeps it there.
enum HistoryPin {
    /// How far above the bottom still counts as there.
    static let slack: CGFloat = 24

    struct Geometry: Equatable {
        var content: CGFloat
        var visibleBottom: CGFloat
    }

    final class Scrolling { var on = false }

    enum Step: Equatable {
        case stay
        /// At the bottom or not, as the scroll left it.
        case pin(Bool)
        /// Something other than a scroll (a line arriving or opening, the space under it changing) left a pinned history
        /// short of its bottom: back there.
        case stick
    }

    static func atBottom(_ contentHeight: CGFloat, visibleBottom: CGFloat) -> Bool {
        contentHeight - visibleBottom <= slack
    }

    static func next(pinned: Bool, scrolling: Bool, _ geometry: Geometry) -> Step {
        let bottom = atBottom(geometry.content, visibleBottom: geometry.visibleBottom)
        if scrolling { return .pin(bottom) }
        // Pinned means right at the bottom, not merely near it.
        return pinned && geometry.content - geometry.visibleBottom > 0.5 ? .stick : .stay
    }
}

/// Which lines of the history are drawn.
enum HistoryWindow {
    /// The oldest line drawn, and its time: the line may go (the oldest go past what is kept) while you read.
    struct Boundary: Equatable {
        var id: String
        var date: Date

        init(_ entry: RouterPage.Entry) {
            id = entry.id
            date = entry.date
        }
    }

    /// From the oldest line drawn on; gone, from the first line left at or after its time (what followed it), so the lines
    /// being read stay; none set (at the bottom): the newest `page`.
    static func drawn(_ all: [RouterPage.Entry], from oldest: Boundary?, page: Int) -> ArraySlice<RouterPage.Entry> {
        guard let oldest else { return all.suffix(page) }
        if let i = all.firstIndex(where: { $0.id == oldest.id }) { return all[i...] }
        guard let next = all.firstIndex(where: { $0.date >= oldest.date }) else { return all.suffix(page) }
        return all[next...]
    }
}

private struct HistoryToggleKey: TransactionKey { static let defaultValue = false }

private extension Transaction {
    /// A history line opening or closing by its click: the one change the history animates.
    var historyToggle: Bool {
        get { self[HistoryToggleKey.self] }
        set { self[HistoryToggleKey.self] = newValue }
    }
}

/// Runs `change` as a history line opening or closing: animated (unless Reduce Motion is on), and only that animates.
@MainActor private func toggleHistoryLine(reduceMotion: Bool, _ change: () -> Void) {
    var transaction = Transaction(animation: Theme.Motion.spring.resolved(reduce: reduceMotion))
    transaction.historyToggle = true
    withTransaction(transaction, change)
}

/// A summary in the history: one line (icon, its session, the text, when), opening to show the whole text.
private struct HistorySummaryLine: View, Equatable {
    let summary: RouterSummary
    let now: Date
    let open: Bool
    let model: RouterModel
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (a: Self, b: Self) -> Bool { a.summary == b.summary && a.now == b.now && a.open == b.open }

    var body: some View {
        let lit = hovered || open
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleHistoryLine(reduceMotion: reduceMotion) { model.toggleExpanded(RouterPage.Entry.summary(summary).id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16)
                    if let title = summary.title {
                        Text(title).cdsText(CDS.Transcript.text, .regular, lit ? CDS.Text.secondary : CDS.Text.muted)
                            .lineLimit(1).truncationMode(.tail).layoutPriority(2)
                        Text("· \(summary.text)").cdsText((12, 16), .regular, CDS.Text.muted)
                            .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    } else {
                        Text(summary.text).cdsText(CDS.Transcript.text, .regular, lit ? CDS.Text.secondary : CDS.Text.muted)
                            .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    }
                    StatusCaret(hot: hovered, open: open)
                    Spacer(minLength: 8)
                    Text(shortAgo(summary.at, now: now)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
                }
                .padding(.horizontal, CDS.Transcript.statusPad)
                .frame(height: CDS.Transcript.statusRow)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .strokeBorder(CDS.Fill.accent, lineWidth: 1).opacity(focused ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .focused($focused)
            .onHover { hovered = $0 }
            .accessibilityLabel(summary.title.map { "Summary of \($0)" } ?? "Overview")
            .accessibilityValue("\(summary.text), \(AgentRow.spokenAge(now.timeIntervalSince(summary.at))) ago, \(open ? "expanded" : "collapsed")")

            if open {
                CDSProse(text: summary.text, color: CDS.Text.primary, inset: false).historyDetails()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A run in the history: one line (icon, what set it off, what was done, when), opening to show the trigger, what was done and
/// its links (the session, the change with its Revert).
private struct HistoryDecisionLine: View, Equatable {
    let decision: RouterDecision
    let now: Date
    let open: Bool
    let store: Store
    let model: RouterModel
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (a: Self, b: Self) -> Bool { a.decision == b.decision && a.now == b.now && a.open == b.open }

    private var key: String { decision.id.uuidString }
    /// While a typed run is under way, how far it is (classifying, sending…); else how it ended. Only a run under way reads
    /// the dispatcher.
    private var status: String {
        decision.outcome == .pending ? store.routerDispatcher.progress[decision.id].map { $0 + "…" } ?? decision.summary : decision.summary
    }

    var body: some View {
        let status = status
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: decision.symbol).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16)
                    Text(RouterDecision.clip(decision.triggerText, 90))
                        .cdsText(CDS.Transcript.text, .regular, hovered || open ? CDS.Text.secondary : CDS.Text.muted)
                        .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    Text("· \(status)").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                    StatusCaret(hot: hovered, open: open)
                    Spacer(minLength: 8)
                    Text(shortAgo(decision.at, now: now)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
                }
                .padding(.horizontal, CDS.Transcript.statusPad)
                .frame(height: CDS.Transcript.statusRow)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .strokeBorder(CDS.Fill.accent, lineWidth: 1).opacity(focused ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .focused($focused)
            .onHover { hovered = $0 }
            .accessibilityLabel(decision.triggerText)
            .accessibilityValue("\(status), \(open ? "expanded" : "collapsed")")

            if open { DecisionDetails(decision: decision, store: store) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle() {
        toggleHistoryLine(reduceMotion: reduceMotion) { model.toggleExpanded(key) }
    }
}

/// An open run's details: what set it off, its reply, what was done, its changes and its sessions.
private struct DecisionDetails: View {
    let decision: RouterDecision
    let store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CDSProse(text: decision.triggerText, color: CDS.Text.secondary, inset: false)
            if let reply = decision.reply { CDSProse(text: reply, color: CDS.Text.primary, inset: false) }
            ForEach(Array(decision.doneLines.enumerated()), id: \.offset) { _, line in
                Text(line).cdsText((12, 16), .regular, CDS.Text.muted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(decision.links.changes, id: \.self) { id in
                if let change = store.router.changes.first(where: { $0.id == id }) {
                    ChangeCard(change: change, store: store)
                }
            }
            let sessions = decision.links.sessions.filter { store.claudeSessions[$0] != nil }
            if !sessions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sessions, id: \.self) { id in
                        ClaudeButton("Open \(store.claudeSessions[id]?.title ?? "session")", variant: .ghost, size: .sm,
                                     icon: "arrow.up.right.square") { store.openAgent(id) }
                    }
                }
            }
        }
        .historyDetails()
    }
}

/// An addressed card in the history: a dim line (its session's glyph, title, how it was addressed, when) opening to its kind,
/// project and text, and Reopen. Clicking it shows it in full with the composer ready to reply to it; hovering it shows
/// Open in Claude in the time's place.
private struct HistoryCardLine: View, Equatable {
    let card: RouterCard
    let now: Date
    let open: Bool
    let marked: Bool
    let store: Store
    let model: RouterModel
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.card == b.card && a.now == b.now && a.open == b.open && a.marked == b.marked
    }

    private var when: Date { card.addressedAt ?? card.createdAt }
    private var how: String {
        if let note = card.addressedNote { return "addressed by your message: \(RouterDecision.clip(note, 60))" }
        return card.addressedBy?.label ?? "Addressed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleHistoryLine(reduceMotion: reduceMotion) { model.tap(card.id, store: store) }
            } label: {
                HStack(spacing: 8) {
                    CardGlyph(store: store, sessionID: card.sessionID, symbol: card.kind.symbol)
                    Text(card.title).cdsText(CDS.Transcript.text, .regular, hovered || open ? CDS.Text.secondary : CDS.Text.muted)
                        .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    Text("· \(how)").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                    StatusCaret(hot: hovered, open: open)
                    Spacer(minLength: 8)
                    // Open in Claude takes the time's place on hover, so the line lines up with the runs around it.
                    Text(shortAgo(when, now: now)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
                        .opacity(hovered ? 0 : 1)
                        .overlay(alignment: .trailing) {
                            HoverOpen(title: card.title, shown: hovered) { store.openAgent(card.sessionID) }
                        }
                }
                .padding(.horizontal, CDS.Transcript.statusPad)
                .frame(height: CDS.Transcript.statusRow)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(marked ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .strokeBorder(CDS.Fill.accent, lineWidth: 1).opacity(focused ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel("\(card.kind.label): \(card.title)")
            .accessibilityValue("\(how), \(AgentRow.spokenAge(now.timeIntervalSince(when))) ago, \(open ? "expanded" : "collapsed")")
            .accessibilityAddTraits(open ? .isSelected : [])
            .accessibilityHint("Shows it in full and replies to it")
            .accessibilityAction(named: "Open in Claude") { store.openAgent(card.sessionID) }
            .accessibilityAction(named: "Reopen") { model.reopen(card.id, store: store) }

            if open { CardDetails(card: card, store: store, model: model) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovered = $0 }
        .contextMenu { CardSessionMenu(store: store, sessionID: card.sessionID) }
    }
}

/// An open history card's details: its kind, project and origin, its text, and Reopen.
private struct CardDetails: View {
    let card: RouterCard
    let store: Store
    let model: RouterModel

    var body: some View {
        let project = store.routerProject(card)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KindTag(kind: card.kind)
                TriageChips(triage: card.triage)
                ProjectLabel(name: project.name, color: project.color)
                    .cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                if let origin = card.origin { OriginTag(origin: origin) }
            }
            CDSProse(text: card.text, color: CDS.Text.secondary, inset: false)
            if store.routerCanReopen(card) {
                ClaudeButton("Reopen", variant: .secondary, size: .sm, icon: "arrow.uturn.backward") {
                    model.reopen(card.id, store: store)
                }
            }
        }
        .historyDetails()
    }
}

/// A history card's session glyph, dimmed; its kind's symbol once the session is gone. A view of its own: the sessions it
/// reads change all the time, and only it redraws for them.
private struct CardGlyph: View {
    let store: Store
    let sessionID: String
    let symbol: String

    var body: some View {
        if let session = store.sessionRow(sessionID) {
            SessionGlyph(row: session, size: 16, dot: false).opacity(0.7)
        } else {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16)
        }
    }
}

/// An open card's session glyph, or with `room` only the room it takes; nothing once the session is gone. A view of its own
/// for the same reason.
private struct CardLead: View {
    let store: Store
    let sessionID: String
    var room = false

    var body: some View {
        if let session = store.sessionRow(sessionID) {
            if room { Color.clear.frame(width: 20, height: 1) } else { SessionGlyph(row: session, size: 20, dot: false) }
        }
    }
}

/// A card's session menu, in a view of its own for the same reason.
private struct CardSessionMenu: View {
    let store: Store
    let sessionID: String

    var body: some View {
        if let session = store.sessionRow(sessionID) { SessionMenu(row: session, store: store) }
    }
}

/// Open in Claude, shown while its card is hovered; its room is kept so nothing moves.
private struct HoverOpen: View {
    let title: String
    let shown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.right.square").font(.system(size: 12, weight: .medium))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CDS.Fill.ghostHover))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in Claude")
        .accessibilityLabel("Open \(title) in Claude")
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .motion(.easeOut(duration: 0.12), value: shown)
        .accessibilityHidden(!shown)
    }
}

private extension View {
    /// An open history line's box under it.
    func historyDetails() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).fill(CDS.Fill.field))
            .overlay { RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
            .padding(.top, 6).padding(.bottom, 4)
    }
}

// MARK: - Zones

/// Working over Needs you, pinned above the composer. Each caps at a part of `room` and scrolls inside; together they stay
/// within it, and take only what they need of it.
private struct RouterZones: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    /// The height the zones may take (their share of the page, the floors kept).
    let room: CGFloat
    let ns: Namespace.ID
    /// Sessions whose card moves between the zones (matched geometry), from the needs side and from the working side.
    let travelling: Set<String>
    let travellingWorking: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.routerGutter) private var gutter
    @Environment(\.cdsColumnWidth) private var columnWidth
    /// The zones' height and their two scrolls' as last measured (kept out of the view's state: they change with every layout).
    @State private var heights = RouterSplit.ZoneHeights()
    /// What the caps read of them: the headers and margins, and Working's scroll, changed only by a point or more, so the caps
    /// never chase their own rounding.
    @State private var chrome: CGFloat = 0
    @State private var workingShown: CGFloat = 0

    /// Working's and Needs you's caps: the room less the headers and margins, shared between the two.
    private var caps: (working: CGFloat, needs: CGFloat) {
        RouterSplit.caps(room: room, chrome: chrome, workingShown: workingShown, needsEmpty: page.needs.isEmpty && page.asks.isEmpty)
    }
    private var needsCap: CGFloat { caps.needs }

    private func measured(_ set: (RouterSplit.ZoneHeights) -> Void) {
        set(heights)
        let needsEmpty = page.needs.isEmpty && page.asks.isEmpty
        let working = page.working.isEmpty && page.waiting.isEmpty ? 0 : heights.working
        let rest = max(0, heights.total - working - (needsEmpty ? 0 : heights.needs))
        if abs(rest - chrome) >= 1 { chrome = rest }
        if abs(working - workingShown) >= 1 { workingShown = working }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !page.working.isEmpty || !page.waiting.isEmpty { working }
            AwayStripView(store: store, model: model)
            needs
        }
        .padding(.horizontal, gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in measured { $0.total = h } }
    }

    // MARK: Working

    private var working: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                WorkingMark()
                Text("Working").cdsText((12, 16), .medium, CDS.Text.muted)
                Text("· \(page.working.count)").cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
                if !page.waiting.isEmpty {
                    Text("· \(page.waiting.count) waiting").cdsText((12, 16), .regular, RouterTriage.waitingTint).monospacedDigit()
                }
            }
            .padding(.leading, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Working, \(page.working.count)" + (page.waiting.isEmpty ? "" : ", \(page.waiting.count) waiting"))
            if !page.working.isEmpty { overview }
            ZoneScroll(maxHeight: caps.working,
                       reveal: model.revealRequest,
                       ids: Set(page.working.map { RouterModel.workingID($0.id) } + page.waiting.map { RouterModel.workingID($0.sessionID) })) {
                VStack(spacing: 0) {
                    ForEach(Array(page.working.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Rectangle().fill(CDS.border.opacity(0.6)).frame(height: CDS.hairline) }
                        WorkingCard(store: store, model: model, row: row, summary: page.summaries[row.id])
                            .id(RouterModel.workingID(row.id))
                            .matched(travellingWorking.contains(row.id) ? row.id : nil, in: ns)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                    ForEach(Array(page.waiting.enumerated()), id: \.element.id) { i, card in
                        if i > 0 || !page.working.isEmpty { Rectangle().fill(CDS.border.opacity(0.6)).frame(height: CDS.hairline) }
                        WaitingCard(store: store, card: card)
                            .id(RouterModel.workingID(card.sessionID))
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.border.opacity(0.7), lineWidth: 1) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in measured { $0.working = h } }
        }
    }

    /// One line over all the working sessions, and the button that summarizes each of them (under its row).
    private var overview: some View {
        let summarizer = model.summarizer
        let ids = Set(page.working.map(\.id))
        return MinuteTicking { now in
            let items = store.overviewItems(now: now)
            HStack(spacing: 8) {
                if let line = RouterOverviewLine.text(items) {
                    Text(line).cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1).truncationMode(.tail)
                        .help(RouterOverviewLine.tooltip(items))
                }
                Spacer(minLength: 4)
                SparklesButton(busy: !summarizer.batch.isEmpty, done: ids.isSubset(of: summarizer.busy),
                               label: "Summarize what's running") { summarizer.requestAll(store: store) }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Needs you

    @ViewBuilder private var needs: some View {
        let open = page.openNeed(preferred: model.expandedNeed)
        let wide = columnWidth >= 620
        // What an open form may take: as much of Needs you's height as leaves the open card's own lines whole in it (the
        // other cards scroll).
        let formCap = max(120, min(400, needsCap - (wide ? 52 : 100) - 24))
        if page.needs.isEmpty && page.asks.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 12, weight: .medium))
                Text("Nothing needs you").cdsText((13, 18), .regular, CDS.Text.muted)
            }
            .foregroundStyle(CDS.Text.muted)
            .padding(.leading, 2)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text("Needs you").cdsText((14, 20), .semibold, CDS.Fill.warning)
                    Text("\(page.needs.count + page.asks.count)")
                        .cdsText((12, 16), .semibold, Color.black.opacity(0.8)).monospacedDigit()
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(CDS.Fill.warning))
                }
                .padding(.leading, 2)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Needs you, \(page.needs.count + page.asks.count)")
                ZoneScroll(maxHeight: needsCap, reveal: model.revealRequest,
                           ids: Set(page.needs.map(\.id) + page.asks.map { $0.id.uuidString })) {
                    VStack(spacing: 6) {
                        ForEach(page.asks) { ask in
                            AskBackCard(store: store, ask: ask)
                                .id(ask.id.uuidString)
                                .transition(.asymmetric(insertion: .scaleFade(0.97, reduce: reduceMotion).combined(with: .opacity),
                                                        removal: .scaleFade(0.97, reduce: reduceMotion)))
                        }
                        ForEach(page.needs) { card in
                            CardView(store: store, model: model, card: card, expanded: card.id == open,
                                     form: store.pendingForm(for: card), project: store.routerProject(card), formCap: formCap)
                                .id(card.id)
                                .matched(travelling.contains(card.sessionID) ? card.sessionID : nil, in: ns)
                                .transition(.asymmetric(insertion: .scaleFade(0.97, reduce: reduceMotion).combined(with: .opacity),
                                                        removal: .scaleFade(0.97, reduce: reduceMotion)))
                        }
                    }
                    // The card's ring and shadow need a little room inside the scroll.
                    .padding(.vertical, 1)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in measured { $0.needs = h } }
            }
        }
    }
}

/// A sparkles icon button that makes summaries, pulsing while they are made. `shown` false keeps its room but hides it, until
/// it has the keyboard or is busy.
private struct SparklesButton: View {
    /// Its summaries are being made: it pulses.
    let busy: Bool
    /// Nothing more to ask for (each of its summaries is under way): it can't be clicked.
    var done = false
    let label: String
    var shown = true
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var help: String { busy ? "Summarizing…" : label }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles").font(.system(size: 11, weight: .medium))
                .symbolEffect(.pulse, options: .repeating, isActive: busy && !reduceMotion)
                .foregroundStyle(busy || hovered ? CDS.Text.secondary : CDS.Text.muted)
                .opacity(busy && reduceMotion ? 0.6 : 1)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered && !done ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
        .focused($focused)
        .onHover { hovered = $0 }
        .opacity(shown || focused || busy ? 1 : 0)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A session's newest summary, under its row: its whole text, wrapped, and its time.
private struct WorkingSummary: View {
    let summary: RouterSummary

    var body: some View {
        let time = summary.at.formatted(date: .omitted, time: .shortened)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 9, weight: .medium)).foregroundStyle(CDS.Text.muted)
                .frame(width: 18)
            Text(summary.text).cdsText((12, 16), .regular, CDS.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(time).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit().fixedSize()
        }
        // The time under the row's duration, past the row's button.
        .padding(.trailing, 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Summary at \(time)")
        .accessibilityValue(summary.text)
    }
}

private extension View {
    @ViewBuilder func matched(_ id: String?, in ns: Namespace.ID) -> some View {
        if let id { matchedGeometryEffect(id: id, in: ns, properties: .position) } else { self }
    }
}

/// A scroll view as tall as its content up to `maxHeight`, scrolling to a requested id inside it.
private struct ZoneScroll<Content: View>: View {
    let maxHeight: CGFloat
    let reveal: ScrollRequest?
    let ids: Set<String>
    @ViewBuilder let content: () -> Content
    @State private var natural: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content().frame(maxWidth: .infinity).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .frame(height: natural == 0 ? nil : min(natural, maxHeight))
            // More below than fits: the last 18 points fade out, so it reads as scrollable.
            .mask(VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, natural > maxHeight + 1 ? .clear : .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
            })
            .onChange(of: reveal) { _, request in
                guard let request, ids.contains(request.id) else { return }
                withAnimation(Theme.Motion.hover.resolved(reduce: reduceMotion)) { proxy.scrollTo(request.id, anchor: .center) }
            }
        }
    }
}

// MARK: - Working card

/// A session working on its own: calm and small, one line. Its icon and title, what it is doing now (shimmering), what it
/// left running, and for how long. A click expands it in place: every summary of it, newest first, and its subagents and
/// commands with what each is on (Open in Claude is there and in its menu). Its sparkles button (on hover) summarizes it, and
/// folded, its newest summary sits under it.
private struct WorkingCard: View {
    let store: Store
    @Bindable var model: RouterModel
    let row: AgentRow
    let summary: RouterSummary?
    @State private var hovered = false
    @State private var expanded = false
    @Environment(\.cdsColumnWidth) private var columnWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summarizer = model.summarizer
        let busy = summarizer.busy.contains(row.id)
        let start = Store.workingStart(row)
        let current = row.session.running ? row.activity?.text ?? "Working" : (row.tasksText ?? "Working")
        // The line composed from its task list and narration, when there is one; the raw step otherwise.
        let explained = store.liveExplanation(row)
        let doing = explained ?? current
        let marked = model.highlighted == RouterModel.workingID(row.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { withAnimation(Theme.Motion.hover.resolved(reduce: reduceMotion)) { expanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        SessionGlyph(row: row, size: 18, dot: false)
                        Text(row.session.title).cdsText((13, 18), .medium, CDS.Text.secondary).lineLimit(1).layoutPriority(2)
                        ShimmerText(text: doing, role: (12, 16)).truncationMode(.tail).layoutPriority(0)
                            .help(RouterLive.tooltip(title: row.session.title, activity: row.activity, tasks: row.tasks))
                        Spacer(minLength: 4)
                        if !row.tasks.isEmpty, columnWidth >= 480 { running.fixedSize().layoutPriority(1) }
                        if let start {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(AgentRow.duration(context.date.timeIntervalSince(start)))
                                    .cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit().fixedSize()
                            }
                            .layoutPriority(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.session.title)
                .accessibilityValue("working, \(row.projectName), \(doing)\(row.tasks.isEmpty ? "" : ", \(row.tasksText ?? "")")")
                .accessibilityHint(expanded ? "Folds its details" : "Shows its summaries, subagents and commands")
                .accessibilityAddTraits(expanded ? .isSelected : [])
                .accessibilityAction(named: "Open in Claude") { store.openAgent(row.id) }
                .accessibilityAction(named: "Summarize") { summarizer.request(row.id, store: store) }
                SparklesButton(busy: busy, done: busy, label: "Summarize this session", shown: hovered) {
                    summarizer.request(row.id, store: store)
                }
            }
            if expanded { details } else if let summary { WorkingSummary(summary: summary) }
            if let error = summarizer.errors[row.id] {
                Text(error).cdsText((12, 16), .regular, CDS.Fill.warning).lineLimit(2).padding(.leading, 26)
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(marked ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu { SessionMenu(row: row, store: store) }
    }

    /// Expanded: its summaries, newest first, then its subagents and commands, then Open in Claude.
    @ViewBuilder private var details: some View {
        let summaries = store.router.summaries.filter { $0.sessionID == row.id }.reversed()
        VStack(alignment: .leading, spacing: 8) {
            if summaries.isEmpty {
                Text("No summary yet: the sparkles button makes one.")
                    .cdsText((12, 16), .regular, CDS.Text.muted).padding(.leading, 26)
            } else {
                ForEach(Array(summaries)) { WorkingSummary(summary: $0) }
            }
            if !row.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(row.tasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: task.kind == .agent ? "person.crop.circle" : "terminal")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(CDS.Text.muted).frame(width: 18)
                            Text(task.title).cdsText((12, 16), .medium, CDS.Text.secondary).lineLimit(1).layoutPriority(1)
                            if let activity = task.activity {
                                Text(activity.text).cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1).truncationMode(.tail)
                            }
                            Spacer(minLength: 4)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(AgentRow.duration(context.date.timeIntervalSince(task.since)))
                                    .cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit().fixedSize()
                            }
                        }
                        .padding(.trailing, 30)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(task.kind == .agent ? "Subagent" : "Command") \(task.title)")
                        .accessibilityValue(task.activity?.text ?? "")
                    }
                }
            }
            Button("Open in Claude") { store.openAgent(row.id) }
                .buttonStyle(.link).font(CDS.sans(12))
                .padding(.leading, 26)
        }
        .transition(.opacity)
    }

    /// "2 agents · 1 command" with their names on hover.
    private var running: some View {
        let agents = row.tasks.filter { $0.kind == .agent }.count
        let commands = row.tasks.count - agents
        var parts: [String] = []
        if agents > 0 { parts.append(agents == 1 ? "1 agent" : "\(agents) agents") }
        if commands > 0 { parts.append(commands == 1 ? "1 command" : "\(commands) commands") }
        return Text(parts.joined(separator: " · "))
            .cdsText((11, 14), .regular, CDS.Text.muted)
            .padding(.horizontal, 6).frame(height: 16)
            .background(Capsule().fill(CDS.Fill.field))
            .runningTip(row.tasks)
    }
}

// MARK: - Waiting card

/// A session whose turn ended waiting on something (CI, a deploy, another session): with the working ones, in a cool tint
/// and an hourglass, saying what for. Once Lookout sees that done it says the session is ready to continue, and Tell it
/// sends the session so; its arrow button continues it on its own next time. Opening it opens the session in Claude.
private struct WaitingCard: View {
    let store: Store
    let card: RouterCard
    @State private var hovered = false

    private var triage: RouterTriage { card.triage ?? RouterTriage() }

    private var line: String {
        if triage.told != nil { return "told it to continue" }
        if let ready = triage.ready { return "ready to continue · \(triage.waitingLabel) finished: \(ready.result)" }
        return "waiting for \(triage.waitingLabel)"
    }

    var body: some View {
        let tint = RouterTriage.waitingTint
        let ready = triage.ready != nil
        HStack(spacing: 8) {
            Button { store.openAgent(card.sessionID) } label: {
                HStack(spacing: 8) {
                    if let row = store.sessionRow(card.sessionID) { SessionGlyph(row: row, size: 18, dot: false) }
                    Text(card.title).cdsText((13, 18), .medium, CDS.Text.secondary).lineLimit(1).layoutPriority(2)
                    Image(systemName: ready ? "checkmark.circle.fill" : "hourglass").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(line).cdsText((12, 16), ready ? .medium : .regular, tint).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    MinuteTicking { now in
                        Text(shortAgo(card.createdAt, now: now)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit().fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(card.text)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(card.title)
            .accessibilityValue(line)
            .accessibilityHint("Opens it in Claude")
            if ready, triage.told == nil, let message = RouterWaits.message(triage) {
                ClaudeButton("Tell it", variant: .secondary, size: .sm, icon: "arrow.turn.down.right") { store.tellWaiting(card.id) }
                    .help("Sends it: \(message)")
            }
            AutoContinueToggle(on: store.continuesAutomatically(card.sessionID), shown: hovered) {
                store.setContinuesAutomatically(card.sessionID, $0)
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(ready ? 0.13 : hovered ? 0.09 : 0.06))
        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(ready ? 0.9 : 0.5)).frame(width: 2) }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Mark handled") { store.setCardAddressed(card.id, true) }
            CardSessionMenu(store: store, sessionID: card.sessionID)
        }
    }
}

/// Whether a waiting session is told on its own once its wait is over: a toggle in an icon, shown on hover or when on.
private struct AutoContinueToggle: View {
    let on: Bool
    let shown: Bool
    let set: (Bool) -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button { set(!on) } label: {
            Image(systemName: on ? "forward.fill" : "forward").font(.system(size: 10, weight: .medium))
                .foregroundStyle(on ? RouterTriage.waitingTint : hovered ? CDS.Text.secondary : CDS.Text.muted)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovered = $0 }
        .opacity(on || shown || focused ? 1 : 0)
        .help(on ? "Continues it automatically when the wait is over: click to stop" : "Continue it automatically when the wait is over")
        .accessibilityLabel("Continue it automatically")
        .accessibilityValue(on ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// What Jev's triage says of a turn's work, in tiny chips: it claims a success it didn't check; its changes aren't pushed,
/// or a PR is open.
struct TriageChips: View {
    let triage: RouterTriage?

    var body: some View {
        if let triage {
            if triage.circles {
                chip("Going in circles", Theme.red, help: "Jev sees the same attempt failing again")
            }
            if triage.unverified {
                chip("unverified", CDS.Fill.warning, help: "It says it works without having checked (“should work”, untested)")
            }
            if let work = triage.workLabel {
                chip(work, CDS.Text.muted, help: "Its changes: \(work)")
            }
        }
    }

    private func chip(_ text: String, _ color: Color, help: String) -> some View {
        Text(text).cdsText((11, 14), .medium, color).lineLimit(1)
            .padding(.horizontal, 6).frame(height: 16)
            .background(Capsule().fill(color.opacity(0.14)))
            .fixedSize()
            .help(help)
    }

    /// What a card's header says to VoiceOver besides its kind and title: how many questions it asks (or are left), its
    /// chips, then whether it is shown in full.
    static func spoken(_ card: RouterCard, expanded: Bool) -> String {
        var parts: [String] = []
        let asked = card.triage?.questions.count ?? 0
        if let left = card.left, let total = card.total {
            parts.append("\(left.count) of \(total) questions left")
        } else if asked > 1 {
            parts.append("\(asked) questions")
        }
        if let triage = card.triage {
            if triage.circles { parts.append("going in circles") }
            if triage.unverified { parts.append("unverified") }
            if let work = triage.workLabel { parts.append("changes \(work)") }
        }
        parts.append(expanded ? "expanded" : "collapsed")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Origin

/// "⚡ from <category> · <thing>": the session was started by an inbox action.
struct OriginTag: View {
    let origin: SessionOrigin

    var body: some View {
        Text(origin.label).cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1).truncationMode(.tail)
            .accessibilityLabel("Started by an action: \(origin.category), \(origin.thing)")
    }
}

// MARK: - Card

/// A card's project as it shows: its folder's name and colour (`Store.routerProject`).
typealias RouterProject = (name: String, color: Color?)

/// An open card in Needs you, warm and solid: a summary row (icon, title, kind, a line of what it asks, project, time) and,
/// for the one shown in full, its form or plan to answer in place, or its text and Mark handled. Clicking its header shows it
/// in full with the composer ready to reply to it; hovering it shows Open in Claude. (Addressed, it is a `HistoryCardLine`.)
struct CardView: View {
    let store: Store
    @Bindable var model: RouterModel
    let card: RouterCard
    let expanded: Bool
    /// Its form or plan held by the hook, and its project, looked up by the zones: the card reads nothing store-wide
    /// itself (its session's glyph is a `CardLead` of its own), so another session's activity doesn't redraw it.
    let form: PendingForm?
    let project: RouterProject
    /// The tallest an open form or plan gets before it scrolls inside.
    var formCap: CGFloat = 400
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cdsColumnWidth) private var columnWidth

    /// Wide enough for an open card's summary on one line.
    private var wide: Bool { columnWidth >= 620 }
    private var marked: Bool { model.selection == card.id || model.highlighted == card.id }
    private var when: Date { card.createdAt }

    /// What the card asks, on one line: the first question still open, else its text (parsed once per text).
    private var excerpt: AttributedString {
        if let first = openQuestions.first { return Self.inline(first) }
        let flat = card.text.split(whereSeparator: \.isNewline).map { $0.drop { "#-* ".contains($0) } }.joined(separator: " ")
        return Self.inline(flat)
    }

    private final class Parsed { let text: AttributedString; init(_ text: AttributedString) { self.text = text } }
    @MainActor private static let parsed: NSCache<NSString, Parsed> = { let c = NSCache<NSString, Parsed>(); c.countLimit = 200; return c }()

    static func inline(_ text: String) -> AttributedString {
        if let hit = parsed.object(forKey: text as NSString) { return hit.text }
        let out = RouterText.inline(text)
        parsed.setObject(Parsed(out), forKey: text as NSString)
        return out
    }

    /// The questions Jev found in the turn's final message that your messages haven't answered.
    private var openQuestions: [String] {
        let all = card.triage?.questions ?? []
        guard let left = card.left else { return all }
        return all.filter(left.contains)
    }

    var body: some View {
        open
            .onHover { hovered = $0 }
            .contextMenu { CardSessionMenu(store: store, sessionID: card.sessionID) }
    }

    /// The header: clicking it shows the card in full and arms the reply.
    private func header<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        Button {
            withAnimation(Theme.Motion.spring.resolved(reduce: reduceMotion)) { model.tap(card.id, store: store) }
        } label: { label() }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel("\(card.kind.label): \(card.title)")
            .accessibilityValue(TriageChips.spoken(card, expanded: expanded))
            .accessibilityAddTraits(expanded ? .isSelected : [])
            .accessibilityHint("Shows it in full and replies to it")
            .accessibilityAction(named: "Open in Claude") { openInClaude() }
    }

    private var hoverOpen: some View { HoverOpen(title: card.title, shown: hovered) { openInClaude() } }

    private func openInClaude() { model.open(card.id, store: store) }

    // MARK: Open

    private var open: some View {
        let warm = card.kind == .approval ? RouterTriage.approvalTint : CDS.Fill.warning
        return VStack(alignment: .leading, spacing: 0) {
            header { summary(project: project) }
            if let left = card.left, let total = card.total {
                Text("\(left.count) of \(total) left").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                    .padding(.horizontal, 14).padding(.bottom, expanded ? 4 : 7).padding(.top, -3)
                    .padding(.leading, wide ? 28 : 0)
            }
            if let origin = card.origin {
                OriginTag(origin: origin).padding(.horizontal, 14).padding(.bottom, expanded ? 4 : 7).padding(.top, -3)
                    .padding(.leading, wide ? 28 : 0)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    content(form: form)
                    if !(wide && form != nil) { markHandled(icon: false) }
                }
                .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.wash(warm, expanded ? 0.15 : hovered ? 0.13 : 0.09)))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(warm.opacity(marked || expanded || focused ? 0.8 : 0.4), lineWidth: marked ? 1.5 : 1)
        }
        .shadow(color: warm.opacity(expanded ? 0.10 : 0), radius: 10, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.kind.label): \(card.title)")
        .accessibilityAction(named: "Mark handled") { model.address(card.id, store: store) }
    }

    /// Who, what kind, what it asks and when: one line when there is room, else two.
    private func summary(project: RouterProject) -> some View {
        let title = Text(card.title).cdsText((14, 20), .semibold, CDS.Text.primary).lineLimit(1)
        let age = Text(shortAgo(when)).cdsText((12, 16), .regular, CDS.Text.secondary).monospacedDigit().fixedSize()
        let ask = Text(excerpt).cdsText((13, 18), .regular, CDS.Text.secondary).lineLimit(1).truncationMode(.tail)
        // A form has its own buttons: Mark handled sits in the header beside it.
        let handle = expanded && wide && form != nil
        return VStack(alignment: .leading, spacing: 1) {
            if wide {
                HStack(spacing: 8) {
                    lead
                    title.layoutPriority(2)
                    KindTag(kind: card.kind)
                    TriageChips(triage: card.triage)
                    if !expanded { ask.padding(.leading, 4).layoutPriority(0) }
                    Spacer(minLength: 4)
                    projectLabel(project)
                    age
                    if handle { markHandled(icon: true) }
                    hoverOpen
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { lead; title; KindTag(kind: card.kind); TriageChips(triage: card.triage); Spacer(minLength: 4); projectLabel(project); age; hoverOpen }
                    HStack(spacing: 8) { lead; title; KindTag(kind: card.kind); Spacer(minLength: 4); age; hoverOpen }
                    HStack(spacing: 8) { lead; title; Spacer(minLength: 4); age; hoverOpen }
                }
                // Under the title, past the glyph's room when it has one.
                if !expanded { HStack(spacing: 8) { CardLead(store: store, sessionID: card.sessionID, room: true); ask } }
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, wide ? 6 : expanded ? 8 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func markHandled(icon: Bool) -> some View {
        if icon {
            ClaudeButton(icon: "checkmark", label: "Mark handled", variant: .ghost, size: .sm) { model.address(card.id, store: store) }
        } else if card.kind.isTurn {
            ClaudeButton("Mark handled", primary: true, size: .sm, icon: "checkmark") { model.address(card.id, store: store) }
        } else {
            ClaudeButton("Mark handled", variant: .ghost, size: .sm, icon: "checkmark") { model.address(card.id, store: store) }
        }
    }

    private var lead: some View { CardLead(store: store, sessionID: card.sessionID) }

    private func projectLabel(_ project: RouterProject) -> some View {
        ProjectLabel(name: project.name, color: project.color)
            .cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1).fixedSize()
    }

    /// The card's full content: its form or plan (capped, scrolling inside), else what it said.
    @ViewBuilder private func content(form: PendingForm?) -> some View {
        if let form {
            ScrollView {
                Group {
                    if form.isPlan { CodePlanCard(form: form, card: card.id, store: store, model: model) }
                    else { CodeFormCard(form: form, card: card.id, store: store, model: model) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: formCap)
            .fixedSize(horizontal: false, vertical: true)
        } else if !openQuestions.isEmpty {
            // What it asks, as it asked it; what the turn did under it.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(openQuestions, id: \.self) { question in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "questionmark.circle").font(.system(size: 11, weight: .medium)).foregroundStyle(card.kind.color)
                        Text(RouterText.inline(question)).cdsText((13, 18), .regular, CDS.Text.primary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                if card.text != RouterFeed.placeholder {
                    CDSProse(text: card.text, color: CDS.Text.secondary, inset: false).padding(.top, 2)
                }
            }
        } else {
            CDSProse(text: card.text, color: card.kind == .stuck ? CDS.Text.danger : CDS.Text.primary, inset: false)
        }
    }
}

// MARK: - Ask-back card

/// "Where should this go?": a message the Router couldn't place with confidence. The top targets are buttons, "Something else…"
/// lists every session and project, and typing a target's name in the composer answers it too. Nothing is sent until you pick.
private struct AskBackCard: View {
    let store: Store
    let ask: RouterAskBack

    var body: some View {
        let warm = CDS.Fill.warning
        let pickers = store.routerDispatcher.pickerOptions()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble").font(.system(size: 13, weight: .medium)).foregroundStyle(warm)
                Text("Where should this go?").cdsText((14, 20), .semibold, CDS.Text.primary)
                Spacer(minLength: 4)
                Text(shortAgo(ask.at)).cdsText((12, 16), .regular, CDS.Text.secondary).monospacedDigit()
            }
            Text("“\(RouterDecision.clip(ask.message, 160))”")
                .cdsText((13, 18), .regular, CDS.Text.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                // What can still be sent to: a card hidden since it was offered (its session's tasks running) has no button.
                ForEach(ask.options.filter { store.routerDispatcher.eligible($0.target, store: store) }) { option in
                    ClaudeButton(option.title + (option.detail.isEmpty ? "" : " · \(option.detail)"), variant: .secondary, size: .sm) {
                        store.routerDispatcher.pick(ask.id, target: option.target)
                    }
                }
                Menu {
                    if !pickers.sessions.isEmpty {
                        Section("Send to a session") {
                            ForEach(pickers.sessions) { option in
                                Button("\(option.title) · \(option.detail)") { store.routerDispatcher.pick(ask.id, target: option.target) }
                            }
                        }
                    }
                    if !pickers.projects.isEmpty {
                        Section("Start a session in") {
                            ForEach(pickers.projects) { option in
                                Button(option.detail) { store.routerDispatcher.pick(ask.id, target: option.target) }
                            }
                        }
                    }
                } label: {
                    Text("Something else…").cdsText((13, 18), .medium, CDS.Text.secondary)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CDS.Fill.field))
                        .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                ClaudeButton("Dismiss", variant: .ghost, size: .sm) { store.routerDispatcher.dismiss(ask.id) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.wash(warm, 0.15)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(warm.opacity(0.8), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where should this go? \(ask.message)")
    }
}
