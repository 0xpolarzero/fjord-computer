import Foundation
import Testing
@testable import Fjord

/// A Triage action for a project that lives in a computer goes through the Router like a Mac project's: its session is
/// prepared in Claude over SSH (the `claude://code/new` link with the prompt filled in), after an automatic checkpoint of
/// the computer, and starts when the owner presses Send there. A Mac project keeps the local flow.
@MainActor
@Suite(.serialized, .ownGuestRuntime) struct TriageGuestSessionTests {
    private let computerID = "10000000-0000-4000-8000-0000000000d1"
    private var guestRef: GuestReference { GuestReference(deviceId: nil, computerId: computerID) }
    private var account: GuestAccount {
        GuestAccount(home: "/home/guest", uid: 1001, operatingSystem: .linux, architecture: "aarch64",
                     nodeExecutable: "/usr/bin/node", claudeExecutable: "/home/guest/.local/bin/claude")
    }
    private let source = "/local/widget"

    private func engine() -> MockEngineClient {
        var inventory = MockEngineClient.demoInventory
        inventory.linux.computers.append(ApplicationComputer(kind: .linux,
            configuration: ComputerConfiguration(id: computerID, name: "Linux dev", cpus: 2, maxCPUs: 8, memoryGiB: 4,
                maxMemoryGiB: 16, workspaceStorageGiB: 32, runtimeStorageGiB: 16),
            purpose: "Local MicroSandbox", state: .running, stateDetail: "Running", canDismissError: false, freshness: "fresh"))
        return MockEngineClient(inventory: inventory)
    }

    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-triage-guest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(_ engine: MockEngineClient, home: URL, placed: Bool) -> Store {
        let store = Store(engineClient: engine)
        store.stateFile = home.appendingPathComponent("state.json")
        store.router.enabled = true
        store.agents.enabled = true
        store.claudeSessions["local_existing"] = ClaudeSession(id: "local_existing", title: "Existing", folder: source,
                                                               lastActivity: Date(), running: false)
        if placed {
            store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computerID, guestPath: "/workspace/repo"), for: source)
        }
        return store
    }

    private func guest() async -> MockGuestClient {
        let guest = MockGuestClient(accounts: [guestRef: account])
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data("1800000000000".utf8), stderr: Data()),
                                  argv: [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"])
        return guest
    }

    private func checkpoints(_ engine: MockEngineClient) -> [ComputerCheckpoint] {
        engine.inventory.computer(computerID)?.checkpoints ?? []
    }

    private func tools(_ store: Store, guest: MockGuestClient, home: URL, action: Bool) -> RouterTools {
        let tools = RouterTools(store: store)
        tools.guestClient = guest
        tools.guestSSHSettings = ClaudeSSHSettings(home: home)
        tools.checkpointBeforeGuestStart = action
        tools.beginTurn("Fix the bug in widget")
        return tools
    }

    @Test func aTriageStartInAComputerSavesAnAutomaticCheckpointThenOpensTheSshLinkWithThePrompt() async throws {
        let home = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: home) }
        let engine = engine()
        let store = store(engine, home: home, placed: true)
        var opened: String?
        var checkpointsWhenOpened: [ComputerCheckpoint] = []
        store.interceptOpen = { message in
            opened = message
            checkpointsWhenOpened = checkpoints(engine)
        }
        let tools = tools(store, guest: await guest(), home: home, action: true)

        let result = try await tools.startSession(store, project: "widget", title: "o/widget#7 Login fails", ticket: tools.ticket())
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])

        // The checkpoint is there, automatic and labeled so, before the link opens.
        let expected = AutomaticCheckpoint.label(task: "o/widget#7 Login fails")
        #expect(checkpointsWhenOpened.map(\.name) == [expected])
        #expect(checkpointsWhenOpened.first?.kind == .automatic)
        #expect(expected.hasSuffix(", deleted automatically"))
        // One Send: the link carries the host, the folder and the prompt.
        let link = try #require(opened?.components(separatedBy: ": ").last.flatMap(URL.init(string:)))
        #expect(link.scheme == "claude" && link.host == "code" && link.path == "/new")
        let fields = Dictionary(uniqueKeysWithValues: (URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(fields["ssh_host"] == "ssh-\(computerID)")
        #expect(fields["ssh_folder"] == "/workspace/repo")
        #expect(fields["q"]?.contains("Fix the bug in widget") == true)
        #expect(object["state"] as? String == "ready_in_claude")
        let pending = try #require(store.router.pendingDesktopStarts.first)
        #expect(pending.state == .readyInClaude && pending.folder == "/workspace/repo")
    }

    @Test func aTriageActionMessageForAComputerProjectGoesThroughTheRouterWithTheCheckpointFirst() async throws {
        let home = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: home) }
        let engine = engine()
        let store = store(engine, home: home, placed: true)
        store.persists = false
        store.setTool(.triage, on: true)
        var opened: [String] = []
        var checkpointsWhenOpened = 0
        store.interceptOpen = { message in
            opened.append(message)
            checkpointsWhenOpened = checkpoints(engine).count
        }
        let guest = await guest()
        let dispatcher = store.routerDispatcher
        let finished = Finished()
        dispatcher.onFinish = { _ in Task { await finished.open() } }
        dispatcher.configure = { tools in
            tools.guestClient = guest
            tools.guestSSHSettings = ClaudeSSHSettings(home: home)
        }
        var context = RouterContext(projects: [source])
        context.action = RouterActionSource(origin: SessionOrigin(category: "Mine", thing: "o/widget#7 Login fails",
                                                                  actionID: UUID().uuidString, runID: UUID().uuidString),
                                            title: "o/widget#7 Login fails", model: nil, effort: nil)

        let id = try #require(dispatcher.submit("start a new session to fix the bug", context: context))
        await finished.wait()
        let entry = try #require(store.router.decisions.first { $0.id == id })

        #expect(opened.count == 1)
        #expect(checkpointsWhenOpened == 1)
        #expect(checkpoints(engine).first?.kind == .automatic)
        #expect(entry.done.contains { if case .preparedGuest = $0 { true } else { false } })
        let outcome = InboxActions.outcome(of: entry, waiting: false, busy: false, held: false, title: { _ in nil })
        #expect(outcome.state == .done && outcome.detail == InboxActions.readyInClaudeWords)
    }

    @Test func automaticCheckpointsOffStartsTheSessionWithoutOne() async throws {
        let home = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: home) }
        let engine = engine()
        engine.settingsSnapshot.settings.automaticCheckpointRetentionCount = 0
        let store = store(engine, home: home, placed: true)
        var opens = 0
        store.interceptOpen = { _ in opens += 1 }
        let tools = tools(store, guest: await guest(), home: home, action: true)

        _ = try await tools.startSession(store, project: "widget", title: "o/widget#7 Login fails", ticket: tools.ticket())

        #expect(opens == 1)
        #expect(checkpoints(engine).isEmpty)
    }

    @Test func aRouterStartThatIsNotATriageActionTakesNoCheckpoint() async throws {
        let home = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: home) }
        let engine = engine()
        let store = store(engine, home: home, placed: true)
        store.interceptOpen = { _ in }
        let tools = tools(store, guest: await guest(), home: home, action: false)

        _ = try await tools.startSession(store, project: "widget", title: "Fix it", ticket: tools.ticket())

        #expect(checkpoints(engine).isEmpty)
    }

    @Test func aCheckpointThatCantBeSavedThrowsWithAReasonSoTheSessionIsNotStarted() async {
        do {
            _ = try await AutomaticCheckpoint.take(engine: UnavailableEngineClient(), computer: guestRef, task: "Fix it")
            Issue.record("a checkpoint was reported with no engine")
        } catch {
            #expect(error.localizedDescription.contains("automatic checkpoint setting"))
        }
    }

    @Test func aMacProjectKeepsTheLocalFlowAndTakesNoCheckpoint() async throws {
        let home = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: home) }
        let engine = engine()
        let store = store(engine, home: home, placed: false)
        store.routerPluginStatus = .installed
        var opens = 0
        store.interceptOpen = { _ in opens += 1 }
        let tools = tools(store, guest: await guest(), home: home, action: true)
        var startedIn: [String] = []
        struct Stop: Error {}
        // The local flow is asked for the session in the clone itself; what follows it is not this test's.
        tools.starter = { folder, _ in
            startedIn.append(folder)
            throw Stop()
        }

        _ = try? await tools.startSession(store, project: "widget", title: "o/widget#7 Login fails", ticket: tools.ticket())

        #expect(startedIn == [source])
        #expect(opens == 0)
        #expect(checkpoints(engine).isEmpty)
        #expect(store.router.pendingDesktopStarts.isEmpty)
    }

    @Test func theRunsChipSaysTheSessionWaitsForYourSend() {
        let action = CategoryAction.make(.askRouter(prompt: "Fix it"))
        var category = InboxFixture.category()
        category.actions = ActionList([action])
        let entry = InboxEntry(thing: InboxFixture.pr(7), categoryID: category.id, facts: [Fact(key: "k", label: "k")],
                               isDone: false, isUnread: true)
        var ledger = ActionLedger()
        ledger.set(ActionRun(category: category.id, thing: entry.id, action: action.id, trigger: "enter", state: .done, at: Date(),
                             detail: InboxActions.readyInClaudeWords, message: UUID()))
        let chip = InboxActions.chips(for: entry, category: category, groups: [], ledger: ledger, me: "me").first
        #expect(chip?.label == "ready in Claude: press Send")
        #expect(chip?.target == .router)
        #expect(chip?.tint == .attention)
    }

    @Test func aRoutersPreparedGuestStartIsDoneAsReadyInClaudeForTheActionsRun() {
        var entry = RouterDecision(trigger: .you("x"), decision: .init(intent: "start"))
        entry.add(.preparedGuest(project: "widget", location: "local/c", pendingStart: UUID().uuidString), session: nil)
        let outcome = InboxActions.outcome(of: entry, waiting: false, busy: false, held: false, title: { _ in nil })
        #expect(outcome.state == .done)
        #expect(outcome.detail == InboxActions.readyInClaudeWords)
    }

    @Test func aSavedHeadlessRunInAComputerActionIsDroppedAndTheCategoryStays() throws {
        let json = Data(#"""
        [{"id":"11111111-1111-4111-8111-111111111111","kind":{"runInComputer":{"_0":{"computerID":"c","computerName":"n","workspaceRoot":"/w","promptTemplate":"x"}}},"trigger":"enter"},
         {"id":"22222222-2222-4222-8222-222222222222","kind":{"rerun":{}},"trigger":"enter"}]
        """#.utf8)
        let list = try JSONDecoder().decode(ActionList.self, from: json)
        #expect(list.items.map(\.title) == ["Re-run failed checks"])
    }
}

private actor Finished {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func open() { opened = true; waiters.forEach { $0.resume() }; waiters = [] }
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
