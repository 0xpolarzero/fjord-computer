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
        /// An overview you asked for.
        case overview(RouterOverview)

        var id: String {
            switch self {
            case .overview(let o): "overview-" + o.id.uuidString
            case .decision(let d): d.id.uuidString
            case .card(let c): c.id
            }
        }

        var date: Date {
            switch self {
            case .card(let c): c.addressedAt ?? c.createdAt
            case .decision(let d): d.at
            case .overview(let o): o.at
            }
        }
    }

    /// Open cards: what blocks a session first (questions, plans, stuck turns), then the finished turns; newest first in each
    /// part, as the sidebar lists them (the arrow keys walk the same order).
    var needs: [RouterCard] = []
    /// Messages waiting for you to say where they go (nothing is sent until you do), above the cards.
    var asks: [RouterAskBack] = []
    /// Sessions working on their own, the longest running first.
    var working: [AgentRow] = []
    /// Oldest first: the Router's runs, the overviews and the addressed cards by time.
    var history: [Entry] = []

    /// The card shown in full: the one asked for while it is still waiting, else the newest.
    func openNeed(preferred: String?) -> String? {
        if let preferred, needs.contains(where: { $0.id == preferred }) { return preferred }
        return needs.first?.id
    }

    static func make(cards: [RouterCard], working: [AgentRow],
                     decisions: [RouterDecision] = [], overviews: [RouterOverview] = [], asks: [RouterAskBack] = []) -> RouterPage {
        let open = cards.filter(\.isOpen).sorted(by: newestFirst)
        var page = RouterPage()
        page.needs = open.filter { $0.kind != .done } + open.filter { $0.kind == .done }
        page.working = working
        page.asks = asks
        let entries = decisions.map(Entry.decision) + overviews.map(Entry.overview) + cards.filter { !$0.isOpen }.map(Entry.card)
        page.history = entries.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }.map(\.element)
        return page
    }

    private static func newestFirst(_ a: RouterCard, _ b: RouterCard) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
    }
}

