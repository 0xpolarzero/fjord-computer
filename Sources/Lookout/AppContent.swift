import SwiftUI

// What the app window shows for a destination, and the inbox list at full width.

/// A tab of the inbox at the window's width: the same rows as the hub's (`EntryRow`: open, mark seen, Done, restore, the
/// context menu), newest first, with the undo line after a Done and "Mark all as seen" in the toolbar.
struct InboxListView: View {
    let store: Store
    let tab: InboxTab
    /// The rows' picked state (a row under the pointer), kept here: the window has no hub.
    @State private var hub: HubState
    @State private var search: InboxSearch
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let column: CGFloat = 880
    /// Room the header leaves at its start (the window's buttons, when the sidebar is away).
    let leadingInset: CGFloat

    init(store: Store, tab: InboxTab, hub: HubState? = nil, search: InboxSearch? = nil, leadingInset: CGFloat = 0) {
        self.store = store
        self.leadingInset = leadingInset
        self.tab = tab
        _hub = State(initialValue: hub ?? HubState())
        _search = State(initialValue: search ?? InboxSearch())
    }

    private var entries: [InboxEntry] { store.inboxRows(tab, search: search.query) }
    private var searching: Bool { search.isSearching }
    private var unread: Int { tab == .done && !searching ? 0 : entries.filter(\.isUnread).count }

    var body: some View {
        let entries = entries
        AppPage(title: title, subtitle: subtitle, leadingInset: leadingInset) {
            InboxSearchField(search: search)
            if unread > 0 {
                IconButton(symbol: "checkmark.circle", help: "Mark all as seen", detail: store.shortcut(.markAllRead).display,
                           size: IconButton.Size.header) {
                    withAnimation(Theme.Motion.fade.resolved(reduce: reduce)) { entries.filter(\.isUnread).forEach(store.markSeen) }
                }
            }
        } content: {
            if entries.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(entries) { EntryRow(entry: $0, store: store, hub: hub).id($0.id) }
                        }
                        .frame(maxWidth: Self.column)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                    // An entry asked for (a banner's click) is scrolled to, also when the list is made after the request.
                    .onAppear { scroll(proxy, to: hub.keyboardSelection) }
                    .onChange(of: hub.keyboardSelection) { _, request in scroll(proxy, to: request) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { undoLine }
        .motion(Theme.Motion.fade, value: store.inboxRevision)
        // A new search picks its first result, so ↩ opens it straight away.
        .onChange(of: search.query) { hub.selection = searching ? entries.first.map { "i:" + $0.id } : nil }
    }

    private func scroll(_ proxy: ScrollViewProxy, to request: ScrollRequest?) {
        guard let id = request?.id.dropFirst(2) else { return }
        DispatchQueue.main.async { withAnimation(Theme.Motion.hover.resolved(reduce: reduce)) { proxy.scrollTo(String(id), anchor: .center) } }
    }

    private var title: String {
        if searching { return "Search" }
        switch tab {
        case .done: return "Done"
        case .category: return store.category(tab)?.title ?? "Inbox"
        }
    }

    private var subtitle: String {
        let all = entries
        if searching { return all.isEmpty ? "" : "\(all.count) found" }
        if all.isEmpty { return "" }
        if tab == .done { return "\(all.count) moved to Done" }
        if store.category(tab)?.isCI == true { return "\(all.count) failing" }
        return unread > 0 ? "\(unread) unread of \(all.count)" : "\(all.count) seen"
    }

    private var empty: some View {
        let text: String = if searching {
            "Nothing found"
        } else if tab == .done {
            "Nothing here yet"
        } else if store.category(tab)?.isCI == true {
            "Everything is passing"
        } else {
            "All caught up"
        }
        return VStack(spacing: 8) {
            Image(systemName: tab == .done ? "archivebox" : (store.category(tab)?.symbol ?? "tray"))
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(CDS.Text.muted.opacity(0.7))
            Text(text).font(CDS.sans(13)).foregroundStyle(CDS.Text.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// After a Done, for a few seconds: what happened and a way to take it back (⌘Z does it for 30 s).
    private var undoLine: some View {
        Group {
            if let entry = store.undoStack.line {
                HStack(spacing: 10) {
                    Text(entry.message).font(CDS.sans(13)).foregroundStyle(CDS.Text.secondary)
                    Button("Undo") { store.undoLast() }
                        .buttonStyle(.plain)
                        .font(CDS.sans(13, .medium))
                        .foregroundStyle(CDS.Text.accent)
                        .help("Puts it back · ⌘Z")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(CDS.Surface.s3))
                .overlay(Capsule().strokeBorder(CDS.border, lineWidth: 1))
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .motion(Theme.Motion.fade, value: store.undoStack.line?.id)
    }
}

/// A page under Claude's 48pt header: the title (13pt, medium) and what it holds, muted, then the page's own buttons at the
/// end. The header's start is left to the window's buttons (sidebar toggle, back, forward).
struct AppPage<Trailing: View, Content: View>: View {
    let title: String
    var subtitle = ""
    var leadingInset: CGFloat = 0
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(title: String, subtitle: String = "", leadingInset: CGFloat = 0, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.leadingInset = leadingInset
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(CDS.sans(CDS.Density.compact.body.0, .medium))
                    .foregroundStyle(CDS.Text.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).font(CDS.sans(CDS.Density.compact.footnote.0)).foregroundStyle(CDS.Text.muted).lineLimit(1)
                }
                Spacer(minLength: 24)
                trailing
            }
            // Past the window's buttons: 12 in, three 26pt buttons 4 apart, 12 more.
            .padding(.leading, leadingInset + 12 + AppNavButtons.width + 14)
            .padding(.trailing, CDS.TitleBar.endInset)
            .frame(height: CDS.TitleBar.header)
            .overlay(alignment: .bottom) { Rectangle().fill(CDS.border).frame(height: 0.5) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The window's content column for the selected destination.
struct AppContent: View {
    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    let hub: HubState
    var search = InboxSearch()
    var checksClaudeCode = true
    /// Room the window's buttons take at the start when the sidebar is away.
    var leadingInset: CGFloat = 0

    var body: some View {
        Group {
            switch navigator.selection {
            case .category(let id): InboxListView(store: store, tab: .category(id), hub: hub, search: search, leadingInset: leadingInset).id(id)
            case .done: InboxListView(store: store, tab: .done, hub: hub, search: search, leadingInset: leadingInset).id("done")
            case .router:
                RouterCodeView(store: store, model: routerModel, checksClaudeCode: checksClaudeCode, embedded: true)
            case .settings:
                AppPage(title: "Settings", leadingInset: leadingInset, trailing: { EmptyView() }) {
                    column { SettingsView(store: store, hub: hub) }
                }
            case .categories:
                AppPage(title: "Inbox categories", leadingInset: leadingInset, trailing: { EmptyView() }) {
                    column { CategoriesView(store: store, hub: hub) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CDS.Surface.s1)
        .clipped()
    }

    /// Settings and the categories were made for a narrow panel: a readable column, centred.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }
}
