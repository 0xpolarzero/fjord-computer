import SwiftUI

// Sections of the bar: a name, an icon picked from it (as a category's is), and the categories put in it. Each section is
// a well in the bar, its icon on top and its categories under it (beside it along the top and bottom). ("Groups" are the
// people and repos the rules name.)
//
// A category says which section it is in; one in none (or in one since deleted) is in the first. With no sections at all,
// the bar shows the categories alone. A section only orders the bar: which category a thing goes to is still the first
// one, in the categories' own order, with a rule matching it.

struct CategorySection: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// SF Symbol, or `CategorySection.githubMark`.
    var symbol: String
    /// Chosen by hand: its name no longer picks it.
    var iconChosen: Bool? = nil
    /// Folded, in the sidebar and the bar: its icon alone, with its categories' counts added up on it.
    var collapsed: Bool? = nil

    var isCollapsed: Bool { collapsed == true }

    var title: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name }

    /// Not an SF Symbol: the GitHub mark, drawn by `GitHubMark`.
    static let githubMark = "lookout.github"
    /// The section every inbox starts with, holding every category: the bar as it always looked.
    static let github = CategorySection(id: UUID(uuidString: "6A1B0000-0000-4000-8000-000000000001")!, name: "GitHub", symbol: githubMark)
}

/// A section's icon from its name: the GitHub mark for a name saying GitHub, else a category's local pick.
enum SectionIcon {
    static func local(name: String) -> String? {
        name.lowercased().contains("github") ? CategorySection.githubMark : CategoryIcon.local(name: name)
    }

    /// Jev's pick when there is a key (the GitHub mark is never his to pick), else the local one.
    static func pick(name: String, choose: Claude.Chooser?) async -> String? {
        if name.lowercased().contains("github") { return CategorySection.githubMark }
        if let choose, let symbol = try? await CategoryIcon.pick(name: name, choose: choose) { return symbol }
        return CategoryIcon.local(name: name)
    }
}

/// A section's icon: the GitHub mark, or its symbol.
struct SectionGlyph: View {
    let symbol: String
    var size: CGFloat = 14
    var color: Color = Theme.secondary

    var body: some View {
        if symbol == CategorySection.githubMark {
            // Optically the weight of a symbol of `size` beside it.
            GitHubMark().fill(color).frame(width: size + 1, height: size + 1)
        } else {
            Image(systemName: symbol).font(Theme.Typography.glyph(size)).foregroundStyle(color)
        }
    }
}

/// A section's tile on the categories page (a category's `CategoryTile`, in grey).
struct SectionTile: View {
    let symbol: String
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size >= 32 ? 8 : 6, style: .continuous)
            .fill(CDS.alpha(0.08))
            .frame(width: size, height: size)
            .overlay(SectionGlyph(symbol: symbol, size: size * 0.5, color: CDS.Text.secondary))
            .accessibilityHidden(true)
    }
}

/// One well of the bar: its section (nil when there are none) and its categories shown, in their order.
struct BarSection: Identifiable, Equatable {
    let section: CategorySection?
    let categories: [InboxCategory]
    var id: UUID { section?.id ?? CategorySection.github.id }
}

extension Store {
    /// The section a category is in: its own while it exists, else the first; nil only when there are none.
    func sectionID(of category: InboxCategory) -> UUID? {
        if let id = category.section, categorySections.contains(where: { $0.id == id }) { return id }
        return categorySections.first?.id
    }

    /// The bar's wells, in the sections' order, each with its shown categories; a section with none shown has no well.
    var barSections: [BarSection] {
        let shown = categories.filter { !$0.hidden }
        guard !categorySections.isEmpty else { return shown.isEmpty ? [] : [BarSection(section: nil, categories: shown)] }
        return categorySections.compactMap { section in
            let inside = shown.filter { sectionID(of: $0) == section.id }
            return inside.isEmpty ? nil : BarSection(section: section, categories: inside)
        }
    }

    /// Folds or unfolds a section, in the sidebar and the bar alike.
    func toggleCollapsed(_ id: UUID) {
        guard let i = categorySections.firstIndex(where: { $0.id == id }) else { return }
        categorySections[i].collapsed = categorySections[i].isCollapsed ? nil : true
    }

    /// What a section's categories hold, added up: shown on its icon while it is folded. In the colour of the first one with
    /// something (CI's red when it is that).
    func sectionBadge(_ part: BarSection) -> RailBadge? {
        let counts = part.categories.map { ($0, badge($0)) }.filter { $0.1 > 0 }
        guard let first = counts.first?.0 else { return nil }
        return RailBadge(count: counts.reduce(0) { $0 + $1.1 }, fill: first.color.swatch, ink: first.color.ink)
    }

