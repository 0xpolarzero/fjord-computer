import SwiftUI

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// Edits that could not be saved when the editor was left (Esc, the back chevron): kept per category, and for a new one,
/// until the editor is reopened. Only Cancel discards them.
struct CategoryDrafts {
    static var shared = CategoryDrafts()
    var kept: [CategoryEditing: InboxCategory] = [:]

    enum Outcome: Equatable { case unchanged, saved, kept }

    /// Why `draft` can't be saved, in words; nil when it can.
    static func blocker(_ draft: InboxCategory, groups: [InboxGroup], missing: Set<String> = []) -> String? {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the category a name." }
        if draft.rules.isEmpty { return "Add a rule: without one nothing lands here." }
        let n = draft.rules.reduce(0) { $0 + RuleEditing.problems($1, groups: groups, isCI: draft.isCI, missing: missing).count }
        if n > 0 { return "Fix the \(plural(n, "chip")) marked red to save." }
        return nil
    }

    /// Leaving without Cancel: a valid draft is saved, an invalid one is kept; one nobody touched is nothing.
    mutating func leave(_ draft: InboxCategory, original: InboxCategory, editing: CategoryEditing,
                        categories: inout [InboxCategory], groups: [InboxGroup]) -> Outcome {
        if draft == original { kept[editing] = nil; return .unchanged }
        guard Self.blocker(draft, groups: groups) == nil else { kept[editing] = draft; return .kept }
        var saved = draft
        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
        if let i = categories.firstIndex(where: { $0.id == saved.id }) { categories[i] = saved } else { categories.append(saved) }
        kept[editing] = nil
        return .saved
    }
}

/// One category: its name, icon (Jev picks it from the name), colour, notifications and rules. Edits a draft; Save writes it.
struct CategoryEditor: View {
    let store: Store
    let editing: CategoryEditing
    let close: () -> Void
    /// A note under the first rule, as after a switch of kind (shots).
    var firstRuleNotice: String?
    @State private var draft: InboxCategory
    private let original: InboxCategory
    /// Set by Save, Cancel and Delete: they decide for themselves, so leaving must not.
    @State private var finished = false
    @State private var restored: Bool
    /// Jev may still choose the icon: until you pick one yourself (and for a category that already has its own).
    @State private var iconAuto: Bool
    @State private var pickingIcon = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    init(store: Store, editing: CategoryEditing, firstRuleNotice: String? = nil, close: @escaping () -> Void) {
        self.firstRuleNotice = firstRuleNotice
        self.store = store
        self.editing = editing
        self.close = close
        let start: InboxCategory
        if case .existing(let id) = editing, let found = store.categories.first(where: { $0.id == id }) {
            start = found
            _iconAuto = State(initialValue: false)
        } else {
            let used = Set(store.categories.map(\.color))
            let color = CategoryColor.allCases.first { !used.contains($0) && $0 != .gray } ?? .blue
            start = InboxCategory(name: "", symbol: CategoryIcon.fallback, color: color, rules: [Rule(scope: Scope(kind: .pr))])
            _iconAuto = State(initialValue: true)
        }
        original = start
        if let kept = CategoryDrafts.shared.kept[editing] {
            _draft = State(initialValue: kept)
            _restored = State(initialValue: true)
            _iconAuto = State(initialValue: false)
        } else {
            _draft = State(initialValue: start)
            _restored = State(initialValue: false)
        }
    }

    private var isNew: Bool { if case .new = editing { true } else { false } }
    private var problemCount: Int {
        draft.rules.reduce(0) { $0 + RuleEditing.problems($1, groups: store.groups, isCI: draft.isCI, missing: store.missingRepos).count }
    }