extension Store {
    /// The Router's page on what is stored and what runs now.
    var routerPage: RouterPage {
        .make(cards: router.cards, working: routerWorkingRows, decisions: router.decisions,
              overviews: router.overviews, asks: routerDispatcher.askBacks)
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

    private var spring: Animation? { Theme.Motion.spring.resolved(reduce: reduceMotion) }

    var body: some View {
        let page = store.routerPage
        // A session moving between the zones is the same card travelling, unless it has one in both.
        let once = Dictionary(grouping: page.needs.map(\.sessionID), by: { $0 }).filter { $0.value.count == 1 }.keys
        let bothZones = Set(page.working.map(\.id))
        let travelling = Set(once).subtracting(bothZones)
        VStack(spacing: 0) {
            RouterHistory(store: store, model: model, page: page)
            VStack(spacing: 0) {
                routerStatus
                RouterZones(store: store, model: model, page: page, height: height, ns: ns, travelling: travelling,
                            travellingWorking: Set(page.working.map(\.id)).subtracting(Set(page.needs.map(\.sessionID))))
            }
            .frame(maxWidth: CDS.Transcript.measure + 2 * CDS.Transcript.gutter)
            .frame(maxWidth: .infinity)
        }
        .motion(Theme.Motion.spring, value: page.needs.map(\.id) + page.working.map(\.id))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { height = $0.height; width = $0.width }
        .environment(\.routerGutter, gutter)
        .environment(\.cdsColumnWidth, min(CDS.Transcript.measure, max(0, width - 2 * gutter)))
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

/// The timeline above the zones: opens at the bottom, keeps its place when something arrives above, loads lazily.
private struct RouterHistory: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    @Environment(\.routerGutter) private var gutter

    var body: some View {
        let entries = page.history
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !entries.isEmpty {
                        Text("History").cdsText((12, 16), .medium, CDS.Text.muted)
                            .padding(.leading, CDS.Transcript.textInset)
                            .padding(.bottom, 14)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                        row(entry)
                            // A line sits close to its neighbours.
                            .padding(.top, i == 0 ? 0 : 2)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id(RouterModel.endID)
                }
                .frame(maxWidth: CDS.Transcript.measure, alignment: .leading)
                .padding(.horizontal, gutter)
                .frame(maxWidth: .infinity)
                .padding(.top, CDS.Transcript.fade)
                .padding(.bottom, 20)
            }
            .cdsTopFade()
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.revealRequest, initial: false) { _, request in
                guard let request, entries.contains(where: { $0.id == request.id }) || request.id == RouterModel.endID else { return }
                withAnimation(Theme.Motion.hover) { proxy.scrollTo(request.id, anchor: request.id == RouterModel.endID ? .bottom : .center) }
            }
            // A message asked for (an action's chip): after the page is shown.
            .onChange(of: model.messageRequest, initial: true) { _, request in
                guard let request, let id = UUID(uuidString: request.id) else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(Theme.Motion.hover) { proxy.scrollTo(id.uuidString, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ entry: RouterPage.Entry) -> some View {
        switch entry {
        case .card(let card):
            HistoryCardLine(store: store, model: model, card: card)
        case .decision(let decision):
            HistoryDecisionLine(store: store, model: model, decision: decision)
        case .overview(let overview):
            HistoryOverviewLine(overview: overview)
        }
    }
}

/// An addressed item in the history: one line (icon, title, how it was addressed, when), opening on click.
private struct HistoryCardLine: View {
    let store: Store
    @Bindable var model: RouterModel
    let card: RouterCard
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var open: Bool { model.expanded.contains(card.id) }
    private var canReopen: Bool { card.addressedBy != .superseded && card.addressedBy != .gone }
    private var how: String {
        if let note = card.addressedNote { return "addressed by your message: \(RouterDecision.clip(note, 60))" }
        return card.addressedBy?.label ?? "Addressed"
    }
    private var marked: Bool { model.selection == card.id || model.highlighted == card.id }

    var body: some View {
        let project = store.routerProject(card)
        let when = card.addressedAt ?? card.createdAt
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle() } label: {
                HStack(spacing: 8) {
                    if let session = store.sessionRow(card.sessionID) {
                        SessionGlyph(row: session, size: 16, dot: false).opacity(0.7)
                    } else {
                        Image(systemName: card.kind.symbol).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16)
                    }
                    Text(card.title).cdsText(CDS.Transcript.text, .regular, hovered || open ? CDS.Text.secondary : CDS.Text.muted)
                        .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    Text("· \(how)").cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                    StatusCaret(hot: hovered, open: open)
                    Spacer(minLength: 8)
                    Text(shortAgo(when)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
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
            .onHover { hovered = $0 }
            .accessibilityLabel("\(card.kind.label): \(card.title)")
            .accessibilityValue("\(how), \(AgentRow.spokenAge(Date().timeIntervalSince(when))) ago, \(open ? "expanded" : "collapsed")")
            .accessibilityAction(named: "Open in Claude") { store.openAgent(card.sessionID) }
            .contextMenu { if let s = store.sessionRow(card.sessionID) { SessionMenu(row: s, store: store) } }

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        KindTag(kind: card.kind)
                        ProjectLabel(name: project.name, color: project.color)
                            .cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1)
                        if let origin = card.origin { OriginTag(origin: origin) }
                    }
                    CDSProse(text: card.text, color: CDS.Text.secondary, inset: false)
                    HStack(spacing: 6) {
                        if canReopen {
                            ClaudeButton("Reopen", variant: .secondary, size: .sm, icon: "arrow.uturn.backward") {
                                model.reopen(card.id, store: store)
                            }
                        }
                        ClaudeButton("Open in Claude", variant: .ghost, size: .sm, icon: "arrow.up.right.square") {
                            store.openAgent(card.sessionID)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).fill(CDS.Fill.field))
                .overlay { RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
                .padding(.top, 6).padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func toggle() {
        withAnimation(Theme.Motion.spring.resolved(reduce: reduceMotion)) {
            if open { model.expanded.remove(card.id) } else { model.expanded.insert(card.id) }
        }
    }
}

/// An overview in the history: one line (icon, the text, when); the whole text on hover.
private struct HistoryOverviewLine: View {
    let overview: RouterOverview
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft").font(.system(size: 10, weight: .medium))
                .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16)
            Text(overview.text).cdsText(CDS.Transcript.text, .regular, hovered ? CDS.Text.secondary : CDS.Text.muted)
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Spacer(minLength: 8)
            Text(shortAgo(overview.at)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
        }
        .padding(.horizontal, CDS.Transcript.statusPad)
        .frame(height: CDS.Transcript.statusRow)
        .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
            .fill(hovered ? CDS.Fill.ghostHover : .clear))
        .onHover { hovered = $0 }
        .help(overview.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overview")
        .accessibilityValue("\(overview.text), \(AgentRow.spokenAge(Date().timeIntervalSince(overview.at))) ago")
    }
}

/// A run in the history: one line (icon, what set it off, what was done, when), opening to show the trigger, what was done and
/// its links (the session, the change with its Revert).
private struct HistoryDecisionLine: View {
    let store: Store
    @Bindable var model: RouterModel
    let decision: RouterDecision
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var key: String { decision.id.uuidString }
    private var open: Bool { model.expanded.contains(key) }
    /// While a typed run is under way, how far it is (classifying, sending…); else how it ended.
    private var status: String {
        decision.outcome == .pending ? store.routerDispatcher.progress[decision.id].map { $0 + "…" } ?? decision.summary : decision.summary
    }

    var body: some View {
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
                    Text(shortAgo(decision.at)).cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
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

            if open { details.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private var details: some View {
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).fill(CDS.Fill.field))
        .overlay { RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
        .padding(.top, 6).padding(.bottom, 4)
    }

    private func toggle() {
        withAnimation(Theme.Motion.spring.resolved(reduce: reduceMotion)) {
            if open { model.expanded.remove(key) } else { model.expanded.insert(key) }
        }
    }
}

// MARK: - Zones

/// Working over Needs you, pinned above the composer. Each caps at a share of the page and scrolls inside.
private struct RouterZones: View {
    let store: Store
    @Bindable var model: RouterModel
    let page: RouterPage
    let height: CGFloat
    let ns: Namespace.ID
    /// Sessions whose card moves between the zones (matched geometry), from the needs side and from the working side.
    let travelling: Set<String>
    let travellingWorking: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.routerGutter) private var gutter
    @Environment(\.cdsColumnWidth) private var columnWidth
    @State private var overviewer = RouterOverviewer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !page.working.isEmpty { working }
            needs
        }
        .padding(.horizontal, gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(CDS.border).frame(height: CDS.hairline) }
    }

