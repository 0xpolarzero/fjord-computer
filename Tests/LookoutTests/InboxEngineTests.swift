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
        Rule(scope: Scope(kind: .pr, by: Pick(include: [.me]), in: Pick(include: [.contributed])),
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
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.first?.label == "last comment: @greptile-apps[bot]")

        t.comments.append(comment("c3", me))  // my reply is now the last comment
        t.threads = [thread("t1", by: maintainer, last: stranger), thread("t2", by: maintainer, last: me),
                     thread("t3", by: stranger, last: stranger)]
        let threads = InboxEngine.facts(specRule, t, marks: nil, context: context())
        #expect(threads?.map(\.key) == ["thread:t1:r1"])
        #expect(threads?.first?.label == "1 unresolved")

        t.threads = []
        t.reviews = [ThingReview(id: "r1", author: maintainer, state: .changesRequested, at: now)]
        #expect(InboxEngine.facts(specRule, t, marks: nil, context: context())?.map(\.key) == ["changes:r1"])

        t.reviews = []
        t.greptileScore = 4
        let score = InboxEngine.facts(specRule, t, marks: nil, context: context())
        #expect(score?.map(\.label) == ["Greptile 4/5"])
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
            InboxEngine.facts(Rule(scope: Scope(kind: .pr, in: Pick(include: [ref]))), t, marks: nil, context: ctx) != nil
        }
        #expect(matches(.owner("A"), pr(repo: "a/one")))
        #expect(matches(.group(group.id), pr(repo: "c/any")))
        #expect(matches(.group(group.id), pr(repo: "d/x")))
        #expect(!matches(.group(group.id), pr(repo: "d/y")))
        #expect(matches(.involved, pr(repo: "z/z", by: me)))
        var other = pr(repo: "z/z", by: stranger)
        #expect(!matches(.involved, other))
        other.comments = [comment("c", me)]
        #expect(matches(.involved, other))
    }

    @Test func toRolesNarrowTheSlot() {
        var t = pr(by: stranger)
        t.requestedReviewers = ["me"]
        var scope = Scope(kind: .pr, to: Pick(include: [.me]), toRoles: [.assigned])
        #expect(InboxEngine.facts(Rule(scope: scope), t, marks: nil, context: context()) == nil)
        scope.toRoles = [.reviewRequested]
        #expect(InboxEngine.facts(Rule(scope: scope), t, marks: nil, context: context()) != nil)
    }

    @Test func approvalsReadEachReviewersLatestOpinion() {
        var t = pr()
        t.reviews = [ThingReview(id: "r1", author: maintainer, state: .changesRequested, at: now.addingTimeInterval(-50)),
                     ThingReview(id: "r2", author: maintainer, state: .approved, at: now.addingTimeInterval(-40)),
                     ThingReview(id: "r3", author: maintainer, state: .commented, at: now.addingTimeInterval(-30))]
        let rule = { (c: Condition) in Rule(scope: Scope(kind: .pr), conditions: [c], createdAt: .distantPast) }
        #expect(InboxEngine.facts(rule(.approved(by: Pick())), t, marks: nil, context: context())?.map(\.key) == ["approved:r2"])
        #expect(InboxEngine.facts(rule(.changesRequested(by: Pick())), t, marks: nil, context: context()) == nil)
    }

    @Test func statusReadyMeansOpenAndNotDraft() {
        let rule = Rule(scope: Scope(kind: .pr), conditions: [.status([.open])])
        #expect(InboxEngine.facts(rule, pr(), marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule, pr(status: .draft), marks: nil, context: context()) == nil)
    }

    @Test func noConditionsMatchEveryOpenThingWithANeutralFact() {
        let rule = Rule(scope: Scope(kind: .pr))
        #expect(InboxEngine.facts(rule, pr(), marks: nil, context: context())?.map(\.key) == ["open"])
        #expect(InboxEngine.facts(rule, pr(status: .draft), marks: nil, context: context()) != nil)
        #expect(InboxEngine.facts(rule, pr(status: .merged), marks: nil, context: context()) == nil)
    }

    @Test func allOfNeedsEveryCondition() {
        var t = pr()
        t.greptileScore = 3
        let rule = Rule(scope: Scope(kind: .pr), match: .all, conditions: [.greptileBelow(5), .hasConflicts])
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) == nil)
        t.hasConflicts = true
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.map(\.key) == ["greptile:3", "conflicts"])
    }

    @Test func staleNeedsTheDays() {
        var t = pr()
        t.updatedAt = now.addingTimeInterval(-8 * 86_400)
        let rule = Rule(scope: Scope(kind: .pr), conditions: [.noActivity(days: 7)])
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.first?.label == "no activity for 7 days")
        t.updatedAt = now.addingTimeInterval(-86_400)
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context()) == nil)
    }

    // MARK: Lifecycle

    @Test func activityIsOnlyNewSinceTheRuleAndSinceDone() {
        var t = pr()
        t.comments = [comment("old", stranger, at: -500), comment("new", stranger, at: -5)]
        var rule = Rule(scope: Scope(kind: .pr), conditions: [.newComment(by: Pick())])
        rule.createdAt = now.addingTimeInterval(-100)
        #expect(InboxEngine.facts(rule, t, marks: nil, context: context())?.map(\.key) == ["comment:new"])
        var marks = EntryMarks()
        marks.doneAt = now.addingTimeInterval(-1)
        #expect(InboxEngine.facts(rule, t, marks: marks, context: context()) == nil)
    }

    @Test func firstMatchingCategoryWinsEvenWhenHidden() {
        var t = pr()
        t.greptileScore = 3
        let any = Rule(scope: Scope(kind: .pr))
        let first = InboxCategory(name: "first", symbol: "a", color: .blue, rules: [any], hidden: true)
        let second = InboxCategory(name: "second", symbol: "b", color: .red, rules: [any])
        let entries = InboxEngine.evaluate(things: [t], categories: [first, second], marks: [:], context: context())
        #expect(entries.map(\.categoryID) == [first.id])
        let skipped = InboxCategory(name: "no", symbol: "c", color: .gray, rules: [Rule(scope: Scope(kind: .issue))])
        let fallback = InboxEngine.evaluate(things: [t], categories: [skipped, second], marks: [:], context: context())
        #expect(fallback.map(\.categoryID) == [second.id])
        #expect(InboxEngine.evaluate(things: [t], categories: [skipped], marks: [:], context: context()).isEmpty)
    }

    @Test func doneHoldsUntilANewFactArrives() {
        var t = pr()
        t.greptileScore = 3
        let category = InboxCategory(name: "c", symbol: "a", color: .blue, rules: [
            Rule(scope: Scope(kind: .pr), conditions: [.greptileBelow(5), .lastComment(by: Pick())], createdAt: .distantPast)])
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
        let rule = Rule(scope: Scope(kind: .workflow, in: Pick()), conditions: [.workflow([.failing])])
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

    @Test func workflowsScopeByBranchAndName() {
        let rule = { (on: [String]?, named: [String]?) in
            Rule(scope: Scope(kind: .workflow, in: Pick(include: [.repo("a/one")]), on: on, named: named),
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
        let loose = Rule(scope: Scope(kind: .pr), conditions: [.greptileBelow(5)])
        #expect(InboxEngine.facts(loose, merged, marks: nil, context: context()) == nil)
        let asking = Rule(scope: Scope(kind: .pr), conditions: [.greptileBelow(5), .status([.merged])])
        #expect(InboxEngine.facts(asking, merged, marks: nil, context: context())?.map(\.key) == ["status:merged"])
        let all = Rule(scope: Scope(kind: .pr), match: .all, conditions: [.greptileBelow(5), .status([.merged])])
        #expect(InboxEngine.facts(all, merged, marks: nil, context: context())?.map(\.key) == ["greptile:2", "status:merged"])
        #expect(InboxEngine.facts(asking, pr(), marks: nil, context: context()) == nil)
    }

    // MARK: Problems

    @Test func impossibleCombinationsAreFlagged() {
        func problems(_ scope: Scope, _ match: MatchMode = .any, _ conditions: [Condition] = []) -> [InboxEngine.Problem] {
            InboxEngine.problems(Rule(scope: scope, match: match, conditions: conditions))
        }
        let byMe = Pick<PersonRef>(include: [.me])
        #expect(problems(Scope(kind: .pr, by: byMe, to: byMe, toRoles: [.reviewRequested])).map(\.slot) == ["to"])
        #expect(problems(Scope(kind: .pr, by: byMe, to: byMe)).isEmpty)
        #expect(problems(Scope(kind: .pr, by: byMe), .any, [.approved(by: byMe), .changesRequested(by: Pick(include: [.user("x")]))])
            .map(\.condition) == [0])
        #expect(problems(Scope(kind: .pr, by: Pick(include: [.me, .bots], except: [.me]))).map(\.slot) == ["by"])
        #expect(problems(Scope(kind: .issue), .any, [.greptileBelow(3), .newComment(by: Pick())]).map(\.condition) == [0])
        #expect(problems(Scope(kind: .workflow), .any, [.workflow([.failing])]).map(\.slot) == ["in"])
        #expect(problems(Scope(kind: .workflow, in: Pick()), .any, [.workflow([.failing])]).isEmpty)
        #expect(problems(Scope(kind: .pr), .all, [.status([.draft]), .status([.merged])]).map(\.condition) == [1])
        #expect(problems(Scope(kind: .pr), .any, [.status([.draft]), .status([.merged])]).isEmpty)
        #expect(problems(Scope(kind: .pr), .all, [.status([.draft, .merged])]).isEmpty)
        #expect(problems(Scope(kind: .pr), .all, [.checks([.failing]), .checks([.passing])]).map(\.condition) == [1])
        #expect(problems(Scope(kind: .pr), .all, [.checks([.failing, .pending]), .checks([.pending])]).isEmpty)
    }

    @Test func everyKindOffersOnlyConditionsItCanMatch() {
        for kind in ThingKind.allCases {
            let rule = Rule(scope: Scope(kind: kind, in: Pick()), conditions: InboxEngine.conditions(for: kind))
            #expect(InboxEngine.problems(rule).isEmpty)
        }
    }
}
