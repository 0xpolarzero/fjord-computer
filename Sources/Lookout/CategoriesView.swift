import SwiftUI

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// What to open first: the editor of a category, or a group unfolded (shots, and the New category button).
enum CategoryEditing: Hashable {
    case existing(UUID)
    /// A category being made by New category: a draft, nowhere in the store until Create.
    case new
}

struct CategoriesPreview {
    var editing: CategoryEditing?
    /// The draft New category opens on (with `editing` `.new`).
    var draft: InboxCategory?
    var expandedGroup: UUID?
    var notice: String?
}

/// The inbox's categories and groups: create, edit rules, reorder, show/hide. The hub's second page, beside Settings.
struct CategoriesView: View {
    let store: Store
    @State private var editing: CategoryEditing?
    @State private var expandedGroup: UUID?
    @State private var dropTarget: String?
    /// A section just made by New section: its name field takes the focus.
    @State private var focusSection: UUID?
    /// Every edit applies at once; this is what takes them back.
    @State private var history: CategoryHistory
    /// What New category opened: not in the store (not listed, matched or saved) until Create; leaving drops it.
    @State private var draft: InboxCategory?
    private let notice: String?
    /// The hub's state, when shown in it: an open editor takes Esc and the back button (back to the list) first.
    private let hub: HubState?

    init(store: Store, hub: HubState? = nil, preview: CategoriesPreview? = nil) {
        self.store = store
        self.hub = hub
        _history = State(initialValue: CategoryHistory(store: store))
        notice = preview?.notice
        _editing = State(initialValue: preview?.editing)
        _draft = State(initialValue: preview?.draft)
        _expandedGroup = State(initialValue: preview?.expandedGroup)
    }

    var body: some View {
        Group {
            if editing == .new, let made = Binding($draft) {
                CategoryEditor(store: store, editing: .new, history: history, draft: made, create: commitDraft) { self.editing = nil }
                    .id(CategoryEditing.new)
            } else if let editing, editing != .new {
                CategoryEditor(store: store, editing: editing, history: history, firstRuleNotice: notice) { self.editing = nil }
                    .id(editing)
            } else {
                list
            }
        }
        .onChange(of: editing != nil, initial: true) { _, open in
            syncStepBack(open)
        }
        // Leaving the draft (back, Esc, another category asked for) leaves nothing behind.
        .onChange(of: editing == .new) { _, drafting in
            if !drafting { draft = nil }
            syncHistory()
        }
        // A Router change's Open button asked for a category's editor or a group.
        .onChange(of: hub?.categoryRequest, initial: true) { _, request in
            guard let request, let id = UUID(uuidString: request.id) else { return }
            hub?.categoryRequest = nil
            if store.categories.contains(where: { $0.id == id }) { editing = .existing(id) }
        }
        .onChange(of: hub?.groupRequest, initial: true) { _, request in
            guard let request, let id = UUID(uuidString: request.id) else { return }
            hub?.groupRequest = nil
            editing = nil
            expandedGroup = id
        }
        .onChange(of: store.categories) {
            history.observe(store, field: CategoryHistory.typingField())
            store.categoriesEdited()
        }
        .onChange(of: store.groups) { history.observe(store, field: CategoryHistory.typingField()) }
        .onChange(of: store.categorySections) { history.observe(store, field: CategoryHistory.typingField()) }
        .onAppear(perform: syncHistory)
        .onDisappear {
            hub?.stepBack = nil
            if store.categoryHistory === history { store.categoryHistory = nil }
        }
    }

    /// The page's history takes ⌘Z, except while a draft is open: its fields keep their own (the draft is no step of the page).
    private func syncHistory() {
        if editing == .new {
            if store.categoryHistory === history { store.categoryHistory = nil }
        } else {
            store.categoryHistory = history
        }
    }

    /// New category: the editor on a draft, in `section` (the first when nil). Nothing is made until Create.
    private func create(in section: UUID?) {
        var made = Self.newDraft(after: store.categories)
        made.section = section
        draft = made
        editing = .new
    }

    /// What New category starts from: no name, the first colour not yet used, one rule (every PR for you).
    static func newDraft(after categories: [InboxCategory]) -> InboxCategory {
        let used = Set(categories.map(\.color))
        let color = CategoryColor.allCases.first { !used.contains($0) && $0 != .gray } ?? .blue
        return InboxCategory(name: "", symbol: CategoryIcon.fallback, color: color, rules: [Rule(scope: Scope(kinds: [.pr]))])
    }

    /// Create: the draft goes in, one step of the page's history, and the page is back on the list.
    private func commitDraft() {
        guard let made = draft, store.createCategory(made, history: history) else { return }
        draft = nil
        editing = nil
    }

