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
    static func pick(name: String, key: String?) async -> String? {
        if name.lowercased().contains("github") { return CategorySection.githubMark }
        if let key, !key.isEmpty, let symbol = try? await CategoryIcon.pick(name: name, key: key) { return symbol }
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

    /// New section: named, its icon from the name (the local pick; the page asks Jev after), at the end.
    @discardableResult
    func createSection(name: String) -> CategorySection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let made = CategorySection(name: trimmed, symbol: SectionIcon.local(name: trimmed) ?? CategoryIcon.fallback)
        categorySections.append(made)
        return made
    }

    /// Deletes a section; its categories go to the first one left (or to none).
    func deleteSection(_ id: UUID) {
        guard let i = categorySections.firstIndex(where: { $0.id == id }) else { return }
        // Theirs is gone: they go to the first left. The others keep theirs, even if that was the first by default.
        let rest = categorySections.filter { $0.id != id }.first?.id
        let next = categories.map { c -> InboxCategory in
            var c = c
            c.section = sectionID(of: c) == id ? rest : sectionID(of: c)
            return c
        }
        if next != categories { categories = next }
        categorySections.remove(at: i)
    }

    func moveCategory(_ id: UUID, toSection section: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == id }), sectionID(of: categories[i]) != section else { return }
        categories[i].section = section
    }

    func moveSection(_ id: UUID, by step: Int) {
        guard let i = categorySections.firstIndex(where: { $0.id == id }), categorySections.indices.contains(i + step) else { return }
        pinSections()
        categorySections.swapAt(i, i + step)
    }

    /// Writes down each category's section, so one that was in the first by default stays where it is when the first changes.
    private func pinSections() {
        let pinned = categories.map { c -> InboxCategory in
            var c = c
            c.section = sectionID(of: c)
            return c
        }
        if pinned != categories { categories = pinned }
    }
}

/// A section's icon in the bar, atop its well: the inbox's GitHub mark cell, with the section's own icon. A click opens it.
struct SectionCell: View {
    let section: CategorySection
    let vertical: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { SectionCellLabel(symbol: section.symbol, vertical: vertical) }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityHint("Opens its first category in the inbox")
    }
}

private struct SectionCellLabel: View {
    let symbol: String
    let vertical: Bool
    @State private var hover = false

    var body: some View {
        SectionGlyph(symbol: symbol, size: 14, color: hover ? Theme.text : Theme.secondary)
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

// MARK: - The categories page's sections

/// The categories page's Sections: one row per section (its icon, its name to edit, how many categories it holds), and New
/// section. A category's own editor (and its row's menu) says which section it is in.
struct SectionsSection: View {
    let store: Store
    @State private var focus: UUID?

    var body: some View {
        SettingsSection("Sections",
                        info: ("Sections", "Each is a well in the bar: its icon, then its categories. A category goes in one from its editor or its menu."),
                        action: {
            Button {
                focus = store.createSection(name: "").id
            } label: {
                HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)); Text("New section") }
            }
            .buttonStyle(SettingsButtonStyle(size: .sm))
            .accessibilityLabel("New section")
        }, content: {
            if store.categorySections.isEmpty {
                SettingsNest {
                    Text("No sections: the bar shows the categories alone.")
                        .cdsText((12, 16), .regular, CDS.Text.muted).padding(.vertical, 10)
                }
            } else {
                SettingsNest {
                    ForEach(Array(store.categorySections.enumerated()), id: \.element.id) { i, section in
                        if i > 0 { SettingsDivider() }
                        SectionRow(store: store, section: section, focusing: $focus)
                    }
                }
            }
        })
    }
}

private struct SectionRow: View {
    let store: Store
    let section: CategorySection
    @State private var picking = false
    @State private var renamed = false
    @FocusState private var focused: Bool
    @Binding var focusing: UUID?
    /// Its icon follows its name until you choose one.
    private var iconAuto: Bool { section.iconChosen != true }

    init(store: Store, section: CategorySection, focusing: Binding<UUID?>) {
        self.store = store
        self.section = section
        _focusing = focusing
    }

    private var name: Binding<String> {
        Binding(get: { section.name }, set: { value in update { $0.name = value } })
    }

    var body: some View {
        let count = store.categories.filter { store.sectionID(of: $0) == section.id }.count
        let index = store.categorySections.firstIndex { $0.id == section.id } ?? 0
        HStack(spacing: 10) {
            Button { picking = true } label: { SectionTile(symbol: section.symbol) }
                .buttonStyle(.plain)
                .tip("Icon", "Picked from the name; click to choose another")
                .accessibilityLabel("Icon of \(section.title). Choose another")
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    SymbolPicker(selection: section.symbol, color: .gray) { symbol in
                        update { $0.symbol = symbol; $0.iconChosen = true }
                        picking = false
                    }
                }
            TextField("", text: name)
                .textFieldStyle(.plain)
                .cdsText(CDS.Density.comfortable.body)
                .cdsPlaceholder("Name, like GitHub or Work", shown: section.name.isEmpty)
                .focused($focused)
                .accessibilityLabel("Section name")
            Spacer(minLength: 8)
            Text(plural(count, "category", "categories")).cdsText((12, 16), .regular, CDS.Text.muted).fixedSize()
            IconButton(symbol: "trash", help: count > 0 ? "Delete: its categories go to the first section left" : "Delete",
                       label: "Delete \(section.title)", size: 24, tint: CDS.Text.muted) {
                store.deleteSection(section.id)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contextMenu {
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
            if focusing == section.id { focused = true; focusing = nil }
        }
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
        guard !Task.isCancelled, iconAuto, let symbol = await SectionIcon.pick(name: name, key: store.typesafeKey),
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
