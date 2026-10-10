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
    /// Searches a refresh makes at most, shared out a turn at a time between the rules so that none goes without.
    static let maxSearches = 16
    /// Workflow things a refresh checks at most.
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
        var out: [String] = []
        var seen = Set<String>()
        var turn = 0
        while out.count < maxSearches, perRule.contains(where: { turn < $0.count }) {
            for queries in perRule where turn < queries.count && out.count < maxSearches {
                if seen.insert(queries[turn]).inserted { out.append(queries[turn]) }
            }
            turn += 1
        }
        return out
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

    /// Whether a refresh needs the teams you're in: a rule names `My teams`, or Jev rates review requests, those to a team of
    /// yours among them.
    static func needsTeams(categories: [InboxCategory], jevReads: Bool) -> Bool {
        jevReads || categories.contains { $0.rules.contains { $0.scope.to?.include.contains(.myTeams) == true } }
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

    static let fragments = """
    fragment C on Comment { id createdAt body authorAssociation author { \(personNode) } }
    fragment P on PullRequest {
      id number title url isDraft state merged createdAt updatedAt body mergeable mergeStateStatus additions deletions changedFiles
      repository { nameWithOwner }
      \(person)
      labels(first: 10) { nodes { name } }
      assignees(first: 5) { nodes { login } }
      reviewRequests(first: 5) { nodes { requestedReviewer { ... on User { login } ... on Team { combinedSlug } } } }
      requestEvents: timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 5) { nodes { ... on ReviewRequestedEvent {
        createdAt requestedReviewer { ... on User { login } ... on Team { combinedSlug } } } } }
      comments(last: 10) { nodes { ...C } }
      latestOpinionatedReviews(first: 10) { nodes { id state submittedAt body authorAssociation author { \(personNode) } } }
      reviews(last: 10) { nodes { id state submittedAt body authorAssociation author { \(personNode) } } }
      reviewThreads(first: 20) { nodes { id isResolved path
        first: comments(first: 1) { nodes { id createdAt body author { \(personNode) } authorAssociation } }
        last: comments(last: 1) { nodes { id createdAt body author { \(personNode) } authorAssociation } } } }
      commits(last: 5) { nodes { commit { oid committedDate author { user { login } } statusCheckRollup { state } } } }
    }
    fragment I on Issue {
      id number title url state createdAt updatedAt body
      repository { nameWithOwner }
      \(person)
      labels(first: 10) { nodes { name } }
      assignees(first: 5) { nodes { login } }
      comments(last: 10) { nodes { ...C } }
    }
    """

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A request for several searches, each from its own cursor.
    fileprivate static func request(_ searches: [(alias: String, query: String, cursor: String?)]) -> String {
        let body = searches.map { s in
            let after = s.cursor.map { ", after: \"\(escape($0))\"" } ?? ""
            return """
            \(s.alias): search(query: "\(escape(s.query))", type: ISSUE, first: \(pageSize)\(after)) {
              pageInfo { hasNextPage endCursor }
              nodes { __typename ...P ...I }
            }
            """
        }
        return "query { rateLimit { cost remaining resetAt } \(body.joined(separator: "\n")) }\n" + fragments
    }

    /// The repos you own and have merged or open PRs in.
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

            // Each reviewer's latest opinion; a review that only commented stands for reviewers with no opinion.
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
            let opinionated = Set(reviews.map { $0.author.login.lowercased() })
            var latestOther: [String: ThingReview] = [:]
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
                let key = who.login.lowercased()
                if !opinionated.contains(key), latestOther[key].map({ $0.at < at }) ?? true {
                    latestOther[key] = ThingReview(id: id, author: who, state: s, at: at)
                }
            }
            reviews += latestOther.values.sorted { $0.at < $1.at }
            thing.reviews = reviews

            for t in nodes(node["reviewThreads"]) {
                guard let id = t["id"] as? String, let first = nodes(t["first"]).first, let last = nodes(t["last"]).first,
                      let lastID = last["id"] as? String, let at = date(last["createdAt"]) else { continue }
                mentioned += mentions(last["body"] as? String)
                thing.threads.append(ThingThread(
                    id: id, isResolved: t["isResolved"] as? Bool ?? false,
                    startedBy: person(first["author"], association: first["authorAssociation"]),
                    lastReplyBy: person(last["author"], association: last["authorAssociation"]), lastReplyID: lastID,
                    lastReplyAt: at, path: t["path"] as? String, snippet: snippet(last["body"] as? String)))
            }

            let commits = nodes(node["commits"]).compactMap { $0["commit"] as? [String: Any] }
            thing.commits = commits.compactMap { c in
                guard let oid = c["oid"] as? String, let at = date(c["committedDate"]) else { return nil }
                return ThingCommit(id: oid, author: dict(dict(c["author"])?["user"])?["login"] as? String ?? "", at: at)
            }
            thing.checks = commits.last.flatMap { checkState(dict($0["statusCheckRollup"])?["state"]) }
            thing.headSha = commits.last?["oid"] as? String
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
            thing.checks = switch workflow.state {
            case .failure: .failing
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

    /// Whether a fact's key is an event the thing still has (a comment, a review, a commit, a thread's reply, a pending
    /// request by when it was made), rather than a state that comes and goes (checks, a label, a score, conflicts).
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
            return thing.threads.contains { "\($0.id):\($0.lastReplyID)" == id }
        case "requested":
            return thing.requestedReviewers.contains { id.hasPrefix($0.lowercased() + ":") }
        default:
            return false
        }
    }

    // MARK: - Workflows

    /// The repo and branch each workflow rule watches; branches nil is the repo's default.
    static func workflowTargets(categories: [InboxCategory], groups: [InboxGroup], owned: Set<String>,
                                contributed: Set<String>) -> [(repo: String, branch: String?)] {
        var out: [(repo: String, branch: String?)] = []
        var seen = Set<String>()
        for category in categories {
            for rule in category.rules where rule.scope.isWorkflow {
                var repos: [String] = []
                for ref in rule.scope.in?.include ?? [] {
                    switch ref {
                    case .repo(let name): repos.append(name)
                    case .group(let id): repos += (groups.first { $0.id == id && $0.kind == .repos }?.members ?? []).filter { !$0.hasSuffix("/*") }
                    case .owned: repos += owned.sorted()
                    case .contributed: repos += contributed.sorted()
                    case .owner, .involved: break
                    }
                }
                let excluded = Set((rule.scope.in?.except ?? []).compactMap { ref -> String? in
                    if case .repo(let name) = ref { return name.lowercased() }
                    return nil
                })
                for repo in repos where repo.contains("/") && !excluded.contains(repo.lowercased()) {
                    for branch in (rule.scope.on.map { $0.map { Optional($0) } } ?? [String?.none]) where seen.insert("\(repo.lowercased())@\(branch ?? "")").inserted {
                        out.append((repo, branch))
                    }
                }
            }
        }
        return Array(out.prefix(maxWorkflows))
    }
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
        // In the background: the refresh never waits on it.
        if !repoNamesChecked, !repoNamesChecking {
            repoNamesChecking = true
            Task { @MainActor in
                await canonicalizeSavedRepos()
                repoNamesChecking = false
            }
        }
        let needsRepos = categories.contains { $0.rules.contains { rule in
            (rule.scope.in?.include ?? []).contains { $0 == .owned || $0 == .contributed }
        } }
        let needsTeams = InboxSync.needsTeams(categories: categories, jevReads: jevReadsInboxNow)
        if needsTeams, teamsResolvedAt.map({ Date().timeIntervalSince($0) > 86400 }) ?? true { await resolveTeams(me: me) }
        if needsRepos, reposResolvedAt.map({ Date().timeIntervalSince($0) > 86400 }) ?? true {
            // A failure leaves what was known; with nothing known, the refresh waits: it would read as "nothing there".
            do { try await resolveRepos(me: me) } catch {
                if ownedRepos.isEmpty && contributedRepos.isEmpty { inboxError = error.localizedDescription; return }
            }
        }
        let searches = InboxSync.searches(categories: categories, groups: groups, me: me, contributed: contributedRepos,
                                          myTeams: myTeams)
        let targets = InboxSync.workflowTargets(categories: categories, groups: groups, owned: ownedRepos,
                                                contributed: contributedRepos)
        guard !searches.isEmpty || !targets.isEmpty else {
            if !things.isEmpty { things = [:] }
            inboxError = nil
            announceInbox()
            return
        }
        // Out of GraphQL points: wait for the reset rather than fail every poll.
        if !searches.isEmpty, InboxSync.waitsForPoints(remaining: gh.graphqlRemaining, resetsAt: gh.graphqlResetsAt, manual: manual) {
            return
        }
        gh.reserveETags(forRepositories: targets.count)

        var found: [String: Thing] = [:]
        var searchFailure: String?
        var fetched = Fetched()
        if !searches.isEmpty {
            do {
                fetched = try await fetchThings(searches)
                for thing in fetched.things { found[thing.id] = thing }
            } catch {
                searchFailure = error.localizedDescription
            }
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
        inboxError = searchFailure ?? fetched.error ?? workflowFailure
        // A search that failed can't say what is gone: the things stay as they were.
        guard searchFailure == nil else { return }
        var next = found
        // Nor can an answer GitHub gave in part: what it left out stays, and so does a thing it gave without some of its
        // parts (its comments, its threads), which would otherwise lose facts and announce them again when they come back.
        if fetched.error != nil {
            for (id, old) in things where old.kind != .workflow && (next[id] == nil || fetched.partial.contains(id)) {
                next[id] = old
            }
        }
        for (id, thing) in workflows { next[id] = thing }
        if !failedRepos.isEmpty {
            let kept = things.filter { $0.value.kind == .workflow && failedRepos.contains($0.value.repo) && next[$0.key] == nil }
            next.merge(kept) { a, _ in a }
        }
        applyThings(next)
        await readInbox()
        announceInbox()
    }

    /// What searches brought: the things, those GitHub gave only in part (an error inside them), and the first error it
    /// said, if any.
    struct Fetched {
        var things: [Thing] = []
        var partial: Set<String> = []
        var error: String?
    }

    /// Searches, a page at a time for those with more, until the caps. An answer with no data at all throws; one with data
    /// and errors (a node GitHub couldn't give, a part of one) is taken for what it has, and says so.
    func fetchThings(_ searches: [String]) async throws -> Fetched {
        var found: [String: Thing] = [:]
        var partial = Set<String>()
        var error: String?
        var cursors: [Int: String?] = Dictionary(uniqueKeysWithValues: searches.indices.map { ($0, String?.none) })
        var pages = 0
        while !cursors.isEmpty, pages < InboxSync.maxPages, found.count < InboxSync.maxThings {
            pages += 1
            var next: [Int: String?] = [:]
            let active = cursors.keys.sorted()
            for start in stride(from: 0, to: active.count, by: InboxSync.searchesPerRequest) {
                let batch = active[start..<min(start + InboxSync.searchesPerRequest, active.count)]
                let json = try await gh.graphql(InboxSync.request(batch.map { ("s\($0)", searches[$0], cursors[$0] ?? nil) }))
                let errors = (json["errors"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
                guard let data = json["data"] as? [String: Any] else {
                    throw GitHubError(message: (errors.first?["message"] as? String) ?? "GitHub gave no answer")
                }
                if let first = errors.first { error = error ?? (first["message"] as? String) ?? "GitHub gave part of an answer" }
                // `["s0", "nodes", 3, "comments", …]`: the fourth thing of search 0 came without some of its parts.
                var broken = Set<[String]>()
                for e in errors {
                    guard let path = e["path"] as? [Any], path.count > 3, let alias = path[0] as? String,
                          let index = path[2] as? Int else { continue }
                    broken.insert([alias, String(index)])
                }
                for i in batch {
                    guard let result = data["s\(i)"] as? [String: Any] else { continue }
                    // A node GitHub couldn't give is null: the others are still things.
                    for (n, value) in ((result["nodes"] as? [Any]) ?? []).enumerated() {
                        guard let node = value as? [String: Any], let thing = InboxSync.thing(node) else { continue }
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
        return Fetched(things: Array(found.values), partial: partial, error: error)
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
        return InboxSync.workflowThings(repo: repo, branch: branch, status: status)
    }

    /// Replaces the things in one assignment, keeping what Jev said of them, and forgets marks of things gone for a month.
    func applyThings(_ next: [String: Thing], now: Date = Date()) {
        var next = next
        let me = inboxContext.me
        for id in next.keys { InboxJev.carry(things[id]?.signals, into: &next[id]!, me: me) }
        if next != things { things = next }
        for id in next.keys { goneSince[id] = nil }
        var forget: [String] = []
        for id in marks.keys where next[id] == nil {
            let since = goneSince[id] ?? now
            goneSince[id] = since
            if now.timeIntervalSince(since) > Double(InboxSync.marksDays) * 86400 { forget.append(id) }
        }
        if !forget.isEmpty {
            var kept = marks
            for id in forget { kept[id] = nil; goneSince[id] = nil }
            marks = kept
        }
    }

    /// The repos you own and those you merged a PR in. Kept for a day.
    func resolveRepos(me: String) async throws {
        let json = try await gh.graphql(InboxSync.reposRequest(me: me))
        guard let data = json["data"] as? [String: Any] else {
            throw GitHubError(message: ((json["errors"] as? [[String: Any]])?.first?["message"] as? String) ?? "GitHub gave no answer")
        }
        func names(_ nodes: Any?, _ path: (([String: Any]) -> String?)) -> Set<String> {
            Set(((nodes as? [[String: Any]]) ?? []).compactMap(path))
        }
        let viewer = data["viewer"] as? [String: Any]
        let owned = names((viewer?["repositories"] as? [String: Any])?["nodes"]) { $0["nameWithOwner"] as? String }
        // A merged or an open PR of yours makes it a repo you contribute to.
        let repoName: ([String: Any]) -> String? = { ($0["repository"] as? [String: Any])?["nameWithOwner"] as? String }
        let merged = names((data["merged"] as? [String: Any])?["nodes"], repoName)
            .union(names((data["open"] as? [String: Any])?["nodes"], repoName))
        if owned != ownedRepos { ownedRepos = owned }
        // Only grows: an older merge isn't forgotten because newer ones fill the page.
        let all = contributedRepos.union(merged)
        if all != contributedRepos { contributedRepos = all }
        reposResolvedAt = Date()
    }

    /// The teams you're in. A failure (no read:org, offline) leaves what was known; asked again in a day.
    func resolveTeams(me: String) async {
        teamsResolvedAt = Date()
        guard let json = try? await gh.graphql(InboxSync.teamsRequest(me: me)),
              let data = json["data"] as? [String: Any] else { return }
        let teams = InboxSync.teams(data)
        if teams != myTeams { myTeams = teams }
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
        let jevReads = jevReadsInboxNow && Date() >= inboxJevPausedUntil
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
        // Facts that are gone: forgotten, for a thing that is still fetched (events only once the thing no longer has them).
        for (id, thing) in things {
            guard var m = updated[id], !m.notified.isEmpty || !m.acked.isEmpty else { continue }
            let current = Set(byThing[id]?.facts.map(\.key) ?? [])
            let kept = { (key: String) in current.contains(key) || InboxSync.isEvent(key, of: thing) }
            let notified = m.notified.filter(kept), acked = m.acked.filter(kept)
            if notified != m.notified || acked != m.acked {
                m.notified = notified
                m.acked = acked
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
