import Foundation
import Testing
@testable import Lookout

private func iso(_ text: String) -> Date? { try? Date.ISO8601FormatStyle().parse(text) }

private func node(_ extra: [String: Any] = [:]) -> [String: Any] {
    var n: [String: Any] = [
        "__typename": "PullRequest", "id": "PR_1", "number": 12, "title": "Add sandbox", "url": "https://github.com/o/r/pull/12",
        "isDraft": false, "state": "OPEN", "merged": false, "createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-09T10:00:00Z",
        "body": "Hello @Reviewer and @org/team\n<!-- greptile_confidence_score:3 -->", "mergeable": "CONFLICTING", "mergeStateStatus": "BEHIND",
        "requestEvents": ["nodes": [
            ["createdAt": "2026-10-02T10:00:00Z", "requestedReviewer": ["login": "bob"]],
            ["createdAt": "2026-10-04T10:00:00Z", "requestedReviewer": ["login": "bob"]],
            ["createdAt": "2026-10-03T10:00:00Z", "requestedReviewer": ["combinedSlug": "org/core"]],
            ["createdAt": "2026-10-01T10:00:00Z", "requestedReviewer": ["login": "gone"]],
        ]],
        "repository": ["nameWithOwner": "o/r"],
        "author": ["login": "me", "__typename": "User", "avatarUrl": "https://a/me"], "authorAssociation": "CONTRIBUTOR",
        "labels": ["nodes": [["name": "bug"]]], "assignees": ["nodes": [["login": "alice"]]],
        "reviewRequests": ["nodes": [["requestedReviewer": ["login": "bob"]], ["requestedReviewer": ["combinedSlug": "org/core"]]]],
        "comments": ["nodes": [
            ["id": "c1", "createdAt": "2026-10-05T10:00:00Z", "body": "ping @Me ```@code```", "authorAssociation": "NONE",
             "author": ["login": "greptile-apps", "__typename": "Bot", "avatarUrl": "https://a/g"]],
        ]],
        "latestOpinionatedReviews": ["nodes": [
            ["id": "r1", "state": "APPROVED", "submittedAt": "2026-10-06T10:00:00Z", "body": "", "authorAssociation": "MEMBER",
             "author": ["login": "bob", "__typename": "User", "avatarUrl": ""]],
        ]],
        "reviews": ["nodes": [
            ["id": "r1", "state": "APPROVED", "submittedAt": "2026-10-06T10:00:00Z", "body": "", "authorAssociation": "MEMBER",
             "author": ["login": "bob", "__typename": "User", "avatarUrl": ""]],
            ["id": "r2", "state": "COMMENTED", "submittedAt": "2026-10-07T10:00:00Z", "body": "Looks odd, cc @carol",
             "authorAssociation": "OWNER", "author": ["login": "dave", "__typename": "User", "avatarUrl": ""]],
        ]],
        "reviewThreads": ["nodes": [
            ["id": "t1", "isResolved": true, "path": "a.swift",
             "first": ["nodes": [["id": "x", "createdAt": "2026-10-02T10:00:00Z", "body": "a", "authorAssociation": "MEMBER",
                                 "author": ["login": "bob", "__typename": "User"]]]],
             "last": ["nodes": [["id": "y", "createdAt": "2026-10-03T10:00:00Z", "body": "done", "authorAssociation": "NONE",
                                "author": ["login": "me", "__typename": "User"]]]]],
            ["id": "t2", "isResolved": false, "path": "b.swift",
             "first": ["nodes": [["id": "z", "createdAt": "2026-10-02T10:00:00Z", "body": "why?", "authorAssociation": "NONE",
                                 "author": ["login": "greptile-apps", "__typename": "Bot"]]]],
             "last": ["nodes": [["id": "w", "createdAt": "2026-10-08T10:00:00Z", "body": "still why? @alice", "authorAssociation": "NONE",
                                "author": ["login": "greptile-apps", "__typename": "Bot"]]]]],
        ]],
        "commits": ["nodes": [
            ["commit": ["oid": "abc", "committedDate": "2026-10-08T11:00:00Z", "author": ["user": ["login": "me"]],
                        "statusCheckRollup": ["state": "FAILURE"]]],
        ]],
    ]
    for (k, v) in extra { n[k] = v }
    return n
}

