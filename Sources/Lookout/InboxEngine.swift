import Foundation

// Pure: which category each thing is in, and why. No I/O, no Store.
enum InboxEngine {
    /// A chip the editor must flag: it can never match given the rest of the rule.
    struct Problem: Hashable {
        /// Index into `rule.conditions`, or nil for a scope slot.
        var condition: Int?
        /// "kind", "by", "to", "in", "on", "named" for scope slots.
        var slot: String?
        var reason: String
    }

    /// Every thing's entry: first matching category in order (hidden ones included), unmatched dropped.
    /// A category's facts are the union of the facts of every one of its rules that matches.
    static func evaluate(things: [Thing], categories: [InboxCategory], marks: [String: EntryMarks],
                         context: InboxContext) -> [InboxEntry] {
        let resolved = Resolved(context)
        // A rule with a chip that can never match is off until it is fixed (edits apply as they are made); judged once here.
        var off = Set<UUID>()
        for category in categories { for rule in category.rules where !problems(rule).isEmpty { off.insert(rule.id) } }
        var entries: [InboxEntry] = []
        for thing in things {
            let m = marks[thing.id]
            let doneIn = m?.doneAt == nil ? nil : m?.doneIn
            for category in categories {
                var union: [Fact] = []
                var keys = Set<String>()
                for rule in category.rules where !off.contains(rule.id) {
                    guard let matched = facts(rule, thing, marks: m, resolved: resolved) else { continue }
                    for fact in matched where keys.insert(fact.key).inserted { union.append(fact) }
                }
                let acked = m?.acked ?? []
                let seen = m?.seen ?? []
                // Done here and nothing new since: it stays Done here with what it was Done with, as long as the rules
                // still take it when Done's cutoff is left aside (an edited rule, or a thing that changed, lets it go).
                if category.id == doneIn, keys.isSubset(of: acked), let kept = m?.doneFacts, !kept.isEmpty {
                    var routing = m
                    routing?.doneAt = nil
                    let stays = category.rules.contains {
                        !off.contains($0.id) && facts($0, thing, marks: routing, resolved: resolved) != nil
                    }
                    if stays {
                        var all = Set(kept.map(\.key))
                        let shown = kept + union.filter { all.insert($0.key).inserted }
                        entries.append(InboxEntry(thing: thing, categoryID: category.id, facts: shown, isDone: true,
                                                  isUnread: !all.isSubset(of: seen), importance: importance(thing, resolved)))
                        break
                    }
                }
                if union.isEmpty { continue }
                entries.append(InboxEntry(thing: thing, categoryID: category.id, facts: union,
                                          isDone: keys.isSubset(of: acked), isUnread: !keys.isSubset(of: seen),
                                          importance: importance(thing, resolved)))
                break
            }
        }
        return entries
    }

    /// The next moment time alone changes what matches: a thing crossing a `no activity` threshold of some rule; nil when
    /// none is ahead.
    static func nextChange(things: [Thing], categories: [InboxCategory], after now: Date) -> Date? {
        let days = Set(categories.flatMap(\.rules).flatMap(\.conditions).compactMap { condition -> Int? in
            if case .noActivity(let days) = condition { days } else { nil }
        })
        guard !days.isEmpty else { return nil }
        var next: Date?
        for thing in things {
            for d in days {
                let at = thing.updatedAt.addingTimeInterval(Double(d) * 86_400)
                if at > now, next.map({ at < $0 }) ?? true { next = at }
            }
        }
        return next
    }

    /// The facts by which `rule` matches `thing`, or nil when it doesn't.
    /// A rule without conditions matches every open thing in scope by one neutral fact (key "open"), so Done and
    /// notifications have something to hold on to.
    static func facts(_ rule: Rule, _ thing: Thing, marks: EntryMarks?, context: InboxContext) -> [Fact]? {
        facts(rule, thing, marks: marks, resolved: Resolved(context))
    }

