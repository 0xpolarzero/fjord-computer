import SwiftUI

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// One category: its name, icon (Jev picks it from the name), colour, notifications and rules. Every change is made in the
/// store as it happens; the page's history (undo and redo, in the header) takes it back. A new one (New category) is a draft
/// outside the store: nothing is made until Create, and leaving drops it.
struct CategoryEditor: View {
    let store: Store
    let editing: CategoryEditing
    let history: CategoryHistory
    /// New category's draft, edited here until Create; nil for a category in the store.
    let newDraft: Binding<InboxCategory>?
    /// Puts the draft in the store.
    let create: () -> Void
    let close: () -> Void
    private var isNew: Bool { newDraft != nil }
    /// A note under the first rule, as after a switch of kind (shots).
    var firstRuleNotice: String?
    /// Jev may still choose the icon: until you pick one yourself (and for a category that already has its own).
    @State private var iconAuto: Bool
    @State private var pickingIcon = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    init(store: Store, editing: CategoryEditing, history: CategoryHistory, draft: Binding<InboxCategory>? = nil,
         create: @escaping () -> Void = {}, firstRuleNotice: String? = nil, close: @escaping () -> Void) {
        self.firstRuleNotice = firstRuleNotice
        self.store = store
        self.editing = editing
        self.history = history
        newDraft = draft
        self.create = create
        self.close = close
        _iconAuto = State(initialValue: draft != nil)
    }

    private var id: UUID { if case .existing(let id) = editing { id } else { UUID() } }
    private var index: Int? { store.categories.firstIndex { $0.id == id } }

    /// The category in the store, edited in place (or the new one's draft).
    private var draft: Binding<InboxCategory> {
        if let newDraft { return newDraft }
        let id = id
        return Binding(get: { store.categories.first { $0.id == id } ?? InboxCategory(id: id, name: "", symbol: "", color: .gray) },
                       set: { if let i = store.categories.firstIndex(where: { $0.id == id }) { store.categories[i] = $0 } })
    }

    var body: some View {
        if let current = newDraft?.wrappedValue ?? index.map({ store.categories[$0] }) {
            content(current)
        } else {
            // Gone (deleted, or undone): back to the list.
            Color.clear.onAppear(perform: close)
        }
    }

