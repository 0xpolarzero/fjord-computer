import AppKit
import Observation
import SwiftUI

// Snippets: prompt texts you write once and insert where you write to Claude. Typing @ in the Router's composer or in a
// category's prompt lists them (`Store.snippets(matching:)`); picking one puts its text at the cursor as plain text, ready to
// edit. There is nothing to fill in: what the prompt is about goes with it.

/// A prompt text kept for reuse, under a name.
struct Snippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var text: String

    /// Its name, or "Untitled snippet" while it has none.
    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled snippet" }

    /// Its first line with text, for a row or a suggestion; nil when it has no text.
    var preview: String? {
        text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// Its symbol wherever it shows: the sidebar, its rows, a suggestion.
    static let symbol = "text.quote"

    /// The snippets `query` finds, best first: each of its words must be in the name or the text (case and accents aside).
    /// A name starting with the query comes first, then a name holding every word, then the rest; each in its own order.
    /// An empty query finds every snippet, in order.
    static func search(_ query: String, in snippets: [Snippet]) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snippets }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let loose: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func has(_ text: String, _ word: String) -> Bool { text.range(of: word, options: loose) != nil }
        func rank(_ snippet: Snippet) -> Int? {
            guard words.allSatisfy({ has(snippet.name, $0) || has(snippet.text, $0) }) else { return nil }
            if snippet.name.trimmingCharacters(in: .whitespaces).range(of: query, options: loose.union(.anchored)) != nil { return 0 }
            return words.allSatisfy { has(snippet.name, $0) } ? 1 : 2
        }
        return snippets.enumerated()
            .compactMap { i, snippet in rank(snippet).map { (rank: $0, at: i, snippet: snippet) } }
            .sorted { ($0.rank, $0.at) < ($1.rank, $1.at) }
            .map(\.snippet)
    }
}

extension Snippet {
    /// The demo's (and the shots').
    static let demo = [
        Snippet(name: "Review for bugs", text: "Review this for correctness bugs only: logic errors, races, missed edge cases. Skip style and naming.\nSay what you would change and why; don't change anything yet."),
        Snippet(name: "Fix CI", text: "Find out why CI fails here, fix the cause (not the test), and push the fix to this branch."),
        Snippet(name: "Answer the review", text: "Go through the open review threads: fix what is right, reply where you disagree and say why."),
    ]
}

extension Store {
    /// The snippets `query` finds, best first (`Snippet.search`): what @ lists.
    func snippets(matching query: String) -> [Snippet] { Snippet.search(query, in: snippets) }

    /// A new snippet at the end.
    @discardableResult
    func addSnippet(name: String = "New snippet", text: String = "") -> Snippet {
        let made = Snippet(name: name, text: text)
        snippets.append(made)
        return made
    }

    /// Changes the snippet `id`, if it is still there.
    func updateSnippet(_ id: UUID, _ change: (inout Snippet) -> Void) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        var snippet = snippets[i]
        change(&snippet)
        if snippet != snippets[i] { snippets[i] = snippet }
    }

    func deleteSnippet(_ id: UUID) {
        snippets.removeAll { $0.id == id }
    }

    /// Puts the snippet `id` where `target` is: after it going down, before it going up.
    func moveSnippet(_ id: UUID, onto target: UUID) {
        guard id != target, let from = snippets.firstIndex(where: { $0.id == id }),
              let to = snippets.firstIndex(where: { $0.id == target }) else { return }
        var list = snippets
        list.insert(list.remove(at: from), at: to)
        snippets = list
    }

    /// One place up (-1) or down (+1); false when it is already at that end.
    @discardableResult
    func moveSnippet(_ id: UUID, by step: Int) -> Bool {
        guard canMoveSnippet(id, by: step), let at = snippets.firstIndex(where: { $0.id == id }) else { return false }
        moveSnippet(id, onto: snippets[at + step].id)
        return true
    }

    func canMoveSnippet(_ id: UUID, by step: Int) -> Bool {
        guard let at = snippets.firstIndex(where: { $0.id == id }) else { return false }
        return snippets.indices.contains(at + step)
    }
}

// MARK: - The page's history