    /// Chips in `rule` that can never match.
    static func problems(_ rule: Rule) -> [Problem] {
        var out: [Problem] = []
        let scope = rule.scope
        let kinds = scope.kinds
        func flag(_ slot: String, _ reason: String) { out.append(Problem(condition: nil, slot: slot, reason: reason)) }

        if kinds.isEmpty { flag("kind", "Pick PRs, issues or workflows") }
        if scope.isWorkflow, kinds.count > 1 { flag("kind", "Workflows are a rule of their own: they don't mix with PRs or issues") }

        if let p = scope.by, overlap(p) { flag("by", Self.bothReason) }
        if let p = scope.by, hasTeam(p) { flag("by", "Teams don't author anything") }
        if let p = scope.to, overlap(p) { flag("to", Self.bothReason) }
        if let p = scope.in, overlap(p) { flag("in", Self.bothReason) }
        if scope.isWorkflow {
            if scope.in == nil { flag("in", "Workflows need a repository") }
            if scope.by != nil { flag("by", "Workflows have no author") }
            if scope.to != nil { flag("to", "Workflows aren't assigned to anyone") }
            if scope.in?.include.contains(.involved) == true { flag("in", "Workflows can't be filtered by involvement") }
        } else {
            if scope.on != nil { flag("on", "Only workflows have branches") }
            if scope.named != nil { flag("named", "Only workflows have names") }
        }
        if let to = scope.to {
            if scope.toRoles.isEmpty { flag("to", "Pick at least one of assigned, review requested, mentioned") }
            if hasTeam(to) {
                if !kinds.contains(.pr) { flag("to", "Issues aren't assigned to teams") }
                else if !scope.toRoles.contains(.reviewRequested) { flag("to", "Teams only come with review requested") }
            }
            // Review requests are a PR's alone: issues need another way to be for someone.
            if kinds.contains(.issue), scope.toRoles == [.reviewRequested] {
                flag("to", "Issues are never review requested: add assigned or mentioned, or leave issues out")
            }
            if kinds.contains(.pr), scope.toRoles == [.reviewRequested], onlyMe(scope.by), onlyMe(to) {
                flag("to", "You can't be asked to review your own PR")
            }
        }

        for (i, condition) in rule.conditions.enumerated() {
            func add(_ reason: String) { out.append(Problem(condition: i, slot: nil, reason: reason)) }
            // Every chosen kind must have it: a condition that only some can meet would quietly leave the others out.
            let lacking = kinds.subtracting(offered(condition))
            if !lacking.isEmpty {
                add("\(lacking.label) don't have this")
                continue
            }
            switch condition {
            case .newComment(let p, let since), .newReview(let p, let since), .newCommits(let p, let since),
                 .mentions(let p, let since):
                if overlap(p) { add(bothReason) }
                if hasTeam(p) { add("Teams don't write comments") }
                if since == .myLastReview, kinds.contains(.issue) { add("Issues have no reviews") }
            case .lastComment(let p):
                if overlap(p) { add(bothReason) }
            case .approved(let p), .changesRequested(let p):
                if overlap(p) { add(bothReason) }
                if onlyMe(scope.by), onlyMe(p) { add("GitHub doesn't let you review your own PR") }
            case .unresolvedThreads(let started, let replied):
                if let started, overlap(started) { add(bothReason) }
                if let replied, overlap(replied) { add(bothReason) }
            case .labeled(let p):
                if overlap(p) { add(bothReason) }
            case .checks(let s):
                if s.isEmpty { add("Pick at least one state") }
            case .workflow(let s):
                if s.isEmpty { add("Pick at least one state") }
            case .status(let s):
                if s.isEmpty { add("Pick at least one status") }
                else if !kinds.contains(.pr), s.isDisjoint(with: [.open, .closed]) { add("Issues are only open or closed") }
            case .greptileBelow(let n):
                if n <= 1 { add("Greptile scores start at 1") }
            case .hasConflicts, .behindBase, .noActivity, .asksMe, .noise, .importance:
                break
            }
        }

        // Under all-of, separate conditions on the same state must share a value: each set reads "is any of".
        if rule.match == .all {
            var status: Set<ThingStatus>?
            var checks: Set<CheckState>?
            var workflow: Set<CheckState>?
            for (i, condition) in rule.conditions.enumerated() {
                func narrow<V: Hashable>(_ acc: inout Set<V>?, _ s: Set<V>, _ what: String) {
                    guard let current = acc else { acc = s; return }
                    let next = current.intersection(s)
                    if next.isEmpty, !s.isEmpty, !current.isEmpty {
                        out.append(Problem(condition: i, slot: nil, reason: "Contradicts the other \(what) in this all-of"))
                    } else {
                        acc = next
                    }
                }
                switch condition {
                case .status(let s): narrow(&status, s, "status")
                case .checks(let s): narrow(&checks, s, "checks")
                case .workflow(let s): narrow(&workflow, s, "state")
                default: break
                }
            }
        }
        return out
    }

