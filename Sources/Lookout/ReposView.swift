import SwiftUI

struct ReposView: View {
    let store: Store
    @State private var input = ""
    @State private var error: String?
    @State private var adding = false
    @FocusState private var fieldFocused: Bool
    /// Keeps the suggestions up while the pointer is on them: clicking one ends the editing before the click lands.
    @State private var overList = false

    private var matches: [String] {
        let q = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(store.suggestions.prefix(5)) }
        return Array(store.suggestions.filter { $0.lowercased().contains(q) }.prefix(5))
    }

    /// Claude's list pattern (settings.md §4): a titled section, the field that adds one, then the watched repos as rows
    /// in a nest card, or a line when there are none. Straight on the island's black.
    var body: some View {
        ScrollView {
            SettingsSection("Repositories",
                            description: "Watch your own repos or any public one you contribute to. You'll only hear about the events you pick.") {
                addField
                if store.repos.isEmpty {
                    Text("No repositories yet.")
                        .cdsText(CDS.Density.comfortable.footnote, .regular, CDS.Text.secondary)
                        .padding(.vertical, CDS.Settings.rowPad)
                } else {
                    legend
                    SettingsNest {
                        ForEach(store.repos) { repo in
                            RepoCard(repo: repo, store: store)
                        }
                    }
                }
            }
            .padding(.horizontal, CDS.Settings.pagePadX)
            .padding(.top, CDS.Settings.pageTop + 8)
            .padding(.bottom, CDS.Settings.pageBottom)
        }
        .scrollIndicators(.never)
        .task { await store.loadSuggestions() }
    }

    /// Column header over the toggles of every row, in the same order and spacing as the badges: the list's header row.
    private var legend: some View {
        HStack(spacing: 10) {
            Text(plural(store.repos.count, "repo") + " watched").cdsText(CDS.Density.comfortable.body)
            Spacer(minLength: 8)
            RepoToggleColumns.legend
            Color.clear.frame(width: RepoCard.menuWidth, height: 1)
        }
        .padding(.horizontal, CDS.Settings.nestPadX)
        .padding(.top, CDS.Settings.rowPad + 4)
        .padding(.bottom, CDS.Settings.rowPad)
        .accessibilityHidden(true)
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(CDS.Text.muted)
                    TextField("", text: $input)
                        .cdsPlaceholder("owner/repo or GitHub URL", shown: input.isEmpty)
                        .accessibilityLabel("Repository to add")
                        .focused($fieldFocused)
                        .onSubmit { add(input) }
                    if adding { ProgressView().controlSize(.mini) }
                }
                // The leading slot: 8 between the icon and the text (§3.1 "with slots").
                .cdsField(focused: fieldFocused, invalid: error != nil)
                Button { add(input) } label: { Text("Watch") }
                    .buttonStyle(SettingsButtonStyle(size: .base))
                    .disabled(input.isEmpty || adding)
                    .accessibilityLabel("Watch repository")
                    .tip("Watch repository", "Add the repo typed on the left")
            }
            if let error {
                Text(error).cdsText(CDS.Density.comfortable.body, .regular, CDS.Text.danger)
            }
            if (fieldFocused || overList) && !matches.isEmpty {
                // The select popup's surface (settings.md §3.2): radius 12, #20201f, `shadow-panel`, 4 in.
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { name in
                        SuggestionRow(name: name) { add(name) }
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CDS.Surface.s3)
                    .shadow(color: CDS.PanelShadow.far.color, radius: CDS.PanelShadow.far.radius, y: CDS.PanelShadow.far.y)
                    .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
                .padding(.top, 2)
                .onHover { overList = $0 }
            }
        }
        .padding(.bottom, 4)
    }

    private func add(_ name: String) {
        guard !name.isEmpty, !adding else { return }
        adding = true
        error = nil
        let draft = input
        Task {
            let err = await store.addRepo(name)
            adding = false
            error = Self.said(err)
            if err == nil {
                // The field stays editable while the add runs: whatever was typed meanwhile is the next one, and stays.
                input = Self.field(afterAdding: draft, typed: input)
                if input.isEmpty { fieldFocused = false }
                overList = false
            }
        }
    }

    /// The sentence that appears under the field is said too, once (the list it joins is not what VoiceOver is on).
    static func said(_ failure: String?) -> String? {
        if let failure { Announce.say(failure) }
        return failure
    }

    /// What the field holds once the add of `draft` went through: emptied, unless something else was typed meanwhile.
    static func field(afterAdding draft: String, typed: String) -> String { typed == draft ? "" : typed }
}

