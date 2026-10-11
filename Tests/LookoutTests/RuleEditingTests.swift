import Foundation
import Testing
@testable import Lookout

@Suite struct RuleEditingTests {
    @Test func switchingToWorkflowsKeepsReposAndSaysWhatWasDropped() {
        let rule = Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me]), in: Pick(include: [.repo("a/b"), .involved])),
                        conditions: [.checks([.failing]), .greptileBelow(4)])
        let (out, dropped) = RuleEditing.switchKinds(rule, to: [.workflow])
        #expect(out.scope.kinds == [.workflow])
        #expect(out.scope.by == nil)
        #expect(out.scope.in?.include == [.repo("a/b")])
        #expect(out.conditions == [.workflow([.failing])])
        #expect(!dropped.isEmpty)
    }

    @Test func switchingToIssuesDropsReviewRequested() {
        let rule = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.me])), conditions: [.approved(by: Pick()), .labeled(Pick())])
        let (out, dropped) = RuleEditing.switchKinds(rule, to: [.issue])
        #expect(!out.scope.toRoles.contains(.reviewRequested))
        #expect(out.conditions == [.labeled(Pick())])
        #expect(!dropped.isEmpty)
    }

    @Test func prsAndIssuesTickTogetherAndWorkflowsAlone() {
        #expect(RuleEditing.toggling(.issue, on: true, in: [.pr]) == [.pr, .issue])
        #expect(RuleEditing.toggling(.pr, on: false, in: [.pr, .issue]) == [.issue])
        // The last one stays.
        #expect(RuleEditing.toggling(.issue, on: false, in: [.issue]) == [.issue])
        #expect(RuleEditing.toggling(.workflow, on: true, in: [.pr, .issue]) == [.workflow])
        #expect(RuleEditing.toggling(.pr, on: true, in: [.workflow]) == [.pr])
        #expect(Set<ThingKind>([.issue, .pr]).label == "PRs and issues" && Set<ThingKind>([.issue]).label == "Issues")
    }

    @Test func addingIssuesKeepsWhatBothHaveAndSaysTheRest() {
        let rule = Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.me]), toRoles: [.assigned, .reviewRequested]),
                        conditions: [.checks([.failing]), .newComment(by: Pick(), since: .myLastReview), .status([.draft, .closed])])
        let (out, dropped) = RuleEditing.switchKinds(rule, to: [.pr, .issue])
        #expect(out.scope.kinds == [.pr, .issue])
        // Review requested still reaches the PRs.
        #expect(out.scope.toRoles == [.assigned, .reviewRequested])
        #expect(out.conditions == [.newComment(by: Pick(), since: .done), .status([.draft, .closed])])
        #expect(dropped == ["check states", "since my last review"])
        #expect(InboxEngine.problems(out).isEmpty)
        // Issues alone: no draft, and no review requested.
        let issues = RuleEditing.switchKinds(out, to: [.issue])
        #expect(issues.rule.conditions.last == .status([.closed]) && issues.rule.scope.toRoles == [.assigned])
        #expect(issues.dropped == ["draft and merged", "review requested"])
    }

    @Test @MainActor func aRepoTypedInAPickerIsARepoOrAWholeOwner() {
        let data = EditorData(store: Store())
        #expect(data.parseRepo(" b/two ") == .repo("b/two"))
        #expect(data.parseRepo("b/*") == .owner("b"))
        // Not owner/name: nothing to add.
        #expect(data.parseRepo("two") == nil && data.parseRepo("b/") == nil && data.parseRepo("b/two/x") == nil)
        #expect(data.parseRepo("b c/two") == nil)
    }

    @Test func sameKindChangesNothing() {
        let rule = Rule(scope: Scope(kinds: [.pr]))
        let (out, dropped) = RuleEditing.switchKinds(rule, to: [.pr])
        #expect(out == rule)
        #expect(dropped.isEmpty)
    }

    @Test @MainActor func greptileIsFoundByAnyOfItsNames() {
        let store = Store()
        store.persists = false
        let data = EditorData(store: store)
        let user = PersonRef.user("greptile-apps[bot]")
        for q in ["greptile", "@greptile", "Greptile", "greptile-apps", "@greptile-apps[bot]"] {
            #expect(data.searchKeys(user).contains { $0.contains(q.lowercased().replacingOccurrences(of: "@", with: "")) })
        }
        #expect(data.parsePerson("@greptile") == user)
        #expect(data.parsePerson("@toks") == .user("toks"))
    }
}

