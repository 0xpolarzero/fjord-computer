import AppKit
import SwiftUI

// The hub's sections: what goes in the bar's cells and beside them.
//
// One set of measures for every piece, so the sections read as one surface, Claude's compact density on black:
// - section headers are 30pt: the title as Claude's sidebar label (12/16 muted), then a status in its state's colour,
//   trailing actions as Claude's 24pt ghost icon buttons;
// - the inbox's tabs (a category each, then Done) are Claude's Tabs, its counts Claude's Badges, its facts chips;
// - rows pad their content 8 × 5 inside a radius-6 fill (white 7.5% on hover or when picked);
//   the layout adds the one outer inset, so nothing here pads itself from the outside;
// - every control has a tooltip: a verb phrase, then what it does and its shortcut, read from the user's settings.

extension LookoutHub {
    // MARK: Inbox

    /// The GitHub mark: opens the inbox on the first category with something unread, its newest entry picked so the keys
    /// act on it at once.
    var inboxIcon: some View {
        InboxCell(vertical: !edge.isHorizontal) {
            openInbox(on: store.tabNeedingYou)
        }
    }

    /// The full view on a tab, its newest entry picked.
    func openInbox(on tab: InboxTab) {
        withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) {
            hub.go(.main)
            hub.endSearch()
            hub.tab = tab
        }
        if let first = store.entries(in: tab).first {
            hub.selection = "i:" + first.id
            hub.requestScroll("i:" + first.id)
            ui.drawerSelection = nil
        }
    }

    /// One cell per category shown, in order: its symbol, and on its corner what is unread. Hovering one peeks its list.
    @ViewBuilder var categoryCells: some View {
        ForEach(store.shownCategories) { category in
            CategoryCell(category: category, badge: store.badge(category), vertical: !edge.isHorizontal) {
                openInbox(on: .category(category.id))
            }
            .onHover { if $0, !hub.expanded { hub.tab = .category(category.id) } }
        }
    }

    /// The tabs are the inbox's title and status; typing swaps them for the search.
    @ViewBuilder var inboxHeader: some View {
        Group {
            if searching || hub.searchOpen { searchField.transition(.opacity) } else { filters.transition(.opacity) }
        }
        .frame(height: Theme.Metrics.line)
    }

    var searchField: some View {
        InboxSearchField(hub: hub, ui: ui, store: store, count: searchCount)
    }

    /// What the search found, by kind: "3 items · 2 sessions".
    var searchCount: String {
        let found = items.count
        let sessions = store.agents.enabled ? store.hubSessions(hub).count : 0
        if found == 0 && sessions == 0 { return "No match" }
        return [found == 0 ? nil : plural(found, "item"), sessions == 0 ? nil : plural(sessions, "session")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var filters: some View {
        let tab = store.hubTab(hub)
        let unread = tab == .done ? 0 : store.entries(in: tab).filter(\.isUnread).count
        // Claude's Tabs abut: each pill is inset 1 at its sides, so two pills are 2 apart.
        return HStack(spacing: 0) {
            // The tabs scroll when the column is narrow: the actions after them stay.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(store.shownCategories) { category in categoryTab(category, selected: tab == .category(category.id)) }
                }
            }
            .scrollIndicators(.never)
            .mask(tabsFade)
            // Done is not a category: after a gap and a rule, at the tabs' trailing end.
            doneTab(selected: tab == .done).padding(.leading, 6)
            Spacer(minLength: 2)
            // The header's own buttons, apart from the tabs.
            IslandRule(axis: .vertical).frame(height: 14).padding(.horizontal, 3)
            if unread > 0 {
                IconButton(symbol: "checkmark.circle", help: "Mark all as seen",
                           detail: "Everything in \(store.category(tab)?.name ?? "Done") · \(store.shortcut(.markAllRead).display)",
                           size: IconButton.Size.header) {
                    withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) { store.markAllSeen(tab) }
                }
                .transition(.opacity)
            }
            categoriesMenu
            if showsDetail { focusButton(.inbox) }
        }
        .padding(.trailing, 3)
        .motion(Theme.Motion.fade, value: unread > 0)
    }

    /// The tabs' end fades out where more are scrolled out of sight.
    private var tabsFade: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 12)
        }
    }

    func categoryTab(_ category: InboxCategory, selected: Bool) -> some View {
        let n = store.badge(category)
        return CategoryTab(category: category, selected: selected, badge: n, store: store) {
            withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) { hub.tab = .category(category.id) }
        }
    }

    func doneTab(selected: Bool) -> some View {
        Button {
            withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) { hub.tab = .done }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "archivebox").font(.system(size: 12, weight: .medium))
                if selected { Text("Done") }
            }
            .font(CDS.sans(13, .medium))
            .foregroundStyle(selected ? CDS.Text.primary : CDS.Text.muted)
            .padding(.horizontal, selected ? CDS.Tabs.pad : 4)
            .frame(height: CDS.Tabs.height)
        }
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Tabs.radius, style: .continuous),
                                          hover: CDS.Fill.ghostHover, active: CDS.Fill.ghostHover,
                                          pressed: CDS.Fill.ghostHover, isActive: selected))
        .accessibilityLabel("Done")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .fixedSize()
        .tip("Done", "What you marked Done · it comes back when something new happens")
    }

    /// Like a table's columns menu: a checkmark per category shown. Hidden ones are muted (no notifications, no icon in
    /// the bar) and still collect, so the menu says how many each holds.
    var categoriesMenu: some View {
        CategoriesMenu(store: store) { hub.go(.categories) }
    }

    /// One quiet line where the list would be: nothing to act on, so nothing to draw the eye.
    var emptyInbox: some View {
        let tab = store.hubTab(hub)
        let text: String = if searching {
            "No inbox item matches"
        } else if store.shownCategories.isEmpty && tab == .done && store.categories.isEmpty == false {
            "Every category is hidden"
        } else if tab == .done {
            "Nothing here yet"
        } else if store.category(tab)?.isCI == true {
            "Everything is passing"
        } else {
            "All caught up"
        }
        return HStack(spacing: 0) {
            Text(text).font(Theme.Typography.body).foregroundStyle(Theme.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 5)
    }

    func itemRow(_ entry: InboxEntry) -> some View {
        EntryRow(entry: entry, store: store, ui: ui, hub: hub).capEdge()
    }

    /// A line of text with a link after it, padded like a row ("No CI shown  Choose repositories").
    func linkRow(_ text: String, action: String, _ perform: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text).foregroundStyle(Theme.tertiary)
            Button(action, action: perform).buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.control)
        .padding(.horizontal, Theme.Space.md)
        .frame(minHeight: Theme.Metrics.line)
    }

    /// After a Done, for a few seconds: what happened and a way to take it back (⌘Z does it for 30 s). Nothing otherwise.
    var undoLine: some View {
        Group {
            if let entry = store.undoStack.line {
                linkRow(entry.message, action: "Undo") { store.undoLast() }
                    .tip("Undo", "Puts it back · ⌘Z")
                    .transition(.opacity)
            }
        }
        .motion(Theme.Motion.fade, value: store.undoStack.line?.id)
    }

    // MARK: Section headers

    /// A section's header: its title and status on the left, its actions on the right; 30pt tall.
    func sectionHeader<Trailing: View>(_ title: String, status: [(String, Color)] = [],
                                       @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.Typography.heading).foregroundStyle(Theme.tertiary).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(status.enumerated()), id: \.offset) { _, part in
                Text(part.0).font(Theme.Typography.meta.monospacedDigit()).foregroundStyle(part.1).lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, Theme.Space.md)
        .padding(.trailing, 3)
        .frame(height: Theme.Metrics.line)
        .motion(Theme.Motion.fade, value: status.map(\.0))
    }

    // MARK: Router

    /// The Router's cell in the bar; a click opens its window.
    var routerCell: some View {
        let counts = store.routerCounts
        return RouterCell(needsYou: counts.needsYou, done: counts.done) { openRouter(nil) }
    }

    /// "Router", then what's open (amber for what needs you, blue for finished turns). The whole line opens its window.
    var routerHeader: some View {
        sectionHeader("Router", status: routerStatusParts)
            .contentShape(Rectangle())
            .onTapGesture { openRouter(nil) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the Router window · \(store.shortcut(.router).display)")
            .accessibilityAction { openRouter(nil) }
    }

    /// A card clicked on the bar: its session opens in Claude, and it is the one picked in the Router's window.
    func openRouterCard(_ id: String) {
        store.openCard(id)
        pickRouterCard(id)
    }

    var routerStatusParts: [(String, Color)] {
        let counts = store.routerCounts
        var status: [(String, Color)] = []
        if counts.needsYou > 0 { status.append(("\(counts.needsYou) need you", Theme.amber)) }
        if counts.done > 0 { status.append(("\(counts.done) done", Theme.accent)) }
        return status.isEmpty ? [("nothing open", Theme.tertiary)] : status
    }

    /// Open cards a panel lists before the rest are left to the window.
    static let routerCardLimit = 5

    /// The Router in its panel: the header, the latest open cards, then the status line and the way to the window.
    @ViewBuilder var peekRouter: some View {
        let cards = store.openRouterCards
        routerHeader.frame(height: Self.peekLine)
        if cards.isEmpty {
            Text("Nothing needs you").font(Theme.Typography.body).foregroundStyle(Theme.tertiary)
                .padding(.horizontal, Theme.Space.md).frame(height: Theme.Metrics.line)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(cards.prefix(Self.routerCardLimit)) { RouterCardLine(card: $0, store: store) { openRouterCard($0) } }
            }
            if cards.count > Self.routerCardLimit {
                Text("\(cards.count - Self.routerCardLimit) more in the Router").font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiary).padding(.horizontal, Theme.Space.md).padding(.top, 2)
            }
        }
        if store.sessionsHidden { routerWorking }
        Hairline(inset: Theme.Space.md).padding(.vertical, Theme.Space.xs)
        routerFooter
    }

    /// Router only: what is working, under the cards (the sessions' section is gone), and Claude's files failing to read,
    /// which the sessions' header would otherwise say: a broken read never goes silent.
    var routerWorking: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClaudeNotice(store: store).padding(.horizontal, Theme.Space.md)
            RouterWorkingList(store: store)
        }
    }

    /// What is running, in one line, and the button to the window.
    var routerFooter: some View {
        HStack(spacing: 8) {
            // Router only: the Working list above says it already.
            if !store.sessionsHidden { RouterStatusView(store: store).layoutPriority(-1) }
            Spacer(minLength: 0)
            ActionButton("Open Router") { openRouter(nil) }
                .fixedSize()
                .tip("Open Router", "Cards and the chat · \(store.shortcut(.router).display)")
        }
        .padding(.leading, Theme.Space.md)
        .frame(minHeight: Theme.Metrics.line)
    }

    /// Kept open beside the bar: under the header, the status line.
    var routerStatusRow: some View {
        RouterStatusView(store: store)
            .padding(.horizontal, Theme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { openRouter(nil) }
    }

    /// Along the top and bottom, kept open: the column under the Router's segment, the status line over the latest cards.
    var routerColumn: some View {
        let cards = store.openRouterCards
        return VStack(alignment: .leading, spacing: 1) {
            if !store.sessionsHidden {
                RouterStatusView(store: store, lines: 3)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.sm)
            }
            if cards.isEmpty {
                Text("Nothing needs you").font(Theme.Typography.body).foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, Theme.Space.md).padding(.vertical, Theme.Space.sm)
            }
            ForEach(cards.prefix(Self.routerColumnLimit)) { RouterCardLine(card: $0, store: store, narrow: true) { openRouterCard($0) } }
            if cards.count > Self.routerColumnLimit {
                Text("\(cards.count - Self.routerColumnLimit) more").font(Theme.Typography.meta).foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, Theme.Space.md).padding(.top, 2)
            }
            if store.sessionsHidden { routerWorking.padding(.top, 6) }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    static let routerColumnLimit = 4

    // MARK: Agents

    var claudeMark: some View {
        Image(systemName: "asterisk")
            .font(Theme.Typography.glyph(14, .bold))
            .foregroundStyle(Theme.claude)
            .frame(width: Theme.Metrics.line, height: Theme.Metrics.line)
            .contentShape(Rectangle())
            .accessibilityLabel("Sessions")
    }

    /// "Sessions", then what's waiting for you (amber) and what's done and unread (blue).
    var agentsHeader: some View {
        let counts = store.agentCounts
        var status: [(String, Color)] = []
        if counts.blocked > 0 { status.append(("\(counts.blocked) waiting", Theme.amber)) }
        if counts.done > 0 { status.append(("\(counts.done) done", Theme.accent)) }
        // Claude's files missing or unreadable: the notice under the header says so; this stays when the list is shrunk.
        switch store.claudeLink {
        case .missing, .unreadable: status.append(("!", Theme.red))
        default: break
        }
        return sectionHeader("Sessions", status: status) { if showsDetail { focusButton(.agents) } }
    }

    /// A session's tile in the bar; opens it in Claude.
    func tile(_ r: AgentRow, size: CGFloat) -> some View {
        BarTile(row: r, size: size, store: store, ui: ui, hub: hub)
    }

    /// The "+" in the bar, a tile like the sessions' above it: a scratch session.
    var newSessionCell: some View {
        NewSessionTile(size: Theme.Metrics.chip) { store.startScratchSession() }
            .frame(height: Theme.Metrics.row)
    }

    /// Beside the "+": the label and the projects to start a session in.
    var newSessionDetail: some View { NewSessionRow(store: store, style: .detail) }

    // MARK: Bar actions

    var pinButton: some View {
        IconButton(symbol: hub.pinned ? "pin.fill" : "pin", help: hub.pinned ? "Unpin" : "Keep open",
                   detail: store.shortcut(.togglePanel).display,
                   size: footerButton, tint: hub.pinned ? Theme.amber : Theme.secondary, active: hub.pinned) {
            hub.pinned.toggle()
        }
    }

    var reposButton: some View {
        IconButton(symbol: "tray.2.fill", help: "Inbox categories", detail: "What the inbox collects, and where",
                   size: footerButton, active: hub.page == .categories) { hub.go(.categories) }
    }

    /// Lit on Settings; on the categories too beside the bar, where the categories button hides with the rows.
    var settingsCell: some View {
        IconButton(symbol: "gearshape.fill", help: "Settings", detail: "⌘,", size: footerButton,
                   active: hub.page == .settings || (hub.page == .categories && !edge.isHorizontal)) { hub.go(.settings) }
    }

    // MARK: Footer

    /// The bar actions' size: header-size in the open column's footer, so it stays one compact line; the bar's size
    /// along the top and bottom, where they sit in the bar itself.
    var footerButton: CGFloat { edge.isHorizontal ? IconButton.Size.bar : IconButton.Size.header }
    /// The open column's footer: a header-size button and 5pt above and below.
    static let footerHeight: CGFloat = 34

    /// Beside the settings cell: how syncing is going, then pin and repositories.
    var footer: some View {
        // 9pt apart: the same step as from repositories to the settings cell beside them.
        HStack(spacing: 9) {
            syncStatus
            Spacer(minLength: 0)
            pinButton
            reposButton
        }
        .frame(height: Self.footerHeight)
    }

    /// Sync state, as a dot and a few words: problems first, then checking, snoozed, and up to date.
    var syncStatus: some View {
        HStack(spacing: 8) {
            Ticking(coarse: true) { now in
                syncLabel(now: now)
            }
            // The rate limit is part of syncing: it pauses at 0, inbox included.
            RateNotice(store: store, fill: false).lineLimit(1).layoutPriority(-1)
        }
    }

    private func syncLabel(now: Date) -> some View {
        let s = sync(now: now)
        return Button {
            if store.authError != nil { hub.go(.settings) } else { store.refreshNow() }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if s.spinning {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    } else if let symbol = s.symbol {
                        Image(systemName: symbol).font(Theme.Typography.glyph(9, .bold)).foregroundStyle(s.color)
                    } else {
                        Circle().fill(s.color).frame(width: CDS.Dot.size, height: CDS.Dot.size)
                    }
                }
                .frame(width: 10, height: 10)
                Text(s.text).font(Theme.Typography.meta).foregroundStyle(s.color == Theme.green ? Theme.tertiary : s.color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.Metrics.chip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.text)
        .accessibilityHint(s.title)
        .disabled(store.isSyncing)
        .tip(s.title, s.detail)
    }

    private struct SyncState {
        var color: Color
        var text: String
        var title: String
        var detail: String?
        var symbol: String? = nil
        var spinning = false
    }

    private func sync(now: Date) -> SyncState {
        let refresh = "Click to check now · \(store.shortcut(.refresh).display)"
        if let error = store.authError {
            return SyncState(color: Theme.red, text: "Sign-in problem", title: "Can't sign in to GitHub",
                             detail: error + "\nClick for Settings")
        }
        if store.unreachable {
            return SyncState(color: Theme.amber, text: "Not syncing", title: "Couldn't reach GitHub",
                             detail: "Check your connection · Lookout tries again on its own\n" + refresh)
        }
        if let error = store.inboxError {
            return SyncState(color: Theme.amber, text: "Inbox didn't sync", title: "GitHub didn't answer the inbox's search",
                             detail: error + "\n" + refresh)
        }
        if store.isSyncing {
            return SyncState(color: Theme.tertiary, text: "Checking…", title: "Checking GitHub",
                             detail: "Pull requests, issues and workflows", spinning: true)
        }
        guard let last = store.lastSync else {
            return SyncState(color: Theme.tertiary, text: store.me == nil ? "Connecting…" : "Not checked yet",
                             title: "Connecting to GitHub", detail: nil)
        }
        let interval = store.settings.pollInterval
        let checked = "Last checked at \(last.formatted(date: .omitted, time: .shortened))"
        if now.timeIntervalSince(last) > interval * 3 {
            return SyncState(color: Theme.amber, text: "Synced \(agoPhrase(last, now: now))", title: "Not syncing",
                             detail: "\(checked) · check your connection or token\n" + refresh)
        }
        if store.isSnoozed, let until = store.settings.snoozeUntil {
            return SyncState(color: Theme.purple, text: "Snoozed until \(until.formatted(date: .omitted, time: .shortened))",
                             title: "Notifications snoozed", detail: "No banners; the inbox keeps filling · resume in Settings",
                             symbol: "moon.fill")
        }
        let next = max(0, Int(last.addingTimeInterval(interval).timeIntervalSince(now)))
        return SyncState(color: Theme.green, text: "Up to date", title: checked,
                         detail: "Next check in about \(next < 60 ? "\(next)s" : "\(next / 60)m")\n\(refresh)")
    }
}

