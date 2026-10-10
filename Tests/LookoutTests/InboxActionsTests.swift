import Foundation
import Testing
@testable import Lookout

/// Stands in for the world: records what actions would do.
@MainActor
final class FakePerformer: ActionPerformer {
    var sessions: [(folder: String, prompt: String, title: String)] = []
    var comments: [(repo: String, number: Int, body: String)] = []
    var reruns: [Int] = []
    var clones: [String: String] = [:]
    var failed: [FailedRun] = []
    var failure: Error?

    func startSession(folder: String, prompt: String, title: String) async throws -> String {
        if let failure { throw failure }
        sessions.append((folder, prompt, title))
        return "local_\(sessions.count)"
    }

    func comment(repo: String, number: Int, body: String) async throws -> URL? {
        if let failure { throw failure }
        comments.append((repo, number, body))
        return URL(string: "https://github.com/\(repo)/pull/\(number)#issuecomment-1")
    }

    func failedRuns(for thing: Thing) async throws -> [FailedRun] { failed }

    func rerun(repo: String, run: FailedRun) async throws -> Int {
        if let failure { throw failure }
        reruns.append(run.id)
        return 2
    }

    func clone(of repo: String) -> String? { clones[repo] }
}

@MainActor
@Suite(.serialized) struct InboxActionsTests {
    private let session = CategoryAction.make(.session(.folder("/p/app"), prompt: "Look at {title} by {author} ({repo}#{number}) {url}"))

    /// A store whose category has `actions` and holds PRs with a Greptile score below 5.
    private func store(_ things: [Thing], actions: [CategoryAction], performer: FakePerformer? = nil) -> (Store, FakePerformer) {
        let performer = performer ?? FakePerformer()
        var category = InboxFixture.category()
        category.actions = ActionList(actions)
        let store = InboxFixture.store(things, category: category)
        store.actionPerformer = performer
        return (store, performer)
    }

    private func add(_ store: Store, _ thing: Thing) { store.things[thing.id] = thing }

    @Test func whatIsAlreadyThereWhenTheActionIsMadeIsNeverRun() async {
        let (store, performer) = store([InboxFixture.pr(1), InboxFixture.pr(2)], actions: [session])
        await store.runActions()
        #expect(performer.sessions.isEmpty)
        // A refresh with the same things is still nothing.
        await store.runActions()
        #expect(performer.sessions.isEmpty)
        // Something new comes in.
        add(store, InboxFixture.pr(3))
        await store.runActions()
        #expect(performer.sessions.count == 1)
    }

    @Test func aRuleChangeTakesWhatMatchesAsOld() async {
        let (store, performer) = store([InboxFixture.pr(1)], actions: [session])
        await store.runActions()
        add(store, InboxFixture.pr(2, greptile: 5))
        // The rule now takes score 5 too: PR 2 is in, but it was not new.
        store.categories[0].rules[0].conditions = [.greptileBelow(6)]
        await store.runActions()
        #expect(performer.sessions.isEmpty)
        add(store, InboxFixture.pr(3, greptile: 5))
        await store.runActions()
        #expect(performer.sessions.count == 1)
    }

    @Test func anActionAddedLaterBaselinesOnlyItself() async {
        let (store, performer) = store([InboxFixture.pr(1)], actions: [session])
        await store.runActions()
        let comment = CategoryAction.make(.comment("hi"))
        store.categories[0].actions.items.append(comment)
        add(store, InboxFixture.pr(2))
        store.baselineActions()
        // The comment never touches PR 1 or 2 (it was made after both); the session, already running, takes PR 2.
        await store.runActions()
        #expect(performer.comments.isEmpty)
        #expect(performer.sessions.count == 1)
    }

    @Test func oncePerThingAndNeverAgainWhileItStays() async {
        let (store, performer) = store([], actions: [session])
        await store.runActions()
        add(store, InboxFixture.pr(4, title: "Fix it"))
        await store.runActions()
        await store.runActions()
        await store.runActions()
        #expect(performer.sessions.count == 1)
    }