@Suite struct InboxSyncMapping {
    @Test func aPullRequestBecomesAThing() throws {
        let t = try #require(InboxSync.thing(node()))
        #expect(t.id == "pr:o/r#12")
        #expect(t.kind == .pr && t.repo == "o/r" && t.number == 12)
        #expect(t.status == .open)
        #expect(t.author == Person(login: "me", isBot: false, association: .contributor, avatar: URL(string: "https://a/me")))
        #expect(t.labels == ["bug"] && t.assignees == ["alice"] && t.requestedReviewers == ["bob", "org/core"])
        #expect(t.greptileScore == 3)
        #expect(t.hasConflicts)
        #expect(t.checks == .failing)
        // Teams and code are not mentions; logins are lowercased, from the body, comments, review words and replies.
        #expect(Set(t.mentioned) == ["reviewer", "me", "carol", "alice"])
        #expect(t.commits.map(\.id) == ["abc"] && t.commits.first?.author == "me")
    }

    @Test func botsGetTheirBotSuffixAndAssociationsAreKept() throws {
        let t = try #require(InboxSync.thing(node()))
        let bot = try #require(t.comments.first { $0.id == "c1" }?.author)
        #expect(bot.login == "greptile-apps[bot]" && bot.isBot)
        #expect(t.reviews.first { $0.id == "r1" }?.author.association == .member)
    }

    @Test func reviewsWithWordsAreCommentsAndOpinionsAreReviews() throws {
        let t = try #require(InboxSync.thing(node()))
        let summary = try #require(t.comments.first { $0.id == "r2" })
        #expect(summary.isReview && summary.author.login == "dave" && summary.author.association == .owner)
        // Comments are in time order.
        #expect(t.comments.map(\.id) == ["c1", "r2"])
        // Bob's approval, and dave's comment-only review (he has no opinion).
        #expect(t.reviews.map(\.state) == [.approved, .commented])
    }

    @Test func threadsKeepWhoStartedWhoRepliedAndWhetherTheyAreResolved() throws {
        let t = try #require(InboxSync.thing(node()))
        #expect(t.threads.map(\.isResolved) == [true, false])
        let open = t.threads[1]
        #expect(open.startedBy.login == "greptile-apps[bot]" && open.lastReplyID == "w" && open.path == "b.swift")
    }

