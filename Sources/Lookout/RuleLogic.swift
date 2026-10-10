import SwiftUI

// What the editor knows about rules without drawing them: names for values, what each kind offers, what survives a change
// of kind, what the autocomplete lists. Pure where it can be (RuleEditing); EditorData reads the Store.

// MARK: - Conditions, as the editor names them

enum RuleEditing {
    static let groupOrder = ["Activity", "Conversation", "Review", "Checks", "Status", "Signals"]

    /// What the editor offers for a rule about `kinds`: what every one of them has, in the engine's order.
    static func offered(_ kinds: Set<ThingKind>) -> [Condition] { InboxEngine.conditions(for: kinds) }

    /// The kinds after ticking or unticking one in the kind chip. PRs and issues go together; workflows only alone, so
    /// ticking them (or, from them, another kind) starts over with the one ticked. The last one can't be unticked.
    static func toggling(_ kind: ThingKind, on: Bool, in kinds: Set<ThingKind>) -> Set<ThingKind> {
        guard on else { return kinds.count > 1 ? kinds.subtracting([kind]) : kinds }
        return kind == .workflow || kinds.contains(.workflow) ? [kind] : kinds.union([kind])
    }

    /// Identity of a condition's kind, whatever its values.
    static func tag(_ c: Condition) -> String {
        switch c {
        case .newComment: "newComment"
        case .newReview: "newReview"
        case .newCommits: "newCommits"
        case .mentions: "mentions"
        case .lastComment: "lastComment"
        case .unresolvedThreads: "unresolvedThreads"
        case .approved: "approved"
        case .changesRequested: "changesRequested"
        case .checks: "checks"
        case .hasConflicts: "hasConflicts"
        case .behindBase: "behindBase"
        case .status: "status"
        case .labeled: "labeled"
        case .noActivity: "noActivity"
        case .greptileBelow: "greptileBelow"
        case .asksMe: "asksMe"
        case .noise: "noise"
        case .importance: "importance"
        case .workflow: "workflow"
        }
    }

    /// The menu group a condition sits in.
    static func group(_ c: Condition) -> String {
        switch c {
        case .newComment, .newReview, .newCommits, .mentions: "Activity"
        case .lastComment, .unresolvedThreads: "Conversation"
        case .approved, .changesRequested: "Review"
        case .checks, .hasConflicts, .behindBase: "Checks"
        case .status, .labeled, .noActivity, .workflow: "Status"
        case .greptileBelow, .asksMe, .noise, .importance: "Signals"
        }
    }

    /// The row in the add menu.
    static func menuTitle(_ c: Condition) -> String {
        switch c {
        case .newComment: "New comment by…"
        case .newReview: "New review by…"
        case .newCommits: "New commits by…"
        case .mentions: "Mentions…"
        case .lastComment: "Last comment by…"
        case .unresolvedThreads: "Unresolved threads"
        case .approved: "Approved by…"
        case .changesRequested: "Changes requested by…"
        case .checks: "Checks failing, pending, passing"
        case .hasConflicts: "Has conflicts"
        case .behindBase: "Behind base branch"
        case .status: "Is draft, ready, merged, closed"
        case .labeled: "Labeled…"
        case .noActivity: "No activity for N days"
        case .greptileBelow: "Greptile score below N"
        case .asksMe: "A comment asks me"
        case .noise: "New comment is noise, or from a person"
        case .importance: "Rated important"
        case .workflow: "Is failing, passing, running"
        }
    }

    /// A condition in the chip's own words, lower case (Greptile is a name), for the "dropped" notice.
    static func name(_ c: Condition) -> String {
        switch c {
        case .newComment: "new comment"
        case .newReview: "new review"
        case .newCommits: "new commits"
        case .mentions: "mentions"
        case .lastComment: "last comment"
        case .unresolvedThreads: "unresolved threads"
        case .approved: "approvals"
        case .changesRequested: "changes requested"
        case .checks: "check states"
        case .hasConflicts: "has conflicts"
        case .behindBase: "behind base branch"
        case .status: "status"
        case .labeled: "labels"
        case .noActivity: "no activity for N days"
        case .greptileBelow: "Greptile score"
        case .asksMe: "asks me"
        case .noise: "noise"
        case .importance: "importance"
        case .workflow: "workflow states"
        }
    }

