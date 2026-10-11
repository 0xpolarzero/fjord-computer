import CryptoKit
import Foundation

// Fetching for the inbox: what the categories' rules ask for, as GitHub search queries; one GraphQL shape that returns
// everything a Thing needs; workflows through the CI code; and the notifications for facts that are new.
enum InboxSync {
    /// Results asked per search page, pages followed per search, and things taken per refresh. A GraphQL search costs about
    /// half a point per result asked for, so a refresh with one search is about 10 points of the 5000 an hour.
    static let pageSize = 20
    static let maxPages = 3
    static let maxThings = 150
    /// Searches in one request.
    static let searchesPerRequest = 4
    /// A PR's review threads: read with it, then a page at a time past those, up to `maxThreads`, for several PRs a request.
    static let threadsFirst = 20
    static let threadsPage = 100
    static let maxThreads = 220
    static let threadPRsPerRequest = 10
    /// The threads past the first page are read again only when the PR changed (its threads' count, its last update), or
    /// once this old: a page of them costs a point or two a PR, and twenty such PRs read at every poll would spend more
    /// than an hour's points. With GitHub's points below `tailPoints`, what was read stands until they come back.
    static let threadsTailAge: TimeInterval = 15 * 60
    static let tailPoints = 1000
    /// How PRs' reviews are read: every latest review, a follow-up after an opinion too (1). A PR last read by a build that
    /// kept only each reviewer's latest gets back reviews it had all along, and they aren't new to its actions.
    static let reviewsShape = 1
    /// Searches a refresh makes at most, shared out a turn at a time between the rules so that none goes without.
    static let maxSearches = 16
    /// Workflow targets a refresh checks at most; past it, they take turns (`workflowWindow`).
    static let maxWorkflows = 30
    /// Closed and merged things are only fetched when updated this recently.
    static let closedDays = 14
    /// Marks of things gone this long are forgotten.
    static let marksDays = 30

    // MARK: - Searches

    /// What a rule's conditions ask of state: open things are always fetched; closed (and merged) only when asked for.
    static func asksForClosed(_ rule: Rule) -> Bool {
        rule.conditions.contains { if case .status(let s) = $0 { s.contains(.merged) || s.contains(.closed) } else { false } }
    }

    /// The GitHub search queries that cover every rule's PRs and issues. What search can't say (maintainers, bots, `except`
    /// of groups) is left out, so a query may return more than the rule matches: the engine decides. Past the cap, every
    /// rule still gets its first queries: they are taken a turn per rule, not the first rules' all.
    static func searches(categories: [InboxCategory], groups: [InboxGroup], me: String, contributed: Set<String>,
                         myTeams: Set<String> = [], now: Date = Date()) -> [String] {
        searchPlan(categories: categories, groups: groups, me: me, contributed: contributed, myTeams: myTeams, now: now).searches
    }