/// Undo and redo for the Snippets page, as the categories page has them (`CategoryHistory`): the snippets as they were
/// before each edit (every edit applies at once). Typing in one field is one step until it pauses.
@MainActor @Observable
final class SnippetHistory {
    private(set) var undos: [[Snippet]] = []
    private(set) var redos: [[Snippet]] = []
    @ObservationIgnored private var current: [Snippet]
    @ObservationIgnored private var lastField: ObjectIdentifier?
    @ObservationIgnored private var lastAt = Date.distantPast

    var canUndo: Bool { !undos.isEmpty }
    var canRedo: Bool { !redos.isEmpty }

    init(store: Store) { current = store.snippets }

    /// Notes what the store holds now. `field` is the text field being typed in, if any: changes in it, each within
    /// `CategoryHistory.pause` of the last, are one step.
    func observe(_ store: Store, field: ObjectIdentifier? = nil, now: Date = Date()) {
        guard store.snippets != current else { return }
        let merges = field != nil && field == lastField && now.timeIntervalSince(lastAt) <= CategoryHistory.pause && !undos.isEmpty
        if !merges {
            undos.append(current)
            if undos.count > CategoryHistory.limit { undos.removeFirst(undos.count - CategoryHistory.limit) }
        }
        redos.removeAll()
        current = store.snippets
        lastField = field
        lastAt = now
    }

    @discardableResult func undo(_ store: Store) -> Bool {
        observe(store, field: lastField, now: lastAt)
        guard let previous = undos.popLast() else { return false }
        redos.append(current)
        apply(previous, to: store)
        return true
    }

    @discardableResult func redo(_ store: Store) -> Bool {
        observe(store, field: lastField, now: lastAt)
        guard let next = redos.popLast() else { return false }
        undos.append(current)
        apply(next, to: store)
        return true
    }

    /// Forgets every step and takes the snippets as they are now as the start (the page shown again).
    func reset(to store: Store) {
        undos.removeAll()
        redos.removeAll()
        current = store.snippets
        lastField = nil
    }

    private func apply(_ snippets: [Snippet], to store: Store) {
        current = snippets
        lastField = nil
        store.snippets = snippets
    }
}

// MARK: - The page

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// The Snippets page: the snippets in order, each unfolding to its name and text, New snippet after them. Every edit
/// applies at once; ⌘Z takes it back. Drag a row, or use its menu, to reorder.
struct SnippetsView: View {
    let store: Store
    @State private var expanded: UUID?
    /// A snippet just made: its name field takes the focus.
    @State private var focusName: UUID?
    @State private var dropTarget: UUID?
    @State private var history: SnippetHistory

    static let about = "Prompts you write once. Type @ in the Router or in a category's prompt to insert one: its text goes in at the cursor, ready to edit, and is sent with what it is about."

    /// `expanded`: a snippet shown unfolded (shots).
    init(store: Store, expanded: UUID? = nil) {
        self.store = store
        _expanded = State(initialValue: expanded)
        _history = State(initialValue: SnippetHistory(store: store))
    }

    var body: some View {
        ScrollView {
            SettingsSection("Snippets", info: ("Snippets", Self.about)) {
                SettingsNest {
                    if store.snippets.isEmpty {
                        SettingsNote("No snippets yet. Type @ in the Router or in a category's prompt to insert one.")
                        SettingsDivider()
                    }
                    ForEach(Array(store.snippets.enumerated()), id: \.element.id) { i, snippet in
                        if i > 0 { SettingsDivider() }
                        row(snippet)
                    }
                    if !store.snippets.isEmpty { SettingsDivider() }
                    NewRow(title: "New snippet", symbol: "plus", action: add)
                }
            }
            .padding(.horizontal, CDS.Settings.pagePadX)
            .padding(.top, CDS.Settings.pageTop + 8)
            .padding(.bottom, CDS.Settings.pageBottom)
        }
        .scrollIndicators(.never)
        .onChange(of: store.snippets) { history.observe(store, field: CategoryHistory.typingField()) }
        // Shown again, the page starts its history afresh, as the categories page does.
        .onAppear {
            history.reset(to: store)
            store.snippetHistory = history
        }
        .onDisappear { if store.snippetHistory === history { store.snippetHistory = nil } }
    }