    /// What `switchKinds` dropped, as a sentence: "Dropped for Workflows: Greptile score, unresolved threads, and the by slot."
    static func droppedNotice(_ dropped: [String], for kinds: Set<ThingKind>) -> String? {
        guard !dropped.isEmpty else { return nil }
        let slots: Set<String> = ["by", "to", "on", "named", "in"]
        var items = dropped.map { slots.contains($0) ? "the \($0) slot" : $0 }
        if let first = items.first, let c = first.first {
            items[0] = c.uppercased() + first.dropFirst()
        }
        let list = items.count > 1 ? items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1] : items[0]
        return "Dropped for \(kinds.label): \(list)"
    }

    /// What `since` offers for a rule about `kinds`: issues have no reviews.
    static func sinces(_ kinds: Set<ThingKind>) -> [Since] {
        kinds.contains(.issue) ? [.done, .myLastComment] : Since.allCases
    }

    static func sinceTitle(_ since: Since) -> String {
        switch since {
        case .done: "Done"
        case .myLastReview: "my last review"
        case .myLastComment: "my last comment"
        }
    }

    /// The roles "to" can mean for a rule about `kinds`: review requested only with PRs among them (it never reaches an issue).
    static func roles(_ kinds: Set<ThingKind>) -> [ToRole] {
        kinds.contains(.pr) ? ToRole.allCases : [.assigned, .mentioned]
    }

    static func roleTitle(_ role: ToRole) -> String {
        switch role {
        case .assigned: "assigned"
        case .reviewRequested: "review requested"
        case .mentioned: "mentioned"
        }
    }

    /// The same rule about other kinds, with what could not come along said in words.
    static func switchKinds(_ rule: Rule, to kinds: Set<ThingKind>) -> (rule: Rule, dropped: [String]) {
        guard kinds != rule.scope.kinds, !kinds.isEmpty else { return (rule, []) }
        var out = rule
        var dropped: [String] = []
        out.scope.kinds = kinds
        let supported = Set(offered(kinds).map(tag))
        var kept: [Condition] = []
        for condition in rule.conditions {
            guard supported.contains(tag(condition)) else { dropped.append(name(condition)); continue }
            // What a condition says that one of the new kinds can't have goes, the condition stays.
            if let since = condition.since, !sinces(kinds).contains(since) {
                dropped.append("since " + sinceTitle(since))
                kept.append(condition.with(since: .done))
            } else if case .status(let s) = condition, !kinds.contains(.pr), !s.isSubset(of: [.open, .closed]) {
                let left = s.intersection([.open, .closed])
                dropped.append(left.isEmpty ? name(condition) : "draft and merged")
                if !left.isEmpty { kept.append(.status(left)) }
            } else {
                kept.append(condition)
            }
        }
        if out.scope.isWorkflow {
            if rule.scope.by != nil { dropped.append("by") }
            if rule.scope.to != nil { dropped.append("to") }
            out.scope.by = nil
            out.scope.to = nil
            out.scope.in = (rule.scope.in ?? Pick()).removing(.involved)
            if let repos = rule.scope.in, (repos.include + repos.except).contains(.involved) {
                dropped.append("anywhere you're involved")
            }
            if kept.isEmpty { kept = [.workflow([.failing])] }
        } else {
            if rule.scope.on != nil { dropped.append("on") }
            if rule.scope.named != nil { dropped.append("named") }
            out.scope.on = nil
            out.scope.named = nil
            if !kinds.contains(.pr), rule.scope.toRoles.contains(.reviewRequested) {
                out.scope.toRoles.remove(.reviewRequested)
                if out.scope.toRoles.isEmpty { out.scope.toRoles = Set(roles(kinds)) }
                if rule.scope.to != nil { dropped.append("review requested") }
            }
        }
        out.conditions = kept
        return (out, dropped)
    }

    /// Under all-of, one thing has one status and one check state, so another condition on the same state may only offer what
    /// every sibling also allows (draft excludes merged and closed, failing excludes passing). Nil: everything. Under any-of: nil.
    static func narrowed<T: Hashable>(_ conditions: [Condition], index: Int, match: MatchMode,
                                      sets: (Condition) -> Set<T>?) -> Set<T>? {
        guard match == .all else { return nil }
        var allowed: Set<T>?
        for (i, c) in conditions.enumerated() where i != index {
            guard let s = sets(c), !s.isEmpty else { continue }
            allowed = allowed.map { $0.intersection(s) } ?? s
        }
        return allowed
    }

    static func noiseTitle(_ noise: Bool) -> String { noise ? "noise" : "from a person" }

    static func statusSet(_ c: Condition) -> Set<ThingStatus>? { if case .status(let s) = c { s } else { nil } }
    static func checkSet(_ c: Condition) -> Set<CheckState>? { if case .checks(let s) = c { s } else { nil } }
    static func workflowSet(_ c: Condition) -> Set<CheckState>? { if case .workflow(let s) = c { s } else { nil } }

    static let noSuchRepo = "No such repo, or no access"

    /// Everything that stops a rule from being saved: the engine's impossible chips, plus what only the editor can see.
    static func problems(_ rule: Rule, groups: [InboxGroup], isCI: Bool, missing: Set<String> = []) -> [InboxEngine.Problem] {
        var found = InboxEngine.problems(rule)
        func gone<V>(_ pick: Pick<V>?, _ id: (V) -> UUID?) -> Bool {
            guard let pick else { return false }
            return (pick.include + pick.except).contains { v in id(v).map { id in !groups.contains { $0.id == id } } ?? false }
        }
        let person: (PersonRef) -> UUID? = { if case .group(let id) = $0 { id } else { nil } }
        let repo: (RepoRef) -> UUID? = { if case .group(let id) = $0 { id } else { nil } }
        if gone(rule.scope.by, person) { found.append(.init(condition: nil, slot: "by", reason: "This group no longer exists")) }
        if gone(rule.scope.to, person) { found.append(.init(condition: nil, slot: "to", reason: "This group no longer exists")) }
        if gone(rule.scope.in, repo) { found.append(.init(condition: nil, slot: "in", reason: "This group no longer exists")) }
        if let pick = rule.scope.in,
           (pick.include + pick.except).contains(where: { if case .repo(let n) = $0 { missing.contains(n.lowercased()) } else { false } }) {
            found.append(.init(condition: nil, slot: "in", reason: Self.noSuchRepo))
        }
        if rule.scope.isWorkflow, !isCI, rule.scope.in?.include.isEmpty ?? true {
            found.append(.init(condition: nil, slot: "in", reason: "Workflows need at least one repo"))
        }
        for (i, c) in rule.conditions.enumerated() {
            switch c {
            case .status(let s) where s.isEmpty: found.append(.init(condition: i, slot: nil, reason: "Pick at least one status"))
            case .checks(let s) where s.isEmpty, .workflow(let s) where s.isEmpty:
                found.append(.init(condition: i, slot: nil, reason: "Pick at least one state"))
            default: break
            }
        }
        var seen = Set<InboxEngine.Problem>()
        return found.filter { seen.insert($0).inserted }
    }
}

