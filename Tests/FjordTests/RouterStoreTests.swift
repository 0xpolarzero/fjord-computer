import Foundation
import Testing
@testable import Fjord

/// The Router as the store runs it: the feed after each read, the cards' actions, and the switch with its hook.
@MainActor
@Suite struct RouterStore {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(_ id: String, turns: Int, focused: Double = -60, summary: String? = "Done it") -> ClaudeSession {
        ClaudeSession(id: id, title: "Session \(id)", folder: "/code/app", completedTurns: turns,
                      lastActivity: now.addingTimeInterval(-60), lastFocused: now.addingTimeInterval(focused * 60),
                      lastUserMessage: now.addingTimeInterval(-120), summary: summary.map { .init(blocked: false, detail: $0) },
                      cliID: "cli-\(id)")
    }

    /// Sessions and Router on, the Router's files in `dir`, every session seen once.
    private func store(_ dir: TempDir, _ sessions: [ClaudeSession]) -> Store {
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Fjord Computer.app/Contents/MacOS/Fjord"
        s.interceptOpen = { _ in }
        s.claudeIsFrontmost = { false }
        s.claudeLink = .ok
        s.agents.enabled = true
        s.agents.enabledAt = now.addingTimeInterval(-3600)
        s.ingest(sessions, appUnread: [], claudeFrontmost: false, now: now)
        s.setRouterEnabled(true, now: now)
        return s
    }