    /// Why Save is off, in words.
    private var blocker: String? { CategoryDrafts.blocker(draft, groups: store.groups, missing: store.missingRepos) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identity
                    SettingsRow("Notify", info: ("Notify", "Once when a thing comes in, and again only on something new.")) {
                        SettingsSwitch("Notify for \(draft.name)", isOn: $draft.notifies)
                    }
                    rules
                    ActionsEditor(actions: $draft.actions, store: store, rules: draft.rules, categoryName: draft.name)
                    if !draft.isCI, !isNew { deleteRow }
                }
                .padding(.horizontal, CDS.Settings.pagePadX)
                .padding(.top, 4)
                .padding(.bottom, CDS.Settings.pageBottom)
            }
            .scrollIndicators(.never)
        }
        .task(id: draft.name) { await pickIcon() }
        .onAppear { if isNew { nameFocused = true } }
        .onDisappear { leave() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: close) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text("Categories") }
                }
                .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                .accessibilityLabel("Back to categories")
                .padding(.leading, -10)
                Spacer(minLength: 8)
                Button("Cancel", action: cancel).buttonStyle(SettingsButtonStyle(size: .sm))
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(blocker != nil)
            }
            if let blocker {
                Text(blocker).cdsText(foot12, .regular, problemCount > 0 ? CDS.Text.danger : CDS.Text.muted)
            }
            if restored, draft != original {
                Text("Unsaved changes kept").cdsText(foot12, .regular, CDS.Text.muted)
            }
        }
        .padding(.horizontal, CDS.Settings.pagePadX)
        .padding(.top, CDS.Settings.pageTop + 4)
        .padding(.bottom, 10)
    }

    // MARK: Name, icon, colour

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { pickingIcon = true } label: { CategoryTile(symbol: draft.symbol, color: draft.color, size: 32) }
                    .buttonStyle(.plain)
                    .tip("Icon", "Picked from the name; click to choose another")
                    .accessibilityLabel("Icon: \(draft.symbol). Choose another")
                    .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                        SymbolPicker(selection: draft.symbol, color: draft.color) { symbol in
                            draft.symbol = symbol
                            iconAuto = false
                            pickingIcon = false
                        }
                    }
                TextField("", text: $draft.name)
                    .cdsPlaceholder("Name, like Reviews or Mine", shown: draft.name.isEmpty)
                    .focused($nameFocused)
                    .cdsField(focused: nameFocused)
                    .accessibilityLabel("Category name")
            }
            HStack(spacing: 8) {
                ForEach(CategoryColor.allCases, id: \.self) { color in
                    Button { draft.color = color } label: {
                        Circle().fill(color.swatch).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(CDS.Text.primary, lineWidth: draft.color == color ? 2 : 0).padding(-3))
                            .frame(width: 24, height: 24).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(draft.color == color ? .isSelected : [])
                    .tip(color.title)
                }
            }
        }
    }

    /// Debounced. Jev's pick wins when it works; without a key or offline, a keyword in the name picks locally. Never once
    /// the icon was chosen by hand.
    private func pickIcon() async {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard iconAuto, name.count >= 2 else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, iconAuto else { return }
        if let key = store.typesafeKey, !key.isEmpty,
           let symbol = try? await CategoryIcon.pick(name: name, key: key) {
            guard !Task.isCancelled, iconAuto else { return }
            draft.symbol = symbol
        } else if !Task.isCancelled, iconAuto, let symbol = CategoryIcon.local(name: name) {
            draft.symbol = symbol
        }
    }

    // MARK: Rules

    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: CDS.Settings.labelGap) {
                Text(draft.isCI ? "Repos" : "Rules").cdsText(CDS.Density.comfortable.heading, .semibold)
                    .accessibilityAddTraits(.isHeader)
                    .tip(draft.isCI ? "Repos" : "Rules",
                         draft.isCI ? "Failures stay until the workflow is green again" : "A thing is here if any rule matches it")
            }
            .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.rules) { $rule in
                    if rule.id != draft.rules.first?.id {
                        Text("or").cdsText(foot12, .regular, CDS.Text.muted).padding(.leading, 4)
                    }
                    RuleEditor(rule: $rule, store: store, isCI: draft.isCI,
                               notice: rule.id == draft.rules.first?.id ? firstRuleNotice : nil,
                               onRemove: draft.isCI ? nil : { draft.rules.removeAll { $0.id == rule.id } })
                }
                if !draft.isCI {
                    Button { draft.rules.append(Rule(scope: Scope(kind: .pr))) } label: {
                        HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)); Text("Add rule") }
                    }
                    .buttonStyle(SettingsButtonStyle(size: .sm))
                    .padding(.top, 6)
                }
            }
        }
    }

    private var deleteRow: some View {
        HStack(spacing: 8) {
            if confirmingDelete {
                Text("Delete “\(draft.name)”? Its things go to the next category that matches.")
                    .cdsText(foot12, .regular, CDS.Text.secondary)
                Spacer(minLength: 8)
                Button("Keep") { confirmingDelete = false }.buttonStyle(SettingsButtonStyle(size: .sm))
                Button("Delete") {
                    store.categories.removeAll { $0.id == draft.id }
                    CategoryDrafts.shared.kept[editing] = nil
                    finished = true
                    close()
                }
                .buttonStyle(SettingsButtonStyle(size: .sm))
            } else {
                Button("Delete category") { confirmingDelete = true }.buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                    .padding(.leading, -10)
            }
        }
    }

    /// Esc or the back chevron: save what is valid, keep what is not. Only Cancel discards.
    private func leave() {
        guard !finished else { return }
        finished = true
        let outcome = CategoryDrafts.shared.leave(draft, original: original, editing: editing,
                                                  categories: &store.categories, groups: store.groups)
        // What is already here is old news to the actions it brought.
        if outcome == .saved { store.baselineActions() }
    }

    private func cancel() {
        CategoryDrafts.shared.kept[editing] = nil
        finished = true
        close()
    }

    private func save() {
        guard blocker == nil else { return }
        CategoryDrafts.shared.kept[editing] = nil
        finished = true
        var saved = draft
        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
        if let i = store.categories.firstIndex(where: { $0.id == saved.id }) {
            store.categories[i] = saved
        } else {
            store.categories.append(saved)
        }
        store.baselineActions()
        close()
    }
}

/// Every symbol Lookout knows, filtered by what is typed.
private struct SymbolPicker: View {
    let selection: String
    let color: CategoryColor
    let pick: (String) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let symbols = q.isEmpty ? CategoryIcon.all : CategoryIcon.all.filter { $0.contains(q) }
        VStack(spacing: 0) {
            TextField("", text: $query)
                .textFieldStyle(.plain).font(CDS.sans(13))
                .focused($focused)
                .cdsPlaceholder("Search symbols", shown: query.isEmpty)
                .padding(.horizontal, 10).frame(height: 34)
                .accessibilityLabel("Search symbols")
            Rectangle().fill(CDS.Settings.divider).frame(height: 1)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 2), count: 8), spacing: 2) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button { pick(symbol) } label: {
                            Image(systemName: symbol).font(.system(size: 13))
                                .foregroundStyle(symbol == selection ? color.swatch : CDS.Text.secondary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                                                          rest: symbol == selection ? CDS.Fill.ghostSelected : .clear,
                                                          hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
                        .help(symbol)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding(6)
            }
            .frame(width: 8 * 32 + 12, height: 220)
        }
        .background(CDS.Surface.s3)
        .onAppear { focused = true }
    }
}