extension Pick {
    func removing(_ value: Value) -> Pick {
        Pick(include: include.filter { $0 != value }, except: except.filter { $0 != value })
    }
}

// Conditions that name people, read and written the same way.
extension Condition {
    var people: Pick<PersonRef>? {
        switch self {
        case .newComment(let p, _), .newReview(let p, _), .newCommits(let p, _), .mentions(let p, _), .lastComment(let p),
             .approved(let p), .changesRequested(let p): p
        default: nil
        }
    }

    /// Activity conditions count events after a point; nil for the others.
    var since: Since? {
        switch self {
        case .newComment(_, let s), .newReview(_, let s), .newCommits(_, let s), .mentions(_, let s): s
        default: nil
        }
    }

    func with(since s: Since) -> Condition {
        switch self {
        case .newComment(let p, _): .newComment(by: p, since: s)
        case .newReview(let p, _): .newReview(by: p, since: s)
        case .newCommits(let p, _): .newCommits(by: p, since: s)
        case .mentions(let p, _): .mentions(p, since: s)
        default: self
        }
    }

    func with(people p: Pick<PersonRef>) -> Condition {
        switch self {
        case .newComment(_, let s): .newComment(by: p, since: s)
        case .newReview(_, let s): .newReview(by: p, since: s)
        case .newCommits(_, let s): .newCommits(by: p, since: s)
        case .mentions(_, let s): .mentions(p, since: s)
        case .lastComment: .lastComment(by: p)
        case .approved: .approved(by: p)
        case .changesRequested: .changesRequested(by: p)
        default: self
        }
    }