/// The search: a real text field (paste, selection, dead keys and input methods work, and VoiceOver reads it), with what it
/// found and the Esc that ends it. Typing elsewhere in the hub opens it and hands it the key (see `HubKeys`), which
/// leaves it alone while it has focus.
struct InboxSearchField: View {
    @Bindable var hub: HubState
    let ui: UIState
    let store: Store
    let count: String
    @FocusState private var focused: Bool

    @State private var hover = false

    /// Claude's sidebar search field (global §2.3), typed into: 26 tall, radius 6, white 5% (14% on hover) inside a 1pt
    /// white-10% ring; the 16pt search glyph in a 24 slot, 13pt text, muted placeholder and count, the Esc keycap.
    var body: some View {
        HStack(spacing: CDS.Sidebar.rowGap) {
            Image(systemName: "magnifyingglass").font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(CDS.Text.muted)
                .frame(width: CDS.Sidebar.leadingSlot, height: CDS.Sidebar.leadingSlot)
                .accessibilityHidden(true)
            TextField("Search inbox and sessions", text: $hub.query,
                      prompt: Text("Search inbox and sessions").foregroundStyle(CDS.Text.muted))
                .textFieldStyle(.plain)
                .font(CDS.sans(CDS.Sidebar.rowFont))
                .foregroundStyle(CDS.Text.primary)
                .lineLimit(1)
                .accessibilityLabel("Search inbox and sessions")
                .focused($focused)
                .focusEffectDisabled()
            if !hub.query.isEmpty {
                Text(count).font(Theme.Typography.meta.monospacedDigit()).foregroundStyle(CDS.Text.muted).lineLimit(1)
            }
            KeyCap("Esc")
        }
        .padding(.leading, CDS.Sidebar.rowPadding)
        .padding(.trailing, 4)
        .frame(height: CDS.Sidebar.rowHeight)
        .background(Theme.Radius.shape(CDS.Sidebar.radius).fill(hover && !focused ? CDS.Fill.secondaryHover : CDS.Fill.field))
        .overlay(Theme.Radius.shape(CDS.Sidebar.radius).strokeBorder(CDS.border, lineWidth: 1))
        .onHover { hover = $0 }
        .motion(Theme.Motion.hover, value: hover)
        .onAppear { requestFocus() }
        .onChange(of: hub.focusRequest) { requestFocus() }
        .onChange(of: focused) { _, isFocused in
            hub.searchFocused = isFocused
            if isFocused { DispatchQueue.main.async(execute: hub.typePendingKeys) }
        }
        .onDisappear { hub.searchFocused = false }
        // What is typed, pasted or composed in the field doesn't go through the keys: the first result is picked like theirs,
        // and nothing stays shrunk behind the results.
        .onChange(of: hub.query) {
            if !hub.query.isEmpty, hub.focus != nil {
                withAnimation(LookoutHub.refocus.resolved(reduce: LookoutHub.reduceNow)) { hub.focus = nil }
            }
            hub.pick(store.hubTargets(hub).first, ui: ui)
        }
    }