    @Test func statusesAndAnIssue() throws {
        #expect(InboxSync.thing(node(["isDraft": true]))?.status == .draft)
        #expect(InboxSync.thing(node(["merged": true, "state": "MERGED"]))?.status == .merged)
        #expect(InboxSync.thing(node(["state": "CLOSED"]))?.status == .closed)
        #expect(InboxSync.thing(node(["mergeable": "MERGEABLE", "body": "none"]))?.hasConflicts == false)
        let issue = try #require(InboxSync.thing(["__typename": "Issue", "number": 3, "title": "Bug", "url": "https://github.com/o/r/issues/3",
                                                  "state": "CLOSED", "createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z",
                                                  "repository": ["nameWithOwner": "o/r"], "author": NSNull()]))
        #expect(issue.id == "issue:o/r#3" && issue.status == .closed && issue.author?.login == "ghost")
    }

    @Test func eachWorkflowOfABranchIsAThingOfItsOwn() {
        let status = CIStatus(branch: "main", sha: "abc", url: URL(string: "https://github.com/o/r/commit/abc"),
                              checkedAt: Date(), title: "Fix", updatedAt: Date(timeIntervalSince1970: 100),
                              workflows: [
                                  CIStatus.Workflow(id: "11", name: "CI", state: .failure, failing: ["build"],
                                                    url: URL(string: "https://github.com/o/r/actions/runs/5"),
                                                    updatedAt: Date(timeIntervalSince1970: 90)),
                                  CIStatus.Workflow(id: "12", name: "Lint", state: .failure, failing: ["lint"], url: nil, updatedAt: nil),
                                  CIStatus.Workflow(id: "13", name: "Docs", state: .success, failing: [], url: nil, updatedAt: nil),
                              ])
        let things = InboxSync.workflowThings(repo: "o/r", branch: "main", status: status)
        #expect(things.map(\.id) == ["workflow:o/r:11@main", "workflow:o/r:12@main", "workflow:o/r:13@main"])
        #expect(things.map(\.workflowName) == ["CI", "Lint", "Docs"])
        #expect(things.map(\.checks) == [.failing, .failing, .passing])
        #expect(things[0].failingJobs == ["build"] && things[1].failingJobs == ["lint"] && things[2].failingJobs.isEmpty)
        #expect(things.allSatisfy { $0.branch == "main" && $0.kind == .workflow && $0.title == "Fix" })
        #expect(things[0].url.path.hasSuffix("/runs/5") && things[1].url.path == "/o/r/commit/abc")
        #expect(things[1].updatedAt == Date(timeIntervalSince1970: 100))
    }
}

@Suite struct InboxSyncQueries {
    private func rule(_ scope: Scope, _ conditions: [Condition] = []) -> InboxCategory {
        InboxCategory(name: "x", symbol: "star", color: .blue, rules: [Rule(scope: scope, conditions: conditions)])
    }

    private func searches(_ categories: [InboxCategory], groups: [InboxGroup] = []) -> [String] {
        InboxSync.searches(categories: categories, groups: groups, me: "me", contributed: ["o/c"],
                           now: Date(timeIntervalSince1970: 1_791_000_000))
    }

    @Test func scopesBecomeQualifiers() {
        let q = searches([rule(Scope(kinds: [.pr], by: Pick(include: [.me]), in: Pick(include: [.repo("o/r"), .owner("org")])))])
        #expect(q.count == 1)
        #expect(["is:pr", "repo:o/r", "user:org", "author:me", "is:open"].allSatisfy { q[0].contains($0) })
    }