    /// New section: named, its icon from the name (the local pick; the page asks Jev after), at the end.
    @discardableResult
    func createSection(name: String) -> CategorySection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let made = CategorySection(name: trimmed, symbol: SectionIcon.local(name: trimmed) ?? CategoryIcon.fallback)
        categorySections.append(made)
        return made
    }

    /// Deletes a section; its categories go to the first one left (or to none), at its end.
    func deleteSection(_ id: UUID) {
        guard let i = categorySections.firstIndex(where: { $0.id == id }) else { return }
        // Theirs is gone: they go to the first left. The others keep theirs, even if that was the first by default.
        let rest = categorySections.filter { $0.id != id }.first?.id
        let next = categories.map { c -> InboxCategory in
            var c = c
            c.section = sectionID(of: c) == id ? rest : sectionID(of: c)
            return c
        }
        categorySections.remove(at: i)
        let ordered = treeOrdered(next)
        if ordered != categories { categories = ordered }
    }

    /// Into `section`, at its end.
    func moveCategory(_ id: UUID, toSection section: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == id }), sectionID(of: categories[i]) != section else { return }
        var list = categories
        var moving = list.remove(at: i)
        moving.section = section
        list.append(moving)
        categories = treeOrdered(list)
    }

    /// Into `section`, at its top (a category dropped on the section's header).
    func moveCategory(_ id: UUID, toTopOf section: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        var list = categories
        var moving = list.remove(at: i)
        moving.section = section
        let first = list.firstIndex { sectionID(of: $0) == section } ?? list.endIndex
        list.insert(moving, at: first)
        let ordered = treeOrdered(list)
        if ordered != categories { categories = ordered }
    }

    func moveSection(_ id: UUID, by step: Int) {
        guard let i = categorySections.firstIndex(where: { $0.id == id }), categorySections.indices.contains(i + step) else { return }
        moveSection(id, onto: categorySections[i + step].id)
    }

    /// Drags a section, its categories with it, to where `target` is.
    func moveSection(_ id: UUID, onto target: UUID) {
        guard id != target, let from = categorySections.firstIndex(where: { $0.id == id }),
              let to = categorySections.firstIndex(where: { $0.id == target }) else { return }
        // Each category's section written down first: one in the first by default stays where it is.
        let pinned = pinnedSections(categories)
        var sections = categorySections
        sections.insert(sections.remove(at: from), at: to)
        categorySections = sections
        let ordered = treeOrdered(pinned)
        if ordered != categories { categories = ordered }
    }

    /// `list` in the page's tree order: section by section, each keeping its categories' order. Which category a thing goes
    /// to is the first, from the top, so the tree reads as it matches.
    func treeOrdered(_ list: [InboxCategory]) -> [InboxCategory] {
        guard !categorySections.isEmpty else { return list }
        let rank = Dictionary(uniqueKeysWithValues: categorySections.enumerated().map { ($1.id, $0) })
        return pinnedSections(list).enumerated()
            .sorted { a, b in
                let ra = a.element.section.flatMap { rank[$0] } ?? 0, rb = b.element.section.flatMap { rank[$0] } ?? 0
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Each category's section written down (a category in none, or in one gone, is in the first).
    private func pinnedSections(_ list: [InboxCategory]) -> [InboxCategory] {
        list.map { c in
            var c = c
            c.section = sectionID(of: c)
            return c
        }
    }
}

/// A section's icon in the bar, atop its well: the inbox's GitHub mark cell, with the section's own icon. A click opens it.
struct SectionCell: View {
    let section: CategorySection
    /// Its categories' counts added up, shown while it is folded.
    let badge: RailBadge?
    let vertical: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { SectionCellLabel(symbol: section.symbol, badge: section.isCollapsed ? badge : nil, vertical: vertical) }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(section.isCollapsed ? "collapsed" + (badge.map { ", \($0.count) new" } ?? "") : "expanded")
            .accessibilityHint(section.isCollapsed ? "Shows its categories" : "Folds its categories into it")
    }
}

private struct SectionCellLabel: View {
    let symbol: String
    let badge: RailBadge?
    let vertical: Bool
    @State private var hover = false

    var body: some View {
        SectionGlyph(symbol: symbol, size: 14, color: hover || badge != nil ? Theme.text : Theme.secondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: CDS.Tile.radius, style: .continuous).fill(hover ? Theme.Fill.hover : .clear))
            .overlay(alignment: .topTrailing) {
                if let badge { CornerBadge(count: badge.count, fill: badge.fill, ink: badge.ink) }
            }
            .frame(width: Theme.Metrics.line, height: Theme.Metrics.line)
            .padding(.vertical, vertical ? 3 : 0)
            .padding(.horizontal, vertical ? 0 : 2)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .motion(Theme.Motion.hover, value: hover)
    }
}

// MARK: - The categories page's sections

/// A section in the categories page's tree: its icon, its name to edit, and delete. Its categories sit under it; dragging it
/// moves them with it.
struct SectionHeaderRow: View {
    let store: Store
    let section: CategorySection
    /// Something dragged over it: a category goes to its top, a section takes its place.
    let dropping: Bool
    /// + : a new category in it.
    let add: () -> Void
    @State private var picking = false
    @State private var renamed = false
    @State private var hovered = false
    @State private var editingName = false
    @FocusState private var focused: Bool
    @Binding var focusing: UUID?
    /// Its icon follows its name until you choose one.
    private var iconAuto: Bool { section.iconChosen != true }

