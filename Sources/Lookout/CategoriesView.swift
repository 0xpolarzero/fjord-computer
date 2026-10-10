import SwiftUI

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// What to open first: the editor of a category, or a group unfolded (shots, and the New category button).
enum CategoryEditing: Hashable {
    case new
    case existing(UUID)
}

struct CategoriesPreview {
    var editing: CategoryEditing?
    var expandedGroup: UUID?
    var notice: String?
}

/// The inbox's categories and groups: create, edit rules, reorder, show/hide. The hub's second page, beside Settings.
struct CategoriesView: View {
    let store: Store
    @State private var editing: CategoryEditing?
    @State private var expandedGroup: UUID?
    @State private var dropTarget: UUID?
    private let notice: String?
    /// The hub's state, when shown in it: an open editor takes Esc and the back button (back to the list) first.
    private let hub: HubState?

    init(store: Store, hub: HubState? = nil, preview: CategoriesPreview? = nil) {
        self.store = store
        self.hub = hub
        notice = preview?.notice
        _editing = State(initialValue: preview?.editing)
        _expandedGroup = State(initialValue: preview?.expandedGroup)
    }

    var body: some View {
        Group {
            if let editing {
                CategoryEditor(store: store, editing: editing, firstRuleNotice: notice) { self.editing = nil }
                    .id(editing)
            } else {
                list
            }
        }
        .onChange(of: editing != nil, initial: true) { _, open in syncStepBack(open) }
        .onDisappear { hub?.stepBack = nil }
    }

    /// Registers the editor's step back with the hub while one is open (its leaving saves or keeps the draft, as "‹ Categories").
    private func syncStepBack(_ open: Bool) {
        guard let hub else { return }
        let binding = $editing
        hub.stepBack = open ? { binding.wrappedValue = nil; return true } : nil
    }

    // MARK: The list

    /// Claude's list pattern (settings.md §4): a titled section, then the rows in a nest card.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDS.Settings.sectionGap) {
                SettingsSection("Categories",
                                info: ("Categories", "A thing goes to the first category, from the top, with a rule matching it. Drag to reorder."),
                                action: {
                    Button { editing = .new } label: {
                        HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)); Text("New category") }
                    }
                    .buttonStyle(SettingsButtonStyle(size: .sm))
                    .accessibilityLabel("New category")
                }, content: {
                    SettingsNest {
                        ForEach(Array(store.categories.enumerated()), id: \.element.id) { i, category in
                            if i > 0 { SettingsDivider() }
                            CategoryRow(store: store, category: category, dropping: dropTarget == category.id) { editing = .existing(category.id) }
                                .draggable(category.id.uuidString)
                                .dropDestination(for: String.self) { items, _ in
                                    move(items.first, onto: category.id)
                                } isTargeted: { dropTarget = $0 ? category.id : (dropTarget == category.id ? nil : dropTarget) }
                        }
                        SettingsDivider()
                        DoneRow(count: store.doneEntries.count)
                    }
                })
                GroupsSection(store: store, expanded: $expandedGroup)
            }
            .padding(.horizontal, CDS.Settings.pagePadX)
            .padding(.top, CDS.Settings.pageTop + 8)
            .padding(.bottom, CDS.Settings.pageBottom)
        }
        .scrollIndicators(.never)
        .task { await store.loadSuggestions() }
    }

    /// A dragged row takes the place of the one it is dropped on.
    private func move(_ dragged: String?, onto id: UUID) -> Bool {
        guard let dragged, let from = store.categories.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = store.categories.firstIndex(where: { $0.id == id }), from != to else { return false }
        store.moveCategory(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
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
                            Text(category.name).cdsText(body14).lineLimit(1)
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
            Divider()
            Button("Move up") { store.moveCategory(category.id, by: -1) }
                .disabled(!store.canMoveCategory(category.id, by: -1))
            Button("Move down") { store.moveCategory(category.id, by: 1) }
                .disabled(!store.canMoveCategory(category.id, by: 1))
            if !category.isCI {
                Divider()
                Button("Delete", role: .destructive) { store.categories.removeAll { $0.id == category.id } }
            }
        }
    }

    private func update(_ change: (inout InboxCategory) -> Void) {
        guard let i = store.categories.firstIndex(where: { $0.id == category.id }) else { return }
        change(&store.categories[i])
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
