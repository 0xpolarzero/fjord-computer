import SwiftUI

private let body14 = CDS.Density.comfortable.body
private let foot12: (CGFloat, CGFloat) = (12, 16)

/// Named lists of people or repos, usable as one chip in any slot of their kind. Editing one updates every rule using it.
struct GroupsSection: View {
    let store: Store
    @Binding var expanded: UUID?

    var body: some View {
        SettingsSection("Groups",
                        info: ("Groups", "Name people or repos once and use them as one chip in any rule. Editing a group updates every rule that uses it."),
                        action: {
            Menu {
                Button("People group") { add(.people) }
                Button("Repo group") { add(.repos) }
            } label: {
                HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)); Text("New group") }
                    .font(CDS.sans(14)).foregroundStyle(CDS.Text.primary)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CDS.Fill.secondary))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("New group")
        }, content: {
            if !store.groups.isEmpty {
                SettingsNest {
                    ForEach(Array(store.groups.enumerated()), id: \.element.id) { i, group in
                        if i > 0 { SettingsDivider() }
                        GroupRow(store: store, group: group, expanded: expanded == group.id) {
                            expanded = expanded == group.id ? nil : group.id
                        }
                    }
                }
            }
        })
    }

    private func add(_ kind: InboxGroup.Kind) {
        let group = InboxGroup(name: kind == .people ? "New people group" : "New repo group", kind: kind)
        store.groups.append(group)
        expanded = group.id
    }
}

private struct GroupRow: View {
    let store: Store
    let group: InboxGroup
    let expanded: Bool
    let toggle: () -> Void
    @FocusState private var nameFocused: Bool
    /// What the last repo check said ("a moved to b").
    @State private var note: String?

    private var index: Int? { store.groups.firstIndex { $0.id == group.id } }

    /// The categories whose rules use this group.
    private var users: [String] {
        store.categories.filter { $0.rules.contains { Self.uses($0, group.id) } }.map(\.name)
    }

    static func uses(_ rule: Rule, _ id: UUID) -> Bool { GroupUse.uses(rule, id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: group.kind == .people ? "person.2" : "folder")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(CDS.Text.secondary)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name).cdsText(body14).lineLimit(1)
                        Text(subtitle).cdsText(foot12, .regular, CDS.Text.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CDS.Text.muted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(subtitle)")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded { editor.padding(.bottom, 10).padding(.leading, 34) }
        }
    }

    private var subtitle: String {
        let count = group.kind == .people ? plural(group.members.count, "person", "people") : plural(group.members.count, "repo")
        let used = users.isEmpty ? "not used yet" : "used in " + users.joined(separator: ", ")
        return "\(count) · \(used)"
    }

    @ViewBuilder private var editor: some View {
        if let index {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: Binding(get: { store.groups[safe: index]?.name ?? "" }, set: { store.groups[index].name = $0 }))
                    .cdsPlaceholder("Group name", shown: group.name.isEmpty)
                    .focused($nameFocused)
                    .cdsField(focused: nameFocused)
                    .accessibilityLabel("Group name")
                SentenceLayout(spacing: 4, lineSpacing: 6) { members(index) }
                if let note { Text(note).cdsText(foot12, .regular, CDS.Text.secondary) }
                if group.kind == .repos, group.members.contains(where: { store.missingRepos.contains($0.lowercased()) }) {
                    Text(RuleEditing.noSuchRepo).cdsText(foot12, .regular, CDS.Text.danger)
                }
                HStack(spacing: 8) {
                    if users.isEmpty {
                        Button("Delete group") { store.groups.removeAll { $0.id == group.id } }
                            .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
                    } else {
                        Text("In use").cdsText(foot12, .regular, CDS.Text.muted)
                            .tip("In use", "Remove it from its rules to delete it")
                    }
                }
            }
        }
    }

    @ViewBuilder private func members(_ index: Int) -> some View {
        let data = EditorData(store: store)
        let pick = Binding(get: { Pick<String>(include: store.groups[safe: index]?.members ?? []) },
                           set: { if store.groups.indices.contains(index) { store.groups[index].members = $0.include } })
        if group.kind == .people {
            SlotField(pick: pick, placeholder: "add people", allowsExcept: false,
                      title: { "@" + $0 },
                      options: { q, p in
                          let q = q.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
                          return data.logins().filter { !p.include.contains($0) && (q.isEmpty || $0.lowercased().contains(q)) }.prefix(8)
                              .map { SlotOption(title: "@" + $0, detail: nil, symbol: nil, value: $0) }
                      },
                      parse: { if case .user(let l) = data.parsePerson($0) { l } else { nil } })
        } else {
            SlotField(pick: pick, placeholder: "add repos", allowsExcept: false,
                      title: { $0 },
                      isBroken: { store.missingRepos.contains($0.lowercased()) },
                      options: { q, p in
                          let q = q.trimmingCharacters(in: .whitespaces).lowercased()
                          let names = data.repoNames()
                          let owners = Array(Set(names.compactMap { $0.split(separator: "/").first.map { String($0) + "/*" } })).sorted()
                          return (names + owners).filter { !p.include.contains($0) && (q.isEmpty || $0.lowercased().contains(q)) }.prefix(8)
                              .map { SlotOption(title: $0, detail: nil, symbol: $0.hasSuffix("/*") ? "building.2" : nil, value: $0) }
                      },
                      parse: { data.parseRepo($0) == nil ? nil : $0.trimmingCharacters(in: .whitespaces) })
                .task(id: group.members) {
                    for name in group.members where !name.hasSuffix("/*") {
                        guard let moved = await store.canonicalRepo(name), let i = store.groups.firstIndex(where: { $0.id == group.id }),
                              let at = store.groups[i].members.firstIndex(of: name) else { continue }
                        if store.groups[i].members.contains(moved) { store.groups[i].members.remove(at: at) } else { store.groups[i].members[at] = moved }
                        note = "\(name) moved to \(moved)"
                    }
                }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