    /// Registers the editor's step back with the hub while one is open (back to the list: there is nothing to save).
    private func syncStepBack(_ open: Bool) {
        guard let hub else { return }
        let binding = $editing
        hub.stepBack = open ? { binding.wrappedValue = nil; return true } : nil
    }

    // MARK: The list

    /// Claude's list pattern (settings.md §4): a titled section, then the rows in a nest card. With sections, a tree: each
    /// section's header and its categories under it, everything dragged into place.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDS.Settings.sectionGap) {
                SettingsSection("Categories",
                                info: ("Categories", store.categorySections.isEmpty
                                       ? "A thing goes to the first category, from the top, with a rule matching it. Drag to reorder."
                                       : "A thing goes to the first category, from the top, with a rule matching it. Drag a category to reorder it or into another section; drag a section to move it with its categories.")) {
                    SettingsNest {
                        if store.categorySections.isEmpty {
                            ForEach(Array(store.categories.enumerated()), id: \.element.id) { i, category in
                                if i > 0 { SettingsDivider() }
                                categoryRow(category)
                            }
                            if !store.categories.isEmpty { SettingsDivider() }
                            NewRow(title: "New category", symbol: "plus") { create(in: nil) }
                        } else {
                            ForEach(Array(store.categorySections.enumerated()), id: \.element.id) { i, section in
                                if i > 0 { SettingsDivider() }
                                sectionBlock(section)
                            }
                        }
                        SettingsDivider()
                        NewRow(title: "New section", symbol: "plus") { focusSection = store.createSection(name: "").id }
                        SettingsDivider()
                        DoneRow(count: store.doneEntries.count)
                    }
                }
                GroupsSection(store: store, expanded: $expandedGroup)
            }
            .padding(.horizontal, CDS.Settings.pagePadX)
            .padding(.top, CDS.Settings.pageTop + 8)
            .padding(.bottom, CDS.Settings.pageBottom)
        }
        .scrollIndicators(.never)
        .task { await store.loadSuggestions() }
    }

    /// A section's header, then its categories, indented under it (or, with none, a place to drop one).
    @ViewBuilder private func sectionBlock(_ section: CategorySection) -> some View {
        let key = "section:\(section.id.uuidString)"
        SectionHeaderRow(store: store, section: section, dropping: dropTarget == key, focusing: $focusSection) { create(in: section.id) }
            .draggable(key)
            .dropDestination(for: String.self) { items, _ in
                drop(items.first) { dragged in
                    switch dragged {
                    case .category(let id): store.moveCategory(id, toTopOf: section.id)
                    case .section(let id): store.moveSection(id, onto: section.id)
                    }
                }
            } isTargeted: { target(key, $0) }
        let inside = store.categories.filter { store.sectionID(of: $0) == section.id }
        if inside.isEmpty {
            let empty = "empty:\(section.id.uuidString)"
            Text("Drag categories here")
                .cdsText(foot12, .regular, CDS.Text.muted)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.leading, 12)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(dropTarget == empty ? CDS.Fill.accent : CDS.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .padding(.leading, Self.indent).padding(.bottom, 8)
                .dropDestination(for: String.self) { items, _ in
                    drop(items.first) { dragged in
                        if case .category(let id) = dragged { store.moveCategory(id, toSection: section.id) }
                    }
                } isTargeted: { target(empty, $0) }
        }
        ForEach(inside) { category in
            SettingsDivider().padding(.leading, Self.indent)
            categoryRow(category).padding(.leading, Self.indent)
        }
    }

    /// How far a section's categories sit in under its header.
    private static let indent: CGFloat = 22

    private func categoryRow(_ category: InboxCategory) -> some View {
        let key = "category:\(category.id.uuidString)"
        return CategoryRow(store: store, category: category, dropping: dropTarget == key) { editing = .existing(category.id) }
            .draggable(key)
            .dropDestination(for: String.self) { items, _ in
                drop(items.first) { dragged in
                    switch dragged {
                    case .category(let id): store.moveCategory(id, onto: category.id)
                    // A section dropped on a category goes where that category's section is.
                    case .section(let id): if let to = store.sectionID(of: category) { store.moveSection(id, onto: to) }
                    }
                }
            } isTargeted: { target(key, $0) }
    }

    private enum Dragged { case category(UUID), section(UUID) }

    /// What a drag carries: "category:<id>" or "section:<id>" (a bare id is a category, as the bar's tabs drag them).
    private func drop(_ payload: String?, _ apply: (Dragged) -> Void) -> Bool {
        guard let payload else { return false }
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        let raw = parts.count == 2 ? parts[1] : payload
        guard let id = UUID(uuidString: raw) else { return false }
        apply(parts.first == "section" ? .section(id) : .category(id))
        dropTarget = nil
        return true
    }

    private func target(_ key: String, _ over: Bool) {
        if over { dropTarget = key } else if dropTarget == key { dropTarget = nil }
    }
}

