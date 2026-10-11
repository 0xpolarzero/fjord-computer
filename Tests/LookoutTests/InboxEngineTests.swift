import Foundation
import Testing
@testable import Lookout

@Suite struct InboxEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let me = Person(login: "me")
    let maintainer = Person(login: "tok", association: .member)
    let greptile = Person(login: "greptile-apps[bot]", isBot: true)
    let stranger = Person(login: "rando")

    private func context(contributed: Set<String> = ["a/one"]) -> InboxContext {
        InboxContext(me: "Me", contributedRepos: contributed, now: now)
    }

    private func pr(_ n: Int = 1, repo: String = "a/one", by: Person? = nil, status: ThingStatus = .open) -> Thing {
        Thing(id: "pr:\(repo)#\(n)", kind: .pr, repo: repo, number: n, title: "t", url: URL(string: "https://github.com/\(repo)/pull/\(n)")!,
              author: by ?? me, status: status, createdAt: now.addingTimeInterval(-1000), updatedAt: now)
    }

    private func workflow(_ state: CheckState?, branch: String = "main") -> Thing {
        var t = Thing(id: "workflow:a/one:1@\(branch)", kind: .workflow, repo: "a/one", number: nil, title: "CI",
                      url: URL(string: "https://github.com/a/one/actions")!, createdAt: now, updatedAt: now)
        t.checks = state
        t.workflowName = "CI"
        t.branch = branch
        return t
    }

    private func comment(_ id: String, _ author: Person, at: TimeInterval = -10) -> ThingComment {
        ThingComment(id: id, author: author, at: now.addingTimeInterval(at), snippet: "")
    }

    private func thread(_ id: String, by: Person, last: Person, reply: String = "r1") -> ThingThread {
        ThingThread(id: id, isResolved: false, startedBy: by, lastReplyBy: last, lastReplyID: reply, lastReplyAt: now, snippet: "")
    }

    private var theBots: Pick<PersonRef> { Pick(include: [.maintainers, .user("@greptile")]) }

    /// PRs by me in Contributing when any of the spec's conditions.
    private var specRule: Rule {
        Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me]), in: Pick(include: [.contributed])),
             conditions: [.lastComment(by: theBots),
                          .unresolvedThreads(startedBy: theBots, lastReplyBy: Pick(except: [.me])),
                          .changesRequested(by: theBots),
                          .greptileBelow(5)],
             createdAt: .distantPast)
    }

    // MARK: Scope and conditions

    @Test func specExampleMatchesByEachFact() {
        var t = pr()
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context()) == nil)

        t.comments = [comment("c1", me, at: -30), comment("c2", greptile, at: -20)]
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.map(\.key) == ["last:c2"])

        t.comments.append(comment("c3", me))  // my reply is now the last comment
        t.threads = [thread("t1", by: maintainer, last: stranger), thread("t2", by: maintainer, last: me),
                     thread("t3", by: stranger, last: stranger)]
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.map(\.key) == ["thread:t1:r1"])

        t.threads = []
        t.reviews = [ThingReview(id: "r1", author: maintainer, state: .changesRequested, at: now)]
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.map(\.key) == ["changes:r1"])

        t.reviews = []
        t.greptileScore = 4
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.map(\.key) == ["greptile:4"])
        t.greptileScore = 5
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context()) == nil)
    }

    @Test func scopeNarrowsByAuthorAndRepo() {
        var t = pr(by: stranger)
        t.greptileScore = 3
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context()) == nil)
        t = pr(repo: "b/two")
        t.greptileScore = 3
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context()) == nil)
        t = pr()
        t.greptileScore = 3
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context()) != nil)
    }

    @Test func reposResolveOwnersGroupsAndInvolvement() {
        let group = InboxGroup(name: "g", kind: .repos, members: ["c/*", "d/x"])
        let ctx = InboxContext(me: "me", groups: [group], now: now)
        func matches(_ ref: RepoRef, _ t: Thing) -> Bool {
            InboxEngine.facts(Rule(scope: Scope(kinds: [.pr], in: Pick(include: [ref]))), t, marks: nil, context: ctx) != nil
        }
        #expect(matches(.owner("A"), pr(repo: "a/one")))
        #expect(matches(.group(group.id), pr(repo: "c/any")))
        #expect(matches(.group(group.id), pr(repo: "d/x")))
        #expect(!matches(.group(group.id), pr(repo: "d/y")))
        #expect(matches(.involved, pr(repo: "z/z", by: me)))
        // Owned goes by the owner, not a list of repos: a repo far past the most recent hundred still counts.
        #expect(matches(.owned, pr(repo: "Me/ancient-repo")))
        #expect(!matches(.owned, pr(repo: "mentor/x")))
        #expect(!matches(.owned, pr(repo: "z/me")))
        var other = pr(repo: "z/z", by: stranger)
        #expect(!matches(.involved, other))
        other.comments = [comment("c", me)]
        #expect(matches(.involved, other))
    }

    @Test func toRolesNarrowTheSlot() {
        var t = pr(by: stranger)
        t.requestedReviewers = ["me"]
        var scope = Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.assigned])
        #expect(InboxEngine.facts(Rule(scope: scope), t, marks: nil, context: context()) == nil)
        scope.toRoles = [.reviewRequested]
        #expect(InboxEngine.facts(Rule(scope: scope), t, marks: nil, context: context()) != nil)
    }

    @Test func approvalsReadEachReviewersLatestOpinion() {
        var t = pr()
        t.reviews = [ThingReview(id: "r1", author: maintainer, state: .changesRequested, at: now.addingTimeInterval(-50)),
                     ThingReview(id: "r2", author: maintainer, state: .approved, at: now.addingTimeInterval(-40)),
                     ThingReview(id: "r3", author: maintainer, state: .commented, at: now.addingTimeInterval(-30))]
        let rule = { (c: Condition) in Rule(scope: Scope(kinds: [.pr]), conditions: [c], createdAt: .distantPast) }
        #expect(InboxEngine.facts(rule(.approved(by: Pick())), t, marks: nil, context: context())?.map(\.key) == ["approved:r2"])
        #expect(InboxEngine.facts(rule(.changesRequested(by: Pick())), t, marks: nil, context: context()) == nil)
    }

    @Test func statusReadyMeansOpenAndNotDraft() {
        let rule = Rule(scope: Scope(kinds: [.pr]), conditions: [.status([.open])])
        #expect(InboxEngine.facts(rule, pr(), marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule, pr(status: .draft), marks: nil, context: context()) == nil)
    }

    @Test func noConditionsMatchEveryOpenThingWithANeutralFact() {
        let rule = Rule(scope: Scope(kinds: [.pr]))
        #expect(InboxEngine.facts(rule, pr(), marks: nil, context: context())?.map(\.key) == ["open"])
        #expect(InboxEngine.facts(rule, pr(status: .draft), marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule, pr(status: .merged), marks: nil, context: context()) == nil)
    }

    @Test func allOfNeedsEveryCondition() {
        var t = pr()
        t.greptileScore = 3
        let rule = Rule(scope: Scope(kinds: [.pr]), match: .all, conditions: [.greptileBelow(5), .hasConflicts])
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) == nil)
        t.hasConflicts = true
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.map(\.key) == ["greptile:3", "conflicts"])
    }

    @Test func staleNeedsTheDays() {
        var t = pr()
        t.updatedAt = now.addingTimeInterval(-8 * 86_400)
        let rule = Rule(scope: Scope(kinds: [.pr]), conditions: [.noActivity(days: 7)])
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) != nil)
        t.updatedAt = now.addingTimeInterval(-86_400)
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) == nil)
    }

    // MARK: Lifecycle

    @Test func activityIsOnlyNewSinceTheRuleAndSinceDone() {
        var t = pr()
        t.comments = [comment("old", stranger, at: -500), comment("new", stranger, at: -5)]
        var rule = Rule(scope: Scope(kinds: [.pr]), conditions: [.newComment(by: Pick())])
        rule.createdAt = now.addingTimeInterval(-100)
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.map(\.key) == ["comment:new"])
        var marks = EntryMarks()
        marks.doneAt = now.addingTimeInterval(-1)
        #expect(InboxEngine.facts(rule, t, marks: marks, context: context()) == nil)
    }

    @Test func firstMatchingCategoryWinsEvenWhenHidden() {
        var t = pr()
        t.greptileScore = 3
        let any = Rule(scope: Scope(kinds: [.pr]))
        let first = InboxCategory(name: "first", symbol: "a", color: .blue, rules: [any], hidden: true)
        let second = InboxCategory(name: "second", symbol: "b", color: .red, rules: [any])
        let entries = InboxEngine.evaluate(things: [t], categories: [first, second], marks: [:], context: context())
        #expect(entries.map(\.categoryID) == [first.id])
        let skipped = InboxCategory(name: "no", symbol: "c", color: .gray, rules: [Rule(scope: Scope(kinds: [.issue]))])
        let fallback = InboxEngine.evaluate(things: [t], categories: [skipped, second], marks: [:], context: context())
        #expect(fallback.map(\.categoryID) == [second.id])
        #expect(InboxEngine.evaluate(things: [t], categories: [skipped], marks: [:], context: context()).isEmpty)
    }

    @Test func doneHoldsUntilANewFactArrives() {
        var t = pr()
        t.greptileScore = 3
        let category = InboxCategory(name: "c", symbol: "a", color: .blue, rules: [
            Rule(scope: Scope(kinds: [.pr]), conditions: [.greptileBelow(5), .lastComment(by: Pick())], createdAt: .distantPast)])
        func entry(_ marks: EntryMarks) -> InboxEntry? {
            InboxEngine.evaluate(things: [t], categories: [category], marks: [t.id: marks], context: context()).first
        }
        var marks = EntryMarks()
        #expect(entry(marks)?.isUnread == true)
        #expect(entry(marks)?.isDone == false)
        marks.seen = ["greptile:3"]
        marks.acked = ["greptile:3"]
        #expect(entry(marks)?.isUnread == false)
        #expect(entry(marks)?.isDone == true)
        t.comments = [comment("c1", stranger)]  // a new fact
        #expect(entry(marks)?.isDone == false)
        #expect(entry(marks)?.isUnread == true)
        t.comments = []
        t.greptileScore = 4  // a different score is a different fact
        #expect(entry(marks)?.isDone == false)
    }

    @Test func aFailureKeepsOneKeyUntilItGoesGreen() {
        let rule = Rule(scope: Scope(kinds: [.workflow], in: Pick()), conditions: [.workflow([.failing])])
        var t = workflow(.failing)
        let first = InboxEngine.facts(rule, t, marks: nil, context: context())
        t.failingJobs = ["build"]
        let again = InboxEngine.facts(rule, t, marks: nil, context: context())
        #expect(first?.map(\.key) == ["workflow:failing"])
        #expect(again?.map(\.key) == first?.map(\.key))
        t.checks = .passing
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) == nil)
        t.checks = .failing
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.map(\.key) == ["workflow:failing"])
    }

    @Test func aRuleTheEditorFlagsInItsCategoryIsOffThereButCIKeepsEveryWatchedRepo() {
        // A workflow rule whose last repo was removed: flagged in a category of yours, so it takes nothing.
        let rule = Rule(scope: Scope(kinds: [.workflow], in: Pick()), conditions: [.workflow([.failing])])
        let mine = InboxCategory(name: "Mine", symbol: "a", color: .blue, rules: [rule])
        #expect(InboxEngine.evaluate(things: [workflow(.failing)], categories: [mine], marks: [:], context: context()).isEmpty)
        // CI's own rule says every watched repo that way.
        var ci = mine
        ci.isCI = true
        #expect(InboxEngine.evaluate(things: [workflow(.failing)], categories: [ci], marks: [:], context: context()).count == 1)
        // A repo group that no longer exists in its except is flagged too: it doesn't widen the rule.
        let gone = Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo("a/one")], except: [.group(UUID())])))
        let category = InboxCategory(name: "Gone", symbol: "b", color: .red, rules: [gone])
        #expect(InboxEngine.evaluate(things: [pr()], categories: [category], marks: [:], context: context()).isEmpty)
    }

    @Test func maintainersAndBotsAreFlaggedWherePeopleAreKnownByLoginOnly() {
        func problems(_ scope: Scope, _ match: MatchMode, _ conditions: [Condition]) -> [InboxEngine.Problem] {
            InboxEngine.problems(Rule(scope: scope, match: match, conditions: conditions))
        }
        let pr = Scope(kinds: [.pr])
        #expect(problems(pr, .any, [.newCommits(by: Pick(include: [.bots]))]).map(\.condition) == [0])
        #expect(problems(pr, .any, [.mentions(Pick(include: [.me], except: [.maintainers]))]).map(\.condition) == [0])
        #expect(problems(Scope(kinds: [.pr], to: Pick(include: [.bots])), .any, []).map(\.slot) == ["to"])
        // Comment and review authors are known in full.
        #expect(problems(pr, .any, [.newComment(by: Pick(include: [.bots])), .newReview(by: Pick(include: [.maintainers]))]).isEmpty)
    }

    @Test func workflowsScopeByBranchAndName() {
        let rule = { (on: [String]?, named: [String]?) in
            Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("a/one")]), on: on, named: named),
                 conditions: [.workflow([.failing])])
        }
        let t = workflow(.failing, branch: "main")
        #expect(InboxEngine.facts(rule(nil, nil), t, marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule(["dev"], nil), t, marks: nil, context: context()) == nil)
        #expect(InboxEngine.facts(rule(["main"], ["ci"]), t, marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule(nil, ["Deploy"]), t, marks: nil, context: context()) == nil)
    }

    @Test func closedAndMergedOnlyMatchWhenAskedFor() {
        var merged = pr(status: .merged)
        merged.greptileScore = 2
        let loose = Rule(scope: Scope(kinds: [.pr]), conditions: [.greptileBelow(5)])
        #expect(InboxEngine.facts(loose, merged, marks: nil, context: context()) == nil)
        let asking = Rule(scope: Scope(kinds: [.pr]), conditions: [.greptileBelow(5), .status([.merged])])
        #expect(InboxEngine.facts(asking, merged, marks: nil, context: context())?.map(\.key) == ["status:merged"])
        let all = Rule(scope: Scope(kinds: [.pr]), match: .all, conditions: [.greptileBelow(5), .status([.merged])])
        #expect(InboxEngine.facts(all, merged, marks: nil, context: context())?.map(\.key) == ["greptile:2", "status:merged"])
        #expect(InboxEngine.facts(asking, pr(), marks: nil, context: context()) == nil)
    }

    // MARK: Problems

    @Test func impossibleCombinationsAreFlagged() {
        func problems(_ scope: Scope, _ match: MatchMode = .any, _ conditions: [Condition] = []) -> [InboxEngine.Problem] {
            InboxEngine.problems(Rule(scope: scope, match: match, conditions: conditions))
        }
        let byMe = Pick<PersonRef>(include: [.me])
        #expect(problems(Scope(kinds: [.pr], by: byMe, to: byMe, toRoles: [.reviewRequested])).map(\.slot) == ["to"])
        #expect(problems(Scope(kinds: [.pr], by: byMe, to: byMe)).isEmpty)
        #expect(problems(Scope(kinds: [.pr], by: byMe), .any, [.approved(by: byMe), .changesRequested(by: Pick(include: [.user("x")]))])
            .map(\.condition) == [0])
        #expect(problems(Scope(kinds: [.pr], by: Pick(include: [.me, .bots], except: [.me]))).map(\.slot) == ["by"])
        #expect(problems(Scope(kinds: [.issue]), .any, [.greptileBelow(3), .newComment(by: Pick())]).map(\.condition) == [0])
        #expect(problems(Scope(kinds: [.workflow]), .any, [.workflow([.failing])]).map(\.slot) == ["in"])
        #expect(problems(Scope(kinds: [.workflow], in: Pick()), .any, [.workflow([.failing])]).isEmpty)
        #expect(problems(Scope(kinds: [.pr]), .all, [.status([.draft]), .status([.merged])]).map(\.condition) == [1])
        #expect(problems(Scope(kinds: [.pr]), .any, [.status([.draft]), .status([.merged])]).isEmpty)
        #expect(problems(Scope(kinds: [.pr]), .all, [.status([.draft, .merged])]).isEmpty)
        #expect(problems(Scope(kinds: [.pr]), .all, [.checks([.failing]), .checks([.passing])]).map(\.condition) == [1])
        #expect(problems(Scope(kinds: [.pr]), .all, [.checks([.failing, .pending]), .checks([.pending])]).isEmpty)
    }

    @Test func everyKindOffersOnlyConditionsItCanMatch() {
        for kinds: Set<ThingKind> in [[.pr], [.issue], [.pr, .issue], [.workflow]] {
            let rule = Rule(scope: Scope(kinds: kinds, in: Pick()), conditions: InboxEngine.conditions(for: kinds))
            #expect(InboxEngine.problems(rule).isEmpty)
        }
        // PRs and issues together: what both have, with values that fit both.
        #expect(InboxEngine.conditions(for: [.pr, .issue]) == InboxEngine.conditions(for: [.issue]))
    }

    // MARK: Since, review requests, behind base, teams

    private func rule(_ conditions: [Condition], scope: Scope? = nil, match: MatchMode = .any) -> Rule {
        Rule(scope: scope ?? Scope(kinds: [.pr]), match: match, conditions: conditions, createdAt: .distantPast)
    }

    private func keys(_ rule: Rule, _ thing: Thing, marks: EntryMarks? = nil, ctx: InboxContext? = nil) -> [String]? {
        InboxEngine.facts(rule, thing, marks: marks, context: ctx ?? context())?.map(\.key)
    }

    @Test func aRuleAboutPRsAndIssuesMatchesBothAndFlagsWhatOnlyOneHas() {
        var issue = pr(2)
        issue.kind = .issue
        issue.id = "issue:a/one#2"
        let both = Rule(scope: Scope(kinds: [.pr, .issue], in: Pick(include: [.repo("a/one")])), createdAt: .distantPast)
        #expect(keys(both, pr()) == ["open"] && keys(both, issue) == ["open"])
        #expect(keys(Rule(scope: Scope(kinds: [.pr]), createdAt: .distantPast), issue) == nil)
        #expect(keys(both, workflow(.failing)) == nil)
        // A condition issues don't have, review requests alone, and workflows mixed in: each says why.
        #expect(InboxEngine.problems(Rule(scope: both.scope, conditions: [.checks([.failing])])).map(\.reason) == ["Issues don't have this"])
        #expect(InboxEngine.problems(Rule(scope: Scope(kinds: [.pr, .issue], to: Pick(include: [.me]), toRoles: [.reviewRequested])))
            .map(\.slot) == ["to"])
        #expect(InboxEngine.problems(Rule(scope: Scope(kinds: [.pr, .workflow], in: Pick()))).contains { $0.slot == "kind" })
    }

    @Test func aScopeSavedWithOneKindReadsAsASetOfIt() throws {
        let old = Data(#"{"kind":"issue","toRoles":["assigned"]}"#.utf8)
        #expect(try JSONDecoder().decode(Scope.self, from: old) == Scope(kinds: [.issue], toRoles: [.assigned]))
        let both = Scope(kinds: [.issue, .pr], in: Pick(include: [.owned]))
        let json = try #require(String(data: JSONEncoder().encode(both), encoding: .utf8))
        #expect(json.contains(#""kinds":["pr","issue"]"#) && !json.contains(#""kind":"#))
        #expect(try JSONDecoder().decode(Scope.self, from: Data(json.utf8)) == both)
    }

    @Test func aBuildFromBeforeKindsReadsTheFirstKindOfEachRuleSaved() throws {
        // The scope as builds from before `kinds` declared it.
        struct OneKind: Decodable { var kind: ThingKind }
        let saving = JSONEncoder()
        saving.userInfo[Scope.withLegacyKind] = true
        for (kinds, first) in [([ThingKind.issue, .pr], ThingKind.pr), ([.issue], .issue), ([.workflow], .workflow)] {
            let data = try saving.encode(Scope(kinds: Set(kinds)))
            #expect(try JSONDecoder().decode(OneKind.self, from: data).kind == first)
            #expect(try JSONDecoder().decode(Scope.self, from: data) == Scope(kinds: Set(kinds)))
        }
        // Only the saved state has it: not the rules' fingerprint, nor what the Router reads.
        #expect(!String(decoding: try JSONEncoder().encode(Scope(kinds: [.pr])), as: UTF8.self).contains(#""kind":"#))
    }

    @Test func oldSavedConditionsDecodeWithTheDefaultSince() throws {
        let labeled = Data(#"{"newComment":{"by":{"include":[{"me":{}}],"except":[]}}}"#.utf8)
        #expect(try JSONDecoder().decode(Condition.self, from: labeled) == .newComment(by: Pick(include: [.me])))
        let mention = Data(#"{"mentions":{"_0":{"include":[],"except":[]}}}"#.utf8)
        #expect(try JSONDecoder().decode(Condition.self, from: mention) == .mentions(Pick()))
        let other = Data(#"{"noActivity":{"days":7}}"#.utf8)
        #expect(try JSONDecoder().decode(Condition.self, from: other) == .noActivity(days: 7))
    }

    @Test func conditionsRoundTripAndOnlyANonDefaultSinceIsWritten() throws {
        let all: [Condition] = [
            .newComment(by: Pick(include: [.me]), since: .myLastReview), .newReview(by: Pick(), since: .myLastComment),
            .newCommits(by: Pick()), .mentions(Pick(include: [.team("o/t"), .myTeams]), since: .myLastComment),
            .lastComment(by: Pick()), .unresolvedThreads(startedBy: Pick(), lastReplyBy: nil), .approved(by: Pick()),
            .changesRequested(by: Pick()), .checks([.failing]), .hasConflicts, .behindBase, .status([.draft]),
            .labeled(Pick(include: ["x"])), .noActivity(days: 3), .greptileBelow(4), .workflow([.failing]),
        ]
        for c in all { #expect(try JSONDecoder().decode(Condition.self, from: JSONEncoder().encode(c)) == c) }
        let plain = String(decoding: try JSONEncoder().encode(Condition.newComment(by: Pick())), as: UTF8.self)
        #expect(!plain.contains("since"))
        let rule = Rule(scope: Scope(kinds: [.pr]), conditions: all)
        #expect(try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule)) == rule)
    }

    @Test func sinceDoneCountsAfterDoneAndRuleCreation() {
        var t = pr()
        t.comments = [comment("c1", stranger, at: -30), comment("c2", stranger, at: -10)]
        let r = Rule(scope: Scope(kinds: [.pr]), conditions: [.newComment(by: Pick())], createdAt: now.addingTimeInterval(-20))
        #expect(keys(r, t) == ["comment:c2"])
        let marks = EntryMarks(doneAt: now.addingTimeInterval(-5))
        #expect(keys(r, t, marks: marks) == nil)
    }

    @Test func sinceMyLastReviewCountsAfterMyLatestReviewAndNeverWithoutOne() {
        var t = pr(by: stranger)
        t.comments = [comment("c1", stranger, at: -300), comment("c2", stranger, at: -100), comment("c3", stranger, at: -20)]
        let r = rule([.newComment(by: Pick(), since: .myLastReview)])
        // I never reviewed: nothing matches, whatever was said.
        #expect(keys(r, t) == nil)
        t.reviews = [ThingReview(id: "r1", author: me, state: .approved, at: now.addingTimeInterval(-200)),
                     ThingReview(id: "r2", author: stranger, state: .commented, at: now.addingTimeInterval(-50))]
        #expect(keys(r, t) == ["comment:c2", "comment:c3"])
        // A later review with words (a comment of mine) moves it on.
        t.comments.append(ThingComment(id: "r3", author: me, at: now.addingTimeInterval(-60), snippet: "x", isReview: true))
        #expect(keys(r, t) == ["comment:c3"])
        // The reviews others wrote after mine are new reviews.
        #expect(keys(rule([.newReview(by: Pick(), since: .myLastReview)]), t) == ["review:r2"])
        // Done doesn't move this cutoff: what is still after my review is still there (keys stay the same).
        #expect(keys(r, t, marks: EntryMarks(doneAt: now)) == ["comment:c3"])
    }

    @Test func sinceMyLastCommentCountsAfterMyCommentsReviewsWithTextAndReplies() {
        var t = pr(by: stranger)
        t.comments = [comment("c1", stranger, at: -300), comment("c2", me, at: -200), comment("c3", stranger, at: -100)]
        let r = rule([.newComment(by: Pick(), since: .myLastComment)])
        #expect(keys(r, t) == ["comment:c3"])
        // A reply of mine in a thread counts.
        var reply = thread("t1", by: stranger, last: me, reply: "r9")
        reply.lastReplyAt = now.addingTimeInterval(-50)
        t.threads = [reply]
        #expect(keys(r, t) == nil)
        // Nothing of mine at all: since the thing was created.
        var fresh = pr(by: stranger)
        fresh.comments = [comment("c1", stranger, at: -300)]
        #expect(keys(r, fresh) == ["comment:c1"])
        #expect(keys(rule([.mentions(Pick(), since: .myLastComment)]), fresh) == nil)
    }

    @Test func sinceNeedsReviewsAndIssuesHaveNone() {
        let issue = Rule(scope: Scope(kinds: [.issue]), conditions: [.newComment(by: Pick(), since: .myLastReview)])
        #expect(InboxEngine.problems(issue).map(\.condition) == [0])
        let ok = Rule(scope: Scope(kinds: [.issue]), conditions: [.newComment(by: Pick(), since: .myLastComment)])
        #expect(InboxEngine.problems(ok).isEmpty)
    }

    @Test func aReviewRequestIsAFactKeyedByWhenItWasMade() {
        var t = pr(by: stranger)
        t.requestedReviewers = ["me"]
        t.reviewRequests = [ThingReviewRequest(reviewer: "me", at: now.addingTimeInterval(-500))]
        let scope = Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.reviewRequested])
        let r = Rule(scope: scope, createdAt: .distantPast)
        let first = InboxEngine.facts(r, t, marks: nil, context: context())
        #expect(first?.count == 1)
        // I review; the request is gone and so is the thing.
        var reviewed = t
        reviewed.requestedReviewers = []
        reviewed.reviewRequests = []
        #expect(InboxEngine.facts(r, reviewed, marks: nil, context: context()) == nil)
        // Asked again: another request, another fact (it notifies and is not Done any more).
        var again = t
        again.reviewRequests = [ThingReviewRequest(reviewer: "me", at: now.addingTimeInterval(-5))]
        let second = InboxEngine.facts(r, again, marks: nil, context: context())
        #expect(second?.count == 1 && second?[0].key != first?[0].key)
        let category = InboxCategory(name: "R", symbol: "eye", color: .blue, rules: [r])
        let done = EntryMarks(seen: Set(first!.map(\.key)), acked: Set(first!.map(\.key)))
        #expect(InboxEngine.evaluate(things: [t], categories: [category], marks: [t.id: done], context: context()).first?.isDone == true)
        #expect(InboxEngine.evaluate(things: [again], categories: [category], marks: [t.id: done], context: context()).first?.isDone == false)
    }

    @Test func aReviewRequestWithoutATimeFallsBackToCreation() {
        var t = pr(by: stranger)
        t.requestedReviewers = ["me"]
        let r = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.reviewRequested]), createdAt: .distantPast)
        #expect(keys(r, t) == ["requested:me:\(Int(t.createdAt.timeIntervalSince1970))"])
        // Only assigned: still the plain open fact.
        t.assignees = ["me"]
        t.requestedReviewers = []
        let assigned = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.assigned]), createdAt: .distantPast)
        #expect(keys(assigned, t) == ["open"])
    }

    @Test func behindBaseIsKeyedByTheHeadCommit() {
        var t = pr()
        let r = rule([.behindBase])
        #expect(keys(r, t) == nil)
        t.behindBase = true
        t.headSha = "abc"
        #expect(keys(r, t) == ["behind:abc"])
        t.headSha = "def"
        #expect(keys(r, t) == ["behind:def"])
        t.headSha = nil
        #expect(keys(r, t) == ["behind:\(Int(t.updatedAt.timeIntervalSince1970))"])
        let issue = Rule(scope: Scope(kinds: [.issue]), conditions: [.behindBase])
        #expect(InboxEngine.problems(issue).map(\.condition) == [0])
    }

    @Test func teamsMatchRequestedTeamReviewersAndMyTeams() {
        var t = pr(by: stranger)
        t.requestedReviewers = ["Acme/Core"]
        t.reviewRequests = [ThingReviewRequest(reviewer: "Acme/Core", at: now.addingTimeInterval(-9))]
        func scope(_ refs: [PersonRef]) -> Rule {
            Rule(scope: Scope(kinds: [.pr], to: Pick(include: refs), toRoles: [.reviewRequested]), createdAt: .distantPast)
        }
        #expect(keys(scope([.team("acme/core")]), t)?.count == 1)
        #expect(keys(scope([.team("@acme/other")]), t) == nil)
        #expect(keys(scope([.myTeams]), t) == nil)
        var ctx = context()
        ctx.myTeams = ["acme/core"]
        #expect(keys(scope([.myTeams]), t, ctx: ctx)?.count == 1)
        // A user doesn't match a team slug.
        #expect(keys(scope([.user("Acme")]), t) == nil)
    }

    @Test func teamsOnlyMakeSenseInToForReviewRequestsOnPRs() {
        let byTeam = Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.team("o/t")])))
        #expect(InboxEngine.problems(byTeam).map(\.slot) == ["by"])
        let assigned = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.myTeams]), toRoles: [.assigned]))
        #expect(InboxEngine.problems(assigned).map(\.slot) == ["to"])
        let issue = Rule(scope: Scope(kinds: [.issue], to: Pick(include: [.team("o/t")]), toRoles: [.mentioned]))
        #expect(InboxEngine.problems(issue).map(\.slot) == ["to"])
        let ok = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.me, .myTeams, .team("o/t")]), toRoles: [.reviewRequested]))
        #expect(InboxEngine.problems(ok).isEmpty)
        let comment = Rule(scope: Scope(kinds: [.pr]), conditions: [.newComment(by: Pick(include: [.myTeams]))])
        #expect(InboxEngine.problems(comment).map(\.condition) == [0])
    }
}