    @Test func leavingAndComingBackAgainRunsOnlyAfterTheCooldown() async {
        let (store, performer) = store([], actions: [session])
        let t0 = Date()
        await store.runActions(now: t0)
        add(store, InboxFixture.pr(4))
        await store.runActions(now: t0)
        #expect(performer.sessions.count == 1)
        // Out of the category (score 5), then back within the hour: the same visit.
        add(store, InboxFixture.pr(4, greptile: 5))
        await store.runActions(now: t0.addingTimeInterval(60))
        add(store, InboxFixture.pr(4, greptile: 3))
        await store.runActions(now: t0.addingTimeInterval(120))
        #expect(performer.sessions.count == 1)
        // Out for good measure, forgotten after the cooldown, back: a new visit.
        add(store, InboxFixture.pr(4, greptile: 5))
        await store.runActions(now: t0.addingTimeInterval(120 + InboxActions.reentryCooldown + 10))
        add(store, InboxFixture.pr(4, greptile: 3))
        await store.runActions(now: t0.addingTimeInterval(120 + InboxActions.reentryCooldown + 20))
        #expect(performer.sessions.count == 2)
    }

    @Test func doneThingsDoNotRun() async {
        let (store, performer) = store([], actions: [session])
        await store.runActions()
        add(store, InboxFixture.pr(5))
        store.markDone(store.entries[0])
        await store.runActions()
        #expect(performer.sessions.isEmpty)
    }

    // MARK: On each new fact

    private func commented(_ id: String, by login: String, at: Date = Date()) -> ThingComment {
        ThingComment(id: id, author: Person(login: login), at: at, snippet: "snippet \(id)")
    }

    private func conversation(_ comments: [ThingComment]) -> Thing {
        var thing = InboxFixture.pr(7, greptile: nil)
        thing.comments = comments
        return thing
    }

    private func watchingComments(_ trigger: ActionTrigger, _ kind: ActionKind) -> (Store, FakePerformer) {
        var action = CategoryAction.make(kind)
        action.trigger = trigger
        let performer = FakePerformer()
        let category = InboxCategory(name: "Talk", symbol: "star", color: .blue,
                                     rules: [Rule(scope: Scope(kind: .pr), conditions: [.lastComment(by: Pick())], createdAt: .distantPast)],
                                     actions: ActionList([action]))
        let store = InboxFixture.store([conversation([commented("c1", by: "alice")])], category: category)
        store.actionPerformer = performer
        return (store, performer)
    }

    @Test func onEachNewFactRunsForEveryNewFactButNotForTheOnesThatWereThere() async {
        let (store, performer) = watchingComments(.eachFact, .comment("seen {number}"))
        await store.runActions()
        #expect(performer.comments.isEmpty)
        add(store, conversation([commented("c1", by: "alice"), commented("c2", by: "bob", at: Date().addingTimeInterval(10))]))
        await store.runActions()
        #expect(performer.comments.count == 1)
        await store.runActions()
        #expect(performer.comments.count == 1)
        add(store, conversation([commented("c3", by: "carol", at: Date().addingTimeInterval(20))]))
        await store.runActions()
        #expect(performer.comments.count == 2)
    }

    @Test func enterModeIgnoresLaterFactsOfAThingAlreadyHandled() async {
        let (store, performer) = watchingComments(.enter, .comment("hi"))
        await store.runActions()
        add(store, conversation([commented("c2", by: "bob", at: Date().addingTimeInterval(10))]))
        await store.runActions()
        #expect(performer.comments.isEmpty)
    }

    // MARK: Loop guard