private struct SuggestionRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SuggestionLabel(name: name)
        }
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), rest: .clear,
                                          hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
        .accessibilityLabel("Watch \(name)")
    }
}

/// A select item (settings.md §3.2): at least 32 tall, 12 in, gap 8, 14/20; the owner muted, the name primary.
private struct SuggestionLabel: View {
    let name: String
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed").font(.system(size: 12)).foregroundStyle(CDS.Text.muted)
            Text(name.split(separator: "/").first.map { "\($0)/" } ?? "").foregroundColor(CDS.Text.muted)
                + Text(name.split(separator: "/").last.map(String.init) ?? "").foregroundColor(CDS.Text.primary)
            Spacer()
            if hover { Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(CDS.Text.secondary) }
        }
        .font(CDS.sans(14))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

/// Shared geometry so the legend lines up with the badges.
private enum RepoToggleColumns {
    static let spacing: CGFloat = 3
    static let badge: CGFloat = 24
    static var kinds: [EventKind] { EventKind.repoToggles.filter { $0 != .ciMain } }

    /// Group captions with a line underneath, spanning the badge columns they describe:
    /// issues (opened, comments), pull requests (opened, comments, review comments), all-comments ("All") and CI.
    static var legend: some View {
        HStack(spacing: spacing) {
            group("Issues", columns: 2)
            group("Pull requests", columns: 3)
            Color.clear.frame(width: 5, height: 1)
            group("All", columns: 1)
            group("CI", columns: 1)
        }
    }

    /// Caption 12 is too wide for three 24pt columns ("Pull requests"): the xs badge's 11 at 460 instead.
    private static func group(_ text: String, columns: Int) -> some View {
        let width = CGFloat(columns) * badge + CGFloat(columns - 1) * spacing
        return VStack(spacing: 3) {
            Text(text).font(CDS.sans(11, .medium)).foregroundStyle(CDS.Text.muted).lineLimit(1).fixedSize()
            Rectangle().fill(CDS.border).frame(height: 1)
        }
        .frame(width: width)
    }
}