    static let sinceTip = "Done: since you last marked the thing done (or made the rule). My last review: after your latest review there; with none, nothing matches. My last comment: after your latest comment, review with text or thread reply; with none, since it was opened"

    /// What hovering the condition's words says.
    var tip: String? {
        switch self {
        case .behindBase:
            "GitHub only says a PR is behind its base branch when the base has branch protection that requires branches to be up to date before merging"
        case .asksMe:
            "Jev (TypeSafe, with your key) reads each new comment, review and thread reply once and says whether it asks you something. A reply of yours there ends it"
        case .noise:
            "Noise: bots, and what Jev (TypeSafe, with your key) reads as automated: CI, coverage, deploy previews, dependency and lint bots. Jev's noise never shows a banner"
        case .importance:
            "Jev (TypeSafe, with your key) rates each review request to you or your teams, and each assignment, once: from its title, size, who asks, age, labels and checks"
        default: nil
        }
    }

    /// The words before the values.
    var phrase: String {
        switch self {
        case .newComment: "new comment by"
        case .newReview: "new review by"
        case .newCommits: "new commits by"
        case .mentions: "mentions"
        case .lastComment: "last comment by"
        case .unresolvedThreads: "unresolved threads"
        case .approved: "approved by"
        case .changesRequested: "changes requested by"
        case .checks: "checks"
        case .hasConflicts: "has conflicts"
        case .behindBase: "is behind base branch"
        case .status: "is"
        case .labeled: "labeled"
        case .noActivity: "no activity for"
        case .greptileBelow: "Greptile score below"
        case .asksMe: "a comment asks me"
        case .noise: "new comment is"
        case .importance: "rated at least"
        case .workflow: "is"
        }
    }
}

// MARK: - What the Store knows, as the editor's lists

@MainActor
struct EditorData {
    let store: Store

    func group(_ id: UUID) -> InboxGroup? { store.groups.first { $0.id == id } }

    func personTitle(_ p: PersonRef) -> String {
        switch p {
        case .me: "me"
        case .user(let login): login.lowercased() == "greptile-apps[bot]" ? "Greptile" : "@" + login
        case .group(let id): group(id)?.name ?? "missing group"
        case .maintainers: "Maintainers"
        case .bots: "Bots"
        case .team(let slug): "@" + slug
        case .myTeams: "My teams"
        }
    }

    func personSymbol(_ p: PersonRef) -> String? {
        switch p {
        case .me: "person"
        case .user: nil
        case .group: "person.2"
        case .maintainers: "wrench.and.screwdriver"
        case .bots: "cpu"
        case .team, .myTeams: "person.3"
        }
    }