    @Test func toRolesMakeOneQueryEach() {
        let q = searches([rule(Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.assigned, .reviewRequested]))])
        #expect(q.count == 2)
        #expect(q.contains { $0.contains("assignee:me") } && q.contains { $0.contains("review-requested:me") })
        // An issue has no review requests.
        let issues = searches([rule(Scope(kinds: [.issue], to: Pick(include: [.me]), toRoles: [.reviewRequested, .mentioned]))])
        #expect(issues.count == 1 && issues[0].contains("mentions:me") && issues[0].contains("is:issue"))
    }

    @Test func involvedUsesInvolvesAndWhatSearchCantSayIsOverFetched() {
        let q = searches([rule(Scope(kinds: [.pr], by: Pick(include: [.maintainers]), in: Pick(include: [.involved])))])
        #expect(q.count == 1 && q[0].contains("involves:me") && !q[0].contains("author:"))
        // Nothing narrowing at all is what involves you, not every PR on GitHub.
        #expect(searches([rule(Scope(kinds: [.pr]))]) == q)
    }

    @Test func groupsOwnedAndContributedExpand() {
        let people = InboxGroup(name: "Team", kind: .people, members: ["alice", "greptile-apps[bot]"])
        let repos = InboxGroup(name: "Mine", kind: .repos, members: ["a/b", "c/*"])
        let q = searches([rule(Scope(kinds: [.pr], by: Pick(include: [.group(people.id)]),
                                     in: Pick(include: [.group(repos.id), .owned, .contributed])))], groups: [people, repos])
        #expect(q.count == 2)
        #expect(["repo:a/b", "user:c", "user:me", "repo:o/c"].allSatisfy { q[0].contains($0) })
        #expect(q[0].contains("author:alice") && q[1].contains("author:app/greptile-apps"))
    }

    @Test func prsAndIssuesShareTheQueriesTheyCan() {
        // The same query finds both without is:pr or is:issue; review requests are a PR's alone.
        let q = searches([rule(Scope(kinds: [.pr, .issue], to: Pick(include: [.me]), toRoles: [.assigned, .reviewRequested],
                                     in: Pick(include: [.owned])))])
        #expect(q == ["archived:false user:me assignee:me sort:updated-desc is:open",
                      "is:pr archived:false user:me review-requested:me sort:updated-desc is:open"])
    }

    @Test func everyRuleGetsSearchesPastTheCap() {
        // A hundred named repos make a rule of many queries; the rule after it still gets its turn.
        let many = Pick<RepoRef>(include: (0..<100).map { .repo("owner/repository-\($0)") })
        let q = searches([InboxCategory(name: "x", symbol: "star", color: .blue, rules: [
            Rule(scope: Scope(kinds: [.pr], in: many)), Rule(scope: Scope(kinds: [.issue], in: Pick(include: [.owned, .owner("org")]))),
        ])])
        #expect(q.count == InboxSync.maxSearches)
        #expect(q.filter { $0.contains("is:issue") } == ["is:issue archived:false user:me user:org sort:updated-desc is:open"])
    }

    @Test func closedThingsAreOnlyFetchedWhenAskedForAndRecent() {
        let plain = searches([rule(Scope(kinds: [.pr], by: Pick(include: [.me])))])
        #expect(plain.count == 1)
        let merged = searches([rule(Scope(kinds: [.pr], by: Pick(include: [.me])), [.status([.merged])])])
        #expect(merged.count == 2 && merged[1].contains("is:closed updated:>=2026-"))
    }

    @Test func workflowsAreRepoTargets() {
        let c = rule(Scope(kinds: [.workflow], in: Pick(include: [.repo("o/r"), .owned], except: [.repo("me/own")]), on: ["main", "dev"]))
        let t = InboxSync.workflowTargets(categories: [c], groups: [], owned: ["me/own"], contributed: [])
        #expect(t.map { "\($0.repo)@\($0.branch ?? "")" } == ["o/r@main", "o/r@dev"])
        let none = InboxSync.workflowTargets(categories: [InboxStore.ci], groups: [], owned: [], contributed: [])
        #expect(none.isEmpty)
    }
}

@MainActor
@Suite struct InboxSyncRefresh {
    final class Log: @unchecked Sendable {
        var queries: [String] = []
        var posted: [String] = []
        var score = 3
    }