    /// Conditions offered for a rule about `kinds`, in menu order: those every one of them has, with values that fit them all
    /// (the narrowest kind's list: an issue's `status` closed, not a PR's draft).
    static func conditions(for kinds: Set<ThingKind>) -> [Condition] {
        let lists = ThingKind.allCases.filter(kinds.contains).map(conditions(for:))
        guard let narrowest = lists.min(by: { $0.count < $1.count }) else { return [] }
        return narrowest.filter { offered($0).isSuperset(of: kinds) }
    }

    private static func conditions(for kind: ThingKind) -> [Condition] {
        switch kind {
        case .pr:
            [.newComment(by: Pick()), .newReview(by: Pick()), .newCommits(by: Pick()),
             .mentions(Pick(include: [.me])),
             .lastComment(by: Pick()), .unresolvedThreads(startedBy: nil, lastReplyBy: nil),
             .approved(by: Pick()), .changesRequested(by: Pick()),
             .checks([.failing]), .hasConflicts, .behindBase,
             .status([.draft]), .labeled(Pick()), .noActivity(days: 7),
             .greptileBelow(5), .asksMe, .noise(true), .importance(.high)]
        case .issue:
            [.newComment(by: Pick()), .mentions(Pick(include: [.me])),
             .lastComment(by: Pick()),
             .status([.closed]), .labeled(Pick()), .noActivity(days: 7),
             .asksMe, .noise(true), .importance(.high)]
        case .workflow:
            [.workflow([.failing])]
        }
    }

    // MARK: - Matching

    private static let bothReason = "The same value is both included and excepted"

    /// What the context resolves to, built once per evaluate call.
    private struct Resolved {
        var me: String
        var now: Date
        var groupPeople: [UUID: Set<String>] = [:]
        var groupRepos: [UUID: (exact: Set<String>, owners: Set<String>)] = [:]
        var contributed: Set<String>
        var myTeams: Set<String>
        var jev: Bool

        init(_ context: InboxContext) {
            me = InboxEngine.normalize(context.me)
            jev = context.jevSignals
            now = context.now
            contributed = Set(context.contributedRepos.map { $0.lowercased() })
            myTeams = Set(context.myTeams.map { $0.lowercased() })
            for group in context.groups {
                switch group.kind {
                case .people:
                    groupPeople[group.id] = Set(group.members.map(InboxEngine.normalize))
                case .repos:
                    var exact = Set<String>(), owners = Set<String>()
                    for member in group.members.map({ $0.lowercased() }) {
                        if member.hasSuffix("/*") { owners.insert(String(member.dropLast(2))) } else { exact.insert(member) }
                    }
                    groupRepos[group.id] = (exact, owners)
                }
            }
        }
    }

    /// Logins compare lowercased, without `@` or the REST API's `[bot]`; `@greptile` is Greptile's account.
    private static func normalize(_ login: String) -> String {
        var s = login.lowercased()
        if s.hasPrefix("@") { s.removeFirst() }
        if s.hasSuffix("[bot]") { s.removeLast(5) }
        return s == "greptile" ? "greptile-apps" : s
    }