    func repoTitle(_ r: RepoRef) -> String {
        switch r {
        case .repo(let name): name
        case .owner(let owner): owner + "/*"
        case .group(let id): group(id)?.name ?? "missing group"
        case .owned: "Repos I own"
        case .contributed: "Repos I contribute to"
        case .involved: "anywhere you're involved"
        }
    }

    func repoSymbol(_ r: RepoRef) -> String? {
        switch r {
        case .repo: nil
        case .owner: "building.2"
        case .group: "folder"
        case .owned: "house"
        case .contributed: "arrow.triangle.merge"
        case .involved: "person.crop.circle.badge.checkmark"
        }
    }

    func isBroken(_ p: PersonRef) -> Bool { if case .group(let id) = p { group(id) == nil } else { false } }
    func isBroken(_ r: RepoRef) -> Bool { if case .group(let id) = r { group(id) == nil } else { false } }

    func pickTitle<V>(_ pick: Pick<V>?, _ title: (V) -> String) -> String {
        guard let pick else { return "" }
        var text = pick.include.map(title).joined(separator: ", ")
        if !pick.except.isEmpty { text += (text.isEmpty ? "" : " ") + "except " + pick.except.map(title).joined(separator: ", ") }
        return text
    }

    /// A rule in one line, for the category's row.
    func summary(_ rule: Rule) -> String {
        var parts = [rule.scope.kinds.label]
        func add(_ word: String, _ text: String) { if !text.isEmpty { parts.append("\(word) \(text)") } }
        if !rule.scope.isWorkflow {
            add("by", pickTitle(rule.scope.by, personTitle))
            add("to", pickTitle(rule.scope.to, personTitle))
        }
        add("in", pickTitle(rule.scope.in, repoTitle))
        if !rule.conditions.isEmpty { parts.append("· " + plural(rule.conditions.count, "condition")) }
        return parts.joined(separator: " ")
    }

    // MARK: Sources

