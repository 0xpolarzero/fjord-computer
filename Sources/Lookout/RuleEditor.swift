import SwiftUI

private let body13: (CGFloat, CGFloat) = (13, 19)
private let foot12: (CGFloat, CGFloat) = (12, 16)

// MARK: - A rule, as a sentence

/// One rule: `PRs by me in Contributing`, the slots added with +, then `when any of:` and its conditions. Chips that can never
/// match turn red with the reason under the sentence. Under it, what the rule matches in what is already fetched.
struct RuleEditor: View {
    @Binding var rule: Rule
    let store: Store
    /// CI: the editor only takes repos.
    var isCI = false
    var onRemove: (() -> Void)?
    @State private var notice: String?
    @State private var matches: Int?
    @State private var previewedKinds: Set<ThingKind>?

    init(rule: Binding<Rule>, store: Store, isCI: Bool = false, notice: String? = nil, onRemove: (() -> Void)? = nil) {
        _rule = rule
        self.store = store
        self.isCI = isCI
        self.onRemove = onRemove
        _notice = State(initialValue: notice)
    }

    private var data: EditorData { EditorData(store: store) }
    private var kinds: Set<ThingKind> { rule.scope.kinds }
    private var problems: [InboxEngine.Problem] { RuleEditing.problems(rule, groups: store.groups, isCI: isCI, missing: store.missingRepos) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SentenceLayout(spacing: 4, lineSpacing: 6) {
                kindChip
                scopeSlots
                addSlotMenu
            }
            if !isCI {
                conditions
            }
            messages
            footer
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
        // Whenever the rule changes (its kinds too), debounced; different kinds are counted at once.
        .task(id: rule) {
            if previewedKinds == rule.scope.kinds { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            previewedKinds = rule.scope.kinds
            matches = store.preview(rule).count
        }
    }

    // MARK: Sentence

    private func tone(_ slot: String) -> ChipTone { problems.contains { $0.slot == slot } ? .danger : .neutral }

    /// PRs and issues tick together; workflows stand alone (`RuleEditing.toggling`).
    @ViewBuilder private var kindChip: some View {
        if isCI {
            Text(kinds.label).modifier(ChipLook())
        } else {
            MenuChip(title: kinds.label, tone: tone("kind"), label: "Kinds of thing") {
                ForEach(ThingKind.allCases, id: \.self) { k in
                    Toggle(k.label, isOn: Binding(get: { kinds.contains(k) },
                                                  set: { change(to: RuleEditing.toggling(k, on: $0, in: kinds)) }))
                }
            }
            .tip("Kinds of thing", "PRs and issues can share a rule; workflows take a rule of their own")
        }
    }

    private func change(to next: Set<ThingKind>) {
        let result = RuleEditing.switchKinds(rule, to: next)
        guard result.rule != rule else { return }
        rule = result.rule
        matches = store.preview(result.rule).count
        previewedKinds = next
        notice = RuleEditing.droppedNotice(result.dropped, for: next)
    }

    @ViewBuilder private var scopeSlots: some View {
        if !rule.scope.isWorkflow {
            peopleScope("by", $rule.scope.by)
            toScope
            repoScope(required: false)
        } else {
            repoScope(required: true)
            stringScope("on", placeholder: "branch", $rule.scope.on,
                        pool: data.values({ [$0.branch].compactMap { $0 } }, in: data.namedRepos(rule.scope.in)))
            stringScope("named", placeholder: "workflow", $rule.scope.named,
                        pool: data.values({ [$0.workflowName].compactMap { $0 } }, in: data.namedRepos(rule.scope.in)))
        }
    }

    /// The word opens the slot's autocomplete; its footer removes the slot.
    @ViewBuilder private func peopleScope(_ word: String, _ slot: Binding<Pick<PersonRef>?>) -> some View {
        if slot.wrappedValue != nil {
            PeopleSlot(pick: Binding(get: { slot.wrappedValue ?? Pick() }, set: { slot.wrappedValue = $0 }), store: store,
                       tone: tone(word))
                .slotWord(SlotWord(name: word, text: word, tone: tone(word), remove: { slot.wrappedValue = nil }))
        }
    }

    /// `to` has its roles at the top of its popover: assigned, review requested, mentioned. Review requested is not offered
    /// where it can never match.
    @ViewBuilder private var toScope: some View {
        if rule.scope.to != nil {
            let roles = RuleEditing.roles(kinds)
            let picked = roles.filter { rule.scope.toRoles.contains($0) }
            let byMe = rule.scope.by?.include == [.me] && rule.scope.by?.except.isEmpty == true
            let toMe = rule.scope.to?.include == [.me]
            let offered = roles.filter { !($0 == .reviewRequested && byMe && toMe) }
            PeopleSlot(pick: Binding(get: { rule.scope.to ?? Pick() }, set: { rule.scope.to = $0 }), store: store,
                       tone: tone("to"), hidden: byMe ? [.me] : [], teams: kinds.contains(.pr))
                .slotWord(SlotWord(
                    name: "to",
                    text: picked.count == roles.count ? "to" : "to (" + picked.map(RuleEditing.roleTitle).joined(separator: ", ") + ")",
                    tone: tone("to"),
                    roles: offered.map { role in
                        SlotToggle(title: RuleEditing.roleTitle(role), isOn: rule.scope.toRoles.contains(role)) { on in
                            if on { rule.scope.toRoles.insert(role) } else if rule.scope.toRoles.count > 1 { rule.scope.toRoles.remove(role) }
                        }
                    },
                    remove: { rule.scope.to = nil }))
        }
    }

    @ViewBuilder private func repoScope(required: Bool) -> some View {
        if required || rule.scope.in != nil {
            let slot = RepoSlot(pick: Binding(get: { rule.scope.in ?? Pick() }, set: { rule.scope.in = $0 }), store: store, involved: !rule.scope.isWorkflow, onMoved: { notice = $0 },
                                placeholder: required ? (isCI ? "all watched repos" : "choose repos") : "anywhere", tone: tone("in"))
            // Required: the word still opens the picker, but there is nothing to remove.
            slot.slotWord(SlotWord(name: "in", text: "in", tone: tone("in"), remove: required ? nil : { rule.scope.in = nil }))
        }
    }

    @ViewBuilder private func stringScope(_ word: String, placeholder: String, _ slot: Binding<[String]?>, pool: [String]) -> some View {
        if slot.wrappedValue != nil {
            StringSlot(pick: Binding(get: { Pick(include: slot.wrappedValue ?? []) }, set: { slot.wrappedValue = $0.include }),
                       store: store, placeholder: placeholder, pool: pool, allowsExcept: false, tone: tone(word))
                .slotWord(SlotWord(name: word, text: word, tone: tone(word), remove: { slot.wrappedValue = nil }))
        }
    }

    /// The + that adds a slot nobody has set yet, named by what it adds: "+ to  in".
    @ViewBuilder private var addSlotMenu: some View {
        let slots = unsetSlots
        if !slots.isEmpty {
            Menu {
                ForEach(slots, id: \.title) { slot in Button(slot.menu, action: slot.add) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text(slots.map(\.title).joined(separator: " · "))
                }
            }
            .menuStyle(.button)
            .buttonStyle(ChipButtonStyle(tone: .dashed))
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Add " + slots.map(\.title).joined(separator: ", "))
        }
    }

    private var unsetSlots: [(title: String, menu: String, add: () -> Void)] {
        var out: [(String, String, () -> Void)] = []
        if !rule.scope.isWorkflow {
            if rule.scope.by == nil { out.append(("by", "by someone", { rule.scope.by = Pick() })) }
            if rule.scope.to == nil { out.append(("to", "to someone", { rule.scope.to = Pick() })) }
            if rule.scope.in == nil { out.append(("in", "in some repos", { rule.scope.in = Pick() })) }
        } else {
            if rule.scope.on == nil { out.append(("on", "on a branch", { rule.scope.on = [] })) }
            if rule.scope.named == nil { out.append(("named", "named…", { rule.scope.named = [] })) }
        }
        return out
    }

    // MARK: Conditions

    @ViewBuilder private var conditions: some View {
        let byMe = rule.scope.by?.include == [.me] && rule.scope.by?.except.isEmpty == true
        VStack(alignment: .leading, spacing: 6) {
            if rule.conditions.isEmpty {
                HStack(spacing: 6) {
                    addConditionMenu
                }
            } else {
                HStack(spacing: 4) {
                    Word("when")
                    // One condition has nothing to be any or all of: just "when".
                    if rule.conditions.count > 1 {
                        MenuChip(title: rule.match.rawValue, label: "Match any or all") {
                            Toggle("any of these", isOn: Binding(get: { rule.match == .any }, set: { _ in rule.match = .any }))
                            Toggle("all of these", isOn: Binding(get: { rule.match == .all }, set: { _ in rule.match = .all }))
                        }
                        Word("of:")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rule.conditions.enumerated()), id: \.offset) { i, _ in
                        ConditionRow(condition: Binding(get: { rule.conditions.indices.contains(i) ? rule.conditions[i] : .hasConflicts },
                                                        set: { if rule.conditions.indices.contains(i) { rule.conditions[i] = $0 } }),
                                     store: store, kinds: kinds, repos: data.namedRepos(rule.scope.in), byOnlyMe: byMe,
                                     siblings: rule.conditions, index: i, match: rule.match,
                                     problem: problems.first { $0.condition == i }?.reason) {
                            if rule.conditions.indices.contains(i) { rule.conditions.remove(at: i) }
                        }
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(CDS.Settings.railLine).frame(width: 1) }
                addConditionMenu
            }
        }
    }

    private var addConditionMenu: some View {
        Menu {
            let offered = RuleEditing.offered(kinds)
            ForEach(RuleEditing.groupOrder.filter { g in offered.contains { RuleEditing.group($0) == g } }, id: \.self) { g in
                Section(g) {
                    ForEach(offered.filter { RuleEditing.group($0) == g }, id: \.self) { c in
                        Button(RuleEditing.menuTitle(c)) { rule.conditions.append(c) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                Text("Condition")
            }
        }
        .menuStyle(.button)
        .buttonStyle(ChipButtonStyle(tone: .dashed))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add a condition")
    }

    // MARK: Messages and preview

    @ViewBuilder private var messages: some View {
        let slotProblems = problems.filter { $0.condition == nil }
        if let notice {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(CDS.Text.accent)
                Text(notice).cdsText(foot12, .regular, CDS.Text.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { self.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(CDS.Text.muted).accessibilityLabel("Dismiss")
            }
        }
        ForEach(slotProblems, id: \.self) { p in
            Text("“\(p.slot ?? "")”: \(p.reason)").cdsText(foot12, .regular, CDS.Text.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            preview
            Spacer(minLength: 8)
            if let onRemove {
                Button(action: onRemove) { Text("Remove rule") }
                    .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
            }
        }
    }

    /// What the rule matches in the things already fetched (no API calls), and the repos it names that have none.
    @ViewBuilder private var preview: some View {
        let empty = data.namedRepos(rule.scope.in).filter { name in
            !store.things.values.contains { $0.repo.caseInsensitiveCompare(name) == .orderedSame }
        }
        HStack(spacing: 6) {
            Text(matches.map { "matches \($0)" } ?? "matches …").cdsText(foot12, .regular, CDS.Text.secondary)
            if !empty.isEmpty {
                Text("·").foregroundStyle(CDS.Text.muted)
                Text("no history yet for " + empty.joined(separator: ", ")).cdsText(foot12, .regular, CDS.Text.warning).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A condition, as a sentence

struct ConditionRow: View {
    @Binding var condition: Condition
    let store: Store
    let kinds: Set<ThingKind>
    let repos: [String]
    /// `by me` in the rule: nobody approves or reviews their own PR, so `me` is not offered.
    var byOnlyMe = false
    /// The rule's conditions, this one's place and the match mode: under all-of, exclusive values are not offered.
    var siblings: [Condition] = []
    var index = 0
    var match: MatchMode = .any
    var problem: String?
    let onRemove: () -> Void

    private var tone: ChipTone { problem == nil ? .neutral : .danger }
    private var data: EditorData { EditorData(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                SentenceLayout(spacing: 4, lineSpacing: 4) {
                    if let tip = condition.tip {
                        Word(condition.phrase, tone: tone).tip(RuleEditing.menuTitle(condition), tip)
                    } else {
                        Word(condition.phrase, tone: tone)
                    }
                    values
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SmallIconButton(symbol: "xmark", label: "Remove condition", size: 24, action: onRemove)
            }
            if let problem {
                Text(problem).cdsText(foot12, .regular, CDS.Text.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Items minus what a sibling condition rules out under all-of; what is already picked stays, so it can be unticked.
    private func narrowed<T: Hashable>(_ items: [(T, String)], _ selected: Set<T>, _ sets: (Condition) -> Set<T>?) -> [(T, String)] {
        guard let allowed = RuleEditing.narrowed(siblings, index: index, match: match, sets: sets) else { return items }
        return items.filter { allowed.contains($0.0) || selected.contains($0.0) }
    }

    @ViewBuilder private var values: some View {
        switch condition {
        case .newComment, .newReview, .newCommits, .mentions, .lastComment, .approved, .changesRequested:
            PeopleSlot(pick: Binding(get: { condition.people ?? Pick() }, set: { condition = condition.with(people: $0) }),
                       store: store, placeholder: "anyone", tone: tone,
                       hidden: byOnlyMe && ["approved", "changesRequested"].contains(RuleEditing.tag(condition)) ? [.me] : [])
            sinceChip
        case .unresolvedThreads(let started, let last):
            if started != nil {
                WordMenu(text: "started by", tone: tone) { Button("Remove “started by”") { condition = .unresolvedThreads(startedBy: nil, lastReplyBy: last) } }
                PeopleSlot(pick: Binding(get: { started ?? Pick() }, set: { condition = .unresolvedThreads(startedBy: $0, lastReplyBy: last) }),
                           store: store, tone: tone)
            }
            if last != nil {
                WordMenu(text: "last reply by", tone: tone) { Button("Remove “last reply by”") { condition = .unresolvedThreads(startedBy: started, lastReplyBy: nil) } }
                PeopleSlot(pick: Binding(get: { last ?? Pick() }, set: { condition = .unresolvedThreads(startedBy: started, lastReplyBy: $0) }),
                           store: store, tone: tone)
            }
            if started == nil || last == nil {
                Menu {
                    if started == nil { Button("started by someone") { condition = .unresolvedThreads(startedBy: Pick(), lastReplyBy: last) } }
                    if last == nil { Button("last reply by someone") { condition = .unresolvedThreads(startedBy: started, lastReplyBy: Pick()) } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text([started == nil ? "started by" : nil, last == nil ? "last reply by" : nil].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                .menuStyle(.button).buttonStyle(ChipButtonStyle(tone: .dashed)).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Add started by or last reply by")
            }
        case .checks(let states):
            SetMenu(items: narrowed([(.failing, "failing"), (.pending, "pending"), (.passing, "passing")], states, RuleEditing.checkSet), selection: states, tone: tone,
                    label: "Check states") { condition = .checks($0) }
        case .workflow(let states):
            SetMenu(items: narrowed([(.failing, "failing"), (.passing, "passing"), (.pending, "running")], states, RuleEditing.workflowSet), selection: states, tone: tone,
                    label: "Workflow states") { condition = .workflow($0) }
        case .status(let states):
            SetMenu(items: narrowed([(.draft, "draft"), (.open, "ready"), (.merged, "merged"), (.closed, "closed")]
                .filter { kinds.contains(.pr) || [.open, .closed].contains($0.0) }, states, RuleEditing.statusSet),
                    selection: states, tone: tone, label: "Status") { condition = .status($0) }
        case .labeled(let pick):
            StringSlot(pick: Binding(get: { pick }, set: { condition = .labeled($0) }), store: store, placeholder: "choose labels",
                       pool: data.values({ $0.labels }, in: repos), tone: tone)
        case .noActivity(let days):
            DaysField(days: days, tone: tone) { condition = .noActivity(days: $0) }
            Word("days")
        case .greptileBelow(let score):
            MenuChip(title: "\(score) / 5", tone: tone, label: "Greptile score") {
                ForEach(1...5, id: \.self) { n in
                    Toggle("\(n) / 5", isOn: Binding(get: { n == score }, set: { _ in condition = .greptileBelow(n) }))
                }
            }
        case .noise(let noise):
            MenuChip(title: RuleEditing.noiseTitle(noise), tone: tone, label: "Noise or a person") {
                ForEach([true, false], id: \.self) { option in
                    Toggle(RuleEditing.noiseTitle(option), isOn: Binding(get: { option == noise }, set: { _ in condition = .noise(option) }))
                }
            }
        case .importance(let level):
            MenuChip(title: level.rawValue, tone: tone, label: "Importance") {
                ForEach(RuleEditing.importances, id: \.self) { option in
                    Toggle(option.rawValue, isOn: Binding(get: { option == level }, set: { _ in condition = .importance(option) }))
                }
            }
        case .hasConflicts, .behindBase, .asksMe:
            EmptyView()
        }
    }

    /// Activity counts events since you marked the thing done, unless told otherwise: that default is not shown, and a
    /// dashed "since" adds the others.
    @ViewBuilder private var sinceChip: some View {
        if let since = condition.since {
            let options = RuleEditing.sinces(kinds)
            if since == .done {
                Menu {
                    ForEach(options.filter { $0 != .done }, id: \.self) { option in
                        Button("since " + RuleEditing.sinceTitle(option)) { condition = condition.with(since: option) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text("since")
                    }
                }
                .menuStyle(.button).buttonStyle(ChipButtonStyle(tone: .dashed)).menuIndicator(.hidden).fixedSize()
                .tip("Since", Condition.sinceTip)
                .accessibilityLabel("Count events since your last review or comment")
            } else {
                Word("since", tone: tone)
                MenuChip(title: RuleEditing.sinceTitle(since), tone: tone, label: "Since") {
                    ForEach(options, id: \.self) { option in
                        Toggle(RuleEditing.sinceTitle(option), isOn: Binding(get: { option == since },
                                                                        set: { _ in condition = condition.with(since: option) }))
                    }
                }
                .tip("Since", Condition.sinceTip)
            }
        }
    }
}

/// A set of states in one chip: "failing or pending", a menu of checkmarks. At least one stays picked.
struct SetMenu<T: Hashable>: View {
    let items: [(T, String)]
    let selection: Set<T>
    var tone: ChipTone = .neutral
    let label: String
    let set: (Set<T>) -> Void

    var body: some View {
        let picked = items.filter { selection.contains($0.0) }.map(\.1)
        MenuChip(title: picked.isEmpty ? "choose" : picked.joined(separator: " or "), tone: tone, label: label) {
            ForEach(items, id: \.0) { item in
                Toggle(item.1, isOn: Binding(
                    get: { selection.contains(item.0) },
                    set: { on in
                        var next = selection
                        if on { next.insert(item.0) } else { next.remove(item.0) }
                        set(next)
                    }))
            }
        }
    }
}

/// N days: a number in a chip.
struct DaysField: View {
    let days: Int
    var tone: ChipTone = .neutral
    let set: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .focused($focused)
            .frame(width: 28)
            .modifier(ChipLook(tone: tone))
            .onAppear { text = String(days) }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                if digits != new { text = digits }
                if let n = Int(digits), n > 0, n != days { set(n) }
            }
            .onChange(of: focused) { _, now in if !now { text = String(days) } }
            .accessibilityLabel("Days without activity")
    }
}