    private static func matches(_ ref: PersonRef, _ person: Person, _ r: Resolved) -> Bool {
        switch ref {
        case .me: return !r.me.isEmpty && normalize(person.login) == r.me
        case .user(let login): return normalize(login) == normalize(person.login)
        case .group(let id): return r.groupPeople[id]?.contains(normalize(person.login)) ?? false
        case .maintainers: return person.association.isMaintainer
        case .bots: return person.isBot
        case .team(let slug): return normalize(slug.hasPrefix("@") ? String(slug.dropFirst()) : slug) == normalize(person.login)
        case .myTeams: return r.myTeams.contains(normalize(person.login))
        }
    }

    /// Empty include is anyone; except always excludes.
    private static func matches(_ pick: Pick<PersonRef>?, _ person: Person, _ r: Resolved) -> Bool {
        guard let pick else { return true }
        if !pick.include.isEmpty, !pick.include.contains(where: { matches($0, person, r) }) { return false }
        return !pick.except.contains { matches($0, person, r) }
    }

    /// For people known by login only (assignees, mentions, commit authors): maintainers and bots can't be told.
    private static func matches(_ pick: Pick<PersonRef>?, login: String, _ r: Resolved) -> Bool {
        matches(pick, Person(login: login), r)
    }

    private static func matches(_ ref: RepoRef, _ thing: Thing, _ r: Resolved) -> Bool {
        let repo = thing.repo.lowercased()
        switch ref {
        case .repo(let name): return name.lowercased() == repo
        case .owner(let owner): return repo.hasPrefix(owner.lowercased() + "/")
        case .group(let id):
            guard let g = r.groupRepos[id] else { return false }
            return g.exact.contains(repo) || g.owners.contains(String(repo.prefix { $0 != "/" }))
        case .owned: return !r.me.isEmpty && repo.hasPrefix(r.me + "/")
        case .contributed: return r.contributed.contains(repo)
        case .involved: return thing.kind != .workflow && involved(thing, r)
        }
    }

    private static func involved(_ thing: Thing, _ r: Resolved) -> Bool {
        guard !r.me.isEmpty else { return false }
        func isMe(_ login: String) -> Bool { normalize(login) == r.me }
        if let a = thing.author, isMe(a.login) { return true }
        return thing.assignees.contains(where: isMe) || thing.requestedReviewers.contains(where: isMe)
            || thing.mentioned.contains(where: isMe) || thing.comments.contains { isMe($0.author.login) }
            || thing.reviews.contains { isMe($0.author.login) }
    }

    private static func inScope(_ scope: Scope, _ thing: Thing, _ r: Resolved) -> Bool {
        if let repos = scope.in {
            if !repos.include.isEmpty, !repos.include.contains(where: { matches($0, thing, r) }) { return false }
            if repos.except.contains(where: { matches($0, thing, r) }) { return false }
        }
        switch thing.kind {
        case .workflow:
            // The fetched thing already carries its branch (the default one unless the rule says otherwise).
            // An empty `on` or `named` is the slot's default: the default branch, every workflow.
            if let on = InboxSync.given(scope.on), let branch = thing.branch, !on.contains(branch) { return false }
            if let named = InboxSync.given(scope.named) {
                guard let name = thing.workflowName?.lowercased(), named.contains(where: { $0.lowercased() == name })
                else { return false }
            }
        case .pr, .issue:
            if let by = scope.by {
                guard let author = thing.author, matches(by, author, r) else { return false }
            }
            if let to = scope.to {
                var logins: [String] = []
                if scope.toRoles.contains(.assigned) { logins += thing.assignees }
                if scope.toRoles.contains(.reviewRequested), thing.kind == .pr { logins += thing.requestedReviewers }
                if scope.toRoles.contains(.mentioned) { logins += thing.mentioned }
                if !logins.contains(where: { matches(to, login: $0, r) }) { return false }
            }
        }
        return true
    }