    @Test func yourOwnCommentNeverStartsAnAction() async {
        let (store, performer) = watchingComments(.eachFact, .comment("auto"))
        await store.runActions()
        // Only my comment is new: the fact is mine.
        add(store, conversation([commented("c9", by: "me", at: Date().addingTimeInterval(30))]))
        await store.runActions()
        #expect(performer.comments.isEmpty)
        // Someone answers: that one counts, once.
        add(store, conversation([commented("c10", by: "alice", at: Date().addingTimeInterval(40))]))
        await store.runActions()
        add(store, conversation([commented("c11", by: "Me", at: Date().addingTimeInterval(50))]))
        await store.runActions()
        #expect(performer.comments.count == 1)
    }

    // MARK: Words

    @Test func placeholdersAreFilled() async {
        let (store, performer) = store([], actions: [session])
        await store.runActions()
        var thing = InboxFixture.pr(12, repo: "o/r", title: "Warm pool", by: Person(login: "alice"))
        thing.comments = [commented("c1", by: "bob")]
        add(store, thing)
        await store.runActions()
        let sent = performer.sessions.first
        #expect(sent?.folder == "/p/app")
        #expect(sent?.prompt.hasPrefix("Look at Warm pool by @alice (o/r#12) https://github.com/o/r/pull/12") == true)
    }

    @Test func aCommentIsPostedWithPlaceholdersAndNothingElse() async {
        let (store, performer) = store([], actions: [.make(.comment("Hi {author}: {repo}#{number} {title}"))])
        await store.runActions()
        add(store, InboxFixture.pr(3, repo: "o/r", title: "T", by: Person(login: "alice")))
        await store.runActions()
        #expect(performer.comments.map(\.body) == ["Hi @alice: o/r#3 T"])
        #expect(performer.comments.first?.number == 3)
    }

    @Test func clonesAreFoundByTheirRemotes() {
        #expect(LocalClones.repo(fromRemote: "git@github.com:Owner/Repo.git") == "owner/repo")
        #expect(LocalClones.repo(fromRemote: "https://github.com/owner/repo") == "owner/repo")
        #expect(LocalClones.repo(fromRemote: "ssh://git@github.com/owner/repo.git") == "owner/repo")
        #expect(LocalClones.repo(fromRemote: "https://gitlab.com/owner/repo") == nil)
        let remotes = ["/a/app/.worktrees/x": ["owner/app"], "/a/app": ["owner/app"], "/a/other": ["owner/other"]]
        #expect(LocalClones.find("Owner/App", in: ["/a/other", "/a/app/.worktrees/x", "/a/app"], remotes: { remotes[$0] ?? [] }) == "/a/app")
        #expect(LocalClones.find("owner/none", in: ["/a/app"], remotes: { remotes[$0] ?? [] }) == nil)
    }

    @Test func theRepoClonePicksTheFolderAndFailsWithoutOne() async {
        let performer = FakePerformer()
        let clone = CategoryAction.make(.session(.clone, prompt: "go"))
        let (store, _) = store([], actions: [clone], performer: performer)
        await store.runActions()
        add(store, InboxFixture.pr(1, repo: "o/r"))
        add(store, InboxFixture.pr(2, repo: "o/none"))
        performer.clones = ["o/r": "/code/r"]
        await store.runActions()
        #expect(performer.sessions.map(\.folder) == ["/code/r"])
        #expect(store.actionLedger.runs.values.contains { $0.state == .failed })
        // A failure is not retried.
        await store.runActions()
        #expect(performer.sessions.count == 1)
    }

    // MARK: Re-running

    @Test func failedChecksAreReRun() async {
        let performer = FakePerformer()
        performer.failed = [FailedRun(id: 11, name: "CI", url: nil), FailedRun(id: 12, name: "Lint", url: nil)]
        let rerun = CategoryAction.make(.rerun)
        let (store, _) = store([], actions: [rerun], performer: performer)
        await store.runActions()
        add(store, InboxFixture.pr(2))
        await store.runActions()
        #expect(performer.reruns == [11, 12])
    }

