import Foundation
import Testing
@testable import Lookout

@Suite struct RuleEditingTests {
    @Test func switchingToWorkflowsKeepsReposAndSaysWhatWasDropped() {
        let rule = Rule(scope: Scope(kind: .pr, by: Pick(include: [.me]), in: Pick(include: [.repo("a/b"), .involved])),
                        conditions: [.checks([.failing]), .greptileBelow(4)])
        let (out, dropped) = RuleEditing.switchKind(rule, to: .workflow)
        #expect(out.scope.kind == .workflow)
        #expect(out.scope.by == nil)
        #expect(out.scope.in?.include == [.repo("a/b")])
        #expect(out.conditions == [.workflow([.failing])])
        #expect(dropped.contains("by"))
        #expect(dropped.contains("anywhere you're involved"))
    }

    @Test func switchingToIssuesDropsReviewRequested() {
        let rule = Rule(scope: Scope(kind: .pr, to: Pick(include: [.me])), conditions: [.approved(by: Pick()), .labeled(Pick())])
        let (out, dropped) = RuleEditing.switchKind(rule, to: .issue)
        #expect(!out.scope.toRoles.contains(.reviewRequested))
        #expect(out.conditions == [.labeled(Pick())])
        #expect(dropped.contains("review requested"))
    }

    @Test func sameKindChangesNothing() {
        let rule = Rule(scope: Scope(kind: .pr))
        let (out, dropped) = RuleEditing.switchKind(rule, to: .pr)
        #expect(out == rule)
        #expect(dropped.isEmpty)
    }

    @Test func droppedNoticeUsesHumanWords() {
        let rule = Rule(scope: Scope(kind: .pr, by: Pick(include: [.me])),
                        conditions: [.greptileBelow(4), .unresolvedThreads(startedBy: nil, lastReplyBy: nil), .lastComment(by: Pick())])
        let (_, dropped) = RuleEditing.switchKind(rule, to: .workflow)
        #expect(RuleEditing.droppedNotice(dropped, for: .workflow)
                == "Dropped for Workflows: Greptile score, unresolved threads, last comment, and the by slot")
        #expect(RuleEditing.droppedNotice([], for: .pr) == nil)
        #expect(RuleEditing.droppedNotice(["by"], for: .workflow) == "Dropped for Workflows: The by slot")
    }

    @Test func iconFromTheNameWithoutJev() {
        #expect(CategoryIcon.local(name: "Security alerts") == "lock.shield")
        #expect(CategoryIcon.local(name: "Reviews") == "eye")
        #expect(CategoryIcon.local(name: "CI") == "xmark.seal")
        #expect(CategoryIcon.local(name: "Dependabot") == "cube")
        #expect(CategoryIcon.local(name: "Mine") == "person")
        #expect(CategoryIcon.local(name: "Team chatter") == "person.2")
        #expect(CategoryIcon.local(name: "Zebra") == nil)
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

    @Test func leavingTheEditorSavesAValidDraftAndKeepsAnInvalidOne() {
        var drafts = CategoryDrafts()
        let original = InboxCategory(name: "Mine", symbol: CategoryIcon.fallback, color: .blue, rules: [Rule(scope: Scope(kind: .pr))])
        var categories = [original]
        let editing = CategoryEditing.existing(original.id)

        #expect(drafts.leave(original, original: original, editing: editing, categories: &categories, groups: []) == .unchanged)

        var valid = original
        valid.name = "  Reviews "
        #expect(drafts.leave(valid, original: original, editing: editing, categories: &categories, groups: []) == .saved)
        #expect(categories.first?.name == "Reviews")
        #expect(drafts.kept.isEmpty)

        var invalid = original
        invalid.name = ""
        #expect(drafts.leave(invalid, original: original, editing: editing, categories: &categories, groups: []) == .kept)
        #expect(categories.first?.name == "Reviews")
        #expect(drafts.kept[editing] == invalid)

        var fresh = InboxCategory(name: "", symbol: CategoryIcon.fallback, color: .blue, rules: [])
        #expect(drafts.leave(fresh, original: fresh, editing: .new, categories: &categories, groups: []) == .unchanged)
        fresh.name = "New"
        #expect(drafts.leave(fresh, original: original, editing: .new, categories: &categories, groups: []) == .kept)
        #expect(drafts.kept[.new] == fresh && categories.count == 1)
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
        let rule = Rule(scope: Scope(kind: .pr, in: Pick(include: [.repo("A/Gone")])), conditions: [])
        let found = RuleEditing.problems(rule, groups: [], isCI: false, missing: ["a/gone"])
        #expect(found.map(\.reason) == [RuleEditing.noSuchRepo])
        #expect(found.first?.slot == "in")
        #expect(RuleEditing.problems(rule, groups: [], isCI: false).isEmpty)
    }

    @Test func savedRulesAndGroupsAreRenamedOnceAtSync() async {
        let calls = RepoCalls()
        let s = store(calls)
        var category = InboxCategory(name: "C", symbol: "star", color: .blue, notifies: false)
        category.rules = [Rule(scope: Scope(kind: .pr, in: Pick(include: [.repo("containers/libkrun"), .owned], except: [.repo("a/ok")])),
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
}