    /// Logins seen on fetched things, most seen first.
    func logins() -> [String] {
        var counts: [String: Int] = [:]
        func see(_ login: String?) { if let login, !login.isEmpty { counts[login, default: 0] += 1 } }
        for t in store.things.values {
            see(t.author?.login)
            t.assignees.forEach(see)
            t.requestedReviewers.filter { !$0.contains("/") }.forEach(see)
            t.comments.forEach { see($0.author.login) }
            t.reviews.forEach { see($0.author.login) }
            t.commits.forEach { see($0.author) }
        }
        let me = store.me?.login.lowercased()
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key).filter { $0.lowercased() != me }
    }

    /// Repos named anywhere the app knows them: watched, fetched, suggested. Never twice.
    func repoNames() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let sources = store.things.values.map(\.repo) + store.suggestions
        for name in sources where seen.insert(name.lowercased()).inserted { out.append(name) }
        return out
    }

    /// Labels, branches and workflow names on fetched things (of `repos` when given), most seen first.
    func values(_ pick: (Thing) -> [String], in repos: [String] = []) -> [String] {
        let scope = Set(repos.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        for t in store.things.values where scope.isEmpty || scope.contains(t.repo.lowercased()) {
            pick(t).forEach { counts[$0, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// The repos a rule's `in` names outright, groups opened.
    func namedRepos(_ pick: Pick<RepoRef>?) -> [String] {
        guard let pick else { return [] }
        return pick.include.flatMap { ref -> [String] in
            switch ref {
            case .repo(let name): return [name]
            case .group(let id): return group(id)?.members.filter { !$0.hasSuffix("/*") } ?? []
            default: return []
            }
        }
    }

    // MARK: Autocomplete

    /// Teams asked to review on fetched things, and yours; `org/team`, most seen first.
    func teams() -> [String] {
        var counts: [String: Int] = [:]
        for t in store.things.values { for r in t.requestedReviewers where r.contains("/") { counts[r, default: 0] += 1 } }
        for team in store.myTeams { counts[team, default: 0] += 1 }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    func peopleOptions(_ query: String, _ pick: Pick<PersonRef>, teams allowsTeams: Bool = false) -> [SlotOption<PersonRef>] {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        var all: [PersonRef] = [.me, .maintainers, .bots]
        if allowsTeams { all.append(.myTeams) }
        all += store.groups.filter { $0.kind == .people }.map { PersonRef.group($0.id) }
        if allowsTeams { all += teams().map(PersonRef.team) }
        all += logins().map(PersonRef.user)
        let taken = Set(pick.include + pick.except)
        let rows = all.filter { !taken.contains($0) && (q.isEmpty || searchKeys($0).contains { $0.contains(q) }) }
        return rows.prefix(q.isEmpty ? 10 : 8).map {
            SlotOption(title: personTitle($0), detail: personDetail($0), symbol: personSymbol($0), value: $0, tip: personTip($0))
        }
    }

    /// What typing can find a person by: the title shown, the login (with or without the @), and aliases (greptile).
    func searchKeys(_ p: PersonRef) -> [String] {
        var keys = [personTitle(p).lowercased()]
        if case .user(let login) = p {
            keys.append(login.lowercased())
            if login.lowercased() == "greptile-apps[bot]" { keys.append("greptile") }
        }
        return keys.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
    }

    private func personDetail(_ p: PersonRef) -> String? {
        switch p {
        case .group(let id): group(id).map { plural($0.members.count, "person", "people") }
        default: nil
        }
    }

    /// `involved`: PRs and issues can be anywhere you're involved; workflows can't.
    func repoOptions(_ query: String, _ pick: Pick<RepoRef>, involved: Bool) -> [SlotOption<RepoRef>] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var all: [RepoRef] = [.owned, .contributed]
        if involved { all.append(.involved) }
        all += store.groups.filter { $0.kind == .repos }.map { RepoRef.group($0.id) }
        let names = repoNames()
        var owners: [String] = []
        for n in names { if let o = n.split(separator: "/").first, !owners.contains(String(o)) { owners.append(String(o)) } }
        all += names.map(RepoRef.repo)
        all += owners.map(RepoRef.owner)
        let taken = Set(pick.include + pick.except)
        let rows = all.filter { !taken.contains($0) && (q.isEmpty || repoTitle($0).lowercased().contains(q)) }
        return rows.prefix(q.isEmpty ? 9 : 8).map {
            SlotOption(title: repoTitle($0), detail: repoDetail($0), symbol: repoSymbol($0), value: $0, tip: repoTip($0))
        }
    }

    private func repoDetail(_ r: RepoRef) -> String? {
        switch r {
        case .group(let id): group(id).map { plural($0.members.count, "repo") }
        default: nil
        }
    }

    private func personTip(_ p: PersonRef) -> String? {
        switch p {
        case .maintainers: "People with write access to the repo the thing is in"
        case .bots: "Accounts GitHub marks as bots"
        case .myTeams: "Every team you're in: PRs asking one of them for review"
        default: nil
        }
    }

    private func repoTip(_ r: RepoRef) -> String? {
        switch r {
        case .contributed: "Repos where you have a merged or open PR"
        case .involved: "Anywhere you are the author, an assignee or a reviewer"
        default: nil
        }
    }

    func stringOptions(_ query: String, _ pick: Pick<String>, from pool: [String]) -> [SlotOption<String>] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = Set(pick.include + pick.except)
        return pool.filter { !taken.contains($0) && (q.isEmpty || $0.lowercased().contains(q)) }.prefix(8)
            .map { SlotOption(title: $0, detail: nil, symbol: nil, value: $0) }
    }

    // MARK: Parsing what is typed

    /// A team is `@org/team`, only where teams are allowed.
    func parsePerson(_ text: String, teams: Bool) -> PersonRef? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if teams, t.lowercased() == "my teams" { return .myTeams }
        let slug = t.hasPrefix("@") ? String(t.dropFirst()) : t
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        if teams, parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }) {
            return .team(slug)
        }
        return parsePerson(text)
    }

    func parsePerson(_ text: String) -> PersonRef? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.lowercased() == "me" { return .me }
        let login = t.hasPrefix("@") ? String(t.dropFirst()) : t
        guard !login.isEmpty, login.allSatisfy({ $0.isLetter || $0.isNumber || "-[]_".contains($0) }) else { return nil }
        // Greptile's account is greptile-apps[bot].
        return .user(login.lowercased() == "greptile" ? "greptile-apps[bot]" : login)
    }

    func parseRepo(_ text: String) -> RepoRef? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, !t.contains(" ") else { return nil }
        return parts[1] == "*" ? .owner(String(parts[0])) : .repo(t)
    }

    /// A group member as stored (`owner/repo`, `owner/*`) back to a value.
    static func repoRef(_ member: String) -> RepoRef {
        member.hasSuffix("/*") ? .owner(String(member.dropLast(2))) : .repo(member)
    }
}