    @Test func aFailureIsShownOnTheEntryInDanger() async {
        let performer = FakePerformer()
        performer.failure = ActionFailure("GitHub rejected the token")
        let (store, _) = store([], actions: [.make(.comment("x"))], performer: performer)
        await store.runActions()
        add(store, InboxFixture.pr(2))
        await store.runActions()
        let chip = store.actionChips(for: store.entries[0]).first
        #expect(chip?.label.contains("GitHub rejected the token") == true && chip?.tint == .danger)
    }

    @Test func actionsThatDoNotApplyAreSkipped() async {
        let performer = FakePerformer()
        var workflow = Thing(id: "workflow:o/r:1@main", kind: .workflow, repo: "o/r", number: nil, title: "CI",
                             url: URL(string: "https://github.com/o/r/actions")!, createdAt: Date(), updatedAt: Date())
        workflow.checks = .failing
        let category = InboxCategory(name: "CI", symbol: "x", color: .red,
                                     rules: [Rule(scope: Scope(kind: .workflow, in: Pick()), conditions: [.workflow([.failing])], createdAt: .distantPast)],
                                     actions: ActionList([.make(.comment("x")), .make(.rerun)]))
        let store = InboxFixture.store([], category: category)
        store.actionPerformer = performer
        performer.failed = [FailedRun(id: 1, name: "CI", url: nil)]
        await store.runActions()
        add(store, workflow)
        await store.runActions()
        #expect(performer.comments.isEmpty)
        #expect(performer.reruns == [1])
    }

    // MARK: Rate limit, chips, persistence

    @Test func atMostTenRunPerRefreshAndTheRestWait() async {
        let (store, performer) = store([], actions: [session])
        await store.runActions()
        for n in 1...13 { add(store, InboxFixture.pr(n)) }
        await store.runActions()
        #expect(performer.sessions.count == 10)
        await store.runActions()
        #expect(performer.sessions.count == 13)
    }

    @Test func aSessionChipOpensTheSession() async {
        let (store, _) = store([], actions: [session])
        await store.runActions()
        add(store, InboxFixture.pr(2))
        await store.runActions()
        #expect(store.actionChips(for: store.entries[0]).first?.target == .session("local_1"))
    }

    @Test func withoutAPerformerNothingHappensInDemoOrWithoutPersistence() async {
        let (store, performer) = store([InboxFixture.pr(1)], actions: [session])
        store.actionPerformer = nil
        await store.runActions()
        add(store, InboxFixture.pr(2))
        await store.runActions()
        #expect(performer.sessions.isEmpty)
        #expect(store.actionLedger == ActionLedger())
    }

    @Test func aCategorysActionsAndTheLedgerSurviveARestart() throws {
        var category = InboxFixture.category()
        category.actions = ActionList([session])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lookout-actions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = Store()
        first.stateFile = folder.appendingPathComponent("state.json")
        first.categories = [category]
        first.actionLedger.set(ActionRun(category: category.id, thing: "pr:a/b#1", action: session.id, trigger: "enter",
                                         state: .running, at: Date()))
        first.save()
        first.flushSave()
        let second = Store()
        second.stateFile = folder.appendingPathComponent("state.json")
        second.load()
        #expect(second.categories.first?.actions == category.actions)
        // What was running when the app quit is said to have been interrupted, never run again.
        #expect(second.actionLedger.runs.values.first?.state == .failed)
    }

    @Test func previewDoesNothing() async {
        let performer = FakePerformer()
        performer.clones = ["o/r": "/code/r"]
        let thing = InboxFixture.pr(12, repo: "o/r", title: "Warm pool")
        let clone = CategoryAction.make(.session(.clone, prompt: "Look at {title}"))
        let lines = await InboxActions.preview(clone, category: "Mine", thing: thing, facts: [Fact(key: "k", label: "Greptile 3/5")],
                                               performer: performer)
        #expect(lines.joined(separator: "\n").contains("/code/r"))
        #expect(lines.joined(separator: "\n").contains("Look at Warm pool"))
        #expect(performer.sessions.isEmpty)
    }
}