    private func requestFocus() {
        DispatchQueue.main.async {
            focused = true
            // Already focused (a key arrived while it was): nothing changes for `onChange` to answer.
            DispatchQueue.main.async(execute: hub.typePendingKeys)
        }
    }
}

/// A category's tab: Claude's Tabs with its unread count, dragged onto another to reorder the categories (their order is
/// their priority: the first to match a thing keeps it).
struct CategoryTab: View {
    let category: InboxCategory
    let selected: Bool
    let badge: Int
    let store: Store
    let action: () -> Void
    @State private var target = false

    var body: some View {
        Button(action: action) { CategoryTabLabel(category: category, selected: selected, badge: badge) }
            .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Tabs.radius, style: .continuous),
                                              hover: CDS.Fill.ghostHover, active: CDS.Fill.ghostHover,
                                              pressed: CDS.Fill.ghostHover, isActive: selected))
            .padding(.horizontal, CDS.Tabs.pillInset)
            .fixedSize()
            .accessibilityLabel(category.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Move earlier") { withAnimation(.spring(duration: 0.25)) { move(-1) } }
            .accessibilityAction(named: "Move later") { withAnimation(.spring(duration: 0.25)) { move(1) } }
            .contextMenu {
                Button("Move earlier") { withAnimation(.spring(duration: 0.25)) { move(-1) } }
                    .disabled(!store.canMoveCategory(category.id, by: -1, among: store.shownCategories))
                Button("Move later") { withAnimation(.spring(duration: 0.25)) { move(1) } }
                    .disabled(!store.canMoveCategory(category.id, by: 1, among: store.shownCategories))
            }
            .overlay(alignment: .leading) {
                if target { Capsule().fill(Theme.accent).frame(width: 2, height: 16) }
            }
            .draggable("category:" + category.id.uuidString) {
                Text(category.name)
                    .font(CDS.sans(CDS.Sidebar.rowFont))
                    .padding(.horizontal, 8)
                    .frame(height: CDS.Sidebar.rowHeight)
                    .background(RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous).fill(CDS.Surface.s3))
                    .foregroundStyle(CDS.Text.primary)
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let raw = ids.first, raw.hasPrefix("category:"), let id = UUID(uuidString: String(raw.dropFirst(9))) else { return false }
                withAnimation(.spring(duration: 0.25)) { store.moveCategory(id, onto: category.id) }
                return true
            } isTargeted: { target = $0 }
            .tip(category.name, "Drag to reorder · ⌃\(store.shownCategories.firstIndex { $0.id == category.id }.map { $0 + 1 } ?? 0)")
    }
}

