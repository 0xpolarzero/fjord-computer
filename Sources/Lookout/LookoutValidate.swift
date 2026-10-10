import AppKit
import Foundation

/// What the editor refuses to save, asked of what the Router sends: the same reasons, in the same words, from the same checks
/// (`RuleEditing.problems`), plus the few the editor makes impossible by what its menus offer.
@MainActor
enum LookoutValidate {
    /// Every reason `category` can't be saved, empty when it can. `old`: the category it replaces, if any.
    static func category(_ c: InboxCategory, old: InboxCategory?, in store: Store) -> [String] {
        var out: [String] = []
        let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { out.append("`name` is empty") }
        else if store.categories.contains(where: { $0.id != c.id && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }) {
            out.append("There is a category called “\(name)” already")
        }
        if NSImage(systemSymbolName: c.symbol, accessibilityDescription: nil) == nil {
            out.append("`symbol` “\(c.symbol)” isn't an SF Symbol. Some that are: " + CategoryIcon.all.prefix(14).joined(separator: ", "))
        }
        if c.isCI != (old?.isCI ?? false) { out.append("`isCI` can't be changed: there is one CI category, and no other can become it") }
        let kinds = Set(c.rules.flatMap(\.scope.kinds))
        for (i, rule) in c.rules.enumerated() {
            let label = "rules[\(i)] (\(RuleWords(store: store).summary(rule)))"
            if c.isCI {
                if rule.scope.kinds != [.workflow] { out.append("\(label): the CI category only has workflow rules") }
                if rule.conditions != [.workflow([.failing])] {
                    out.append("\(label): the CI category only takes repos (its condition is always `workflow` failing)")
                }
                if rule.scope.on != nil || rule.scope.named != nil { out.append("\(label): the CI category only takes repos") }
            }
            for problem in RuleEditing.problems(rule, groups: store.groups, isCI: c.isCI, missing: store.missingRepos) {
                if let index = problem.condition {
                    out.append("\(label): conditions[\(index)]: \(problem.reason)")
                } else {
                    out.append("\(label): “\(problem.slot ?? "")”: \(problem.reason)")
                }
            }
            out += extra(rule, label: label, store: store)
        }
        for (i, action) in c.actions.items.enumerated() {
            if !kinds.isEmpty, !kinds.contains(where: { action.applies(to: $0) }) {
                out.append("actions[\(i)] (\(action.title)): None of this category's rules is something this applies to.")
            }
            if case .comment(let text) = action.kind, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append("actions[\(i)] (\(action.title)): the comment is empty")
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// What the editor never lets a rule hold, that `problems` doesn't say: teams outside `to`, groups of the wrong kind,
    /// roles an issue doesn't have, scores that don't exist.
    private static func extra(_ rule: Rule, label: String, store: Store) -> [String] {
        var out: [String] = []
        func people(_ pick: Pick<PersonRef>?) -> [PersonRef] { pick.map { $0.include + $0.except } ?? [] }
        func teamless(_ pick: Pick<PersonRef>?, _ what: String) {
            if people(pick).contains(where: { if case .team = $0 { true } else if case .myTeams = $0 { true } else { false } }) {
                out.append("\(label): \(what): Teams only go in `to`, asking for a review")
            }
        }
        func wrongGroups(_ pick: Pick<PersonRef>?, _ what: String) {
            for case .group(let id) in people(pick) {
                if let group = store.groups.first(where: { $0.id == id }), group.kind != .people {
                    out.append("\(label): \(what): “\(group.name)” is a repos group; a people slot takes people groups")
                }
            }
        }
        wrongGroups(rule.scope.by, "“by”")
        wrongGroups(rule.scope.to, "“to”")
        if let repos = rule.scope.in {
            for case .group(let id) in repos.include + repos.except {
                if let group = store.groups.first(where: { $0.id == id }), group.kind != .repos {
                    out.append("\(label): “in”: “\(group.name)” is a people group; a repo slot takes repo groups")
                }
            }
        }
        if !rule.scope.kinds.contains(.pr), rule.scope.to != nil, rule.scope.toRoles.contains(.reviewRequested) {
            out.append("\(label): “to”: Only PRs have review requests; toRoles is assigned and/or mentioned")
        }
        for (i, condition) in rule.conditions.enumerated() {
            let what = "conditions[\(i)]"
            if let p = condition.people { teamless(p, what); wrongGroups(p, what) }
            if case .unresolvedThreads(let a, let b) = condition {
                teamless(a, what); teamless(b, what); wrongGroups(a, what); wrongGroups(b, what)
            }
            if case .greptileBelow(let n) = condition, n > 5 { out.append("\(label): \(what): Greptile scores go up to 5") }
            if case .noActivity(let days) = condition, days < 1 { out.append("\(label): \(what): Days start at 1") }
        }
        return out
    }

    // MARK: Groups

    /// Every reason `group` can't be saved.
    static func group(_ g: InboxGroup, old: InboxGroup?, in store: Store) -> [String] {
        var out: [String] = []
        let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { out.append("`name` is empty") }
        else if store.groups.contains(where: { $0.id != g.id && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }) {
            out.append("There is a group called “\(name)” already")
        }
        if let old, old.kind != g.kind, !users(of: old.id, in: store).isEmpty {
            out.append("The kind can't change while rules use the group (\(users(of: old.id, in: store).joined(separator: ", ")))")
        }
        let data = EditorData(store: store)
        for member in g.members {
            switch g.kind {
            case .people:
                if data.parsePerson(member) == nil || member.contains("/") { out.append("“\(member)” isn't a GitHub login") }
            case .repos:
                if data.parseRepo(member) == nil { out.append("“\(member)” isn't a repo: write owner/repo, or owner/* for all of an owner's") }
            }
        }
        return out
    }

    /// Names of the categories whose rules use the group.
    static func users(of group: UUID, in store: Store) -> [String] {
        store.categories.filter { $0.rules.contains { GroupUse.uses($0, group) } }.map(\.title)
    }
}

/// Whether a rule names a group (shared with the groups page).
enum GroupUse {
    static func uses(_ rule: Rule, _ id: UUID) -> Bool {
        func people(_ p: Pick<PersonRef>?) -> Bool { (p.map { $0.include + $0.except } ?? []).contains(.group(id)) }
        if people(rule.scope.by) || people(rule.scope.to) { return true }
        if let repos = rule.scope.in, (repos.include + repos.except).contains(.group(id)) { return true }
        return rule.conditions.contains { c in
            if people(c.people) { return true }
            if case .unresolvedThreads(let a, let b) = c { return people(a) || people(b) }
            return false
        }
    }
}