    private func content(_ c: InboxCategory) -> some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identity(c)
                    SettingsRow("Notify", info: ("Notify", "Once when a thing comes in, and again only on something new.")) {
                        SettingsSwitch("Notify for \(c.title)", isOn: draft.notifies)
                    }
                    rules(c)
                    ActionsEditor(actions: draft.actions, store: store, rules: c.rules, categoryName: c.name)
                    if !c.isCI, !isNew { deleteRow(c) }
                }
                .padding(.horizontal, CDS.Settings.pagePadX)
                .padding(.top, 4)
                .padding(.bottom, CDS.Settings.pageBottom)
            }
            .scrollIndicators(.never)
        }
        .task(id: c.name) { await pickIcon() }
        .onAppear { if isNew { nameFocused = true } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: close) {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text("Categories") }
            }
            .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
            .accessibilityLabel("Back to categories")
            .padding(.leading, -10)
            Spacer(minLength: 8)
            if isNew { createButton } else { undoRedo }
        }
        .padding(.horizontal, CDS.Settings.pagePadX)
        .padding(.top, CDS.Settings.pageTop + 4)
        .padding(.bottom, 10)
    }

    /// Whether Create can make it: it needs a name.
    private var canCreate: Bool { !draft.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var createButton: some View {
        Button("Create", action: create)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canCreate)
            .tip(canCreate ? "Create category" : "Name it first")
    }

    @ViewBuilder private var undoRedo: some View {
        IconButton(symbol: "arrow.uturn.backward", help: "Undo", label: "Undo", size: 24,
                   tint: history.canUndo ? CDS.Text.secondary : CDS.Text.muted) { _ = history.undo(store) }
            .disabled(!history.canUndo)
        IconButton(symbol: "arrow.uturn.forward", help: "Redo", label: "Redo", size: 24,
                   tint: history.canRedo ? CDS.Text.secondary : CDS.Text.muted) { _ = history.redo(store) }
            .disabled(!history.canRedo)
    }

    // MARK: Name, icon, colour

    private func identity(_ c: InboxCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { pickingIcon = true } label: { CategoryTile(symbol: c.symbol, color: c.color, size: 32) }
                    .buttonStyle(.plain)
                    .tip("Icon", "Picked from the name; click to choose another")
                    .accessibilityLabel("Icon: \(c.symbol). Choose another")
                    .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                        SymbolPicker(selection: c.symbol, color: c.color) { symbol in
                            draft.wrappedValue.symbol = symbol
                            iconAuto = false
                            pickingIcon = false
                        }
                    }
                TextField("", text: draft.name)
                    .cdsPlaceholder("Name, like Reviews or Mine", shown: c.name.isEmpty)
                    .focused($nameFocused)
                    .onSubmit { if isNew, canCreate { create() } }
                    .cdsField(focused: nameFocused)
                    .accessibilityLabel("Category name")
            }
            HStack(spacing: 8) {
                ForEach(CategoryColor.allCases, id: \.self) { color in
                    Button { draft.wrappedValue.color = color } label: {
                        Circle().fill(color.swatch).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(CDS.Text.primary, lineWidth: c.color == color ? 2 : 0).padding(-3))
                            .frame(width: 24, height: 24).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(c.color == color ? .isSelected : [])
                    .tip(color.title)
                }
            }
        }
    }

    /// Debounced. Jev's pick wins when it works; without a key or offline, a keyword in the name picks locally. Never once
    /// the icon was chosen by hand.
    private func pickIcon() async {
        let name = draft.wrappedValue.name.trimmingCharacters(in: .whitespaces)
        guard iconAuto, name.count >= 2 else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, iconAuto else { return }
        if let key = store.typesafeKey, !key.isEmpty,
           let symbol = try? await CategoryIcon.pick(name: name, key: key) {
            guard !Task.isCancelled, iconAuto else { return }
            draft.wrappedValue.symbol = symbol
        } else if !Task.isCancelled, iconAuto, let symbol = CategoryIcon.local(name: name) {
            draft.wrappedValue.symbol = symbol
        }
    }

    // MARK: Rules

    private func rules(_ c: InboxCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: CDS.Settings.labelGap) {
                Text(c.isCI ? "Repos" : "Rules").cdsText(CDS.Density.comfortable.heading, .semibold)
                    .accessibilityAddTraits(.isHeader)
                    .tip(c.isCI ? "Repos" : "Rules",
                         c.isCI ? "Failures stay until the workflow is green again" : "A thing is here if any rule matches it")
            }
            .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(draft.rules) { $rule in
                    if rule.id != c.rules.first?.id {
                        Text("or").cdsText(foot12, .regular, CDS.Text.muted).padding(.leading, 4)
                    }
                    RuleEditor(rule: $rule, store: store, isCI: c.isCI,
                               notice: rule.id == c.rules.first?.id ? firstRuleNotice : nil,
                               onRemove: c.isCI ? nil : { draft.wrappedValue.rules.removeAll { $0.id == rule.id } })
                    let off = InboxEngine.problems(rule)
                    if !off.isEmpty {
                        Text("Off until fixed").cdsText(foot12, .regular, CDS.Text.danger).padding(.leading, 4)
                            .tip("Off until fixed", off.map(\.reason).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ". "))
                    }
                }
                if !c.isCI {
                    Button { draft.wrappedValue.rules.append(Rule(scope: Scope(kinds: [.pr]))) } label: {
                        HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)); Text("Add rule") }
                    }
                    .buttonStyle(SettingsButtonStyle(size: .sm))
                    .padding(.top, 6)
                }
            }
        }
    }

    private func deleteRow(_ c: InboxCategory) -> some View {
        HStack(spacing: 8) {
            if confirmingDelete {
                Text("Delete “\(c.title)”? Its things go to the next category that matches.")
                    .cdsText(foot12, .regular, CDS.Text.secondary)
                Spacer(minLength: 8)
                Button("Keep") { confirmingDelete = false }.buttonStyle(SettingsButtonStyle(size: .sm))
                Button("Delete") {
                    store.categories.removeAll { $0.id == c.id }
                    close()
                }
                .buttonStyle(SettingsButtonStyle(size: .sm))
            } else {
                Button("Delete category") { confirmingDelete = true }.buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                    .padding(.leading, -10)
            }
        }
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
