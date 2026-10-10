import SwiftUI

// MARK: - Sidebar

/// Claude's Code-tab sidebar, compact density with the hub rail (docs/design/spec/global-sidebar-titlebar.md §2): the 46pt
/// title row under the window's buttons, the search field, the New row and a nav row (the Router itself), then the cards by
/// what they need, each with Claude's status dot.
struct RouterSidebar: View {
    let store: Store
    @Bindable var model: RouterModel

    typealias M = CDS.Sidebar

    var body: some View {
        // The cards' sections are the model's, which the keys walk in the same order.
        let (needs, done, earlier) = model.sections(store)
        let working = store.allAgentRows.filter { $0.group == .working }
        // Searching also finds any session, listed or not, to open in Claude.
        let found = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : Array(store.searchSessions(query).prefix(8))
        var sections: [(String, [AnyView])] = []
        if !needs.isEmpty { sections.append(("Needs you", needs.map { cardRow($0) })) }
        if !done.isEmpty { sections.append(("Done", done.map { cardRow($0) })) }
        if !working.isEmpty {
            sections.append(("Working", working.map { row in
                AnyView(SidebarRow(dot: .working, glyph: row, title: row.session.title, on: false,
                               action: { pick(row) }, openInClaude: { store.openAgent(row.id) })
                    .contextMenu { SessionMenu(row: row, store: store) }
                    .accessibilityIdentifier(Self.workingRowID))
            }))
        }
        if !earlier.isEmpty { sections.append(("Earlier", earlier.map { cardRow($0) })) }
        if !found.isEmpty {
            sections.append(("Sessions", found.map { row in
                AnyView(SidebarRow(dot: ClaudeDot.Kind(row), glyph: row, title: row.session.title, on: false,
                               action: { pick(row) }, openInClaude: { store.openAgent(row.id) })
                    .contextMenu { SessionMenu(row: row, store: store) })
            }))
        }

        return VStack(alignment: .leading, spacing: 0) {
            // The title row (§2.2): room for the window's buttons. Lookout has no sidebar toggle, back/forward or
            // Chat|Code switch, so it is only the drag area.
            Color.clear.frame(height: M.titleRow)
            VStack(alignment: .leading, spacing: 0) {
                search
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // §2.4: the nav rows (here the Router's own chat).
                        NavRow(symbol: "bubble.left", title: "Router", on: model.selection == nil) {
                            model.select(nil, store: store)
                        }
                        .padding(.bottom, M.navGap)
                        // `[data-testid=nav-pin-rows] > .h-3`.
                        Color.clear.frame(height: 12)
                        ForEach(sections.indices, id: \.self) { i in
                            if i > 0 { Color.clear.frame(height: M.sectionGap) }
                            section(sections[i].0, sections[i].1)
                        }
                        if sections.isEmpty {
                            Text(query.isEmpty ? "Nothing needs you" : "No match").cdsText(CDS.Density.compact.body, .regular, CDS.Text.muted)
                                .padding(.leading, M.labelInset).padding(.top, M.groupTop)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
            .padding(.top, 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .font(CDS.sans(M.rowFont))
    }

    private var query: String { model.search }

    /// What each row of the Working section is identified by in the accessibility tree.
    static let workingRowID = "router-working-row"

    /// §2.3: a 26pt field, white 5% with a 1pt white 10% inset ring, the magnifying glass in a 24pt slot, muted text.
    private var search: some View { SearchField(query: $model.search, wanted: $model.searchWanted) }

    private func cardRow(_ card: RouterCard) -> AnyView {
        AnyView(SidebarRow(dot: ClaudeDot.Kind(card), glyph: store.sessionRow(card.sessionID), title: card.title,
                           on: model.selection == card.id, action: {
            model.reply(to: card.id, store: store)
        }, openInClaude: { store.openAgent(card.sessionID) }))
    }

    /// A session row clicked: its newest card is picked and armed for a reply; one with no card opens in Claude.
    private func pick(_ row: AgentRow) {
        if let card = store.routerCards.first(where: { $0.sessionID == row.id }) {
            model.reply(to: card.id, store: store)
        } else {
            store.openAgent(row.id)
        }
    }

    /// §2.6: a group label, 12/16 muted, 12 above and 4 below, its text inset 10; then the rows at a 27.5 pitch.
    private func section(_ title: String, _ rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).cdsText((M.groupFont, 16), .regular, CDS.Text.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: M.labelMinHeight - M.groupTop - 4, alignment: .leading)
                .padding(.leading, M.labelInset)
                .padding(.top, M.groupTop).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows.indices, id: \.self) { rows[$0].padding(.bottom, M.sessionGap) }
        }
    }
}

private struct SearchField: View {
    @Binding var query: String
    /// Set to ask for the keyboard (the sessions shortcut); taken once the field has it.
    @Binding var wanted: Bool
    @State private var hovered = false
    @FocusState private var focused: Bool
    typealias M = CDS.Sidebar

    private func takeWanted() {
        guard wanted else { return }
        wanted = false
        DispatchQueue.main.async { focused = true }
    }