extension Store {
    /// New category's Create: `draft` goes in at the end, named (trimmed) and its rules new from now, as one step of `history`.
    /// False, and nothing made, without a name.
    @discardableResult
    func createCategory(_ draft: InboxCategory, history: CategoryHistory?, now: Date = Date()) -> Bool {
        var made = draft
        made.name = made.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !made.name.isEmpty else { return false }
        for i in made.rules.indices { made.rules[i].createdAt = now }
        // At the end of its section (the tree's order is the order things match in).
        changingInbox(.newCategoryButton) { categories = treeOrdered(categories + [made]) }
        history?.observe(self)
        return true
    }
}

// MARK: - Rows

private struct CategoryRow: View {
    let store: Store
    let category: InboxCategory
    let dropping: Bool
    let open: () -> Void

    var body: some View {
        let data = EditorData(store: store)
        let summary = category.rules.first.map(data.summary) ?? "No rules"
        let more = category.rules.count - 1
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    CategoryTile(symbol: category.symbol, color: category.color)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(category.title).cdsText(body14).lineLimit(1)
                            if !category.actions.isEmpty {
                                Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(CDS.Text.muted)
                                    .help("Does something by itself when a thing comes in")
                                    .accessibilityLabel("Has actions")
                            }
                        }
                        Text(summary + (more > 0 ? "  +\(more) more" : ""))
                            .cdsText(foot12, .regular, CDS.Text.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(category.name)")
            Text("\(store.count(category.id))")
                .cdsText((CDS.Badge.font + 1, 16), .medium, CDS.Text.secondary)
                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: CDS.Badge.height)
                .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(CDS.Badge.fill))
                .accessibilityLabel(plural(store.count(category.id), "thing"))
            IconButton(symbol: category.notifies ? "bell" : "bell.slash",
                       help: category.notifies ? "Notifications on" : "Notifications off",
                       label: "Notifications for \(category.name): \(category.notifies ? "on" : "off")",
                       size: 24, tint: category.notifies ? CDS.Text.secondary : CDS.Text.muted) {
                update { $0.notifies.toggle() }
            }
            IconButton(symbol: category.hidden ? "eye.slash" : "eye",
                       help: category.hidden ? "Hidden from the bar: still collects, never notifies" : "Shown in the bar",
                       label: "\(category.name) is \(category.hidden ? "hidden" : "shown")",
                       size: 24, tint: category.hidden ? CDS.Text.muted : CDS.Text.secondary) {
                update { $0.hidden.toggle() }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .opacity(category.hidden ? 0.6 : 1)
        .overlay(alignment: .top) {
            if dropping { Rectangle().fill(CDS.Fill.accent).frame(height: 2).offset(y: -1) }
        }
        .accessibilityAction(named: "Move up") { store.moveCategory(category.id, by: -1) }
        .accessibilityAction(named: "Move down") { store.moveCategory(category.id, by: 1) }
        .contextMenu {
            Button("Edit", action: open)
            Button(category.hidden ? "Show in the bar" : "Hide from the bar") { update { $0.hidden.toggle() } }
            if store.categorySections.count > 1 {
                Menu("Move to section") {
                    ForEach(store.categorySections) { section in
                        Button(section.title) { store.moveCategory(category.id, toSection: section.id) }
                            .disabled(store.sectionID(of: category) == section.id)
                    }
                }
            }
            Divider()
            Button("Move up") { store.moveCategory(category.id, by: -1) }
                .disabled(!store.canMoveCategory(category.id, by: -1))
            Button("Move down") { store.moveCategory(category.id, by: 1) }
                .disabled(!store.canMoveCategory(category.id, by: 1))
            Divider()
            Button("Delete", role: .destructive) { store.categories.removeAll { $0.id == category.id } }
        }
    }

    private func update(_ change: (inout InboxCategory) -> Void) {
        guard let i = store.categories.firstIndex(where: { $0.id == category.id }) else { return }
        change(&store.categories[i])
    }
}

/// The last row of the tree: a dashed tile with a plus, and what it makes ("New section"; "New category" with no sections).
private struct NewRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(CDS.Text.muted.opacity(hovered ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hovered ? CDS.Text.secondary : CDS.Text.muted))
                Text(title).cdsText(CDS.Density.comfortable.body, .regular, hovered ? CDS.Text.secondary : CDS.Text.muted)
                Spacer(minLength: 8)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
    }
}

/// Done is not a category: the things you acknowledged, back when something new matches. Fixed, last.
private struct DoneRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            CategoryTile(symbol: "checkmark", color: .gray)
            VStack(alignment: .leading, spacing: 1) {
                Text("Done").cdsText(body14)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .cdsText((CDS.Badge.font + 1, 16), .medium, CDS.Text.secondary)
                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: CDS.Badge.height)
                .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(CDS.Badge.fill))
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