    init(store: Store, section: CategorySection, dropping: Bool, focusing: Binding<UUID?>, add: @escaping () -> Void) {
        self.store = store
        self.section = section
        self.dropping = dropping
        self.add = add
        _focusing = focusing
    }

    private var name: Binding<String> {
        Binding(get: { section.name }, set: { value in update { $0.name = value } })
    }

    var body: some View {
        let count = store.categories.filter { store.sectionID(of: $0) == section.id }.count
        let index = store.categorySections.firstIndex { $0.id == section.id } ?? 0
        HStack(spacing: 10) {
            Button { picking = true } label: { SectionTile(symbol: section.symbol, size: 22) }
                .buttonStyle(.plain)
                .tip("Icon", "Picked from the name; click to choose another")
                .accessibilityLabel("Icon of \(section.title). Choose another")
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    SymbolPicker(selection: section.symbol, color: .gray) { symbol in
                        update { $0.symbol = symbol; $0.iconChosen = true }
                        picking = false
                    }
                }
            // Its name is text until clicked (a field first would take the page's focus as it opens); a new one starts in it.
            if editingName {
                TextField("", text: name)
                    .textFieldStyle(.plain)
                    .cdsText(CDS.Density.comfortable.body, .semibold)
                    .cdsPlaceholder("Name, like GitHub or Work", shown: section.name.isEmpty)
                    .focused($focused)
                    .onSubmit { editingName = false }
                    .onChange(of: focused) { _, now in if !now { editingName = false } }
                    .accessibilityLabel("Section name")
            } else {
                Text(section.title).cdsText(CDS.Density.comfortable.body, .semibold)
                    .foregroundStyle(section.name.isEmpty ? CDS.Text.muted : CDS.Text.primary)
                    .lineLimit(1)
                    .onTapGesture { beginEditing() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Rename")
                    .accessibilityAction { beginEditing() }
            }
            Spacer(minLength: 8)
            IconButton(symbol: "plus", help: "New category in \(section.title)", label: "New category in \(section.title)",
                       size: 24, tint: CDS.Text.secondary, action: add)
            IconButton(symbol: "trash", help: count > 0 ? "Delete: its categories go to the first section left" : "Delete",
                       label: "Delete \(section.title)", size: 24, tint: CDS.Text.muted) {
                store.deleteSection(section.id)
            }
            .opacity(hovered || focused ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(dropping ? CDS.Fill.ghostSelected : .clear))
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename") { beginEditing() }
            Button("Move up") { store.moveSection(section.id, by: -1) }.disabled(index == 0)
            Button("Move down") { store.moveSection(section.id, by: 1) }.disabled(index == store.categorySections.count - 1)
            Divider()
            Button("Delete", role: .destructive) { store.deleteSection(section.id) }
        }
        .accessibilityAction(named: "Move up") { store.moveSection(section.id, by: -1) }
        .accessibilityAction(named: "Move down") { store.moveSection(section.id, by: 1) }
        // Only once you rename it: opening the page asks nothing.
        .onChange(of: section.name) { renamed = true }
        .task(id: section.name) { if renamed { await pickIcon() } }
        .onAppear {
            if focusing == section.id { focusing = nil; beginEditing() }
        }
    }

    private func beginEditing() {
        editingName = true
        DispatchQueue.main.async { focused = true }
    }

    private func update(_ change: (inout CategorySection) -> Void) {
        guard let i = store.categorySections.firstIndex(where: { $0.id == section.id }) else { return }
        change(&store.categorySections[i])
    }

    /// Debounced, as a category's: Jev's pick with a key, else a word in the name; never once you chose one.
    private func pickIcon() async {
        let name = section.name.trimmingCharacters(in: .whitespaces)
        guard iconAuto, name.count >= 2 else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, iconAuto, let symbol = await SectionIcon.pick(name: name, choose: store.jevChooser(.categoryIcons)),
              !Task.isCancelled, iconAuto else { return }
        update { $0.symbol = symbol }
    }
}

/// A category's section, in its editor: a menu of the sections. Nothing when there are none.
struct CategorySectionPicker: View {
    let store: Store
    @Binding var category: InboxCategory

    var body: some View {
        if !store.categorySections.isEmpty {
            let current = store.sectionID(of: category)
            SettingsRow("Section", info: ("Section", "The well of the bar it sits in. Which category a thing goes to doesn't change.")) {
                Menu {
                    ForEach(store.categorySections) { section in
                        Button { category.section = section.id } label: {
                            if section.id == current { Label(section.title, systemImage: "checkmark") } else { Text(section.title) }
                        }
                    }
                } label: {
                    Text(store.categorySections.first { $0.id == current }?.title ?? "None")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Section")
            }
        }
    }
}