    var body: some View {
        HStack(spacing: M.rowGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: M.symbol, weight: .medium))
                .foregroundStyle(CDS.Text.muted)
                .frame(width: M.leadingSlot, height: M.leadingSlot)
                .padding(.leading, M.railShift / 2)
            // The label is muted (§2.3); what you type is primary.
            TextField("Search", text: $query, prompt: Text(""))
                .textFieldStyle(.plain)
                .font(CDS.sans(M.rowFont))
                .foregroundStyle(CDS.Text.primary)
                .accessibilityLabel("Search sessions")
                .focused($focused)
                .background(alignment: .leading) {
                    if query.isEmpty {
                        Text("Search").font(CDS.sans(M.rowFont)).foregroundStyle(CDS.Text.muted)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        }
        .padding(.horizontal, M.rowPadding)
        .frame(height: M.rowHeight)
        .background(RoundedRectangle(cornerRadius: M.radius, style: .continuous)
            .fill(hovered ? CDS.Fill.secondaryHover : CDS.Fill.field)
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1))
        .overlay(RoundedRectangle(cornerRadius: M.radius, style: .continuous)
            .strokeBorder(hovered ? Color.clear : CDS.border, lineWidth: 1))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.06), value: hovered)
        .onChange(of: wanted) { takeWanted() }
        .onAppear { takeWanted() }
        .padding(.horizontal, M.railShift / 2)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Claude's row primitive (§2.5, §2.7): 26 tall, radius 6, 2 padding, a 24pt leading slot shifted 4 by the hub rail, a 4 gap,
/// 13pt text at wght 360 in secondary; white 7.5% on hover, 15% and primary text when picked. An overflowing title fades out
/// over its last 24pt instead of an ellipsis.
struct SidebarRowButton<Leading: View>: View {
    let title: String
    var titleColor: Color = CDS.Text.secondary
    let on: Bool
    let action: () -> Void
    /// A trailing icon button shown on hover ("Open in Claude"), overlaid so the row's layout stays as it is.
    var openInClaude: (() -> Void)?
    @ViewBuilder let leading: (_ hovered: Bool) -> Leading
    @State private var hovered = false
    typealias M = CDS.Sidebar

    var body: some View {
        Button(action: action) {
            HStack(spacing: M.rowGap) {
                leading(hovered)
                    .frame(width: M.leadingSlot, height: M.leadingSlot)
                    .padding(.leading, M.railShift)
                Text(title)
                    .font(CDS.sans(M.rowFont))
                    .foregroundStyle(on ? CDS.Text.primary : titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .mask(HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                    })
            }
            .padding(.horizontal, M.rowPadding)
            .frame(height: M.rowHeight)
            .background(RoundedRectangle(cornerRadius: M.radius, style: .continuous)
                .fill(on ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if let openInClaude {
                Button(action: openInClaude) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CDS.Text.secondary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CDS.Fill.ghostHover))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .opacity(hovered ? 1 : 0)
                .allowsHitTesting(hovered)
                .animation(.easeOut(duration: 0.12), value: hovered)
                .help("Open in Claude")
                .accessibilityLabel("Open \(title) in Claude")
            }
        }
        .onHover { hovered = $0 }
    }
}

/// §2.5: a nav row, its 16pt icon in secondary (primary when picked).
private struct NavRow: View {
    let symbol: String
    let title: String
    let on: Bool
    let action: () -> Void
    typealias M = CDS.Sidebar

    var body: some View {
        SidebarRowButton(title: title, on: on, action: action) { _ in
            Image(systemName: symbol)
                .font(.system(size: M.symbol, weight: .medium))
                .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
        }
    }
}

/// A session row (§2.7): Claude's status dot in the leading slot.
struct SidebarRow: View {
    let dot: ClaudeDot.Kind
    /// The session behind it, when there is one: its icon takes the dot's place, the dot on its corner.
    var glyph: AgentRow?
    let title: String
    let on: Bool
    let action: () -> Void
    var openInClaude: (() -> Void)?

    var body: some View {
        SidebarRowButton(title: title, on: on, action: action, openInClaude: openInClaude) { _ in
            if let glyph {
                SessionGlyph(row: glyph, size: 18, dot: false)
                    .overlay(alignment: .topTrailing) {
                        if dot != .quiet {
                            ClaudeDot(kind: dot).scaleEffect(0.8)
                                .background(Circle().fill(Color.black).frame(width: 9, height: 9))
                                .offset(x: 5, y: -5)
                        }
                    }
            } else {
                ClaudeDot(kind: dot)
            }
        }
    }
}

/// Claude's session status dot (§1.7), 6pt in a 14pt box: awaiting #fab219 (a question or a plan), ready #2a78d6 (a
/// finished turn), running #898781 blinking (a working session), idle a 1pt hollow ring at 50% (addressed). Claude has no
/// "stuck" state; Lookout's stuck card keeps a red 6pt dot (`CDS.Text.danger`).
struct ClaudeDot: View {
    enum Kind {
        case needsYou, done, stuck, working, quiet

        init(_ card: RouterCard) {
            guard card.isOpen else { self = .quiet; return }
            switch card.kind {
            case .question, .plan: self = .needsYou
            case .stuck: self = .stuck
            case .done: self = .done
            }
        }
    }

    let kind: Kind

    var body: some View {
        ZStack {
            switch kind {
            case .needsYou: Circle().fill(CDS.Fill.warning).frame(width: 6, height: 6)
            case .done: Circle().fill(CDS.Fill.accent).frame(width: 6, height: 6)
            case .stuck: Circle().fill(CDS.Text.danger).frame(width: 6, height: 6)
            case .quiet: Circle().strokeBorder(CDS.Text.muted, lineWidth: 1).frame(width: 6, height: 6).opacity(0.5)
            case .working: BlinkingDot()
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// `dframe-dot-blink`: 1.2s ease-in-out, opacity .3 → 1 → .3, forever.
private struct BlinkingDot: View {
    @State private var lit = false
    var body: some View {
        Circle().fill(CDS.Text.muted).frame(width: 6, height: 6)
            .opacity(lit ? 1 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { lit = true }
            }
    }
}

/// Claude's "···" while it works, in clay.
struct WorkingDots: View {
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3) { i in Circle().fill(Theme.claude.opacity(1 - Double(i) * 0.3)).frame(width: 2.5, height: 2.5) }
        }
    }
}