/// A watched repo: a row in the list's nest card (settings.md §2.2, §4), the name 14/20 over its owner in muted, the event
/// toggles and a "more" menu as the control. No hover fill (rows don't react, their controls do); dragging one onto
/// another reorders them, its target outlined in accent.
struct RepoCard: View {
    let repo: RepoConfig
    let store: Store
    @State private var dropTarget = false
    @FocusState private var menuFocused: Bool
    @Environment(\.previewTip) private var previewTip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ghost sm icon button's 28 (forms-buttons.md §4.4).
    static let menuWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.name).cdsText(CDS.Density.comfortable.body)
                Text(repo.owner).cdsText(CDS.Density.comfortable.body, .regular, CDS.Text.muted)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            // The spec's 28 between text and control, cut to 8: the toggles take most of the island's width.
            Spacer(minLength: 8)
            if let error = store.repoErrors[repo.fullName] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(CDS.Text.warning)
                    .frame(width: 18, height: 24)
                    .accessibilityLabel("Sync failed: \(error)")
                    .tip("Sync failed", error)
            }
            HStack(spacing: RepoToggleColumns.spacing) {
                ForEach(RepoToggleColumns.kinds) { kind in
                    badge(kind)
                }
                Rectangle().fill(CDS.border).frame(width: 1, height: 14).padding(.horizontal, 2)
                allCommentsBadge
                ciBadge
            }
            menu
        }
        .padding(.vertical, CDS.Settings.rowPad)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CDS.Fill.accent, lineWidth: 1)
                .padding(.horizontal, -6)
                .opacity(dropTarget ? 1 : 0)
        )
        .motion(Theme.Motion.hover, value: dropTarget)
        // Screenshots target one badge as "owner/repo|Tooltip title"; only that card shows it.
        .environment(\.previewTip, previewTip.flatMap { spec in
            spec.hasPrefix(repo.fullName + "|") ? String(spec.dropFirst(repo.fullName.count + 1)) : nil
        })
        .draggable(repo.fullName) {
            Text(repo.fullName)
                .cdsText(CDS.Density.comfortable.body)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CDS.Surface.s3))
        }
        .dropDestination(for: String.self) { names, _ in
            guard let name = names.first else { return false }
            withAnimation(Theme.Motion.spring.resolved(reduce: reduceMotion)) { store.moveRepo(name, onto: repo.fullName) }
            return true
        } isTargeted: { dropTarget = $0 }
    }

    // MARK: Badges

    private func badge(_ kind: EventKind) -> some View {
        let on = repo.events.contains(kind)
        let filtered = kind != .issueOpened && kind != .prOpened && !repo.allComments
        let detail = filtered ? "Only on your threads, @mentions and replies to you" : kind.tipDetail
        return BadgeButton(symbol: kind.symbol, color: kind.color, on: on, label: kind.toggleLabel,
                           tip: detail + (on ? "" : "\nOff · click to turn on")) { store.toggle(kind, on: repo) }
    }

    private var allCommentsBadge: some View {
        let hasComments = !repo.events.isDisjoint(with: [.issueComment, .prComment, .reviewComment])
        return BadgeButton(symbol: "bubble.left.and.bubble.right.fill", color: Theme.accent, on: repo.allComments,
                           label: "All comments", tipTitle: repo.allComments ? "All comments" : "Comments for you",
                           tip: repo.allComments ? "Every comment in this repo" : "Click to get every comment, not only the ones for you") {
            store.toggleAllComments(repo)
        }
        .opacity(hasComments ? 1 : 0.35)
        .disabled(!hasComments)
    }

    private var ciBadge: some View {
        let on = repo.events.contains(.ciMain)
        let status = store.ci[repo.fullName]
        let state = status?.state ?? .none
        let symbol = on ? state.symbol : "seal"
        let branch = status?.branch ?? repo.defaultBranch ?? "default branch"
        var detail = on ? "\(branch) \(state.label)" : "Hidden from the bar · click to show"
        if on, state == .failure, let failing = status?.failing, !failing.isEmpty {
            detail += "\n" + failing.prefix(4).joined(separator: "\n")
        }
        return BadgeButton(symbol: symbol, color: state == .none ? Theme.secondary : state.color, on: on, label: "CI",
                           value: on ? "\(state.label), shown on the bar" : "Hidden from the bar", tip: detail) {
            store.toggle(.ciMain, on: repo)
        }
    }

    private var menu: some View {
        Menu {
            Button("Open on GitHub") { Link.open(repo.url) }
            Button("Open Actions") { Link.open(repo.url.appendingPathComponent("actions")) }
            if store.ci[repo.fullName]?.url != nil {
                Button("Open latest commit checks") { store.openChecks(repo) }
            }
            Divider()
            Button("Stop watching", role: .destructive) { store.removeRepo(repo) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(CDS.Text.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm, iconOnly: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(repo.fullName)")
        .focused($menuFocused)
        .tip("More", "Open on GitHub, or stop watching", focused: menuFocused)
    }
}

private struct BadgeButton: View {
    let symbol: String
    let color: Color
    let on: Bool
    var label = ""
    /// What VoiceOver reads as the state; defaults to On/Off.
    var value: String? = nil
    /// Its tooltip: the title (the label, unless another says more) and what it adds.
    var tipTitle: String? = nil
    let tip: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { BadgeLabel(symbol: symbol, color: color, on: on) }
            // Off, a quiet field (white 5%, 7.5% on hover); on, the event's own colour, as before: they are a legend too.
            .buttonStyle(HoverFillButtonStyle(
                shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                rest: on ? color.opacity(0.15) : CDS.Fill.field,
                hover: on ? color.opacity(0.24) : CDS.Fill.ghostHover,
                pressed: on ? color.opacity(0.32) : CDS.Fill.ghostSelected))
            .accessibilityLabel(label)
            .accessibilityValue(value ?? (on ? "On" : "Off"))
            .focused($focused)
            .tip(tipTitle ?? label, tip, focused: focused)
    }
}

private struct BadgeLabel: View {
    let symbol: String
    let color: Color
    let on: Bool
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5))
            .foregroundStyle(on ? color : hover ? CDS.Text.secondary : CDS.Text.muted)
            .frame(width: RepoToggleColumns.badge, height: RepoToggleColumns.badge)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? color.opacity(0.25) : CDS.border))
    }
}