private final class RepoCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func add(_ p: String) { lock.withLock { paths.append(p) } }
    var all: [String] { lock.withLock { paths } }
}

@Suite @MainActor struct RepoCanonicalTests {
    private func store(_ calls: RepoCalls) -> Store {
        let s = Store()
        s.persists = false
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        s.gh.session = StubbedGitHub.session { request in
            let path = request.url?.path ?? ""
            calls.add(path)
            switch path {
            case "/repos/containers/libkrun":
                return .init(200, #"{"full_name":"libkrun/libkrun","default_branch":"main"}"#)
            case "/repos/libkrun/libkrun": return .init(200, #"{"full_name":"libkrun/libkrun","default_branch":"main"}"#)
            case "/repos/a/gone": return .init(404, #"{"message":"Not Found"}"#)
            case "/repos/a/ok": return .init(200, #"{"full_name":"a/ok","default_branch":"main"}"#)
            default: return .init(500, "{}")
            }
        }
        return s
    }

    @Test func aMovedRepoIsFoundOnceAndAMissingOneIsMarked() async {
        let calls = RepoCalls()
        let s = store(calls)
        #expect(await s.lookUpRepo("containers/libkrun") == .moved("libkrun/libkrun"))
        #expect(await s.lookUpRepo("Containers/libkrun") == .moved("libkrun/libkrun"))
        #expect(await s.lookUpRepo("a/ok") == .same)
        #expect(await s.lookUpRepo("a/gone") == .missing)
        #expect(await s.lookUpRepo("a/gone") == .missing)
        #expect(s.missingRepos == ["a/gone"])
        #expect(calls.all.filter { $0 == "/repos/containers/libkrun" }.count == 1)
        #expect(calls.all.filter { $0 == "/repos/a/gone" }.count == 1)
        // An error that isn't a 404 (offline, rate limit) leaves it as typed, not red.
        #expect(await s.lookUpRepo("x/y") == .unknown)
        #expect(s.missingRepos == ["a/gone"])
    }

    @Test func aMissingRepoBlocksSavingAndShowsTheReason() {
        let rule = Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo("A/Gone")])), conditions: [])
        let found = RuleEditing.problems(rule, groups: [], isCI: false, missing: ["a/gone"])
        #expect(found.map(\.slot) == ["in"])
        #expect(RuleEditing.problems(rule, groups: [], isCI: false).isEmpty)
    }

    @Test func aGroupGoneFromAConditionTurnsTheRuleOff() {
        let trusted = InboxGroup(name: "Trusted", kind: .people, members: ["ann"])
        let gone = Pick<PersonRef>(except: [.group(trusted.id)])
        for condition: Condition in [.newComment(by: gone, since: .done), .approved(by: gone),
                                     .unresolvedThreads(startedBy: nil, lastReplyBy: gone),
                                     .unresolvedThreads(startedBy: gone, lastReplyBy: nil)] {
            let rule = Rule(scope: Scope(kinds: [.pr]), conditions: [condition])
            #expect(RuleEditing.problems(rule, groups: [trusted], isCI: false).isEmpty)
            let found = RuleEditing.problems(rule, groups: [], isCI: false)
            #expect(found.map(\.condition) == [0])
            #expect(found.map(\.reason) == ["This group no longer exists"])
        }
    }