    /// The searches a refresh makes, out of all the rules ask for: each rule's first query, then the others a window at a
    /// time from `cursor` (or every query, first ones first, a window at a time, when the first ones alone fill the cap), so
    /// that past the cap every query gets its turn over the refreshes. `next` is where the next refresh's window starts.
    static func searchPlan(categories: [InboxCategory], groups: [InboxGroup], me: String, contributed: Set<String>,
                           myTeams: Set<String> = [], now: Date = Date(), cursor: Int = 0)
        -> (searches: [String], all: Set<String>, next: Int) {
        let since = ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double(closedDays) * 86400)).prefix(10)
        var perRule: [[String]] = []
        for category in categories {
            for rule in category.rules where !rule.scope.isWorkflow {
                let queries = searches(for: rule, groups: groups, me: me, contributed: contributed, myTeams: myTeams)
                perRule.append(queries.flatMap { query in
                    [query + " is:open"] + (asksForClosed(rule) ? [query + " is:closed updated:>=\(since)"] : [])
                })
            }
        }
        var firsts: [String] = [], rest: [String] = []
        var seen = Set<String>()
        var turn = 0
        while perRule.contains(where: { turn < $0.count }) {
            for queries in perRule where turn < queries.count && seen.insert(queries[turn]).inserted {
                if turn == 0 { firsts.append(queries[turn]) } else { rest.append(queries[turn]) }
            }
            turn += 1
        }
        func window(_ list: [String], _ count: Int) -> ([String], Int) {
            guard list.count > count else { return (list, 0) }
            let start = cursor % list.count
            return ((0..<count).map { list[(start + $0) % list.count] }, (start + count) % list.count)
        }
        // The first queries alone fill the cap: the window goes over every query, so the others still get their turn.
        if firsts.count >= maxSearches {
            let (taken, next) = window(firsts + rest, maxSearches)
            return (taken, seen, next)
        }
        let (more, next) = window(rest, maxSearches - firsts.count)
        return (firsts + more, seen, next)
    }

    /// Results each search asks for on a page, so that what all of them ask for stays within `budget` things.
    static func pageSizes(searches: Int, budget: Int) -> Int {
        guard searches > 0 else { return 0 }
        return max(1, min(pageSize, budget / searches))
    }

    /// People a slot names as search logins, nil when search can't say it (anyone, maintainers, bots).
    static func logins(_ pick: Pick<PersonRef>?, groups: [InboxGroup], me: String) -> [String]? {
        guard let pick, !pick.include.isEmpty else { return nil }
        var found: [String] = []
        for ref in pick.include {
            switch ref {
            case .me: found.append(me)
            case .user(let login): found.append(login.hasPrefix("@") ? String(login.dropFirst()) : login)
            case .group(let id): found += groups.first { $0.id == id && $0.kind == .people }?.members ?? []
            case .maintainers, .bots: return nil
            // Teams are asked about by `teams(_:)`, not as logins.
            case .team, .myTeams: break
            }
        }
        var seen = Set<String>()
        let unique = found.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return unique.isEmpty ? nil : unique
    }

    /// Whether a refresh needs the teams you're in: a rule names `My teams` (to take them in or to leave them out: "to me
    /// except My teams" can't leave out what isn't known), or Jev rates review requests, those to a team of yours among them.
    static func needsTeams(categories: [InboxCategory], jevReads: Bool) -> Bool {
        jevReads || categories.contains { category in
            category.rules.contains { rule in
                var picks = [rule.scope.to, rule.scope.by] + rule.conditions.map(\.people)
                for case .unresolvedThreads(let started, let last) in rule.conditions { picks += [started, last] }
                return picks.contains { pick in pick.map { ($0.include + $0.except).contains(.myTeams) } ?? false }
            }
        }
    }

    /// Whether a refresh needs the repos you own or contribute to: a rule names them, to take them in or to leave them out
    /// ("acme/* except Repos I contribute to" can't leave out what isn't known).
    static func needsRepos(categories: [InboxCategory]) -> Bool {
        categories.contains { category in
            category.rules.contains { rule in
                rule.scope.in.map { ($0.include + $0.except).contains { $0 == .owned || $0 == .contributed } } ?? false
            }
        }
    }

    /// How soon the teams are asked again after looking them up failed.
    static let teamsRetry: TimeInterval = 15 * 60

    /// Teams are looked up once a day, and a failed look again after `teamsRetry`.
    static func teamsDue(resolvedAt: Date?, failedAt: Date?, now: Date = Date()) -> Bool {
        if let failedAt, now.timeIntervalSince(failedAt) < teamsRetry { return false }
        return resolvedAt.map { now.timeIntervalSince($0) > 86400 } ?? true
    }

    /// `org/team` a slot names: its teams, and yours for `My teams`.
    static func teams(_ pick: Pick<PersonRef>?, myTeams: Set<String>) -> [String] {
        var found: [String] = []
        for ref in pick?.include ?? [] {
            switch ref {
            case .team(let slug): found.append(slug.hasPrefix("@") ? String(slug.dropFirst()) : slug)
            case .myTeams: found += myTeams.sorted()
            default: break
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The qualifier for an author: a bot's login is `app/name` in search.
    private static func author(_ login: String) -> String {
        login.hasSuffix("[bot]") ? "app/" + login.dropLast(5) : login
    }

    /// Repo qualifiers a slot names (`repo:`/`user:`), and `involves:` when it says anywhere you're involved. Repos you own
    /// are `user:` you, one qualifier however many there are (each a `repo:` would take the searches of a hundred repos).
    static func places(_ pick: Pick<RepoRef>?, groups: [InboxGroup], me: String, contributed: Set<String>)
        -> (qualifiers: [String], involved: Bool, except: [String]) {
        guard let pick else { return ([], false, []) }
        func qualifier(_ name: String) -> String? {
            if name.hasSuffix("/*") { return "user:" + name.dropLast(2) }
            return name.contains("/") ? "repo:" + name : nil
        }
        func expand(_ ref: RepoRef) -> [String] {
            switch ref {
            case .repo(let name): [qualifier(name)].compactMap { $0 }
            case .owner(let owner): ["user:" + owner]
            case .group(let id): (groups.first { $0.id == id && $0.kind == .repos }?.members ?? []).compactMap(qualifier)
            case .owned: ["user:" + me]
            case .contributed: contributed.sorted().map { "repo:" + $0 }
            case .involved: []
            }
        }
        var seen = Set<String>()
        let include = pick.include.flatMap(expand).filter { seen.insert($0).inserted }
        let except = pick.except.flatMap(expand).map { "-" + $0 }
        return (include, pick.include.contains(.involved), Array(except.prefix(8)))
    }

    /// Queries (without state) for one rule about PRs, issues or both. A query PRs and issues share is one search without
    /// `is:pr`/`is:issue`, which finds both; what only one has (review requests) says which.
    static func searches(for rule: Rule, groups: [InboxGroup], me: String, contributed: Set<String>,
                         myTeams: Set<String> = []) -> [String] {
        let each = [ThingKind.pr, .issue].filter(rule.scope.kinds.contains).map { kind in
            (kind, searches(for: rule, kind: kind, groups: groups, me: me, contributed: contributed, myTeams: myTeams))
        }
        var out: [String] = []
        for (kind, queries) in each {
            for query in queries {
                let shared = each.count > 1 && each.allSatisfy { $0.1.contains(query) }
                out.append(shared ? query : (kind == .pr ? "is:pr " : "is:issue ") + query)
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// The queries for the rule's things of one kind, without the kind.
    private static func searches(for rule: Rule, kind: ThingKind, groups: [InboxGroup], me: String, contributed: Set<String>,
                                 myTeams: Set<String>) -> [String] {
        let scope = rule.scope
        let base = "archived:false"
        let by = logins(scope.by, groups: groups, me: me)
        let exclude = (scope.by?.except ?? []).compactMap { ref -> String? in
            if case .user(let login) = ref { return "-author:" + author(login.hasPrefix("@") ? String(login.dropFirst()) : login) }
            if case .me = ref { return "-author:" + me }
            return nil
        }
        // `to`: one query per role and person (a search can't say "or" between different qualifiers).
        var roles = scope.toRoles
        if kind == .issue { roles.remove(.reviewRequested) }
        let to = roles.isEmpty ? nil : logins(scope.to, groups: groups, me: me)
        let teams = kind == .pr && roles.contains(.reviewRequested) ? teams(scope.to, myTeams: myTeams) : []
        // Only teams asked for, and none known yet (not resolved, or you're in none): nothing to search for.
        if let include = scope.to?.include, !roles.isEmpty, teams.isEmpty,
           !include.isEmpty, include.allSatisfy({ if case .team = $0 { true } else { $0 == .myTeams } }) {
            return []
        }
        var toQualifiers: [String?] = [nil]
        if to != nil || !teams.isEmpty {
            toQualifiers = (to ?? []).flatMap { login in
                roles.sorted { $0.rawValue < $1.rawValue }.map { role -> String? in
                    switch role {
                    case .assigned: "assignee:" + login
                    case .reviewRequested: "review-requested:" + login
                    case .mentioned: "mentions:" + login
                    }
                }
            } + teams.map { "team-review-requested:" + $0 }
        }
        var authors: [String?] = by?.map { "author:" + author($0) } ?? [nil]
        // Past the cap, the narrower slot is dropped: it over-fetches, and the engine filters.
        if authors.count * toQualifiers.count > maxSearches { authors = [nil] }
        if authors.count * toQualifiers.count > maxSearches { toQualifiers = [nil] }

        let place = places(scope.in, groups: groups, me: me, contributed: contributed)
        var clauses: [[String]] = []
        if place.involved || (place.qualifiers.isEmpty && scope.by == nil && scope.to == nil) {
            clauses.append(["involves:" + me])
        }
        // Repos go together in one query (they are or-ed), within the length search allows.
        var chunk: [String] = []
        for qualifier in place.qualifiers {
            if (chunk + [qualifier]).joined(separator: " ").count > 150 { clauses.append(chunk); chunk = [] }
            chunk.append(qualifier)
        }
        if !chunk.isEmpty { clauses.append(chunk) }
        if clauses.isEmpty { clauses = [[]] }

        var out: [String] = []
        for clause in clauses {
            for a in authors {
                for t in toQualifiers {
                    let parts = [base] + clause + [a, t].compactMap { $0 } + place.except + exclude
                    out.append((parts + ["sort:updated-desc"]).joined(separator: " "))
                }
            }
        }
        return out
    }

    // MARK: - GraphQL

    private static let person = "author { login __typename avatarUrl } authorAssociation"
    private static let personNode = "login __typename avatarUrl"
    private static let assignEvents = "assignEvents: timelineItems(itemTypes: [ASSIGNED_EVENT], last: 20) { nodes { ... on AssignedEvent { createdAt assignee { ... on User { login } } } } }"

    /// A page of review threads: where the next one starts, and each thread's first and latest comments (who wrote the
    /// last few, and when: an answer in the middle of a thread is one; asking more of them costs no more points).
    static let threadReplies = 10
    private static let threadFields = """
    pageInfo { hasNextPage endCursor } nodes { id isResolved path
        first: comments(first: 1) { nodes { id createdAt body author { \(personNode) } authorAssociation } }
        last: comments(last: \(threadReplies)) { nodes { id createdAt body author { \(personNode) } authorAssociation } } }
    """

    static let fragments = """
    fragment C on Comment { id createdAt body authorAssociation author { \(personNode) } }
    fragment P on PullRequest {
      id number title url isDraft state merged createdAt updatedAt body mergeable mergeStateStatus additions deletions changedFiles
      repository { nameWithOwner }
      \(person)
      labels(first: 10) { nodes { name } }
      assignees(first: 10) { nodes { login } }
      \(assignEvents)
      reviewRequests(first: 100) { nodes { requestedReviewer { ... on User { login } ... on Team { combinedSlug } } } }
      requestEvents: timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 50) { nodes { ... on ReviewRequestedEvent {
        createdAt requestedReviewer { ... on User { login } ... on Team { combinedSlug } } } } }
      comments(last: 10) { nodes { ...C } }
      latestOpinionatedReviews(first: 10) { nodes { id state submittedAt body authorAssociation author { \(personNode) } } }
      reviews(last: 10) { nodes { id state submittedAt body authorAssociation author { \(personNode) } } }
      reviewThreads(first: \(threadsFirst)) { totalCount \(threadFields) }
      commits(last: 5) { nodes { commit { oid committedDate author { user { login } } statusCheckRollup { state } } } }
      head: commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts(first: 50) { totalCount
        checkRunCountsByState { state count } statusContextCountsByState { state count } nodes {
        __typename ... on CheckRun { databaseId status } ... on StatusContext { context state createdAt } } } } } } }
    }
    fragment I on Issue {
      id number title url state createdAt updatedAt body
      repository { nameWithOwner }
      \(person)
      labels(first: 10) { nodes { name } }
      assignees(first: 10) { nodes { login } }
      \(assignEvents)
      comments(last: 10) { nodes { ...C } }
    }
    """

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A request for several searches, each from its own cursor.
    fileprivate static func request(_ searches: [(alias: String, query: String, cursor: String?)], first: Int = pageSize) -> String {
        let body = searches.map { s in
            let after = s.cursor.map { ", after: \"\(escape($0))\"" } ?? ""
            return """
            \(s.alias): search(query: "\(escape(s.query))", type: ISSUE, first: \(first)\(after)) {
              pageInfo { hasNextPage endCursor }
              nodes { __typename ...P ...I }
            }
            """
        }
        return "query { rateLimit { cost remaining resetAt } \(body.joined(separator: "\n")) }\n" + fragments
    }

    /// The repos you own and have merged or open PRs in.
    /// The next page of review threads of several PRs, by their node ids, each from its own cursor.
    fileprivate static func threadsRequest(_ pages: [(alias: String, node: String, cursor: String, first: Int)]) -> String {
        let body = pages.map { p in
            "\(p.alias): node(id: \"\(escape(p.node))\") { ... on PullRequest { reviewThreads(first: \(p.first), after: \"\(escape(p.cursor))\") { \(threadFields) } } }"
        }
        return "query { rateLimit { cost remaining resetAt } \(body.joined(separator: "\n")) }"
    }

    /// Where a PR's review threads go on past the page read, if they do: its node id, the cursor, and how many it has.
    static func moreThreads(_ node: [String: Any]) -> (node: String, cursor: String, total: Int)? {
        guard node["__typename"] as? String == "PullRequest", let id = node["id"] as? String else { return nil }
        let total = dict(node["reviewThreads"])?["totalCount"] as? Int ?? maxThreads
        return nextPage(node["reviewThreads"]).map { (id, $0, total) }
    }

    /// The size of the next page of a PR's threads: what is left of them (as many as it has said), within a page and the cap.
    static func threadsPageSize(read: Int, total: Int) -> Int {
        max(1, min(threadsPage, total - read, maxThreads - read))
    }

    /// Whether a PR's threads past the first page, as read before, stand for now: the PR is as it was then (as many threads,
    /// the same last update) and they were read recently, or GitHub's points are running low.
    static func keepsTail(_ old: Thing?, total: Int, updatedAt: Date, now: Date, remaining: Int?) -> Bool {
        guard let tail = old?.threadsTail else { return false }
        if let remaining, remaining < tailPoints { return true }
        return tail.total == total && tail.updatedAt == updatedAt && now.timeIntervalSince(tail.readAt) < threadsTailAge
    }

    /// The threads past the first page as read before, and what their replies mention, added to a PR fetched again.
    static func takeTail(of old: Thing, into thing: inout Thing) {
        let have = Set(thing.threads.map(\.id))
        thing.threads += old.threads.filter { !have.contains($0.id) }
        var seen = Set(thing.mentioned)
        thing.mentioned += (old.threadsTail?.mentions ?? []).filter { seen.insert($0).inserted }
        thing.threadsTail = old.threadsTail
    }

    static func nextPage(_ connection: Any?) -> String? {
        let info = dict(dict(connection)?["pageInfo"])
        guard info?["hasNextPage"] as? Bool == true else { return nil }
        return info?["endCursor"] as? String
    }

    /// Takes in a page of review threads (those not already there) and the mentions in their latest replies, and says those.
    @discardableResult
    static func addThreads(_ connection: Any?, to thing: inout Thing) -> [String] {
        var mentioned: [String] = []
        for t in nodes(connection) {
            guard let thread = thread(t), !thing.threads.contains(where: { $0.id == thread.thread.id }) else { continue }
            thing.threads.append(thread.thread)
            mentioned += thread.mentions
        }
        var seen = Set(thing.mentioned)
        thing.mentioned += mentioned.filter { seen.insert($0).inserted }
        return mentioned
    }

    private static func thread(_ t: [String: Any]) -> (thread: ThingThread, mentions: [String])? {
        let replies = nodes(t["last"])
        guard let id = t["id"] as? String, let first = nodes(t["first"]).first, let last = replies.last,
              let lastID = last["id"] as? String, let at = date(last["createdAt"]) else { return nil }
        var latestBy: [String: Date] = [:]
        for reply in replies {
            guard let when = date(reply["createdAt"]) else { continue }
            let who = person(reply["author"], association: nil).login.lowercased()
            if latestBy[who].map({ $0 < when }) ?? true { latestBy[who] = when }
        }
        return (ThingThread(
            id: id, isResolved: t["isResolved"] as? Bool ?? false,
            startedBy: person(first["author"], association: first["authorAssociation"]),
            lastReplyBy: person(last["author"], association: last["authorAssociation"]), lastReplyID: lastID,
            lastReplyAt: at, path: t["path"] as? String, snippet: snippet(last["body"] as? String), latestBy: latestBy),
                mentions(last["body"] as? String))
    }

    fileprivate static func reposRequest(me: String) -> String {
        """
        query { viewer { repositories(first: 100, ownerAffiliations: OWNER, orderBy: {field: PUSHED_AT, direction: DESC}) { nodes { nameWithOwner } } }
          merged: search(query: "is:pr is:merged author:\(escape(me)) sort:updated-desc", type: ISSUE, first: 100) {
            nodes { ... on PullRequest { repository { nameWithOwner } } } }
          open: search(query: "is:pr is:open author:\(escape(me)) sort:updated-desc", type: ISSUE, first: 100) {
            nodes { ... on PullRequest { repository { nameWithOwner } } } } }
        """
    }

    /// The teams you're in, across your organizations (`org/team`). Needs the read:org scope; without it, none.
    fileprivate static func teamsRequest(me: String) -> String {
        """
        query { viewer { organizations(first: 50) { nodes { teams(first: 100, userLogins: ["\(escape(me))"]) { nodes { combinedSlug } } } } } }
        """
    }

    /// `org/team` out of a teams response.
    fileprivate static func teams(_ data: [String: Any]?) -> Set<String> {
        let orgs = nodes(dict(dict(data?["viewer"])?["organizations"]))
        return Set(orgs.flatMap { nodes($0["teams"]).compactMap { $0["combinedSlug"] as? String } })
    }

    // MARK: - Mapping

    private static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func nodes(_ value: Any?) -> [[String: Any]] { (dict(value)?["nodes"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [] }
    private static func date(_ value: Any?) -> Date? { (value as? String).flatMap { try? Date.ISO8601FormatStyle().parse($0) } }

    static func association(_ raw: Any?) -> Association {
        switch raw as? String {
        case "OWNER": .owner
        case "MEMBER": .member
        case "COLLABORATOR": .collaborator
        case "CONTRIBUTOR": .contributor
        case "FIRST_TIME_CONTRIBUTOR": .firstTimeContributor
        case "FIRST_TIMER": .firstTimer
        case "MANNEQUIN": .mannequin
        default: .none
        }
    }

    /// GraphQL gives a bot's login without the `[bot]` REST adds; it's added so the two agree (`greptile-apps[bot]`).
    static func person(_ author: Any?, association raw: Any?) -> Person {
        guard let a = dict(author), let login = a["login"] as? String else { return Person(login: "ghost") }
        let bot = a["__typename"] as? String == "Bot" || login.hasSuffix("[bot]")
        return Person(login: bot && !login.hasSuffix("[bot]") ? login + "[bot]" : login, isBot: bot, association: association(raw),
                      avatar: (a["avatarUrl"] as? String).flatMap { URL(string: $0) })
    }

    /// Logins @-mentioned in a text, lowercased, without teams, emails or what code blocks hold.
    static func mentions(_ text: String?) -> [String] {
        guard let text, text.contains("@") else { return [] }
        let clean = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_/.@`])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:\\[bot\\])?)(?![A-Za-z0-9_/\\-])") else { return [] }
        var seen = Set<String>()
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap { match in
            Range(match.range(at: 1), in: clean).map { String(clean[$0]).lowercased() }
        }.filter { seen.insert($0).inserted }
    }

    /// A comment's text as a line: no HTML comments, code, markup.
    static func snippet(_ body: String?) -> String {
        guard var text = body else { return "" }
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " [code] ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[#*_>`]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespaces).prefix(280))
    }

    /// `<!-- greptile_confidence_score:4 -->` in a PR body.
    static func greptileScore(_ body: String?) -> Int? {
        guard let body, let r = body.range(of: "greptile_confidence_score:\\s*(\\d+)", options: .regularExpression) else { return nil }
        return Int(body[r].filter(\.isNumber))
    }

    static func checkState(_ raw: Any?) -> CheckState? {
        switch raw as? String {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .pending
        default: nil
        }
    }

    /// Which execution of a commit's checks GitHub shows, and whether any of them still runs: the check runs by id (a rerun
    /// makes new ones; one finishing keeps its own) and the statuses by context and when last posted. Only the first page is
    /// read by id; whether any runs comes from GitHub's counts of all of them by state, and past the first page those
    /// counts are in the identity too (one beyond it failing again where it passed is another outcome).
    static func ciExecution(sha: String, contexts: [String: Any]) -> (run: String, running: Bool) {
        var ids: [String] = []
        var running = false
        let seen = nodes(contexts)
        for c in seen {
            if let id = c["databaseId"] as? Int {
                ids.append("c\(id)")
                running = running || c["status"] as? String != "COMPLETED"
            } else if let context = c["context"] as? String {
                ids.append("s\(context)@\(c["createdAt"] as? String ?? "")")
                running = running || checkState(c["state"]) == .pending
            }
        }
        func counts(_ key: String) -> [(state: String, count: Int)] {
            (contexts[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { c in
                (c["state"] as? String).flatMap { state in (c["count"] as? Int).map { (state, $0) } }
            }
        }
        let runs = counts("checkRunCountsByState"), statuses = counts("statusContextCountsByState")
        let unfinished: Set<String> = ["QUEUED", "IN_PROGRESS", "PENDING", "WAITING"]
        running = running || runs.contains { unfinished.contains($0.state) && $0.count > 0 }
            || statuses.contains { ($0.state == "PENDING" || $0.state == "EXPECTED") && $0.count > 0 }
        let total = contexts["totalCount"] as? Int ?? seen.count
        guard total > seen.count else { return (ciRun(sha: sha, ids: ids), running) }
        let tally = (runs.map { "c\($0.state)=\($0.count)" } + statuses.map { "s\($0.state)=\($0.count)" }).sorted()
        return (ciRun(sha: sha, ids: ids + tally) + "+\(total)", running)
    }

    /// `ci:<commit>:<digest of the checks' ids>`, whatever order they came in.
    nonisolated static func ciRun(sha: String, ids: [String]) -> String {
        let digest = SHA256.hash(data: Data(ids.sorted().joined(separator: "\n").utf8)).prefix(12)
            .map { String(format: "%02x", $0) }.joined()
        return "ci:\(sha):\(digest)"
    }

    /// A search node (a PR or an issue) as a Thing; nil when it lacks what a Thing needs.
    static func thing(_ node: [String: Any]) -> Thing? {
        guard let kindName = node["__typename"] as? String, kindName == "PullRequest" || kindName == "Issue",
              let repo = dict(node["repository"])?["nameWithOwner"] as? String, let number = node["number"] as? Int,
              let url = (node["url"] as? String).flatMap({ URL(string: $0) }),
              let created = date(node["createdAt"]), let updated = date(node["updatedAt"]) else { return nil }
        let isPR = kindName == "PullRequest"
        let body = node["body"] as? String
        var thing = Thing(id: "\(isPR ? "pr" : "issue"):\(repo)#\(number)", kind: isPR ? .pr : .issue, repo: repo, number: number,
                          title: node["title"] as? String ?? "#\(number)", url: url, createdAt: created, updatedAt: updated)
        thing.author = person(node["author"], association: node["authorAssociation"])
        thing.labels = nodes(node["labels"]).compactMap { $0["name"] as? String }
        thing.assignees = nodes(node["assignees"]).compactMap { $0["login"] as? String }
        // When each current assignee was assigned: the latest event for them.
        var assigned: [String: Date] = [:]
        for event in nodes(node["assignEvents"]) {
            guard let who = (dict(event["assignee"])?["login"] as? String)?.lowercased(), let at = date(event["createdAt"]),
                  thing.assignees.contains(where: { $0.lowercased() == who }) else { continue }
            if assigned[who].map({ $0 < at }) ?? true { assigned[who] = at }
        }
        thing.assignedAt = assigned.isEmpty ? nil : assigned
        var mentioned = mentions(body)

        var comments: [ThingComment] = []
        for c in nodes(node["comments"]) {
            guard let id = c["id"] as? String, let at = date(c["createdAt"]) else { continue }
            let text = c["body"] as? String
            let found = mentions(text)
            mentioned += found
            comments.append(ThingComment(id: id, author: person(c["author"], association: c["authorAssociation"]), at: at,
                                         snippet: snippet(text), mentions: found))
        }

        if isPR {
            thing.status = node["merged"] as? Bool == true ? .merged : node["state"] as? String == "CLOSED" ? .closed
                : node["isDraft"] as? Bool == true ? .draft : .open
            func reviewer(_ node: [String: Any]) -> String? {
                let r = dict(node["requestedReviewer"])
                return r?["login"] as? String ?? r?["combinedSlug"] as? String
            }
            thing.requestedReviewers = nodes(node["reviewRequests"]).compactMap(reviewer)
            // When each current request was made: the latest event for that reviewer.
            var requested: [String: Date] = [:]
            for event in nodes(node["requestEvents"]) {
                guard let who = reviewer(event), let at = date(event["createdAt"]) else { continue }
                if requested[who].map({ $0 < at }) ?? true { requested[who] = at }
            }
            thing.reviewRequests = thing.requestedReviewers.compactMap { who in requested[who].map { ThingReviewRequest(reviewer: who, at: $0) } }
            thing.behindBase = node["mergeStateStatus"] as? String == "BEHIND"
            thing.greptileScore = greptileScore(body)
            thing.hasConflicts = node["mergeable"] as? String == "CONFLICTING"
            thing.additions = node["additions"] as? Int
            thing.deletions = node["deletions"] as? Int
            thing.changedFiles = node["changedFiles"] as? Int

            // Each reviewer's latest opinion, and the latest reviews, each once: a review that only comments after an opinion
            // (changes requested, then a follow-up) is a review too. The opinion a reviewer holds is told from them all.
            var reviews: [ThingReview] = []
            let state: (Any?) -> ReviewState? = {
                switch $0 as? String {
                case "APPROVED": .approved
                case "CHANGES_REQUESTED": .changesRequested
                case "COMMENTED": .commented
                case "DISMISSED": .dismissed
                default: nil
                }
            }
            for r in nodes(node["latestOpinionatedReviews"]) {
                guard let id = r["id"] as? String, let s = state(r["state"]), let at = date(r["submittedAt"]) else { continue }
                reviews.append(ThingReview(id: id, author: person(r["author"], association: r["authorAssociation"]), state: s, at: at))
            }
            var reviewIDs = Set(reviews.map(\.id))
            for r in nodes(node["reviews"]) {
                guard let id = r["id"] as? String, let s = state(r["state"]), let at = date(r["submittedAt"]) else { continue }
                let who = person(r["author"], association: r["authorAssociation"])
                let text = r["body"] as? String
                // The review's own words are a comment on the Conversation tab.
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let found = mentions(text)
                    mentioned += found
                    comments.append(ThingComment(id: id, author: who, at: at, snippet: snippet(text), mentions: found, isReview: true))
                }
                if reviewIDs.insert(id).inserted { reviews.append(ThingReview(id: id, author: who, state: s, at: at)) }
            }
            thing.reviews = reviews.sorted { $0.at < $1.at }
            thing.reviewsShape = reviewsShape

            for t in nodes(node["reviewThreads"]) {
                guard let thread = thread(t) else { continue }
                mentioned += thread.mentions
                thing.threads.append(thread.thread)
            }

            let commits = nodes(node["commits"]).compactMap { $0["commit"] as? [String: Any] }
            thing.commits = commits.compactMap { c in
                guard let oid = c["oid"] as? String, let at = date(c["committedDate"]) else { return nil }
                return ThingCommit(id: oid, author: dict(dict(c["author"])?["user"])?["login"] as? String ?? "", at: at)
            }
            thing.checks = commits.last.flatMap { checkState(dict($0["statusCheckRollup"])?["state"]) }
            thing.headSha = commits.last?["oid"] as? String
            if let head = nodes(node["head"]).first.flatMap({ dict($0["commit"]) }),
               let rollup = dict(head["statusCheckRollup"]), let contexts = dict(rollup["contexts"]) {
                let execution = ciExecution(sha: head["oid"] as? String ?? "", contexts: contexts)
                thing.ciRun = execution.run
                thing.ciRunning = execution.running || checkState(rollup["state"]) == .pending
            }
        } else {
            thing.status = node["state"] as? String == "CLOSED" ? .closed : .open
        }
        thing.comments = comments.sorted { $0.at < $1.at }
        var seen = Set<String>()
        thing.mentioned = mentioned.filter { seen.insert($0).inserted }
        return thing
    }

    /// A branch's CI as workflow things: one per workflow (and one for the external checks and statuses, if it has any), each
    /// with its own state and the jobs that failed in it. A workflow that didn't run on the branch's latest commit isn't there.
    static func workflowThings(repo: String, branch: String, status: CIStatus) -> [Thing] {
        status.workflows.map { workflow in
            let at = workflow.updatedAt ?? status.updatedAt ?? status.checkedAt
            var thing = Thing(id: workflowID(repo: repo, workflow: workflow.id, branch: branch), kind: .workflow, repo: repo,
                              number: nil, title: status.title ?? repo,
                              url: workflow.url ?? status.url ?? URL(string: "https://github.com/\(repo)/actions")!,
                              createdAt: at, updatedAt: at)
            thing.workflowName = workflow.name
            thing.branch = branch
            thing.failingJobs = workflow.failing
            thing.ciRun = workflow.run
            thing.ciRunning = workflow.running ?? false
            // Cancelled isn't passing: it counts as failing (as GitHub's rollup has it), and the wait says it was cancelled.
            thing.ciCancelled = workflow.state == .cancelled
            thing.checks = switch workflow.state {
            case .failure, .cancelled: .failing
            case .pending: .pending
            case .success: .passing
            case .none: nil
            }
            return thing
        }
    }

    static func workflowID(repo: String, workflow: String, branch: String) -> String {
        "workflow:\(repo):\(workflow)@\(branch)"
    }

    /// Searches wait while GitHub's GraphQL points are nearly spent, until they come back at the reset. A refresh by hand
    /// tries anyway, and so does one that doesn't know when they come back: its answer says how many there are now.
    static func waitsForPoints(remaining: Int?, resetsAt: Date?, manual: Bool, now: Date = Date()) -> Bool {
        guard let remaining, remaining < 100, !manual, let resetsAt else { return false }
        return now < resetsAt
    }

    /// A fetched thing with the times its requests were made (and its assignees assigned) kept from before, for those still
    /// pending whose event is past the ones fetched: that time is its identity (its facts' keys, what Jev rated), and must
    /// not move.
    static func keepingRequestTimes(_ thing: Thing, from old: Thing?) -> Thing {
        guard let old, thing.kind != .workflow else { return thing }
        var thing = thing
        for who in thing.assignees.map({ $0.lowercased() }) where thing.assignedAt?[who] == nil
            && old.assignees.contains(where: { $0.lowercased() == who }) {
            if let before = old.assignedAt?[who] { thing.assignedAt = (thing.assignedAt ?? [:]).merging([who: before]) { a, _ in a } }
        }
        let known = Set(thing.reviewRequests.map { $0.reviewer.lowercased() })
        for who in thing.requestedReviewers where !known.contains(who.lowercased())
            && old.requestedReviewers.contains(where: { $0.caseInsensitiveCompare(who) == .orderedSame }) {
            if let before = old.reviewRequests.first(where: { $0.reviewer.caseInsensitiveCompare(who) == .orderedSame }) {
                thing.reviewRequests.append(ThingReviewRequest(reviewer: who, at: before.at))
            }
        }
        return thing
    }

    /// A thing your `involves:` search found is marked so (for you): GitHub knows you're involved there even once what
    /// you did is past what is fetched of it (your comment before ten newer ones), and that is kept from now on.
    static func markInvolved(_ thing: inout Thing, foundBy searches: Set<String>, me: String) {
        let qualifier = "involves:" + me.lowercased()
        guard thing.kind != .workflow, !me.isEmpty,
              searches.contains(where: { $0.lowercased().split(separator: " ").contains { $0 == qualifier } }) else { return }
        var signals = InboxEngine.signals(thing, me) ?? ThingSignals(viewer: InboxEngine.viewer(me))
        signals.involved = true
        thing.signals = signals
    }

    /// When a pending review request was made, as its fact's key has it: the thing's creation when GitHub didn't say.
    static func requestTime(_ reviewer: String, of thing: Thing) -> Date {
        thing.reviewRequests.first { $0.reviewer.caseInsensitiveCompare(reviewer) == .orderedSame }?.at ?? thing.createdAt
    }

    /// Whether what an importance rating was for (`InboxEngine.importanceStamp`) is still open on the thing: the review
    /// request made then, or the assignment made then (or any, for one GitHub gave no time for).
    static func isCurrent(stamp: String, of thing: Thing) -> Bool {
        guard thing.kind != .workflow, thing.status == .open || thing.status == .draft else { return false }
        if stamp == "assigned" { return !thing.assignees.isEmpty }
        let parts = stamp.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let at = Int(parts[1]) else { return false }
        switch parts[0] {
        case "requested":
            return thing.kind == .pr && thing.requestedReviewers.contains { Int(requestTime($0, of: thing).timeIntervalSince1970) == at }
        case "assigned":
            let assignees = Set(thing.assignees.map { $0.lowercased() })
            return thing.assignedAt?.contains { assignees.contains($0.key.lowercased()) && Int($0.value.timeIntervalSince1970) == at } ?? false
        default:
            return false
        }
    }

    /// Whether a fact's key is an event the thing still has (a comment, a review, a commit, an unresolved thread's reply, a
    /// pending request by when it was made, Jev's rating of what is still asked of you), rather than a state that comes and goes (checks, a label, a score, conflicts).
    static func isEvent(_ key: String, of thing: Thing) -> Bool {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let id = parts[1]
        switch parts[0] {
        case "comment", "mention", "last", "asks", "noise", "person":
            return thing.comments.contains { $0.id == id } || thing.threads.contains { $0.lastReplyID == id }
        case "review", "approved", "changes":
            return thing.reviews.contains { $0.id == id }
        case "commit":
            return thing.commits.contains { $0.id == id }
        case "thread":
            // Unresolved is part of it: resolved, it is gone, and reopened later it is new again.
            return thing.threads.contains { !$0.isResolved && "\($0.id):\($0.lastReplyID)" == id }
        case "importance":
            // Jev's rating of a request or assignment: kept while that request or assignment is the one asked of you now,
            // so turning his reading off and on again doesn't make it new.
            let stamp = id.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            return isCurrent(stamp: stamp, of: thing)
        case "requested":
            // The request as it is now, who and when: a review then a new request is a new one, the old one gone.
            return thing.requestedReviewers.contains { "\($0.lowercased()):\(Int(requestTime($0, of: thing).timeIntervalSince1970))" == id }
        default:
            return false
        }
    }

    // MARK: - Workflows

    /// Repos an owner's wildcard (`owner/*`, Anyone's at) stands for in a workflow rule, at most.
    static let reposPerOwner = 10

    /// Owners (lowercased) whose repos workflow rules ask for with a wildcard: `ownerRepos` of `workflowTargets`.
    static func workflowOwners(categories: [InboxCategory], groups: [InboxGroup]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for category in categories {
            for rule in category.rules where rule.scope.isWorkflow {
                for ref in rule.scope.in?.include ?? [] {
                    var owners: [String] = []
                    switch ref {
                    case .owner(let owner): owners = [owner]
                    case .group(let id):
                        owners = (groups.first { $0.id == id && $0.kind == .repos }?.members ?? []).filter { $0.hasSuffix("/*") }
                            .map { String($0.dropLast(2)) }
                    default: break
                    }
                    for owner in owners where !owner.isEmpty && seen.insert(owner.lowercased()).inserted { out.append(owner.lowercased()) }
                }
            }
        }
        return out
    }

    /// The names a workflow rule's `on` or `named` gives, without blanks: nil (the default branch, every workflow) when
    /// none is left, which is what an empty slot says.
    static func given(_ names: [String]?) -> [String]? {
        let kept = (names ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept
    }

    /// The repo and branch each workflow rule watches; branches nil is the repo's default. An owner's wildcard is the repos
    /// `ownerRepos` has for it (by owner, lowercased).
    static func workflowTargets(categories: [InboxCategory], groups: [InboxGroup], owned: Set<String>,
                                contributed: Set<String>, ownerRepos: [String: [String]] = [:]) -> [(repo: String, branch: String?)] {
        var out: [(repo: String, branch: String?)] = []
        var seen = Set<String>()
        func members(_ id: UUID) -> [String] { groups.first { $0.id == id && $0.kind == .repos }?.members ?? [] }
        func ownerOf(_ wildcard: String) -> String { String(wildcard.dropLast(2)).lowercased() }
        for category in categories {
            for rule in category.rules where rule.scope.isWorkflow {
                var repos: [String] = []
                for ref in rule.scope.in?.include ?? [] {
                    switch ref {
                    case .repo(let name): repos.append(name)
                    case .group(let id):
                        for member in members(id) {
                            if member.hasSuffix("/*") { repos += ownerRepos[ownerOf(member)] ?? [] } else { repos.append(member) }
                        }
                    case .owned: repos += owned.sorted()
                    case .contributed: repos += contributed.sorted()
                    case .owner(let owner): repos += ownerRepos[owner.lowercased()] ?? []
                    case .involved: break
                    }
                }
                var excluded = Set<String>(), excludedOwners = Set<String>()
                for ref in rule.scope.in?.except ?? [] {
                    switch ref {
                    case .repo(let name): excluded.insert(name.lowercased())
                    case .owner(let owner): excludedOwners.insert(owner.lowercased())
                    case .group(let id):
                        for member in members(id) {
                            if member.hasSuffix("/*") { excludedOwners.insert(ownerOf(member)) } else { excluded.insert(member.lowercased()) }
                        }
                    default: break
                    }
                }
                let branches = given(rule.scope.on).map { $0.map { Optional($0) } } ?? [String?.none]
                for repo in repos where repo.contains("/") && !excluded.contains(repo.lowercased())
                    && !excludedOwners.contains(String(repo.lowercased().prefix { $0 != "/" })) {
                    for branch in branches where seen.insert("\(repo.lowercased())@\(branch ?? "")").inserted {
                        out.append((repo, branch))
                    }
                }
            }
        }
        return out
    }

    /// The targets a refresh checks: all of them, or past `maxWorkflows` a window from `cursor`, so that each gets its turn
    /// over the refreshes. `next` is where the next refresh's window starts.
    static func workflowWindow(_ all: [(repo: String, branch: String?)], cursor: Int)
        -> (targets: [(repo: String, branch: String?)], next: Int) {
        guard all.count > maxWorkflows else { return (all, 0) }
        let start = cursor % all.count
        return ((0..<maxWorkflows).map { all[(start + $0) % all.count] }, (start + maxWorkflows) % all.count)
    }

    /// The key of a workflow target, `repo@branch` lowercased (`repo@` for the default branch).
    static func targetKey(repo: String, branch: String?) -> String { "\(repo.lowercased())@\(branch ?? "")" }

    /// The targets a workflow thing may come from: its branch, and the default one when it is that.
    static func targetKeys(of thing: Thing) -> [String] {
        let branch = thing.branch ?? ""
        return [targetKey(repo: thing.repo, branch: branch)] + (branch == thing.defaultBranch ? [targetKey(repo: thing.repo, branch: nil)] : [])
    }

    /// The repos of each owner (aliased `o0`, `o1`…), most recently pushed first, archived ones left out.
    fileprivate static func ownerReposRequest(_ owners: [String]) -> String {
        let body = owners.enumerated().map { i, owner in
            "o\(i): repositoryOwner(login: \"\(escape(owner))\") { repositories(first: \(reposPerOwner), isArchived: false, orderBy: {field: PUSHED_AT, direction: DESC}) { nodes { nameWithOwner } } }"
        }
        return "query { \(body.joined(separator: "\n")) }"
    }
}

/// What the inbox's refreshes keep between them this session (InboxSync.swift): all of it about the account signed in.
struct InboxSyncState {
    /// Which sign-in this is about: new for each account, so an answer asked for the last one is told apart.
    var account = UUID()
    /// When looking your teams up last failed: asked again after `InboxSync.teamsRetry`, not a day.
    var teamsFailedAt: Date?
    /// Where the next refresh's window of searches starts (`InboxSync.searchPlan`).
    var searchCursor = 0
    /// By thing, the searches that found it: one not found this time stays while a search that found it hasn't run since.
    var foundBy: [String: Set<String>] = [:]
    /// The searches run since launch: until all have, a thing no search is known to have found (kept from the last
    /// session) stays.
    var ranSinceLaunch: Set<String> = []
    /// The repos of owners workflow rules name with a wildcard (by owner, lowercased), and when they were asked.
    var ownerRepos: [String: [String]] = [:]
    var ownerReposAt: [String: Date] = [:]
    /// Where the next refresh's window of workflow targets starts (`InboxSync.workflowWindow`).
    var workflowCursor = 0
}

// MARK: - Repos that moved

extension Store {
    enum RepoLookup: Equatable {
        /// GitHub knows it by this name.
        case same
        /// GitHub redirects it to this canonical name (search doesn't follow redirects).
        case moved(String)
        case missing
        /// Not asked, or no answer (demo, offline, signed out): the name stays as typed.
        case unknown
    }

    func isMissing(_ ref: RepoRef) -> Bool {
        if case .repo(let name) = ref { missingRepos.contains(name.lowercased()) } else { false }
    }

    /// What GitHub calls `owner/name`, asked once a session per name.
    func lookUpRepo(_ name: String) async -> RepoLookup {
        let key = name.lowercased()
        guard !Self.isDemo, key.split(separator: "/").count == 2, !key.hasSuffix("/*") else { return .unknown }
        if missingRepos.contains(key) { return .missing }
        if let known = repoAnswers[key] { return known.lowercased() == key ? .same : .moved(known) }
        do {
            let repo: GHRepo = try await gh.get("/repos/\(name)")
            repoAnswers[key] = repo.fullName
            return repo.fullName.lowercased() == key ? .same : .moved(repo.fullName)
        } catch let error as GitHubError where error.status == 404 {
            missingRepos.insert(key)
            return .missing
        } catch {
            return .unknown
        }
    }

    /// The canonical name when `name` has moved, else nil (a missing repo is marked, see `missingRepos`).
    func canonicalRepo(_ name: String) async -> String? {
        if case .moved(let to) = await lookUpRepo(name) { return to }
        return nil
    }

    /// A safety net for rules saved before this check: the repos they name outright are asked about once per launch, and
    /// renamed in place. Capped, since each is a call.
    func canonicalizeSavedRepos() async {
        guard !repoNamesChecked, !Self.isDemo else { return }
        func explicit(_ pick: Pick<RepoRef>?) -> [String] {
            (pick.map { $0.include + $0.except } ?? []).compactMap { if case .repo(let n) = $0 { n } else { nil } }
        }
        var names: [String] = []
        for category in categories { for rule in category.rules { names += explicit(rule.scope.in) } }
        for group in groups where group.kind == .repos { names += group.members.filter { !$0.hasSuffix("/*") } }
        var seen = Set<String>()
        names = names.filter { seen.insert($0.lowercased()).inserted }.prefix(40).map { $0 }
        var moves: [String: String] = [:]
        var answered = true
        for name in names {
            switch await lookUpRepo(name) {
            case .moved(let to): moves[name] = to
            case .unknown: answered = false
            default: break
            }
        }
        // Offline: asked again with the next sync.
        repoNamesChecked = answered
        guard !moves.isEmpty else { return }
        func rewrite(_ pick: inout Pick<RepoRef>?) {
            guard var p = pick else { return }
            func swap(_ list: inout [RepoRef]) {
                list = list.map { if case .repo(let n) = $0, let to = moves[n] { .repo(to) } else { $0 } }
                var seen = Set<RepoRef>()
                list = list.filter { seen.insert($0).inserted }
            }
            swap(&p.include)
            swap(&p.except)
            pick = p
        }
        var next = categories
        for c in next.indices { for r in next[c].rules.indices { rewrite(&next[c].rules[r].scope.in) } }
        if next != categories { changingInbox(.sync) { categories = next } }
        var nextGroups = groups
        for g in nextGroups.indices where nextGroups[g].kind == .repos {
            var seen = Set<String>()
            nextGroups[g].members = nextGroups[g].members.map { moves[$0] ?? $0 }.filter { seen.insert($0.lowercased()).inserted }
        }
        if nextGroups != groups { changingInbox(.sync) { groups = nextGroups } }
    }
}

// MARK: - The Store's refresh

extension Store {
    /// Refreshes the inbox's things from GitHub, then notifies what is new. Failing leaves the things as they were. `manual`
    /// is a refresh asked for by hand: it searches even when the points looked spent.
    func syncInbox(manual: Bool = false) async {
        guard let me = me?.login else { return }
        // Signed in as someone else, or with other credentials, while it waits (suggestions sign in too): what it was
        // answered is about the last sign-in, and nothing of it is taken, said or acted on.
        let fence = inboxFence
        func current() -> Bool { inboxFence == fence }
        // In the background: the refresh never waits on it.
        if !repoNamesChecked, !repoNamesChecking {
            repoNamesChecking = true
            Task { @MainActor in
                await canonicalizeSavedRepos()
                repoNamesChecking = false
            }
        }
        let needsRepos = InboxSync.needsRepos(categories: categories)
        let needsTeams = InboxSync.needsTeams(categories: categories, jevReads: jevReadsInboxNow)
        // What couldn't be looked up but left what was known: said once the refresh is done.
        var scopeFailure: String?
        if needsTeams, InboxSync.teamsDue(resolvedAt: teamsResolvedAt, failedAt: inboxSyncState.teamsFailedAt) {
            // With no teams known, rules naming My teams would search nothing and empty: the refresh says so and waits.
            let failure = await resolveTeams(me: me)
            guard current() else { return }
            if let failure {
                if myTeams.isEmpty, InboxSync.needsTeams(categories: categories, jevReads: false) {
                    inboxError = "Your teams couldn't be looked up: " + failure
                    return
                }
                scopeFailure = "Your teams couldn't all be looked up: " + failure
            }
        } else if inboxSyncState.teamsFailedAt != nil, myTeams.isEmpty, InboxSync.needsTeams(categories: categories, jevReads: false) {
            return
        }
        if needsRepos, reposResolvedAt.map({ Date().timeIntervalSince($0) > 86400 }) ?? true {
            // A failure leaves what was known; with nothing known, the refresh waits: it would read as "nothing there".
            do { try await resolveRepos(me: me) } catch {
                guard current() else { return }
                // Never looked up whole: a part left empty may be the part that failed.
                let unknown = reposResolvedAt == nil ? ownedRepos.isEmpty || contributedRepos.isEmpty
                    : ownedRepos.isEmpty && contributedRepos.isEmpty
                if unknown { inboxError = error.localizedDescription; return }
                scopeFailure = scopeFailure ?? "Your repos couldn't all be looked up: " + error.localizedDescription
            }
            guard current() else { return }
        }
        let plan = InboxSync.searchPlan(categories: categories, groups: groups, me: me, contributed: contributedRepos,
                                        myTeams: myTeams, cursor: inboxSyncState.searchCursor)
        let searches = plan.searches
        let owners = InboxSync.workflowOwners(categories: categories, groups: groups)
        let ownersFailure = await resolveOwnerRepos(owners)
        guard current() else { return }
        if let failure = ownersFailure {
            scopeFailure = scopeFailure ?? "The repos of an owner couldn't be looked up: " + failure
        }
        // Owners whose repos aren't known (their lookup failed since launch): their workflow things stay as they were.
        let unknownOwners = Set(owners.filter { inboxSyncState.ownerRepos[$0] == nil })
        let allTargets = InboxSync.workflowTargets(categories: categories, groups: groups, owned: ownedRepos,
                                                   contributed: contributedRepos, ownerRepos: inboxSyncState.ownerRepos)
        let window = InboxSync.workflowWindow(allTargets, cursor: inboxSyncState.workflowCursor)
        let targets = window.targets
        guard !searches.isEmpty || !targets.isEmpty || !unknownOwners.isEmpty else {
            // Nothing asked for: every thing is gone, and its marks start their month.
            applyThings([:])
            inboxError = nil
            announceInbox()
            return
        }
        // Out of GraphQL points: the searches wait for the reset rather than fail every poll, and the PRs and issues stay as
        // they were; the workflows, read with REST, are still refreshed.
        let searchesWait = !searches.isEmpty
            && InboxSync.waitsForPoints(remaining: gh.graphqlRemaining, resetsAt: gh.graphqlResetsAt, manual: manual)
        if searchesWait, targets.isEmpty { return }
        // Room for every target's answers, not only this refresh's window: those asked a turn ago are 304s when their turn
        // comes again.
        gh.reserveETags(forRepositories: allTargets.count)

        var found: [String: Thing] = [:]
        var searchFailure: String?
        var fetched = Fetched()
        if !searches.isEmpty, !searchesWait {
            do {
                fetched = try await fetchThings(searches)
                for thing in fetched.things {
                    var thing = InboxSync.keepingRequestTimes(thing, from: things[thing.id])
                    InboxSync.markInvolved(&thing, foundBy: fetched.foundBy[thing.id] ?? [], me: me)
                    found[thing.id] = thing
                }
            } catch {
                searchFailure = error.localizedDescription
            }
            guard current() else { return }
        }
        // Workflows: a repo that can't be read keeps the things it had.
        var workflowFailure: String?
        var failedRepos = Set<String>()
        var workflows: [String: Thing] = [:]
        await withTaskGroup(of: (repo: String, things: [Thing], error: String?).self) { group in
            var queue = targets.makeIterator()
            func add(_ target: (repo: String, branch: String?)) {
                group.addTask { @MainActor in
                    do { return (target.repo, try await self.workflowThings(target.repo, target.branch), nil) } catch {
                        return (target.repo, [], error.localizedDescription)
                    }
                }
            }
            for _ in 0..<4 { if let t = queue.next() { add(t) } }
            while let done = await group.next() {
                for thing in done.things { workflows[thing.id] = thing }
                if let error = done.error {
                    workflowFailure = workflowFailure ?? error
                    failedRepos.insert(done.repo)
                }
                if let t = queue.next() { add(t) }
            }
        }
        guard current() else { return }
        // Each workflow thing says its repo's default branch, as its default target found it (or as known from before).
        var defaults: [String: String] = [:]
        for thing in workflows.values { if let main = thing.defaultBranch { defaults[thing.repo.lowercased()] = main } }
        for (id, thing) in workflows where thing.defaultBranch == nil {
            workflows[id]?.defaultBranch = defaults[thing.repo.lowercased()] ?? defaultBranches[thing.repo]
        }
        inboxError = searchFailure ?? fetched.error ?? workflowFailure ?? scopeFailure
        // A search that failed can't say what is gone: the PRs and issues stay as they were, as when the points are spent,
        // and the workflows read are still taken.
        let searchesKept = searchesWait || searchFailure != nil
        var next = found
        if searchesKept {
            for (id, old) in things where old.kind != .workflow { next[id] = old }
        } else {
            inboxSyncState.searchCursor = plan.next
        }
        // Nor can an answer GitHub gave in part: what it left out stays, and so does a thing it gave without some of its
        // parts (its comments, its threads), which would otherwise lose facts and announce them again when they come back.
        if fetched.error != nil {
            for (id, old) in things where old.kind != .workflow && (next[id] == nil || fetched.partial.contains(id)) {
                next[id] = old
            }
        }
        // Past the cap the searches take turns: what those not run this time found stays until they run. One GitHub didn't
        // answer whole hasn't run: what it found stays, and is still its own, until it does.
        if !searchesKept {
            let ran = searches.filter { !fetched.failed.contains($0) }
            next.merge(keepingUnvisited(fetched, ran: ran, all: plan.all)) { a, _ in a }
        }
        for (id, thing) in workflows { next[id] = thing }
        if !failedRepos.isEmpty {
            let kept = things.filter { $0.value.kind == .workflow && failedRepos.contains($0.value.repo) && next[$0.key] == nil }
            next.merge(kept) { a, _ in a }
        }
        if !unknownOwners.isEmpty {
            let kept = things.filter { $0.value.kind == .workflow && next[$0.key] == nil
                && unknownOwners.contains(String($0.value.repo.lowercased().prefix { $0 != "/" })) }
            next.merge(kept) { a, _ in a }
        }
        // Past the cap the workflow targets take turns: those not checked this time keep their things until their turn.
        if targets.count < allTargets.count {
            let visited = Set(targets.map { InboxSync.targetKey(repo: $0.repo, branch: $0.branch) })
            let waiting = Set(allTargets.map { InboxSync.targetKey(repo: $0.repo, branch: $0.branch) }).subtracting(visited)
            func waits(_ thing: Thing) -> Bool {
                let keys = InboxSync.targetKeys(of: thing)
                return !keys.contains(where: visited.contains) && keys.contains(where: waiting.contains)
            }
            let kept = things.filter { $0.value.kind == .workflow && next[$0.key] == nil && waits($0.value) }
            next.merge(kept) { a, _ in a }
        }
        inboxSyncState.workflowCursor = window.next
        applyThings(next)
        await readInbox()
        guard current() else { return }
        announceInbox()
    }

    /// What searches brought: the things, those GitHub gave only in part (an error inside them), and the first error it
    /// said, if any.
    struct Fetched {
        var things: [Thing] = []
        var partial: Set<String> = []
        var error: String?
        /// By thing, the searches that returned it.
        var foundBy: [String: Set<String>] = [:]
        /// The searches GitHub didn't answer whole (a page of one null, a node of it it couldn't give): they haven't run.
        var failed: Set<String> = []
    }

    /// Searches, a page at a time for those with more, until the caps: what a round asks for is shared out of the things
    /// left before it is asked, so a refresh never takes in more than `maxThings`. An answer with no data at all throws;
    /// one with data and errors (a node GitHub couldn't give, a part of one) is taken for what it has, and says so.
    func fetchThings(_ searches: [String]) async throws -> Fetched {
        var found: [String: Thing] = [:]
        var partial = Set<String>()
        var error: String?
        var foundBy: [String: Set<String>] = [:]
        var failed = Set<String>()
        // PRs with more review threads than came with them: read on before they are taken, unless what was read of them
        // before stands (`keepsTail`).
        var moreThreads: [String: (node: String, cursor: String, total: Int)] = [:]
        let now = Date()
        var cursors: [Int: String?] = Dictionary(uniqueKeysWithValues: searches.indices.map { ($0, String?.none) })
        var pages = 0
        while !cursors.isEmpty, pages < InboxSync.maxPages, found.count < InboxSync.maxThings {
            pages += 1
            var next: [Int: String?] = [:]
            let left = InboxSync.maxThings - found.count
            // More searches than things left: the first of them, one each.
            let active = Array(cursors.keys.sorted().prefix(left))
            let first = InboxSync.pageSizes(searches: active.count, budget: left)
            for start in stride(from: 0, to: active.count, by: InboxSync.searchesPerRequest) {
                let batch = active[start..<min(start + InboxSync.searchesPerRequest, active.count)]
                let json = try await gh.graphql(InboxSync.request(batch.map { ("s\($0)", searches[$0], cursors[$0] ?? nil) }, first: first))
                let errors = (json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
                guard let data = json["data"] as? [String: Any] else {
                    throw GitHubError(message: (errors.first?["message"] as? String) ?? "GitHub gave no answer")
                }
                if let first = errors.first { error = error ?? (first["message"] as? String) ?? "GitHub gave part of an answer" }
                // `["s0", "nodes", 3, "comments", …]`: the fourth thing of search 0 came without some of its parts.
                var broken = Set<[String]>()
                // `["s0"]` or `["s0", "nodes", 3]`: search 0, or its fourth thing, didn't come at all.
                var missing = Set<String>()
                for e in errors {
                    guard let path = e["path"] as? [Any], let alias = path.first as? String else { continue }
                    guard path.count > 3, let index = path[2] as? Int else { missing.insert(alias); continue }
                    broken.insert([alias, String(index)])
                }
                for i in batch {
                    if missing.contains("s\(i)") { failed.insert(searches[i]) }
                    guard let result = data["s\(i)"] as? [String: Any] else { failed.insert(searches[i]); continue }
                    // A node GitHub couldn't give is null: the others are still things.
                    for (n, value) in ((result["nodes"] as? [Any]) ?? []).enumerated() {
                        guard let node = value as? [String: Any], var thing = InboxSync.thing(node) else { continue }
                        foundBy[thing.id, default: []].insert(searches[i])
                        moreThreads[thing.id] = nil
                        if let more = InboxSync.moreThreads(node) {
                            if let old = things[thing.id], InboxSync.keepsTail(old, total: more.total, updatedAt: thing.updatedAt,
                                                                              now: now, remaining: gh.graphqlRemaining) {
                                InboxSync.takeTail(of: old, into: &thing)
                            } else {
                                moreThreads[thing.id] = more
                            }
                        }
                        // Given whole by another search, it is whole.
                        if broken.contains(["s\(i)", String(n)]) {
                            if found[thing.id] == nil { partial.insert(thing.id); found[thing.id] = thing }
                        } else {
                            partial.remove(thing.id)
                            found[thing.id] = thing
                        }
                    }
                    let info = result["pageInfo"] as? [String: Any]
                    if info?["hasNextPage"] as? Bool == true, let end = info?["endCursor"] as? String { next[i] = end }
                }
            }
            cursors = next
        }
        // The rest of their review threads, a page at a time up to the cap: an unresolved one past the first page is there.
        // One that can't be read is a thing given in part.
        var read: [String: Int] = moreThreads.mapValues { _ in InboxSync.threadsFirst }
        var tailMentions: [String: [String]] = [:]
        while !moreThreads.isEmpty {
            let ids = moreThreads.keys.sorted()
            var next: [String: (node: String, cursor: String, total: Int)] = [:]
            for start in stride(from: 0, to: ids.count, by: InboxSync.threadPRsPerRequest) {
                let batch = Array(ids[start..<min(start + InboxSync.threadPRsPerRequest, ids.count)])
                let pages = batch.enumerated().map { p in
                    let more = moreThreads[p.element]!
                    return ("p\(p.offset)", more.node, more.cursor, InboxSync.threadsPageSize(read: read[p.element] ?? 0, total: more.total))
                }
                var json: [String: Any] = [:]
                do { json = try await gh.graphql(InboxSync.threadsRequest(pages)) } catch let failure {
                    json = ["errors": [["message": failure.localizedDescription]]]
                }
                let errors = (json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
                let data = json["data"] as? [String: Any]
                for (n, id) in batch.enumerated() {
                    let alias = "p\(n)"
                    let failedHere = errors.contains { e in ((e["path"] as? [Any])?.first as? String).map { $0 == alias } ?? true }
                    guard !failedHere, let connection = (data?[alias] as? [String: Any])?["reviewThreads"] else {
                        error = error ?? (errors.first?["message"] as? String) ?? "GitHub gave part of an answer"
                        partial.insert(id)
                        continue
                    }
                    if found[id] != nil { tailMentions[id, default: []] += InboxSync.addThreads(connection, to: &found[id]!) }
                    read[id, default: 0] += pages[n].3
                    if let cursor = InboxSync.nextPage(connection), read[id, default: 0] < InboxSync.maxThreads {
                        next[id] = (moreThreads[id]!.node, cursor, moreThreads[id]!.total)
                    } else if found[id] != nil, !partial.contains(id) {
                        // Read to its end (or the cap): what it was read for.
                        found[id]!.threadsTail = ThreadsTail(total: moreThreads[id]!.total, updatedAt: found[id]!.updatedAt, readAt: now,
                                                             mentions: tailMentions[id] ?? [])
                    }
                }
            }
            moreThreads = next
        }
        return Fetched(things: Array(found.values), partial: partial, error: error, foundBy: foundBy, failed: failed)
    }

    /// Notes which searches found what, and gives back the things this refresh didn't find that a search it didn't run
    /// may still find: one that found it before, or, for a thing kept from before launch, any not yet run since.
    func keepingUnvisited(_ fetched: Fetched, ran: [String], all: Set<String>) -> [String: Thing] {
        var state = inboxSyncState
        let ran = Set(ran)
        state.ranSinceLaunch = state.ranSinceLaunch.union(ran).intersection(all)
        var kept: [String: Thing] = [:]
        var foundBy: [String: Set<String>] = [:]
        for (id, thing) in things where thing.kind != .workflow && fetched.foundBy[id] == nil {
            if let before = state.foundBy[id] {
                let maybe = before.intersection(all).subtracting(ran)
                if !maybe.isEmpty { kept[id] = thing; foundBy[id] = maybe }
            } else if !all.isSubset(of: state.ranSinceLaunch) {
                kept[id] = thing
            }
        }
        for (id, by) in fetched.foundBy {
            foundBy[id] = (state.foundBy[id] ?? []).intersection(all).subtracting(ran).union(by)
        }
        state.foundBy = foundBy
        inboxSyncState = state
        return kept
    }

    private func workflowThings(_ repo: String, _ requested: String?) async throws -> [Thing] {
        let status: CIStatus
        let branch: String
        if let requested {
            branch = requested
            status = try await fetchBranchCI(repo, branch: requested)
        } else {
            status = try await fetchCI(repo)
            branch = status.branch
        }
        var things = InboxSync.workflowThings(repo: repo, branch: branch, status: status)
        if requested == nil { for i in things.indices { things[i].defaultBranch = branch } }
        return things
    }

    /// Replaces the things in one assignment, keeping what Jev said of them, and forgets marks of things gone for a month.
    func applyThings(_ next: [String: Thing], now: Date = Date()) {
        var next = next
        let me = inboxContext.me
        for id in next.keys { InboxJev.carry(things[id]?.signals, into: &next[id]!, me: me) }
        // Read for the first time as this build reads reviews: those it had all along and that come back now are old (those
        // it was read with already were never left out). It had them by the time it was last read (when it was last updated then, or its newest review): one made after,
        // while Lookout was closed, is new.
        var restored = actionLedger.restoredReviewIDs ?? [:]
        for (id, thing) in next where thing.kind == .pr && thing.reviewsShape != nil {
            guard let stored = things[id], stored.reviewsShape == nil else { continue }
            let cutoff = max(stored.updatedAt, stored.reviews.map(\.at).max() ?? .distantPast)
            let had = Set(stored.reviews.map(\.id))
            let old = thing.reviews.filter { $0.at <= cutoff && !had.contains($0.id) }.map(\.id)
            if !old.isEmpty { restored[id, default: []].formUnion(old) }
        }
        if !restored.isEmpty, restored != actionLedger.restoredReviewIDs { actionLedger.restoredReviewIDs = restored }
        if next != things { things = next }
        // When each thing went missing is kept in its marks (and so across restarts).
        var kept = marks
        for (id, m) in marks {
            if next[id] != nil {
                if m.goneSince != nil { kept[id]?.goneSince = nil }
            } else if let since = m.goneSince {
                if now.timeIntervalSince(since) > Double(InboxSync.marksDays) * 86400 { kept[id] = nil }
            } else {
                kept[id]?.goneSince = now
            }
        }
        if kept != marks { marks = kept }
    }

    /// Signed in as someone else: the last account's repos, teams and what was asked about them go, and are asked again.
    func forgetAccountCaches() {
        ownedRepos = []
        contributedRepos = []
        myTeams = []
        reposResolvedAt = nil
        teamsResolvedAt = nil
        missingRepos = []
        repoAnswers = [:]
        inboxSyncState = InboxSyncState()
    }

    /// Which sign-in (`InboxSyncState.account`), with which credentials, the inbox's refresh is asking about: an answer
    /// asked for under another is dropped.
    struct InboxFence: Equatable {
        let account: UUID
        let credentials: Int
    }

    var inboxFence: InboxFence { InboxFence(account: inboxSyncState.account, credentials: credentialsChanged) }

    /// Whether `me` is still who is signed in (or no one is known yet): an answer about someone else is dropped.
    private func stillSignedIn(as me: String) -> Bool {
        let current = self.me?.login ?? login
        return current.isEmpty || current.caseInsensitiveCompare(me) == .orderedSame
    }

    /// The repos you own and those you merged a PR in. Kept for a day.
    func resolveRepos(me: String) async throws {
        let fence = inboxFence
        let json = try await gh.graphql(InboxSync.reposRequest(me: me))
        guard inboxFence == fence else { return }
        guard let data = json["data"] as? [String: Any] else {
            throw GitHubError(message: ((json["errors"] as? [[String: Any]])?.first?["message"] as? String) ?? "GitHub gave no answer")
        }
        func names(_ nodes: Any?, _ path: (([String: Any]) -> String?)) -> Set<String> {
            Set(((nodes as? [[String: Any]]) ?? []).compactMap(path))
        }
        guard stillSignedIn(as: me) else { return }
        // An answer in part (`viewer.repositories` null, with an error): what came is taken, what didn't stays as it was,
        // and it is asked again with the next refresh rather than in a day.
        let errors = (json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        let failed = { (part: String) in errors.contains { ($0["path"] as? [Any])?.first as? String == part } }
        let viewer = data["viewer"] as? [String: Any]
        if let repos = viewer?["repositories"] as? [String: Any], !failed("viewer") {
            let owned = names(repos["nodes"]) { $0["nameWithOwner"] as? String }
            if owned != ownedRepos { ownedRepos = owned }
        }
        // A merged or an open PR of yours makes it a repo you contribute to.
        let repoName: ([String: Any]) -> String? = { ($0["repository"] as? [String: Any])?["nameWithOwner"] as? String }
        let merged = names((data["merged"] as? [String: Any])?["nodes"], repoName)
            .union(names((data["open"] as? [String: Any])?["nodes"], repoName))
        // Only grows: an older merge isn't forgotten because newer ones fill the page.
        let all = contributedRepos.union(merged)
        if all != contributedRepos { contributedRepos = all }
        let parts = [viewer?["repositories"], data["merged"], data["open"]]
        if let error = errors.first ?? (parts.contains { !($0 is [String: Any]) } ? [:] : nil) {
            throw GitHubError(message: (error["message"] as? String) ?? "GitHub gave part of an answer")
        }
        reposResolvedAt = Date()
    }

    /// The repos of owners workflow rules name with a wildcard, asked once a day per owner. A failure (the whole answer, or
    /// an owner's part of it) leaves what was known for that owner and is asked again with the next refresh; an owner GitHub
    /// doesn't know has none. What went wrong, if it did.
    @discardableResult
    func resolveOwnerRepos(_ owners: [String], now: Date = Date()) async -> String? {
        let due = owners.filter { owner in inboxSyncState.ownerReposAt[owner].map { now.timeIntervalSince($0) > 86400 } ?? true }
        guard !due.isEmpty else { return nil }
        let fence = inboxFence
        let json: [String: Any]
        do { json = try await gh.graphql(InboxSync.ownerReposRequest(due)) } catch {
            return inboxFence == fence ? error.localizedDescription : nil
        }
        // Asked for an account signed out since: not taken.
        guard inboxFence == fence else { return nil }
        let errors = (json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        guard let data = json["data"] as? [String: Any] else {
            return (errors.first?["message"] as? String) ?? "GitHub gave no answer"
        }
        var failure: String?
        for (i, owner) in due.enumerated() {
            let alias = "o\(i)"
            let error = errors.first { ($0["path"] as? [Any])?.first as? String == alias }
            let result = data[alias] as? [String: Any]
            if let repos = (result?["repositories"] as? [String: Any])?["nodes"] as? [Any], error == nil {
                inboxSyncState.ownerRepos[owner] = repos.compactMap { ($0 as? [String: Any])?["nameWithOwner"] as? String }
            } else if result == nil, error == nil || error?["type"] as? String == "NOT_FOUND" {
                // No such owner: none.
                inboxSyncState.ownerRepos[owner] = []
            } else {
                failure = failure ?? (error?["message"] as? String) ?? "GitHub gave part of an answer"
                continue
            }
            inboxSyncState.ownerReposAt[owner] = now
        }
        return failure
    }

    /// The teams you're in, asked again in a day. A failure (offline, GitHub's trouble) leaves what was known and is asked
    /// again sooner (`InboxSync.teamsRetry`); without read:org GitHub answers with none, which is an answer. What went wrong,
    /// if it did.
    @discardableResult
    func resolveTeams(me: String) async -> String? {
        let fence = inboxFence
        let json: [String: Any]
        do { json = try await gh.graphql(InboxSync.teamsRequest(me: me)) } catch {
            // Asked for an account signed out since: its failure isn't the new one's to wait on.
            guard inboxFence == fence else { return nil }
            inboxSyncState.teamsFailedAt = Date()
            return error.localizedDescription
        }
        guard inboxFence == fence else { return nil }
        guard let data = json["data"] as? [String: Any] else {
            inboxSyncState.teamsFailedAt = Date()
            return ((json["errors"] as? [[String: Any]])?.first?["message"] as? String) ?? "GitHub gave no answer"
        }
        guard stillSignedIn(as: me) else { return nil }
        let teams = InboxSync.teams(data)
        // An answer in part (an organization that couldn't say its teams): what came is added to what was known, and the
        // rest is asked again soon. Missing read:org is an answer (none), not a failure.
        let errors = ((json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [])
            .filter { $0["type"] as? String != "INSUFFICIENT_SCOPES" }
        if let error = errors.first {
            inboxSyncState.teamsFailedAt = Date()
            let all = myTeams.union(teams)
            if all != myTeams { myTeams = all }
            return (error["message"] as? String) ?? "GitHub gave part of an answer"
        }
        teamsResolvedAt = Date()
        inboxSyncState.teamsFailedAt = nil
        if teams != myTeams { myTeams = teams }
        return nil
    }

    // MARK: Notifications

    /// For each open entry, the facts not seen before: one notification per entry, once per fact. A category's first
    /// evaluation (and any with rules it hasn't seen) is a baseline: what is there is noted, not announced. A state that
    /// goes away (checks failing, a label) is forgotten, so it announces again if it comes back; an event (a comment, a
    /// review) is kept while the thing still has it, so a rule that stops matching for a while doesn't announce it twice.
    func announceInbox() {
        defer { scheduleActions() }
        let all = entries
        var updated = marks
        var baselines = categoryBaselines
        var posts: [(category: InboxCategory, entry: InboxEntry, fresh: [Fact])] = []
        let context = inboxContext
        // Jev reads at each refresh: a banner for a message it hasn't read yet waits for it, a refresh or two at most.
        let jevReads = jevReadsInboxNow && jevGate.isOpen(for: typesafeKey ?? "")
        var waits: [String: Int] = [:]
        let byThing = Dictionary(all.map { ($0.thing.id, $0) }, uniquingKeysWith: { a, _ in a })
        for category in categories {
            let ruleIDs = Set(category.rules.map(\.id))
            let baseline = baselines[category.id] != ruleIDs
            let silent = baseline || category.hidden || !category.notifies
            for entry in all where entry.categoryID == category.id {
                var m = updated[entry.id] ?? EntryMarks()
                var fresh = entry.facts.filter { !m.notified.contains($0.key) }
                if jevReads, !silent, !entry.isDone {
                    fresh = fresh.filter { fact in
                        let key = entry.thing.id + "|" + fact.key
                        let waited = inboxBannerWaits[key] ?? 0
                        guard waited < InboxJev.bannerWaits, !InboxJev.isQuiet(fact, entry.thing, context: context),
                              InboxJev.awaitsReading(fact, entry.thing, context: context) else { return true }
                        waits[key] = waited + 1
                        return false
                    }
                }
                guard !fresh.isEmpty else { continue }
                m.notified.formUnion(fresh.map(\.key))
                updated[entry.id] = m
                // Noise is noted, never announced.
                let loud = fresh.filter { !InboxJev.isQuiet($0, entry.thing, context: context) }
                if !silent, !entry.isDone, !loud.isEmpty { posts.append((category, entry, loud)) }
            }
            if baseline { baselines[category.id] = ruleIDs }
        }
        // Facts that are gone: forgotten, for a thing that is still fetched (events only once the thing no longer has them),
        // whether notified, acknowledged or seen.
        for (id, thing) in things {
            guard var m = updated[id], !m.notified.isEmpty || !m.acked.isEmpty || !m.seen.isEmpty else { continue }
            let current = Set(byThing[id]?.facts.map(\.key) ?? [])
            let kept = { (key: String) in current.contains(key) || InboxSync.isEvent(key, of: thing) }
            let notified = m.notified.filter(kept), acked = m.acked.filter(kept), seen = m.seen.filter(kept)
            if notified != m.notified || acked != m.acked || seen != m.seen {
                m.notified = notified
                m.acked = acked
                m.seen = seen
                updated[id] = m
            }
        }
        inboxBannerWaits = waits
        // A deleted category's baseline goes with it.
        baselines = baselines.filter { id, _ in categories.contains { $0.id == id } }
        if baselines != categoryBaselines { categoryBaselines = baselines }
        if updated != marks { marks = updated }
        // Away, each post goes by Jev's rating as its own banner would (RouterAttention.swift), before any batch is made:
        // the rest is counted for when you're back, and a batch is only of what may interrupt you.
        if settings.notifications, !isSnoozed {
            posts = posts.filter { routerAttention.admitInbox(InboxEngine.importance(things[$0.entry.thing.id] ?? $0.entry.thing, context: context)) }
        }
        guard !posts.isEmpty else { return }
        if posts.count > 4 {
            let names = Set(posts.map(\.category.title)).sorted()
            notify(id: Notifier.summaryPrefix + UUID().uuidString, title: "\(posts.count) new in your inbox",
                   subtitle: names.joined(separator: ", "), body: "", quiet: false)
            return
        }
        for post in posts {
            let thing = post.entry.thing
            let name = thing.number.map { "\(thing.repo)#\($0)" } ?? "\(thing.repo) · \(thing.branch ?? "")"
            notify(id: Self.inboxNotificationPrefix + thing.id, title: "\(post.category.title) · \(name)", subtitle: thing.title,
                   body: post.fresh.map(\.label).joined(separator: " · "), quiet: false, url: thing.url)
        }
    }
}

// MARK: - Dev only

/// `--check-inbox`: one real sync with sample categories (read-only; nothing saved, nothing announced), prints every entry.
@MainActor
enum InboxCheck {
    static func run(store: Store) {
        store.persists = false
        store.stateFile = FileManager.default.temporaryDirectory.appendingPathComponent("lookout-check-\(UUID().uuidString).json")
        Task {
            await store.authenticate()
            print("auth:", store.me?.login ?? "nil", store.authError ?? "")
            let repos = Pick<RepoRef>(include: [.repo("superradcompany/microsandbox"), .repo("libkrun/libkrun")])
            let bots = PersonRef.user("greptile-apps[bot]")
            let both = Pick<PersonRef>(include: [.maintainers, bots])
            let mine = Pick<PersonRef>(include: [.me])
            let scope = Scope(kinds: [.pr], by: mine, in: repos)
            let past = Date.distantPast
            store.categories = [
                InboxCategory(name: "Contributions", symbol: "arrow.triangle.pull", color: .violet, rules: [
                    Rule(scope: scope, match: .any, conditions: [
                        .lastComment(by: both),
                        .unresolvedThreads(startedBy: both, lastReplyBy: Pick(except: [.me])),
                        .changesRequested(by: Pick(include: [.maintainers])),
                        .greptileBelow(5),
                    ], createdAt: past),
                    Rule(scope: scope, conditions: [.status([.merged])], createdAt: past),
                ]),
                InboxCategory(name: "All mine", symbol: "list.bullet", color: .blue, rules: [Rule(scope: scope, createdAt: past)]),
                InboxCategory(name: "CI", symbol: "xmark.seal", color: .red, rules: [
                    Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("amontlabs/lcu"), .repo("0xpolarzero/lookout")])),
                         conditions: [.workflow([.failing])], createdAt: past),
                ]),
                InboxCategory(name: "Probe", symbol: "magnifyingglass", color: .gray, rules: [
                    Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.involved])), conditions: [
                        .lastComment(by: Pick()), .unresolvedThreads(startedBy: nil, lastReplyBy: nil),
                        .changesRequested(by: Pick()), .approved(by: Pick()), .greptileBelow(6),
                    ], createdAt: past),
                ]),
                InboxCategory(name: "Reviews for you", symbol: "eye", color: .green, rules: [
                    Rule(scope: Scope(kinds: [.pr], to: mine, toRoles: [.reviewRequested], in: Pick(include: [.involved])), createdAt: past),
                ]),
            ]
            let before = store.gh.graphqlRemaining
            await store.syncInbox()
            print("error:", store.inboxError ?? "none", "things:", store.things.count)
            for category in store.categories {
                print("== \(category.name)")
                for e in store.entries.filter({ $0.categoryID == category.id }).sorted(by: { $0.thing.updatedAt > $1.thing.updatedAt }) {
                    print(e.id, "|", e.thing.title.prefix(60), "| labels:", e.thing.labels.joined(separator: ","), "| facts:",
                          e.facts.map { "\($0.label) {\($0.key)}" }.joined(separator: " · "))
                }
            }
            print("graphql before/after:", before ?? -1, store.gh.graphqlRemaining ?? -1, "rest:", store.gh.rateRemaining ?? -1)
            exit(0)
        }
    }
}