    private func row(_ snippet: Snippet) -> some View {
        SnippetRow(store: store, snippet: snippet, expanded: expanded == snippet.id, dropping: dropTarget == snippet.id,
                   focusName: $focusName) {
            expanded = expanded == snippet.id ? nil : snippet.id
        } drop: { payload in
            guard let payload, payload.hasPrefix(SnippetRow.dragPrefix),
                  let id = UUID(uuidString: String(payload.dropFirst(SnippetRow.dragPrefix.count))) else { return false }
            store.moveSnippet(id, onto: snippet.id)
            dropTarget = nil
            return true
        } target: { over in
            if over { dropTarget = snippet.id } else if dropTarget == snippet.id { dropTarget = nil }
        }
    }

    private func add() {
        let made = store.addSnippet()
        expanded = made.id
        focusName = made.id
    }
}

/// A snippet's row: its symbol, name and first line, unfolding to its editor (name, text, Delete).
private struct SnippetRow: View {
    let store: Store
    let snippet: Snippet
    let expanded: Bool
    let dropping: Bool
    @Binding var focusName: UUID?
    let toggle: () -> Void
    let drop: (String?) -> Bool
    let target: (Bool) -> Void
    @FocusState private var nameFocused: Bool

    /// What a row's drag carries: "snippet:<id>".
    static let dragPrefix = "snippet:"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded { editor.padding(.bottom, 10).padding(.leading, 34) }
        }
        .overlay(alignment: .top) {
            if dropping { Rectangle().fill(CDS.Fill.accent).frame(height: 2).offset(y: -1) }
        }
        .onAppear {
            if focusName == snippet.id {
                focusName = nil
                DispatchQueue.main.async { nameFocused = true }
            }
        }
    }

    /// The row's line; dragged to reorder, its menu and the accessibility actions on it (not on the editor, whose fields
    /// keep their own).
    private var header: some View {
        let detail = snippet.preview ?? "No text yet"
        return Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: Snippet.symbol)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(CDS.Text.secondary)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.title).cdsText(body14).lineLimit(1)
                    Text(detail).cdsText(foot12, .regular, CDS.Text.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CDS.Text.muted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(snippet.title), \(detail)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityAction(named: "Move up") { store.moveSnippet(snippet.id, by: -1) }
        .accessibilityAction(named: "Move down") { store.moveSnippet(snippet.id, by: 1) }
        .draggable(Self.dragPrefix + snippet.id.uuidString)
        .dropDestination(for: String.self) { items, _ in drop(items.first) } isTargeted: { target($0) }
        .contextMenu {
            Button(expanded ? "Fold" : "Edit", action: toggle)
            Divider()
            Button("Move up") { store.moveSnippet(snippet.id, by: -1) }
                .disabled(!store.canMoveSnippet(snippet.id, by: -1))
            Button("Move down") { store.moveSnippet(snippet.id, by: 1) }
                .disabled(!store.canMoveSnippet(snippet.id, by: 1))
            Divider()
            Button("Delete", role: .destructive) { store.deleteSnippet(snippet.id) }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: field(\.name))
                .cdsPlaceholder("Snippet name", shown: snippet.name.isEmpty)
                .focused($nameFocused)
                .cdsField(focused: nameFocused)
                .accessibilityLabel("Snippet name")
            SnippetTextBox(text: field(\.text), placeholder: "What it says, as you would type it to Claude", label: "Snippet text")
            HStack(spacing: 8) {
                Button("Delete snippet") { store.deleteSnippet(snippet.id) }
                    .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
                    .help("⌘Z brings it back")
            }
        }
    }

    private func field(_ key: WritableKeyPath<Snippet, String>) -> Binding<String> {
        Binding(get: { store.snippets.first { $0.id == snippet.id }?[keyPath: key] ?? "" },
                set: { value in store.updateSnippet(snippet.id) { $0[keyPath: key] = value } })
    }
}

/// A snippet's text: several lines in the field's look, with a placeholder (as a category's prompt is written).
private struct SnippetTextBox: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(CDS.sans(13))
            .foregroundStyle(CDS.Text.primary)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(minHeight: 120)
            .background(RoundedRectangle(cornerRadius: CDS.Settings.fieldRadius, style: .continuous).fill(CDS.Fill.field))
            .overlay(RoundedRectangle(cornerRadius: CDS.Settings.fieldRadius, style: .continuous)
                .strokeBorder(focused ? CDS.Fill.accent : CDS.Settings.fieldRing, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(CDS.sans(13)).foregroundStyle(CDS.Text.muted)
                        .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .accessibilityLabel(label)
    }
}