    private static func facts(_ rule: Rule, _ thing: Thing, marks: EntryMarks?, resolved r: Resolved) -> [Fact]? {
        guard rule.scope.kinds.contains(thing.kind), inScope(rule.scope, thing, r) else { return nil }
        // Merged and closed things only match through a status condition asking for them.
        let gated = thing.kind != .workflow && (thing.status == .merged || thing.status == .closed)
        let conditions = rule.conditions

        let done = max(rule.createdAt, marks?.doneAt ?? .distantPast)
        func isStatus(_ c: Condition) -> Bool { if case .status = c { true } else { false } }

        var out: [Fact] = []
        var keys = Set<String>()
        func add(_ facts: [Fact]) { for f in facts where keys.insert(f.key).inserted { out.append(f) } }
        // Review requests are facts with identity: a request made again after a review is a new one.
        let requests = reviewRequestFacts(rule.scope, thing, r)

        if conditions.isEmpty { return gated ? nil : requests.isEmpty ? [Fact(key: "open", label: "open")] : requests }

        switch rule.match {
        case .any:
            for condition in conditions where !gated || isStatus(condition) {
                add(facts(condition, thing, done: done, r))
            }
            if out.isEmpty { return nil }
        case .all:
            if gated, !conditions.contains(where: isStatus) { return nil }
            for condition in conditions {
                let matched = facts(condition, thing, done: done, r)
                if matched.isEmpty { return nil }
                add(matched)
            }
        }
        add(requests)
        return out
    }

    /// One fact per review request that put the thing in the rule's `to`, keyed by who and when it was made.
    private static func reviewRequestFacts(_ scope: Scope, _ thing: Thing, _ r: Resolved) -> [Fact] {
        guard thing.kind == .pr, let to = scope.to, scope.toRoles.contains(.reviewRequested) else { return [] }
        return thing.requestedReviewers.filter { matches(to, login: $0, r) }.map { reviewer in
            let at = thing.reviewRequests.first { $0.reviewer.caseInsensitiveCompare(reviewer) == .orderedSame }?.at ?? thing.createdAt
            let label = reviewer.contains("/") ? "review requested from @\(reviewer)" : "review requested"
            return Fact(key: "requested:\(reviewer.lowercased()):\(Int(at.timeIntervalSince1970))", label: label, tint: .attention)
        }
    }

    /// The moment an activity condition counts events after; nil when there is none, so nothing can match.
    private static func cutoff(_ since: Since, _ thing: Thing, done: Date, _ r: Resolved) -> Date? {
        func mine(_ person: Person) -> Bool { !r.me.isEmpty && normalize(person.login) == r.me }
        switch since {
        case .done:
            return done
        case .myLastReview:
            let reviews = thing.reviews.filter { mine($0.author) }.map(\.at)
            let withText = thing.comments.filter { $0.isReview && mine($0.author) }.map(\.at)
            return (reviews + withText).max()
        case .myLastComment:
            let comments = thing.comments.filter { mine($0.author) }.map(\.at)
            let replies = thing.threads.filter { mine($0.lastReplyBy) }.map(\.lastReplyAt)
            return (comments + replies).max() ?? thing.createdAt
        }
    }