// MARK: - Slots, ready to drop in a sentence

struct PeopleSlot: View {
    @Binding var pick: Pick<PersonRef>
    let store: Store
    var placeholder = "anyone"
    var tone: ChipTone = .neutral
    /// Values that can never match here, so are not offered.
    var hidden: Set<PersonRef> = []
    /// `to` can name teams asked to review.
    var teams = false

    var body: some View {
        let data = EditorData(store: store)
        let users = pick.include.filter { if case .user = $0 { true } else { false } }
        SlotField(pick: $pick, placeholder: placeholder, tone: tone,
                  title: data.personTitle, symbol: data.personSymbol, isBroken: data.isBroken,
                  options: { q, p in data.peopleOptions(q, p, teams: teams).filter { !hidden.contains($0.value) } },
                  parse: { data.parsePerson($0, teams: teams) },
                  groupable: users.count,
                  saveGroup: users.count >= 2 ? { name in
                      let members = users.compactMap { v -> String? in if case .user(let l) = v { l } else { nil } }
                      let group = InboxGroup(name: name, kind: .people, members: members)
                      store.groups.append(group)
                      pick.include.removeAll { users.contains($0) }
                      pick.include.append(.group(group.id))
                  } : nil,
                  groupNoun: "people")
    }
}

struct RepoSlot: View {
    @Binding var pick: Pick<RepoRef>
    let store: Store
    /// Offers "anywhere you're involved" (not for workflows).
    var involved = true
    /// Told when a repo typed in turned out to have moved ("a moved to b").
    var onMoved: (String) -> Void = { _ in }
    var placeholder = "anywhere"
    var tone: ChipTone = .neutral

    var body: some View {
        let data = EditorData(store: store)
        let named = (pick.include + pick.except).compactMap { if case .repo(let n) = $0 { n } else { nil } }
        let plain = pick.include.filter { if case .repo = $0 { true } else if case .owner = $0 { true } else { false } }
        SlotField(pick: $pick, placeholder: placeholder, tone: tone,
                  title: data.repoTitle, symbol: data.repoSymbol,
                  isBroken: { data.isBroken($0) || store.isMissing($0) },
                  options: { q, p in data.repoOptions(q, p, involved: involved) },
                  parse: data.parseRepo,
                  groupable: plain.count,
                  saveGroup: plain.count >= 2 ? { name in
                      let members = plain.compactMap { ref -> String? in
                          switch ref {
                          case .repo(let n): n
                          case .owner(let o): o + "/*"
                          default: nil
                          }
                      }
                      let group = InboxGroup(name: name, kind: .repos, members: members)
                      store.groups.append(group)
                      pick.include.removeAll { plain.contains($0) }
                      pick.include.append(.group(group.id))
                  } : nil,
                  groupNoun: "repos")
        .task(id: named) {
            for name in named {
                guard let moved = await store.canonicalRepo(name) else { continue }
                func swap(_ list: inout [RepoRef]) {
                    guard let i = list.firstIndex(of: .repo(name)) else { return }
                    list[i] = .repo(moved)
                    var seen = Set<RepoRef>()
                    list = list.filter { seen.insert($0).inserted }
                }
                swap(&pick.include)
                swap(&pick.except)
                onMoved("\(name) moved to \(moved)")
            }
        }
    }
}