    @Test func theFeedMakesCardsFromWhatTheStoreRead() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1), session("local_b", turns: 1)])
        await s.routerHookWork?.value
        var fresh: [RouterCard] = []
        s.onNewRouterCards = { fresh += $0 }
        #expect(s.router.cards.isEmpty)
        s.ingest([session("local_a", turns: 2), session("local_b", turns: 2, summary: nil)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(fresh.map(\.id).sorted() == ["local_a#t2", "local_b#t2"])
        #expect(s.routerCounts.notes == 2 && s.routerCounts.needsYou == 0)

        // Not again for the same read; nothing while the sessions extension is off.
        fresh = []
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(fresh.isEmpty)
        s.agents.enabled = false
        s.ingest([session("local_a", turns: 3)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(3))
        #expect(s.router.cards.count == 2)
    }

    @Test func aHandledTurnOutlastsItsSessionsArchivingAsTheStoreReadsIt() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 2)])
        s.router.handledTurns = ["local_a": 2]
        // Archived: the store's sessions leave it out, but the read still lists it, so the turn stays handled.
        var archived = session("local_a", turns: 2)
        archived.isArchived = true
        s.ingest([archived], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.claudeSessions["local_a"] == nil && s.router.handledTurns == ["local_a": 2])
        // Gone for good: forgotten.
        s.ingest([], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(s.router.handledTurns.isEmpty)
    }

    @Test func aSessionStillRunningSubagentsGetsItsCardWhenTheyAreDone() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        s.ingest([session("local_a", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.claudeTasks = ["local_a": [ClaudeTask(id: "t1", kind: .command, title: "swift test", since: now)]]
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.openRouterCards.isEmpty)
        s.claudeTasks = [:]
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
    }

    @Test func aTurnWhoseWorkIsntKnownYetIsReadAgainSoonAndOnlyThen() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        #expect(s.inventoryRecheck == nil)
        // The turn ended; the last read couldn't tell what it left running.
        s.ingest([session("local_a", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.claudeTaskInventory = []
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.openRouterCards.isEmpty && s.inventoryRecheck != nil)
        // The read it brings knows: the card, and no more re-reads.
        s.claudeTaskInventory = ["local_a"]
        s.feedRouter(now: now.addingTimeInterval(7))
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"] && s.inventoryRecheck == nil)
    }

    @Test func cardsAreListedOpenFirstNewestFirstAndCanBeMarked() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1), session("local_b", turns: 1)])
        await s.routerHookWork?.value
        s.ingest([session("local_a", turns: 2), session("local_b", turns: 1)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        s.ingest([session("local_a", turns: 2), session("local_b", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(s.routerCards.map(\.id) == ["local_b#t2", "local_a#t2"])
        s.setCardAddressed("local_b#t2", true, now: now.addingTimeInterval(3))
        #expect(s.routerCards.map(\.id) == ["local_a#t2", "local_b#t2"])
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
        #expect(s.router.cards.first { $0.id == "local_b#t2" }?.addressedBy == .you)
        s.setCardAddressed("local_b#t2", false)
        #expect(s.openRouterCards.count == 2)

        s.addressCards(forSession: "local_b", by: .router)
        #expect(s.router.cards.first { $0.id == "local_b#t2" }?.addressedBy == .router)
        var opened: [String] = []
        s.interceptOpen = { opened.append($0) }
        s.openCard("local_a#t2")
        #expect(opened.count == 1 && opened.first?.contains("Session local_a") == true)
        // Opening it addresses nothing.
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
    }

    @Test func routerCountsMatchFilteringAcrossKindsAndOutstandingWork() {
        let s = Store()
        s.persists = false
        let kinds: [RouterCard.Kind] = [.question, .plan, .done, .stuck, .asks, .approval, .waiting]
        s.router.cards = kinds.flatMap { kind in
            [RouterCard(id: "open-\(kind.rawValue)", sessionID: "open-\(kind.rawValue)", kind: kind,
                        title: "Open", folder: nil, text: "", createdAt: now),
             RouterCard(id: "closed-\(kind.rawValue)", sessionID: "closed-\(kind.rawValue)", kind: kind,
                        title: "Closed", folder: nil, text: "", createdAt: now, addressedAt: now, addressedBy: .you)]
        }
        s.router.cards.append(RouterCard(id: "busy-done", sessionID: "busy-done", kind: .done,
                                         title: "Still working", folder: nil, text: "", createdAt: now))
        let task = ClaudeTask(id: "t1", kind: .command, title: "swift test", since: now)
        s.claudeTasks = ["busy-done": [task], "open-question": [task]]
        func filteredCounts() -> (needsYou: Int, done: Int) {
            let open = s.router.cards.filter(\.isOpen)
            let tasks = s.routerTasks
            return (open.filter { $0.kind.needsYou }.count,
                    open.filter { $0.kind == .done && RouterPage.shows($0, tasks: tasks) }.count)
        }
        #expect(s.routerCounts == filteredCounts())
        #expect(s.routerCounts.needsYou == 5 && s.routerCounts.notes == 1)
        s.claudeTasks["busy-done"] = nil
        #expect(s.routerCounts == filteredCounts())
        #expect(s.routerCounts.needsYou == 5 && s.routerCounts.notes == 2)
    }

    @Test func switchingItOnInstallsTheHookAndOffRemovesIt() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        let paths = try #require(s.routerPaths)
        let installer = FormHookInstaller(claudeDir: paths.claudeDir)
        #expect(s.routerHookStatus == .installed && s.routerHookError == nil)
        #expect(installer.status(executable: "/Applications/Fjord Computer.app/Contents/MacOS/Fjord") == .installed)
        #expect(FileManager.default.fileExists(atPath: paths.forms.appendingPathComponent(".enabled").path))

        s.setRouterEnabled(false)
        await s.routerHookWork?.value
        #expect(s.routerHookStatus == .notInstalled && s.routerHookError == nil)
        #expect(!FileManager.default.fileExists(atPath: paths.forms.appendingPathComponent(".enabled").path))
        #expect(!FileManager.default.fileExists(atPath: installer.script.path))
    }

    @Test func aHookThatCantBeInstalledSaysWhy() async throws {
        let dir = TempDir()
        try FileManager.default.createDirectory(at: dir.path("claude"), withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: dir.path("claude/settings.json"))
        let s = store(dir, [])
        await s.routerHookWork?.value
        #expect(s.routerHookError != nil)
        #expect(s.routerHookStatus == .notInstalled)
        #expect(try Data(contentsOf: dir.path("claude/settings.json")) == Data("{ nope".utf8))
    }

    @Test func atLaunchAnOutdatedHookIsInstalledAgain() async throws {
        let dir = TempDir()
        let s = store(dir, [])
        await s.routerHookWork?.value
        let installer = FormHookInstaller(claudeDir: dir.path("claude"))
        // The app moved.
        let moved = Store()
        moved.persists = false
        moved.routerPaths = s.routerPaths
        moved.routerExecutable = "/Users/me/Applications/Fjord Computer.app/Contents/MacOS/Fjord"
        moved.router.enabled = true
        moved.startRouter()
        await moved.routerHookWork?.value
        #expect(installer.status(executable: "/Users/me/Applications/Fjord Computer.app/Contents/MacOS/Fjord") == .installed)
        #expect(moved.routerHookStatus == .installed)

        // Not installed (you took it out yourself): launch leaves it so.
        try installer.uninstall()
        let again = Store()
        again.persists = false
        again.routerPaths = s.routerPaths
        again.routerExecutable = moved.routerExecutable
        again.router.enabled = true
        again.startRouter()
        await again.routerHookWork?.value
        #expect(again.routerHookStatus == .notInstalled)
    }

    @Test func pendingFormsArePublishedForTheirCards() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        let forms = try #require(s.routerPaths?.forms)
        let pending: [String: Any] = ["key": "cli-local_a-1-1", "session_id": "cli-local_a", "transcript_path": "",
                                      "tool_input": sampleInput, "created_at": 1, "pid": Int(getpid())]
        try JSONSerialization.data(withJSONObject: pending).write(to: forms.appendingPathComponent("cli-local_a-1-1.json"))
        s.formBridge.refresh()
        await waitUntil { !s.pendingForms.isEmpty }
        #expect(s.pendingForms["cli-local_a"]?.questions.count == 2)
        let form = try #require(s.pendingForms["cli-local_a"])
        try s.formBridge.answer(form, answers: ["Which database?": "SQLite", "Which features?": "Auth"])
        #expect(FileManager.default.fileExists(atPath: FormBridge.answerURL(form.id, in: forms).path))

        s.setRouterEnabled(false)
        #expect(s.pendingForms.isEmpty)
    }

    private func asking(_ s: Store, _ id: String, since: Date, call: String = "toolu_1", turns: Int = 1,
                        tool: String = "AskUserQuestion") {
        var running = session(id, turns: turns)
        running.running = true
        running.summary = nil
        s.ingest([running], appUnread: [], claudeFrontmost: false, now: now)
        let text = tool == "ExitPlanMode" ? "Approve the plan: Ship it" : "Which one?"
        s.claudeActivity = [id: ClaudeActivity(text: text, since: since, waitsForYou: true, tool: tool, toolUseID: call)]
    }

    /// The hook holds a form for `call` (nil: not found yet): written to the forms folder and read back by the bridge when
    /// the store has one running, else set directly.
    private func form(_ s: Store, call: String?, key: String = "k", plan: Bool = false) async {
        guard s.router.enabled, let forms = s.routerPaths?.forms else {
            s.routerFormsLoaded = true
            s.pendingForms = ["cli-local_a": PendingForm(id: key, cliSessionID: "cli-local_a", transcriptPath: "",
                                                         questions: [.init(question: "Q?", header: "", multiSelect: false, options: [])],
                                                         createdAt: now, pid: 1, toolUseID: call)]
            return
        }
        await release(s)
        var record: [String: Any] = ["key": key, "session_id": "cli-local_a", "tool_input": plan ? planInput : sampleInput,
                                     "created_at": 1, "pid": Int(getpid())]
        record["tool_use_id"] = call
        if plan { record["tool_name"] = "ExitPlanMode" }
        try! JSONSerialization.data(withJSONObject: record).write(to: forms.appendingPathComponent("\(key).json"))
        s.formBridge.refresh()
        await waitUntil { s.pendingForms["cli-local_a"]?.id == key }
    }

    /// The hook lets go of every form.
    private func release(_ s: Store) async {
        guard let forms = s.routerPaths?.forms else { return }
        for file in (try? FileManager.default.contentsOfDirectory(at: forms, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "json" { try? FileManager.default.removeItem(at: file) }
        s.formBridge.refresh()
        await waitUntil { s.pendingForms.isEmpty && s.routerFormsLoaded }
    }

    @Test func aFormBelongsOnlyToTheCardOfItsOwnCall() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        // The form is published before the activity read that makes the card: it binds once the card is there.
        await form(s, call: "toolu_1", key: "first")
        s.feedRouter(now: now.addingTimeInterval(9))
        #expect(s.openRouterCards.isEmpty)
        asking(s, "local_a", since: now.addingTimeInterval(10), call: "toolu_1")
        s.feedRouter(now: now.addingTimeInterval(11))
        let firstCard = try #require(s.openRouterCards.first)
        #expect(firstCard.toolUseID == "toolu_1" && s.pendingForm(for: firstCard)?.id == "first")
        // A form whose call the hook hasn't found yet isn't answerable.
        await form(s, call: nil, key: "unpinned")
        #expect(s.pendingForm(for: firstCard) == nil)

        // The same question asked again: a new call, a new card; each card only takes its own call's form.
        asking(s, "local_a", since: now.addingTimeInterval(20), call: "toolu_2")
        s.feedRouter(now: now.addingTimeInterval(21))
        await form(s, call: "toolu_2", key: "second")
        let old = try #require(s.router.cards.first { $0.id == firstCard.id })
        let current = try #require(s.openRouterCards.first)
        #expect(current.text == old.text && current.toolUseID == "toolu_2")
        #expect(s.pendingForm(for: old) == nil && s.pendingForm(for: current)?.id == "second")
        s.setCardAddressed(old.id, false)
        let reopened = try #require(s.router.cards.first { $0.id == firstCard.id })
        #expect(s.pendingForm(for: reopened) == nil)
        await form(s, call: "toolu_1", key: "stale")
        #expect(s.pendingForm(for: reopened)?.id == "stale")
        #expect(s.router.cards.first { $0.id == current.id }.map { s.pendingForm(for: $0) } == .some(nil))
    }

    /// A relaunch: the router's saved state has the question; the sessions and the forms come back in either order, and the
    /// session no longer counts as running (no activity is read for it).
    @Test(arguments: [true, false]) func aRelaunchKeepsTheQuestionAndItsForm(formsFirst: Bool) async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        asking(s, "local_a", since: now.addingTimeInterval(10), call: "toolu_1")
        s.feedRouter(now: now.addingTimeInterval(11))
        await form(s, call: "toolu_1")
        s.feedRouter(now: now.addingTimeInterval(12))
        let saved = s.router

        let next = Store()
        next.persists = false
        next.claudeIsFrontmost = { false }
        next.router = saved
        next.agents = s.agents
        let idle = session("local_a", turns: 1, summary: nil)
        func sessionsArrive() async {
            next.claudeLink = .ok
            next.ingest([idle], appUnread: [], claudeFrontmost: false, now: now)
            next.feedRouter(now: now.addingTimeInterval(7300))
        }
        func formsArrive() async {
            await form(next, call: "toolu_1")
            next.feedRouter(now: now.addingTimeInterval(7301))
        }
        if formsFirst { await formsArrive(); await sessionsArrive() } else { await sessionsArrive(); await formsArrive() }
        let card = try #require(next.openRouterCards.first)
        #expect(card.kind == .question && next.pendingForm(for: card)?.id == "k")
    }

    @Test func viewingIsAskedAfreshAtEachFeed() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        // The last full read saw the app in front, on this session; then you went to another app.
        var front = true
        s.claudeIsFrontmost = { front }
        s.ingest([session("local_a", turns: 1)], appUnread: [], claudeFrontmost: true, now: now)
        front = false
        // Only the activity changes (no full read): the question is carded.
        asking(s, "local_a", since: now.addingTimeInterval(5))
        s.feedRouter(now: now.addingTimeInterval(6))
        #expect(s.openRouterCards.map(\.kind) == [.question])

        // Watching it in the app: no card.
        front = true
        s.ingest([session("local_a", turns: 2, focused: 1)], appUnread: [], claudeFrontmost: true, now: now)
        s.claudeActivity = [:]
        s.feedRouter(now: now.addingTimeInterval(7))
        #expect(s.router.cards.count == 1)
    }

    @Test func aTurnEndedInTheFrontAppIsCardedOnceYouLeaveItUnread() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        s.claudeIsFrontmost = { true }
        s.ingest([session("local_a", turns: 2, focused: 1)], appUnread: [], claudeFrontmost: true, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.router.cards.isEmpty)
        // Another app in front, and the app has the session unread.
        s.claudeIsFrontmost = { false }
        s.ingest([session("local_a", turns: 2, focused: 1)], appUnread: ["local_a"], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
    }

    @Test func reopeningSupersedesTheNewerCard() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        s.ingest([session("local_a", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        s.ingest([session("local_a", turns: 3)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(2))
        s.setCardAddressed("local_a#t2", false)
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
        #expect(s.router.cards.first { $0.id == "local_a#t3" }?.addressedBy == .superseded)
    }

    @Test func turningItOffAndOnSettlesWhatHappenedMeanwhile() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1), session("local_b", turns: 1)])
        await s.routerHookWork?.value
        s.ingest([session("local_a", turns: 2), session("local_b", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.openRouterCards.count == 2)
        s.setRouterEnabled(false)
        // Off: you open a in the app (which addresses nothing); b's turn stays unseen.
        s.ingest([session("local_a", turns: 2, focused: 1), session("local_b", turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.setRouterEnabled(true, now: now.addingTimeInterval(120))
        await s.routerHookWork?.value
        #expect(s.openRouterCards.count == 2)
    }

    @Test func aFormGoingAwayAnswersItsCard() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        asking(s, "local_a", since: now.addingTimeInterval(10))
        s.feedRouter(now: now.addingTimeInterval(11))
        await form(s, call: "toolu_1")
        // Past the running timeout: the session isn't running, its form is still held.
        s.ingest([session("local_a", turns: 1, summary: nil)], appUnread: [], claudeFrontmost: false, now: now)
        s.claudeActivity = [:]
        s.feedRouter(now: now.addingTimeInterval(7300))
        #expect(s.openRouterCards.map(\.kind) == [.question])
        await release(s)
        s.feedRouter(now: now.addingTimeInterval(7301))
        #expect(s.openRouterCards.isEmpty)
        #expect(s.router.cards.first?.addressedBy == .answered)
    }

    @Test func aPlanCardShowsItsPlanAndItsDecisionGoesToTheHook() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        asking(s, "local_a", since: now.addingTimeInterval(10), call: "toolu_p", tool: "ExitPlanMode")
        s.feedRouter(now: now.addingTimeInterval(11))
        let card = try #require(s.openRouterCards.first)
        #expect(card.kind == .plan && card.text == "Ship it" && card.toolUseID == "toolu_p")
        // A question's form held for the same call is not this card's; the plan's is.
        await form(s, call: "toolu_p", key: "question")
        #expect(s.pendingForm(for: card) == nil)
        await form(s, call: "toolu_p", key: "plan", plan: true)
        let held = try #require(s.pendingForm(for: card))
        #expect(held.plan == planInput["plan"] as? String)

        // Sent back with a note: the decision is written where the hook waits for it.
        let forms = try #require(s.routerPaths?.forms)
        try await FormWriter.write(held, plan: .init(approve: false, feedback: "Add tests"), dir: forms)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: FormBridge.answerURL(held.id, in: forms))) as? NSDictionary
        #expect(written == ["plan": ["approve": false, "feedback": "Add tests"]] as NSDictionary)
        // A question's answers aren't taken for a plan.
        await #expect(throws: FormBridge.Failure.notAQuestion) { try await FormWriter.write(held, answers: ["Q?": "A"], dir: forms) }

        // The hook passes it on and lets go: the card is answered.
        await release(s)
        s.claudeActivity = ["local_a": ClaudeActivity(text: "Thinking", since: now.addingTimeInterval(20))]
        s.feedRouter(now: now.addingTimeInterval(21))
        #expect(s.openRouterCards.isEmpty && s.router.cards.first?.addressedBy == .answered)
    }

    @Test func turningItOnWithAnIdleSessionAndALiveFormKeepsTheWait() async throws {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        asking(s, "local_a", since: now.addingTimeInterval(10))
        s.feedRouter(now: now.addingTimeInterval(11))
        await form(s, call: "toolu_1")
        s.setRouterEnabled(false)
        await s.routerHookWork?.value
        s.ingest([session("local_a", turns: 1, summary: nil)], appUnread: [], claudeFrontmost: false, now: now)
        s.claudeActivity = [:]
        s.setRouterEnabled(true, now: now.addingTimeInterval(7300))
        await s.routerHookWork?.value
        // The hook still holds the form: the bridge reads it again.
        await waitUntil { !s.pendingForms.isEmpty }
        s.feedRouter(now: now.addingTimeInterval(7301))
        let card = try #require(s.openRouterCards.first)
        #expect(card.kind == .question && s.pendingForm(for: card) != nil)
    }

    @Test func aStuckTurnsBannerWaitsForJevSoAStreakGoingInCirclesIsSaidOnce() async {
        let dir = TempDir()
        let s = store(dir, [session("local_a", turns: 1)])
        await s.routerHookWork?.value
        s.routerTriager.rescanned = true
        s.routerTriager.reader = { _ in "The linker still fails with undefined symbol _foo after rebuilding the framework target." }
        s.routerTriager.earlier = { _ in ["The linker fails with undefined symbol _foo after rebuilding the framework.",
                                          "Rebuilt the framework target; the linker still fails: undefined symbol _foo."] }
        final class Jev { var down = false; var hang = false }
        let jev = Jev()
        s.routerTriager.asker = { questions, _ in
            if jev.down { throw URLError(.notConnectedToInternet) }
            while jev.hang { try await Task.sleep(for: .milliseconds(5)) }
            var a: [String: JevClient.Answer] = ["urgency": .score(2, confidence: 0.8)]
            if questions["circles"] != nil { a["circles"] = .noul(0.9) }
            return a
        }
        // The banners as the app decides them.
        var bannered: [String] = []
        s.settings.notifications = true
        s.notifier.onPost = { bannered.append(String($0.identifier.dropFirst(RouterBanners.prefix.count))) }
        s.onNewRouterCards = { [weak s] in if let s { RouterBanners.post($0, store: s, windowIsKey: false) } }
        func blocked(_ turns: Int) -> ClaudeSession {
            var x = session("local_a", turns: turns)
            x.summary = .init(blocked: true, detail: "Still failing")
            return x
        }
        // A stuck turn: no banner until Jev answers, then one, going in circles.
        s.ingest([blocked(2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        #expect(s.router.cards.last?.id == "local_a#t2" && s.router.cards.last?.kind == .stuck && bannered.isEmpty)
        await s.routerTriager.idle()
        #expect(bannered == ["local_a#t2"] && s.router.cards.last?.triage?.circles == true)
        // The next one of the streak: none at all.
        s.ingest([blocked(3)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(2))
        await s.routerTriager.idle()
        #expect(s.router.cards.last?.id == "local_a#t3" && s.router.cards.last?.kind == .stuck && bannered == ["local_a#t2"])
        // Jev down: the banner comes all the same, as soon as that is known.
        jev.down = true
        s.ingest([blocked(4)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(3))
        await s.routerTriager.idle()
        #expect(bannered == ["local_a#t2", "local_a#t4"])
        // Jev slow: it comes after a little, and once only when he answers.
        jev.down = false
        jev.hang = true
        s.routerTriager.bannerWait = .milliseconds(20)
        s.routerTriager.earlier = { _ in [] }
        s.ingest([blocked(5)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(4))
        for _ in 0..<400 where bannered.count < 3 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(bannered == ["local_a#t2", "local_a#t4", "local_a#t5"] && s.router.cards.last?.triage == nil)
        jev.hang = false
        await s.routerTriager.idle()
        #expect(s.router.cards.last?.triage != nil && bannered.count == 3)
    }
}