    private static func facts(_ condition: Condition, _ thing: Thing, done: Date, _ r: Resolved) -> [Fact] {
        guard offered(condition).contains(thing.kind) else { return [] }
        var cutoff = done
        if let since = condition.since {
            guard let date = Self.cutoff(since, thing, done: done, r) else { return [] }
            cutoff = date
        }
        switch condition {
        case .newComment(let by, _):
            return thing.comments.filter { !$0.isReview && $0.at > cutoff && matches(by, $0.author, r) }
                .map { Fact(key: "comment:\($0.id)", label: "comment by @\($0.author.login)", tint: .attention) }
        case .newReview(let by, _):
            return thing.reviews.filter { $0.at > cutoff && matches(by, $0.author, r) }
                .map { Fact(key: "review:\($0.id)", label: "review by @\($0.author.login)", tint: .attention) }
        case .newCommits(let by, _):
            return thing.commits.filter { $0.at > cutoff && matches(by, login: $0.author, r) }
                .map { Fact(key: "commit:\($0.id)", label: "commit by @\($0.author)", tint: .neutral) }
        case .mentions(let pick, _):
            return thing.comments.filter { c in
                c.at > cutoff && c.mentions.contains { matches(pick, login: $0, r) }
            }.map { Fact(key: "mention:\($0.id)", label: "mentioned by @\($0.author.login)", tint: .attention) }
        case .lastComment(let by):
            guard let last = thing.comments.max(by: { $0.at < $1.at }), matches(by, last.author, r) else { return [] }
            return [Fact(key: "last:\(last.id)", label: "last comment: @\(last.author.login)", tint: .attention)]
        case .unresolvedThreads(let started, let replied):
            let open = thing.threads.filter {
                !$0.isResolved && matches(started, $0.startedBy, r) && matches(replied, $0.lastReplyBy, r)
            }
            // One fact per thread so resolving one never revives a Done item; they all say the same.
            let label = "\(open.count) unresolved"
            return open.map { Fact(key: "thread:\($0.id):\($0.lastReplyID)", label: label, tint: .attention) }
        case .approved(let by):
            return latestOpinions(thing).filter { $0.state == .approved && matches(by, $0.author, r) }
                .map { Fact(key: "approved:\($0.id)", label: "approved by @\($0.author.login)", tint: .success) }
        case .changesRequested(let by):
            return latestOpinions(thing).filter { $0.state == .changesRequested && matches(by, $0.author, r) }
                .map { Fact(key: "changes:\($0.id)", label: "changes requested by @\($0.author.login)", tint: .danger) }
        case .checks(let states):
            guard let state = thing.checks, states.contains(state) else { return [] }
            return [Fact(key: "checks:\(state.rawValue)", label: "checks \(state.rawValue)", tint: tint(state))]
        case .hasConflicts:
            return thing.hasConflicts ? [Fact(key: "conflicts", label: "has conflicts", tint: .danger)] : []
        case .behindBase:
            // Keyed by the head commit: pushing (or merging the base in) and falling behind again is new.
            guard thing.behindBase else { return [] }
            let head = thing.headSha ?? String(Int(thing.updatedAt.timeIntervalSince1970))
            return [Fact(key: "behind:\(head)", label: "behind base branch", tint: .attention)]
        case .status(let statuses):
            guard statuses.contains(thing.status) else { return [] }
            let label = thing.status == .open && thing.kind == .pr ? "ready for review" : thing.status.rawValue
            return [Fact(key: "status:\(thing.status.rawValue)", label: label,
                         tint: thing.status == .merged ? .success : .neutral)]
        case .labeled(let pick):
            return thing.labels.filter { label in
                (pick.include.isEmpty || pick.include.contains { $0.caseInsensitiveCompare(label) == .orderedSame })
                    && !pick.except.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
            }.map { Fact(key: "label:\($0)", label: $0) }
        case .noActivity(let days):
            guard r.now.timeIntervalSince(thing.updatedAt) >= Double(days) * 86_400 else { return [] }
            return [Fact(key: "stale:\(Int(thing.updatedAt.timeIntervalSince1970))",
                         label: "no activity for \(days) day\(days == 1 ? "" : "s")", tint: .attention)]
        case .greptileBelow(let n):
            guard let score = thing.greptileScore, score < n else { return [] }
            return [Fact(key: "greptile:\(score)", label: "Greptile \(score)/5", tint: .attention)]
        case .asksMe:
            // Answering there is what stops a question asking: only what came after your latest word, and after Done.
            let after = max(cutoff, Self.cutoff(.myLastComment, thing, done: done, r) ?? .distantPast,
                            signals(thing, r)?.answeredAt ?? .distantPast)
            return messages(thing).filter { m in
                m.at > after && !isMe(m.author, r) && signals(thing, r)?.messages[m.id]?.asksMe == true
            }.map { Fact(key: "asks:\($0.id)", label: "Asks you", tint: .attention) }
        case .noise(let wanted):
            return messages(thing).filter { m in m.at > cutoff && !isMe(m.author, r) && isNoise(m, signals(thing, r)) == wanted }.map {
                wanted ? Fact(key: "noise:\($0.id)", label: "noise from @\($0.author.login)")
                    : Fact(key: "person:\($0.id)", label: "comment by @\($0.author.login)", tint: .attention)
            }
        case .importance(let least):
            guard let level = importance(thing, r), level >= least, let stamp = importanceStamp(thing, r) else { return [] }
            // Keyed by what was rated too: a new request after Done on an old one is new.
            return [Fact(key: "importance:\(level.rawValue):\(stamp)", label: level == .urgent ? "urgent" : "\(level.rawValue) importance",
                         tint: level == .urgent ? .danger : level == .high ? .attention : .neutral)]
        case .workflow(let states):
            guard let state = thing.checks, states.contains(state) else { return [] }
            // The state alone is the key: a failure notifies once, until it goes green and fails again.
            var label = state == .pending ? "running" : state.rawValue
            if state == .failing, !thing.failingJobs.isEmpty { label += ": " + thing.failingJobs.joined(separator: ", ") }
            return [Fact(key: "workflow:\(state.rawValue)", label: label, tint: tint(state))]
        }
    }

