import SwiftUI

private let body13: (CGFloat, CGFloat) = (13, 19)
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// A category's "Then": what it does by itself when a thing comes in. Each action is edited in place; "Try on latest match"
/// shows what it would do to the latest thing the rules match, and does nothing.
struct ActionsEditor: View {
    @Binding var actions: ActionList
    let store: Store
    let rules: [Rule]
    let categoryName: String

    private var kinds: Set<ThingKind> { Set(rules.map(\.scope.kind)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Then").cdsText(CDS.Density.comfortable.heading, .semibold)
                .accessibilityAddTraits(.isHeader)
                .tip("Then", "Runs once for each thing that comes in, never for what is already here when you add it")
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                ForEach($actions.items) { $action in
                    ActionRow(action: $action, store: store, rules: rules, categoryName: categoryName, kinds: kinds) {
                        actions.items.removeAll { $0.id == action.id }
                    }
                }
                addMenu.padding(.top, actions.isEmpty ? 0 : 6)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Ask the Router") { actions.items.append(.make(.askRouter(prompt: ""))) }
            Button("Comment on GitHub") { actions.items.append(.make(.comment(""))) }
            Button("Re-run failed checks") { actions.items.append(.make(.rerun)) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                Text("Action")
            }
        }
        .menuStyle(.button)
        .buttonStyle(ChipButtonStyle(tone: .dashed))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add an action")
    }
}

private struct ActionRow: View {
    @Binding var action: CategoryAction
    let store: Store
    let rules: [Rule]
    let categoryName: String
    let kinds: Set<ThingKind>
    let remove: () -> Void
    @State private var preview: [String]?
    @State private var trying = false

    private var applies: Bool { kinds.isEmpty || kinds.contains { action.applies(to: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: action.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(CDS.Text.secondary)
                    .frame(width: 16)
                Text(action.title).cdsText(body13, .medium)
                Spacer(minLength: 8)
                MenuChip(title: action.trigger == .enter ? "when it comes in" : "on each new fact", label: "When it runs") {
                    Toggle("When it comes in", isOn: Binding(get: { action.trigger == .enter }, set: { _ in action.trigger = .enter }))
                    Toggle("On each new fact", isOn: Binding(get: { action.trigger == .eachFact }, set: { _ in action.trigger = .eachFact }))
                }
                IconButton(symbol: "xmark", help: "Remove", label: "Remove \(action.title)", size: 24, tint: CDS.Text.muted, action: remove)
            }
            switch action.kind {
            case .askRouter(let prompt):
                ActionTextBox(text: Binding(get: { prompt }, set: { action.kind = .askRouter(prompt: $0) }),
                              placeholder: "What to do, like “Review {url} and fix what Greptile flagged”", label: "Prompt")
                    .tip("Prompt", "The Router starts a new session in a local clone of the repo (Jev picks when there are several; no clone, no session). Its title, link, repo, why it is here and the last comment are added for you. {title} {url} {number} {repo} {author} are filled in.")
                HStack(spacing: 8) {
                    MenuChip(title: "Model: " + (action.model?.capitalized ?? "Default"), label: "Model") {
                        Toggle("Default", isOn: Binding(get: { action.model == nil }, set: { _ in action.model = nil }))
                        ForEach(ActionSettings.models, id: \.self) { model in
                            Toggle(model.capitalized, isOn: Binding(get: { action.model == model }, set: { _ in action.model = model }))
                        }
                    }
                    .tip("Model", "The model of the session it starts. Default is the one in your Claude Code settings.")
                    MenuChip(title: "Effort: " + (action.effort ?? "Default"), label: "Effort") {
                        Toggle("Default", isOn: Binding(get: { action.effort == nil }, set: { _ in action.effort = nil }))
                        ForEach(ActionSettings.efforts, id: \.self) { effort in
                            Toggle(effort, isOn: Binding(get: { action.effort == effort }, set: { _ in action.effort = effort }))
                        }
                    }
                    .tip("Effort", "How hard the session it starts thinks. Default is the one in your Claude Code settings.")
                }
                RouterWarning(strong: InboxActions.rulesMatchOthers(rules))
            case .comment(let text):
                ActionTextBox(text: Binding(get: { text }, set: { action.kind = .comment($0) }),
                              placeholder: "The comment, like “Thanks @{author}, taking a look”", label: "Comment")
                    .tip("Comment", "{title} {url} {number} {repo} {author} are filled in. PRs and issues only.")
            case .rerun:
                EmptyView()
            }
            if !applies {
                Text("None of this category's rules is something this applies to.").cdsText(foot12, .regular, CDS.Text.danger)
            }
            HStack(spacing: 8) {
                Button { Task { await tryIt() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye").font(.system(size: 11, weight: .medium))
                        Text(trying ? "Looking…" : "Try on latest match")
                    }
                }
                .buttonStyle(SettingsButtonStyle(size: .sm))
                .disabled(trying)
                .tip("Try on latest match", "Shows what it would do. Nothing is done.")
                if preview != nil {
                    Button("Hide") { preview = nil }.buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                }
            }
            if let preview {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
                        Text(line).cdsText(foot12, .regular, CDS.Text.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CDS.Fill.field))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preview")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
    }

    private func tryIt() async {
        trying = true
        defer { trying = false }
        guard let match = store.latestMatch(of: rules) else {
            preview = ["Nothing matches yet, so there is nothing to try it on."]
            return
        }
        let performer = store.actionPerformer ?? (store.persists && !Store.isDemo ? StoreActionPerformer(store: store) : nil)
        preview = await InboxActions.preview(action, category: categoryName.isEmpty ? "New category" : categoryName,
                                             thing: match.thing, facts: match.facts, performer: performer)
    }
}

/// Under "Ask the Router": what reaches the session is written by others; stronger when the rules can match their items.
private struct RouterWarning: View {
    let strong: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold))
            Text("GitHub text reaches a Claude session on your Mac").cdsText(foot12, strong ? .medium : .regular, CDS.Text.warning)
        }
        .foregroundStyle(CDS.Text.warning)
        .padding(.horizontal, strong ? 8 : 0).padding(.vertical, strong ? 4 : 0)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CDS.Text.warning.opacity(strong ? 0.16 : 0)))
        .tip("Prompt injection", "Anyone who can write a title or comment on matching items can try to steer that session. It runs with your Claude Code permission settings, unattended. Keep the prompt narrow and the rules tight (by me, Maintainers)."
             + (strong ? " These rules match items others write." : ""))
        .accessibilityElement(children: .combine)
    }
}

/// A few lines of text in the field's look, with a placeholder.
private struct ActionTextBox: View {
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
            .frame(minHeight: 72)
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