/// Free values (labels, branches, workflow names), suggested from what was fetched.
struct StringSlot: View {
    @Binding var pick: Pick<String>
    let store: Store
    let placeholder: String
    let pool: [String]
    var allowsExcept = true
    var tone: ChipTone = .neutral

    var body: some View {
        let data = EditorData(store: store)
        SlotField(pick: $pick, placeholder: placeholder, tone: tone, allowsExcept: allowsExcept,
                  title: { $0 }, options: { q, p in data.stringOptions(q, p, from: pool) },
                  parse: { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) })
    }
}

// MARK: - The icon, picked by Jev from the name

enum CategoryIcon {
    static let fallback = "tray"

    /// A symbol for a category called `name`: Jev picks a kind of icon, then an icon of it (the sessions' way).
    static func pick(name: String, key: String) async throws -> String {
        let open = SessionIcons.open(excluding: [])
        guard !open.isEmpty else { return fallback }
        let state = ["category name": name,
                     "what it is": "a folder in a developer's GitHub inbox that collects the pull requests, issues and failing workflows that need them"]
        let client = JevClient(key: key)
        let kinds = try await client.choose(open.map(\.category.key),
                                            hints: Dictionary(uniqueKeysWithValues: open.map { ($0.category.key, $0.category.about) }),
                                            for: state, instructions: "Which kind of icon would best show what this inbox category is about?")
        let options = SessionIcons.shortlist(open, probabilities: kinds.probabilities)
        let choice = try await client.choose(options, hints: SessionIcons.hints, for: state,
                                             instructions: "Pick the icon that best shows what this inbox category is about, so its owner can tell categories apart at a glance.")
        return choice.choice
    }

    /// Words a category name may hold, and the symbol each stands for: the pick when Jev isn't there (no key, offline).
    /// A word matches a name's word that starts with it ("review" finds "Reviews"); the first entry that matches wins.
    static let keywords: [(words: [String], symbol: String)] = [
        (["security", "vuln", "cve", "audit"], "lock.shield"),
        (["dependabot", "renovate", "deps", "dependenc", "package"], "cube"),
        (["review"], "eye"),
        (["bot", "automat"], "cpu"),
        (["ci", "pipeline", "workflow", "action"], "xmark.seal"),
        (["build", "test", "compile"], "hammer"),
        (["release", "deploy", "ship"], "shippingbox"),
        (["doc", "readme", "wiki"], "book"),
        (["bug", "issue", "incident"], "ant"),
        (["team", "group", "squad"], "person.2"),
        (["mine", "my", "me", "assigned"], "person"),
        (["chatter", "comment", "discussion", "mention", "thread", "chat"], "bubble.left.and.bubble.right"),
    ]

    /// The symbol a name's words point to, if any.
    static func local(name: String) -> String? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return nil }
        for entry in keywords {
            // Short keywords (ci, my, me, bot) must be the whole word; longer ones may start it.
            let hit = words.contains { w in entry.words.contains { $0.count <= 3 ? w == $0 || w == $0 + "s" : w.hasPrefix($0) } }
            if hit, NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil) != nil { return entry.symbol }
        }
        return nil
    }

    /// Every symbol the picker offers.
    static let all: [String] = {
        let extra = ["tray", "tray.full", "bell", "star", "flame", "bolt", "eye", "person.2", "ant", "lock.shield", "xmark.seal",
                     "checkmark.seal", "exclamationmark.bubble", "bubble.left.and.bubble.right", "arrow.triangle.pull", "flag"]
        var seen = Set<String>()
        return (extra + SessionIcons.categories.flatMap(\.icons)).filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil && seen.insert($0).inserted
        }
    }()
}