    nonisolated static func body(_ request: URLRequest) -> String {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(contentsOf: buffer[..<n])
            }
            stream.close()
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func store(_ log: Log, notifies: Bool = true) -> (Store, UUID) {
        let s = Store()
        s.persists = false
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        s.gh.session = StubbedGitHub.session { request in
            let text = Self.body(request)
            log.queries.append(text)
            let pr = node(["body": "<!-- greptile_confidence_score:\(log.score) -->"])
            let reply: [String: Any] = ["data": ["rateLimit": ["cost": 3, "remaining": 4000],
                                                  "s0": ["pageInfo": ["hasNextPage": false], "nodes": [pr]]]]
            return StubbedGitHub.Reply(200, String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self))
        }
        var category = InboxCategory(name: "Mine", symbol: "star", color: .blue, notifies: notifies)
        category.rules = [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me])), conditions: [.greptileBelow(5)])]
        s.categories = [category]
        s.notifier.onPost = { log.posted.append($0.identifier) }
        return (s, category.id)
    }

    @Test func aRefreshFillsThingsAndTheFirstEvaluationIsSilent() async {
        let log = Log()
        let (s, category) = store(log)
        await s.syncInbox()
        #expect(s.things.keys.sorted() == ["pr:o/r#12"])
        #expect(s.entries(in: category).map(\.id) == ["pr:o/r#12"])
        #expect(log.queries.count == 1 && log.queries[0].contains("author:me"))
        #expect(log.posted.isEmpty)
        #expect(s.marks["pr:o/r#12"]?.notified == ["greptile:3"])
        // The baseline is a field of its own, by the rules it was taken for; marks are marks of things only.
        #expect(s.categoryBaselines == [category: Set(s.categories[0].rules.map(\.id))])
        #expect(s.marks.keys.sorted() == ["pr:o/r#12"])
    }

    @Test func aChangedRuleSetIsANewBaselineAndADeletedCategoryTakesItsBaselineWithIt() async {
        let log = Log()
        let (s, category) = store(log)
        await s.syncInbox()
        log.score = 2
        // The rule changes at the same time as the fact: what is there under the new rule is noted, not announced.
        s.categories[0].rules = [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me])), conditions: [.greptileBelow(4)])]
        await s.syncInbox()
        #expect(log.posted.isEmpty && s.categoryBaselines[category] == Set(s.categories[0].rules.map(\.id)))
        s.categories = []
        await s.syncInbox()
        #expect(s.categoryBaselines.isEmpty)
    }

    @Test func aNewFactNotifiesOnceAndAGoneFactIsForgotten() async {
        let log = Log()
        let (s, _) = store(log)
        await s.syncInbox()
        await s.syncInbox()
        #expect(log.posted.isEmpty)
        log.score = 2
        await s.syncInbox()
        #expect(log.posted == ["inbox:pr:o/r#12"])
        #expect(s.marks["pr:o/r#12"]?.notified == ["greptile:2"])
        await s.syncInbox()
        #expect(log.posted.count == 1)
        // Back above the bar and below again: the same fact is new again.
        log.score = 5
        await s.syncInbox()
        #expect(s.marks["pr:o/r#12"]?.notified == [])
        log.score = 2
        await s.syncInbox()
        #expect(log.posted.count == 2)
    }

    @Test func aCategoryThatDoesNotNotifyStaysQuiet() async {
        let log = Log()
        let (s, _) = store(log, notifies: false)
        await s.syncInbox()
        log.score = 2
        await s.syncInbox()
        #expect(log.posted.isEmpty)
        #expect(s.marks["pr:o/r#12"]?.notified == ["greptile:2"])
    }

    @Test func marksOfThingsGoneForAMonthAreForgotten() {
        let (s, _) = store(Log())
        s.marks = ["pr:o/r#9": EntryMarks(seen: ["x"])]
        let now = Date()
        s.applyThings([:], now: now)
        #expect(s.marks["pr:o/r#9"] != nil)
        s.applyThings([:], now: now.addingTimeInterval(31 * 86400))
        #expect(s.marks["pr:o/r#9"] == nil)
    }
}


/// CI as workflow things: each failing workflow is one entry and one notification, until it is green.
@MainActor
@Suite struct InboxWorkflowRefresh {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _failing: Set<Int> = [11, 12]
        var failing: Set<Int> {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
    }

    nonisolated private static func runs(_ failing: Set<Int>) -> String {
        let all = [(11, "CI"), (12, "Lint"), (13, "Docs")].map { id, name in
            """
            {"name":"\(name)","workflow_id":\(id),"head_sha":"s1","display_title":"Fix","status":"completed",\
            "conclusion":"\(failing.contains(id) ? "failure" : "success")","check_suite_id":\(id)}
            """
        }
        return #"{"workflow_runs":[\#(all.joined(separator: ","))]}"#
    }