    // MARK: Working

    private var working: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WorkingMark()
                Text("Working").cdsText((12, 16), .medium, CDS.Text.muted)
                Text("· \(page.working.count)").cdsText((12, 16), .regular, CDS.Text.muted).monospacedDigit()
            }
            .padding(.leading, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Working, \(page.working.count)")
            overview
            ZoneScroll(maxHeight: max(88, height * 0.18), reveal: model.revealRequest,
                         ids: Set(page.working.map { RouterModel.workingID($0.id) })) {
                VStack(spacing: 0) {
                    ForEach(Array(page.working.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Rectangle().fill(CDS.border.opacity(0.6)).frame(height: CDS.hairline) }
                        WorkingCard(store: store, model: model, row: row)
                            .id(RouterModel.workingID(row.id))
                            .matched(travellingWorking.contains(row.id) ? row.id : nil, in: ns)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.border.opacity(0.7), lineWidth: 1) }
            }
        }
    }

    /// One line over all the working sessions, the Overview button, and the newest overview under them.
    private var overview: some View {
        MinuteTicking { now in
            let items = store.overviewItems(now: now)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let line = RouterOverviewLine.text(items) {
                        Text(line).cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1).truncationMode(.tail)
                            .help(RouterOverviewLine.tooltip(items))
                    }
                    Spacer(minLength: 4)
                    OverviewButton(overviewer: overviewer) { overviewer.request(store: store) }
                }
                if let error = overviewer.error {
                    Text(error).cdsText((12, 16), .regular, CDS.Fill.warning).lineLimit(2)
                }
                if let last = store.router.overviews.last {
                    (Text(last.at.formatted(date: .omitted, time: .shortened) + " · ").foregroundStyle(CDS.Text.muted)
                        + Text(last.text).foregroundStyle(CDS.Text.secondary))
                        .cdsText((12, 16), .regular, CDS.Text.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Latest overview, \(last.text)")
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Needs you

    @ViewBuilder private var needs: some View {
        let open = page.openNeed(preferred: model.expandedNeed)
        let wide = columnWidth >= 620
        // What an open form may take: the page less the other rows, the working zone and a sliver of history.
        let working = page.working.isEmpty ? 0 : 24 + CGFloat(page.working.count) * 34 + 12 + 40
        let rows = CGFloat(max(0, page.needs.count - 1)) * (wide ? 40 : 58)
        let formCap = max(180, min(400, height - working - 28 - rows - (wide ? 52 : 100) - 24 - 12 - 24))
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
                ZoneScroll(maxHeight: max(220, height * 0.9), reveal: model.revealRequest,
                           ids: Set(page.needs.map(\.id) + page.asks.map { $0.id.uuidString })) {
                    VStack(spacing: 6) {
                        ForEach(page.asks) { ask in
                            AskBackCard(store: store, ask: ask)
                                .id(ask.id.uuidString)
                                .transition(.asymmetric(insertion: .scaleFade(0.97, reduce: reduceMotion).combined(with: .opacity),
                                                        removal: .scaleFade(0.97, reduce: reduceMotion)))
                        }
                        ForEach(page.needs) { card in
                            NeedsCard(store: store, model: model, card: card, expanded: card.id == open, formCap: formCap)
                                .id(card.id)
                                .matched(travelling.contains(card.sessionID) ? card.sessionID : nil, in: ns)
                                .transition(.asymmetric(insertion: .scaleFade(0.97, reduce: reduceMotion).combined(with: .opacity),
                                                        removal: .scaleFade(0.97, reduce: reduceMotion)))
                        }
                    }
                    // The card's ring and shadow need a little room inside the scroll.
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

/// "Summarize what's happening": a small icon button, a spinner while it runs.
private struct OverviewButton: View {
    let overviewer: RouterOverviewer
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if overviewer.busy { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                else { Image(systemName: "text.alignleft").font(.system(size: 11, weight: .medium)) }
            }
            .foregroundStyle(hovered ? CDS.Text.secondary : CDS.Text.muted)
            .frame(width: 22, height: 20)
            .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                .fill(hovered && !overviewer.busy ? CDS.Fill.ghostHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(overviewer.busy)
        .onHover { hovered = $0 }
        .help("Summarize what's happening")
        .accessibilityLabel("Overview")
        .accessibilityHint("Summarize what's happening")
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
                withAnimation(Theme.Motion.hover) { proxy.scrollTo(request.id, anchor: .center) }
            }
        }
    }
}

// MARK: - Working card

/// A session working on its own: calm and small, one line. Its icon and title, what it is doing now (shimmering), what it
/// left running, and for how long; opening it opens the session in Claude.
private struct WorkingCard: View {
    let store: Store
    @Bindable var model: RouterModel
    let row: AgentRow
    @State private var hovered = false
    @Environment(\.cdsColumnWidth) private var columnWidth

    var body: some View {
        let start = Store.workingStart(row)
        let current = row.session.running ? row.activity?.text ?? "Working" : (row.tasksText ?? "Working")
        // The line composed from its task list and narration, when there is one; the raw step otherwise.
        let explained = store.liveExplanation(row)
        let doing = explained ?? current
        let marked = model.highlighted == RouterModel.workingID(row.id)
        Button { store.openAgent(row.id) } label: {
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
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(marked ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu { SessionMenu(row: row, store: store) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.session.title)
        .accessibilityValue("working, \(row.projectName), \(doing)\(row.tasks.isEmpty ? "" : ", \(row.tasksText ?? "")")")
        .accessibilityHint("Opens it in Claude")
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

// MARK: - Origin

/// "⚡ from <category> · <thing>": the session was started by an inbox action.
struct OriginTag: View {
    let origin: SessionOrigin

    var body: some View {
        Text(origin.label).cdsText((12, 16), .regular, CDS.Text.muted).lineLimit(1).truncationMode(.tail)
            .accessibilityLabel("Started by an action: \(origin.category), \(origin.thing)")
    }
}

// MARK: - Needs-you card

/// A card that needs you, warm and solid: a summary row (icon, title, kind, a line of what it asks, project, time), and,
/// for the one open at a time, its full form or plan to answer in place, or the reply, open and handled buttons.
private struct NeedsCard: View {
    let store: Store
    @Bindable var model: RouterModel
    let card: RouterCard
    let expanded: Bool
    /// The tallest an open form or plan gets before it scrolls inside.
    let formCap: CGFloat
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cdsColumnWidth) private var columnWidth

    /// Wide enough for the summary on one line.
    private var wide: Bool { columnWidth >= 620 }

    private var marked: Bool { model.selection == card.id || model.highlighted == card.id }

    /// What the card asks, on one line.
    private var excerpt: AttributedString {
        let flat = card.text.split(whereSeparator: \.isNewline).map { $0.drop { "#-* ".contains($0) } }.joined(separator: " ")
        return RouterText.inline(flat)
    }

    var body: some View {
        let project = store.routerProject(card)
        let form = store.pendingForm(for: card)
        let warm = CDS.Fill.warning
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.Motion.spring.resolved(reduce: reduceMotion)) { model.expandedNeed = card.id }
            } label: { summary(project: project) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(expanded ? .isSelected : [])
                .accessibilityHint(expanded ? "" : "Shows it in full")
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
                    body(form: form)
                    actions
                }
                .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(warm.opacity(expanded ? 0.15 : hovered ? 0.13 : 0.09)))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(warm.opacity(marked || expanded ? 0.8 : 0.4), lineWidth: marked ? 1.5 : 1)
        }
        .shadow(color: warm.opacity(expanded ? 0.10 : 0), radius: 10, y: 2)
        .onHover { hovered = $0 }
        .contextMenu { if let s = store.sessionRow(card.sessionID) { SessionMenu(row: s, store: store) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.kind.label): \(card.title)")
    }

    /// Who, what kind, what it asks and when: one line when there is room, else two.
    private func summary(project: (name: String, color: Color?)) -> some View {
        let glyph = store.sessionRow(card.sessionID)
        let title = Text(card.title).cdsText((14, 20), .semibold, CDS.Text.primary).lineLimit(1)
        let age = Text(shortAgo(card.createdAt)).cdsText((12, 16), .regular, CDS.Text.secondary).monospacedDigit().fixedSize()
        let ask = Text(excerpt).cdsText((13, 18), .regular, CDS.Text.secondary).lineLimit(1).truncationMode(.tail)
        let handle = expanded && store.pendingForm(for: card) != nil
        return VStack(alignment: .leading, spacing: 1) {
            if wide {
                HStack(spacing: 8) {
                    lead(glyph)
                    title.layoutPriority(2)
                    KindTag(kind: card.kind)
                    if !expanded { ask.padding(.leading, 4).layoutPriority(0) }
                    Spacer(minLength: 4)
                    projectLabel(project)
                    age
                    if handle { handlers }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { lead(glyph); title; KindTag(kind: card.kind); Spacer(minLength: 4); projectLabel(project); age }
                    HStack(spacing: 8) { lead(glyph); title; KindTag(kind: card.kind); Spacer(minLength: 4); age }
                    HStack(spacing: 8) { lead(glyph); title; Spacer(minLength: 4); age }
                }
                if !expanded { ask.padding(.leading, glyph == nil ? 0 : 28) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, wide ? 7 : expanded ? 9 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Open in Claude and Mark handled as icons in the header of an open question or plan (its form has its own buttons).
    private var handlers: some View {
        HStack(spacing: 2) {
            ClaudeButton(icon: "arrow.up.right.square", label: "Open in Claude", variant: .ghost, size: .sm) {
                model.open(card.id, store: store)
            }
            ClaudeButton(icon: "checkmark", label: "Mark handled", variant: .ghost, size: .sm) { model.address(card.id, store: store) }
        }
    }

    @ViewBuilder private func lead(_ session: AgentRow?) -> some View {
        if let session { SessionGlyph(row: session, size: 20, dot: false) }
    }

    private func projectLabel(_ project: (name: String, color: Color?)) -> some View {
        ProjectLabel(name: project.name, color: project.color)
            .cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1).fixedSize()
    }

    /// The card's full content: its form or plan (capped, scrolling inside), else what it said.
    @ViewBuilder private func body(form: PendingForm?) -> some View {
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
        } else {
            CDSProse(text: card.text, color: card.kind == .stuck ? CDS.Text.danger : CDS.Text.primary, inset: false)
        }
    }

    @ViewBuilder private var actions: some View {
        if wide, store.pendingForm(for: card) != nil {
            EmptyView()
        } else { actionRow }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if card.kind.isTurn {
                ClaudeButton("Mark handled", primary: true, size: .sm, icon: "checkmark") { model.address(card.id, store: store) }
                ClaudeButton("Reply", variant: .secondary, size: .sm, icon: "arrowshape.turn.up.left") {
                    model.reply(to: card.id, store: store)
                }
                ClaudeButton("Open in Claude", variant: .ghost, size: .sm, icon: "arrow.up.right.square") {
                    model.open(card.id, store: store)
                }
            } else if columnWidth < 420 {
                handlers
            } else {
                ClaudeButton("Open in Claude", variant: .ghost, size: .sm, icon: "arrow.up.right.square") {
                    model.open(card.id, store: store)
                }
                ClaudeButton("Mark handled", variant: .ghost, size: .sm, icon: "checkmark") { model.address(card.id, store: store) }
            }
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
                ForEach(ask.options) { option in
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
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                ClaudeButton("Dismiss", variant: .ghost, size: .sm) { store.routerDispatcher.dismiss(ask.id) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(warm.opacity(0.15)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(warm.opacity(0.8), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where should this go? \(ask.message)")
    }
}