    // MARK: - Jev's signals

    /// A comment, a review's words or a thread's latest reply: what Jev reads, and what `asksMe` and `noise` are about.
    struct Message: Hashable {
        var id: String
        var author: Person
        var at: Date
        var text: String
        var isReview = false
        /// A thread's file (empty when GitHub didn't say) for a reply in one; nil for the conversation.
        var path: String?
    }

    /// Every message of a thing, oldest first.
    static func messages(_ thing: Thing) -> [Message] {
        let comments = thing.comments.map { Message(id: $0.id, author: $0.author, at: $0.at, text: $0.snippet, isReview: $0.isReview) }
        let replies = thing.threads.map {
            Message(id: $0.lastReplyID, author: $0.lastReplyBy, at: $0.lastReplyAt, text: $0.snippet, path: $0.path ?? "")
        }
        return (comments + replies).sorted { $0.at < $1.at }
    }

    /// A login as signals keep it: lowercased, without `@` or `[bot]`.
    static func viewer(_ login: String) -> String { normalize(login) }

    /// What Jev said of a thing for `me` (any login form): nothing when it was read for someone else.
    static func signals(_ thing: Thing, _ me: String) -> ThingSignals? {
        guard let signals = thing.signals, !me.isEmpty, signals.viewer == normalize(me) else { return nil }
        return signals
    }

    /// Your latest comment or thread reply on a thing, as it was fetched.
    static func latestWord(_ thing: Thing, by me: String) -> Date? {
        let me = normalize(me)
        guard !me.isEmpty else { return nil }
        let comments = thing.comments.filter { normalize($0.author.login) == me }.map(\.at)
        let replies = thing.threads.filter { normalize($0.lastReplyBy.login) == me }.map(\.lastReplyAt)
        return (comments + replies).max()
    }

    /// What Jev said that counts: nothing when it was for someone else, or Jev's reading is switched off.
    static func signals(_ thing: Thing, context: InboxContext) -> ThingSignals? {
        context.jevSignals ? signals(thing, context.me) : nil
    }

    private static func signals(_ thing: Thing, _ r: Resolved) -> ThingSignals? { r.jev ? signals(thing, r.me) : nil }