    private func store(_ state: State, posted: @escaping (String) -> Void) -> (Store, UUID) {
        let s = Store()
        s.persists = false
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        s.gh.session = StubbedGitHub.session { request in
            switch request.url?.path ?? "" {
            case "/repos/a/x": return .init(200, #"{"full_name":"a/x","default_branch":"main"}"#)
            case "/repos/a/x/actions/runs": return .init(200, Self.runs(state.failing))
            case "/repos/a/x/commits/s1/check-runs": return .init(200, #"{"total_count":0,"check_runs":[]}"#)
            case "/repos/a/x/commits/s1/status": return .init(200, #"{"state":"success","total_count":0,"sha":"s1","statuses":[]}"#)
            default: return .init(404, #"{"message":"unrouted"}"#)
            }
        }
        var ci = InboxStore.ci
        ci.rules = [Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("a/x")])), conditions: [.workflow([.failing])],
                         createdAt: .distantPast)]
        s.categories = [ci]
        s.notifier.onPost = { posted($0.identifier) }
        return (s, ci.id)
    }

    @Test func everyFailingWorkflowIsAnEntryAndNotifiesOnceUntilItIsGreen() async {
        let state = State()
        var posted: [String] = []
        let (s, ci) = store(state) { posted.append($0) }
        await s.syncInbox()
        // One thing per workflow (the passing one too), the failing ones in CI; the first look is silent.
        #expect(s.things.keys.sorted() == ["workflow:a/x:11@main", "workflow:a/x:12@main", "workflow:a/x:13@main"])
        #expect(s.entries(in: ci).map(\.id).sorted() == ["workflow:a/x:11@main", "workflow:a/x:12@main"] && s.count(ci) == 2)
        #expect(posted.isEmpty)
        // Docs fails: a third entry and one notification, for that workflow alone.
        state.failing.insert(13)
        await s.syncInbox()
        #expect(s.count(ci) == 3 && posted == ["inbox:workflow:a/x:13@main"])
        await s.syncInbox()
        #expect(posted.count == 1)
        // Lint goes green and fails again: that failure is new.
        state.failing.remove(12)
        await s.syncInbox()
        #expect(s.count(ci) == 2)
        state.failing.insert(12)
        await s.syncInbox()
        #expect(s.count(ci) == 3 && posted == ["inbox:workflow:a/x:13@main", "inbox:workflow:a/x:12@main"])
    }

    @Test func aRuleCanNameTheWorkflowsItWants() async {
        let state = State()
        let (s, _) = store(state) { _ in }
        s.categories[0].rules[0].scope.named = ["lint"]
        await s.syncInbox()
        #expect(s.entries.map(\.id) == ["workflow:a/x:12@main"])
    }
}


@Suite struct InboxSyncRequestsAndTeams {
    private func rule(_ scope: Scope) -> InboxCategory {
        InboxCategory(name: "T", symbol: "eye", color: .blue, rules: [Rule(scope: scope)])
    }

    private func searches(_ categories: [InboxCategory]) -> [String] {
        InboxSync.searches(categories: categories, groups: [], me: "me", contributed: [])
    }

    // MARK: Review requests, behind base, teams, contributed

    @Test func reviewRequestsKeepWhenEachWasMadeAndTheLatestOfARepeatedOneWins() throws {
        let t = try #require(InboxSync.thing(node()))
        let at = Dictionary(uniqueKeysWithValues: t.reviewRequests.map { ($0.reviewer, $0.at) })
        #expect(at["bob"] == iso("2026-10-04T10:00:00Z"))
        #expect(at["org/core"] == iso("2026-10-03T10:00:00Z"))
        // Requests no longer pending (gone) aren't kept.
        #expect(at["gone"] == nil && t.reviewRequests.count == 2)
    }

    @Test func behindBaseAndTheHeadCommitAreRead() throws {
        let t = try #require(InboxSync.thing(node()))
        #expect(t.behindBase && t.headSha == "abc")
        #expect(try #require(InboxSync.thing(node(["mergeStateStatus": "CLEAN"]))).behindBase == false)
    }