    @Test func savedRulesAndGroupsAreRenamedOnceAtSync() async {
        let calls = RepoCalls()
        let s = store(calls)
        var category = InboxCategory(name: "C", symbol: "star", color: .blue, notifies: false)
        category.rules = [Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo("containers/libkrun"), .owned], except: [.repo("a/ok")])),
                               conditions: [])]
        s.categories = [category]
        s.groups = [InboxGroup(name: "G", kind: .repos, members: ["containers/libkrun", "libkrun/libkrun", "o/*"])]
        await s.canonicalizeSavedRepos()
        #expect(s.categories[0].rules[0].scope.in?.include == [.repo("libkrun/libkrun"), .owned])
        #expect(s.categories[0].rules[0].scope.in?.except == [.repo("a/ok")])
        #expect(s.groups[0].members == ["libkrun/libkrun", "o/*"])
        let first = calls.all.count
        await s.canonicalizeSavedRepos()
        #expect(calls.all.count == first)
    }

    @Test func sinceIsOnlyOnActivityAndIssuesDontOfferMyLastReview() {
        let c = Condition.newComment(by: Pick())
        #expect(c.with(since: .myLastReview) == .newComment(by: Pick(), since: .myLastReview))
        #expect(Condition.mentions(Pick(include: [.me])).with(since: .myLastComment).since == .myLastComment)
        #expect(Condition.hasConflicts.since == nil && Condition.hasConflicts.with(since: .myLastReview) == .hasConflicts)
        // Changing who keeps the since; the other way round too.
        #expect(c.with(since: .myLastComment).with(people: Pick(include: [.me])) == .newComment(by: Pick(include: [.me]), since: .myLastComment))
        #expect(c.with(people: Pick(include: [.me])).since == .done)
        #expect(RuleEditing.sinces([.pr]).contains(.myLastReview) && !RuleEditing.sinces([.issue]).contains(.myLastReview))
    }

    @Test func behindBaseIsOfferedForPRsOnlyAndSurvivesSwitchingToIssuesNever() {
        #expect(RuleEditing.offered([.pr]).contains(.behindBase) && !RuleEditing.offered([.issue]).contains(.behindBase))
        let result = RuleEditing.switchKinds(Rule(scope: Scope(kinds: [.pr]), conditions: [.behindBase, .newComment(by: Pick(), since: .myLastComment)]), to: [.issue])
        #expect(result.rule.conditions == [.newComment(by: Pick(), since: .myLastComment)] && result.dropped.count == 1)
    }

    @Test @MainActor func teamsAreTypedAndSuggestedOnlyWhereTheyAreAllowed() {
        let s = Store()
        s.persists = false
        s.myTeams = ["acme/core"]
        var t = Thing(id: "pr:a/b#1", kind: .pr, repo: "a/b", number: 1, title: "t", url: URL(string: "https://github.com/a/b/pull/1")!,
                      createdAt: Date(), updatedAt: Date())
        t.requestedReviewers = ["acme/ops", "bob"]
        s.things[t.id] = t
        let data = EditorData(store: s)
        let withTeams = data.peopleOptions("", Pick(), teams: true).map(\.value)
        #expect(withTeams.contains(.myTeams) && withTeams.contains(.team("acme/core")) && withTeams.contains(.team("acme/ops")))
        let without = data.peopleOptions("", Pick()).map(\.value)
        #expect(!without.contains(.myTeams) && !without.contains(.team("acme/core")))
        #expect(data.peopleOptions("ops", Pick(), teams: true).map(\.value) == [.team("acme/ops")])
        #expect(data.parsePerson("@acme/core", teams: true) == .team("acme/core"))
        #expect(data.parsePerson("acme/core", teams: false) == nil)
        #expect(data.parsePerson("my teams", teams: true) == .myTeams)
        #expect(data.parsePerson("@bob", teams: true) == .user("bob"))
    }

    @Test func theDaysFieldFollowsUndoUnlessYouAreTypingIt() {
        // Undo took 14 back to 7 while the field wasn't being typed in: it shows 7.
        #expect(DaysField.synced("14", to: 7, focused: false) == "7")
        #expect(DaysField.synced("7", to: 7, focused: false) == nil)
        // Typing: what you typed is what set it, and a field you cleared to type in stays clear.
        #expect(DaysField.synced("14", to: 14, focused: true) == nil)
        #expect(DaysField.synced("", to: 7, focused: true) == nil)
        // An undo while the field has the keyboard still shows what it is now.
        #expect(DaysField.synced("14", to: 7, focused: true) == "7")
    }

    @MainActor @Test func theCountUnderARuleIsTakenAgainWhenWhatItCountsInChanges() {
        let store = InboxFixture.store([InboxFixture.pr(1)])
        let rule = store.categories[0].rules[0]
        let before = RuleEditor.previewKey(rule, store: store)
        // A refresh brings a thing: the same rule, counted again.
        store.things["pr:a/one#2"] = InboxFixture.pr(2)
        #expect(RuleEditor.previewKey(rule, store: store) != before)
        let refreshed = RuleEditor.previewKey(rule, store: store)
        // So do a group edited and time crossing a threshold.
        store.groups.append(InboxGroup(name: "g", kind: .people, members: ["x"]))
        #expect(RuleEditor.previewKey(rule, store: store) != refreshed)
        let grouped = RuleEditor.previewKey(rule, store: store)
        store.inboxTimePassed()
        #expect(RuleEditor.previewKey(rule, store: store) != grouped)
    }
}