    /// Noise: what Jev said of it once it read it (nil when it wasn't sure); before that, whether a bot wrote it.
    private static func isNoise(_ m: Message, _ signals: ThingSignals?) -> Bool? {
        guard let signal = signals?.messages[m.id] else { return m.author.isBot }
        return signal.noise
    }

    private static func isMe(_ person: Person, _ r: Resolved) -> Bool { !r.me.isEmpty && normalize(person.login) == r.me }

    /// What an importance rating is for: the review request (to you or a team of yours) by when it was made, else your
    /// assignment. Nil when it is neither, or not open.
    static func importanceStamp(_ thing: Thing, context: InboxContext) -> String? { importanceStamp(thing, Resolved(context)) }
    /// Jev's rating of what is asked of you now, as the inbox counts it (for you, Jev's reading on, the request it rated).
    static func importance(_ thing: Thing, context: InboxContext) -> Importance? { importance(thing, Resolved(context)) }

    private static func importanceStamp(_ thing: Thing, _ r: Resolved) -> String? {
        guard thing.kind != .workflow, thing.status == .open || thing.status == .draft, !r.me.isEmpty else { return nil }
        if thing.kind == .pr {
            let mine = thing.requestedReviewers.filter { normalize($0) == r.me || r.myTeams.contains(normalize($0)) }
            let at = mine.map { who in
                thing.reviewRequests.first { $0.reviewer.caseInsensitiveCompare(who) == .orderedSame }?.at ?? thing.createdAt
            }.max()
            if let at { return "requested:\(Int(at.timeIntervalSince1970))" }
        }
        guard thing.assignees.contains(where: { normalize($0) == r.me }) else { return nil }
        // By when you were assigned: taken off and assigned again is a new thing to rate.
        return thing.assignedAt?.first { normalize($0.key) == r.me }.map { "assigned:\(Int($0.value.timeIntervalSince1970))" } ?? "assigned"
    }

    /// Jev's rating of what is asked of you now; nil when nothing is, or it wasn't rated (or wasn't sure).
    private static func importance(_ thing: Thing, _ r: Resolved) -> Importance? {
        guard let signal = signals(thing, r)?.importance, let stamp = importanceStamp(thing, r), signal.stamp == stamp else { return nil }
        return signal.level
    }

    private static func tint(_ state: CheckState) -> FactTint {
        switch state {
        case .failing: .danger
        case .pending: .attention
        case .passing: .success
        }
    }

    /// Each reviewer's latest review that states an opinion; commented and dismissed ones don't change it.
    private static func latestOpinions(_ thing: Thing) -> [ThingReview] {
        var latest: [String: ThingReview] = [:]
        for review in thing.reviews where review.state == .approved || review.state == .changesRequested {
            let who = normalize(review.author.login)
            if let current = latest[who], current.at >= review.at { continue }
            latest[who] = review
        }
        return latest.values.sorted { $0.at < $1.at }
    }

    // MARK: - Problems

    private static func overlap<V: Hashable>(_ pick: Pick<V>) -> Bool {
        !pick.include.isEmpty && !Set(pick.include).isDisjoint(with: pick.except)
    }

    private static func hasTeam(_ pick: Pick<PersonRef>) -> Bool {
        (pick.include + pick.except).contains { if case .team = $0 { true } else { $0 == .myTeams } }
    }

    /// The slot or pick names only me.
    private static func onlyMe(_ pick: Pick<PersonRef>?) -> Bool {
        guard let pick, !pick.include.isEmpty else { return false }
        return pick.include.allSatisfy { $0 == .me }
    }

    private static func offered(_ condition: Condition) -> Set<ThingKind> {
        switch condition {
        case .newComment, .mentions, .lastComment, .status, .labeled, .noActivity, .asksMe, .noise, .importance: [.pr, .issue]
        case .newReview, .newCommits, .unresolvedThreads, .approved, .changesRequested, .checks, .hasConflicts,
             .behindBase, .greptileBelow: [.pr]
        case .workflow: [.workflow]
        }
    }
}