extension CategoryTab {
    fileprivate func move(_ step: Int) { store.moveCategory(category.id, by: step, among: store.shownCategories) }
}

/// The inbox's columns menu: a checkmark per category shown; hidden ones carry their count.
struct CategoriesMenu: View {
    let store: Store
    let edit: () -> Void
    @State private var hover = false

    var body: some View {
        Menu {
            ForEach(store.categories) { category in
                Toggle(isOn: Binding(get: { !category.hidden }, set: { store.setHidden(category.id, !$0) })) {
                    Text(category.hidden ? "\(category.name) · \(store.count(category.id))" : category.name)
                }
            }
            Divider()
            Button("Edit Categories…", action: edit)
        } label: {
            Image(systemName: "eye")
                .font(.system(size: CDS.GhostIcon.glyph(IconButton.Size.header), weight: .medium))
                .foregroundStyle(hover ? Color.white : Theme.secondary)
                .frame(width: IconButton.Size.header, height: IconButton.Size.header)
                .background(Theme.Radius.shape(CDS.GhostIcon.radius(IconButton.Size.header)).fill(hover ? Theme.Fill.hover : .clear))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
        .accessibilityLabel("Show or hide categories")
        .tip("Show or hide categories", "Hidden ones keep collecting, quietly")
    }
}

/// A tab's face: its symbol in the category's colour; the picked one (and any with something unread) says its name too, so
/// the tabs fit a narrow column.
private struct CategoryTabLabel: View {
    let category: InboxCategory
    let selected: Bool
    let badge: Int
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        HStack(spacing: selected ? 5 : 3) {
            Image(systemName: category.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(badge > 0 || selected ? category.color.swatch : CDS.Text.muted)
            if selected { Text(category.name).lineLimit(1) }
            if badge > 0 { CountBadge(badge, tint: category.color.swatch) }
        }
        .font(CDS.sans(13, .medium))
        .foregroundStyle(selected ? CDS.Text.primary : hover ? CDS.Text.secondary : CDS.Text.muted)
        // Only the picked tab has its name: the rest are tight, so all the tabs fit the column.
        .padding(.horizontal, selected ? CDS.Tabs.pad - CDS.Tabs.pillInset : 3)
        .frame(height: CDS.Tabs.height)
    }
}