    @Test func teamsInToBecomeTeamReviewRequestedQueries() {
        let mixed = searches([rule(Scope(kinds: [.pr], to: Pick(include: [.me, .team("@acme/core")]), toRoles: [.reviewRequested]))])
        #expect(mixed.count == 2)
        #expect(mixed.contains { $0.contains("review-requested:me") } && mixed.contains { $0.contains("team-review-requested:acme/core") })
        let mine = InboxSync.searches(categories: [rule(Scope(kinds: [.pr], to: Pick(include: [.myTeams]), toRoles: [.reviewRequested]))],
                                      groups: [], me: "me", contributed: [], myTeams: ["a/x", "a/y"])
        #expect(mine.count == 2 && mine.allSatisfy { $0.contains("team-review-requested:a/") })
        // Not resolved yet (or in none): nothing to search, rather than every PR on GitHub.
        #expect(searches([rule(Scope(kinds: [.pr], to: Pick(include: [.myTeams]), toRoles: [.reviewRequested]))]).isEmpty)
        // Teams only count for review requests.
        #expect(searches([rule(Scope(kinds: [.pr], to: Pick(include: [.team("a/x")]), toRoles: [.assigned]))]).isEmpty)
    }

    @Test @MainActor func teamsAreResolvedWhenJevRatesReviewRequestsEvenWithNoRuleNamingThem() async {
        let none = [InboxCategory(name: "Mine", symbol: "star", color: .blue,
                                  rules: [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me])))])]
        #expect(!InboxSync.needsTeams(categories: none, jevReads: false))
        #expect(InboxSync.needsTeams(categories: none, jevReads: true))
        let s = Store()
        s.persists = false
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        s.categories = none
        s.gh.session = StubbedGitHub.session { request in
            let data: [String: Any] = InboxSyncRefresh.body(request).contains("organizations")
                ? ["viewer": ["organizations": ["nodes": [["teams": ["nodes": [["combinedSlug": "acme/core"]]]]]]]]
                : ["rateLimit": ["cost": 1, "remaining": 4000], "s0": ["pageInfo": ["hasNextPage": false], "nodes": []]]
            return StubbedGitHub.Reply(200, String(decoding: try JSONSerialization.data(withJSONObject: ["data": data]), as: UTF8.self))
        }
        // Jev switched off: not asked.
        s.settings.jevReadsInbox = false
        s.inboxAsker = { _, _ in [:] }
        await s.syncInbox()
        #expect(s.myTeams.isEmpty)
        s.settings.jevReadsInbox = true
        await s.syncInbox()
        #expect(s.myTeams == ["acme/core"])
    }

    @Test @MainActor func contributedReposAreMergedAndOpenPRsAndTeamsAreKept() async throws {
        let s = Store()
        s.persists = false
        s.gh.session = StubbedGitHub.session { request in
            let text = InboxSyncRefresh.body(request)
            let data: [String: Any]
            if text.contains("organizations") {
                data = ["viewer": ["organizations": ["nodes": [["teams": ["nodes": [["combinedSlug": "acme/core"]]]]]]]]
            } else {
                data = ["viewer": ["repositories": ["nodes": [["nameWithOwner": "me/own"]]]],
                        "merged": ["nodes": [["repository": ["nameWithOwner": "o/merged"]]]],
                        "open": ["nodes": [["repository": ["nameWithOwner": "o/open"]]]]]
            }
            return StubbedGitHub.Reply(200, String(decoding: try JSONSerialization.data(withJSONObject: ["data": data]), as: UTF8.self))
        }
        try await s.resolveRepos(me: "me")
        #expect(s.ownedRepos == ["me/own"] && s.contributedRepos == ["o/merged", "o/open"])
        await s.resolveTeams(me: "me")
        #expect(s.myTeams == ["acme/core"])
        // The context hands both to the engine.
        #expect(s.inboxContext.myTeams == ["acme/core"] && s.inboxContext.contributedRepos.contains("o/open"))
    }
}
