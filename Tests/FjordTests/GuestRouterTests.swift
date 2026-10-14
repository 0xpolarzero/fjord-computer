import Foundation
import Testing
@testable import Fjord

private actor GuestRelayStateRecorder {
    private(set) var values: [GuestRelayRecord] = []
    func append(_ value: GuestRelayRecord) { values.append(value) }
}

@Suite struct GuestRouterTests {
    private let computer = GuestReference(deviceId: "owner-1", computerId: "computer-1")
    private var localComputer: GuestReference { GuestReference(deviceId: nil, computerId: computer.computerId) }
    private var account: GuestAccount {
        GuestAccount(home: "/home/guest", uid: 1001, operatingSystem: .linux, architecture: "aarch64",
                     nodeExecutable: "/usr/bin/node", claudeExecutable: "/home/guest/.local/bin/claude")
    }

    private func client() -> MockGuestClient { MockGuestClient(accounts: [computer: account, localComputer: account]) }

    @MainActor private func engineWithComputer(state: LinuxComputerState) -> MockEngineClient {
        var inventory = MockEngineClient.demoInventory
        inventory.linux.computers.append(ApplicationComputer(kind: .linux,
            configuration: ComputerConfiguration(id: computer.computerId, name: "Linux dev", cpus: 2, maxCPUs: 8,
                memoryGiB: 4, maxMemoryGiB: 16, workspaceStorageGiB: 32, runtimeStorageGiB: 16),
            purpose: "Local MicroSandbox", state: state, stateDetail: state.rawValue.capitalized,
            canDismissError: false, freshness: "fresh"))
        return MockEngineClient(inventory: inventory)
    }

    @Test func guestInstallerWritesGuestOnlyPluginHookSettingsAndPrivateKey() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        let originalSettings = try JSONSerialization.data(withJSONObject: [
            "theme": "dark", "sshConfigs": [["id": "mine", "name": "Existing", "sshHost": "ssh-existing"]],
            "hooks": ["PermissionRequest": [["matcher": "OtherTool", "hooks": [["type": "command", "command": "custom-hook"]]]]],
        ], options: [.sortedKeys])
        try await guest.filesWrite(.init(computer: computer, path: paths.settings, data: originalSettings, mode: 0o640))
        let installed = try await GuestRouterInstaller(client: guest).install(computer: computer)
        let files = await guest.filesSnapshot(for: computer)
        let hook = String(data: try #require(files[installed.paths.hook]), encoding: .utf8)!
        let plugin = try #require(files[GuestRouterPaths.join(installed.paths.plugin, "hooks/register.ts")])
        let key = try #require(files[installed.paths.key])
        let settings = try #require(files[installed.paths.settings])
        let root = try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        let permission = try #require(hooks["PermissionRequest"] as? [[String: Any]])
        let backup = try await guest.filesRead(computer: computer, path: paths.settings + ".fjord-backup", offset: nil, length: nil)

        #expect(key.count == 65)
        #expect(await guest.writeRecords().first(where: { $0.path == installed.paths.key })?.mode == 0o600)
        #expect(await guest.writeRecords().first(where: { $0.path == installed.paths.hook })?.mode == 0o755)
        #expect(hook.contains("/usr/bin/node"))
        #expect(hook.contains(installed.paths.formModule))
        #expect(!hook.contains("--form-hook"))
        #expect(!String(decoding: plugin, as: UTF8.self).contains("Fjord --form-hook"))
        #expect(permission.contains { ($0["matcher"] as? String) == "AskUserQuestion|ExitPlanMode" })
        #expect(permission.contains { ($0["matcher"] as? String) == "OtherTool" })
        #expect(root["theme"] as? String == "dark")
        #expect((root["sshConfigs"] as? [[String: String]])?.first?["id"] == "mine")
        #expect(backup.data == originalSettings)
        #expect(backup.mode == 0o600)
        #expect(files[GuestRouterPaths.join(installed.paths.forms, FormBridge.marker)] != nil)
        #expect(await guest.execRecords().map(\.argv).contains([account.claudeExecutable, "plugin", "install", ClaudePlugin.id, "--scope", "user"]))
        #expect(FileManager.default.fileExists(atPath: installed.paths.hook) == false)

        _ = try await GuestRouterInstaller(client: guest).install(computer: computer)
        #expect(await guest.execRecords().contains { $0.argv == [account.claudeExecutable, "plugin", "update", ClaudePlugin.id, "--scope", "user"] })
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(installed.paths.presence, "cli-1"),
                                         data: Data("{}".utf8), mode: 0o600))
        try await GuestRouterInstaller(client: guest).disable(computer: computer)
        let afterDisable = try await guest.filesRead(computer: computer, path: paths.settings, offset: nil, length: nil)
        let disabledRoot = try #require(try JSONSerialization.jsonObject(with: afterDisable.data) as? [String: Any])
        let disabledHooks = try #require(disabledRoot["hooks"] as? [String: Any])
        #expect((disabledHooks["PermissionRequest"] as? [[String: Any]])?.contains { ($0["matcher"] as? String) == "OtherTool" } == true)
        #expect(await guest.filesSnapshot(for: computer)[paths.key] == nil)
        #expect(await guest.filesSnapshot(for: computer)[GuestRouterPaths.join(paths.forms, FormBridge.marker)] == nil)
        #expect(await guest.filesSnapshot(for: computer)[GuestRouterPaths.join(paths.presence, "cli-1")] == nil)
    }

    @Test func guestFormWatcherAnswersCreateOnlyAndUsesGuestProcessChecks() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.forms, FormBridge.marker),
                                         data: Data(), mode: 0o600))
        let formData = try JSONSerialization.data(withJSONObject: [
            "key": "session-100-42", "session_id": "session", "transcript_path": "/home/guest/.claude/projects/p/session.jsonl",
            "tool_name": FormHook.questionTool, "tool_input": ["questions": [["question": "Ship?", "options": [["label": "Yes"]]]]],
            "created_at": 100, "pid": 42, "tool_use_id": "tool-1",
        ])
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.forms, "session-100-42.json"),
                                         data: formData, mode: 0o600))
        let reader = GuestForms(client: guest)
        let snapshot = try await reader.watch(computer: computer, paths: paths)
        let key = GuestFormKey(location: .computer(deviceId: computer.deviceId, computerId: computer.computerId),
                               cliSessionID: "session")
        let pending = try #require(snapshot.forms[key])
        try await reader.answer(pending, answers: ["Ship?": "Yes"])
        let answerPath = GuestRouterPaths.join(paths.forms, "session-100-42.answer.json")
        let answer = try await guest.filesRead(computer: computer, path: answerPath, offset: nil, length: nil)
        #expect(try JSONSerialization.jsonObject(with: answer.data) as? [String: Any] != nil)
        #expect(await guest.execRecords().contains { $0.argv == ["/bin/kill", "-0", "42"] })
        let log = await guest.callLog()
        let watch = try #require(log.firstIndex(of: "watch:\(paths.forms)"))
        let markerRead = try #require(log.firstIndex(of: "read:\(GuestRouterPaths.join(paths.forms, FormBridge.marker))"))
        #expect(watch < markerRead)
        await #expect(throws: FormWriter.AlreadyAnswered.self) { try await reader.answer(pending, answers: ["Ship?": "Yes"]) }
    }

    @Test func guestRelaySubscribesBeforeWriteAndConsumesAck() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        let session = "cli-session-1"
        let nonce = "0123456789abcdef0123456789abcdef"
        let folder = GuestRouterPaths.join(paths.inbox, session)
        let ack = GuestRouterPaths.join(folder, "\(nonce).ack")
        try await guest.filesWrite(.init(computer: computer, path: ack, data: Data("ok model=opus".utf8), mode: 0o600))
        let signed = "⟦fjord v1 \(session) \(nonce) 2000000000000 \(String(repeating: "a", count: 64))⟧\nYWJj"
        let answer = try await GuestRelayInbox(client: guest).deliver(signed, to: session, computer: computer)
        let log = await guest.callLog()
        let watch = try #require(log.firstIndex(where: { $0.hasPrefix("watch:") }))
        let write = try #require(log.firstIndex(of: "write:\(GuestRouterPaths.join(folder, "\(nonce).msg"))"))
        #expect(answer == "ok model=opus")
        #expect(watch < write)
        #expect(await guest.filesSnapshot(for: computer)[ack] == nil)
        #expect(await guest.removalRecords().last?.1.count == 2)
    }

    @Test func guestClockSamplesTheGuestNodeRuntime() async throws {
        let guest = client()
        let milliseconds: Int64 = 1_800_000_000_000
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data(String(milliseconds).utf8), stderr: Data()),
                                  argv: [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"])

        let sampled = try await GuestClock.sampleMilliseconds(client: guest, computer: computer)

        #expect(sampled >= milliseconds && sampled < milliseconds + 5_000)
        #expect(await guest.execRecords().last?.argv == [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"])
    }

    @Test func guestDeepLinkUsesDocumentedSSHFieldsAndPreservesGuestFolderAndPrompt() async throws {
        let guest = client()
        try await guest.filesWrite(.init(computer: computer, path: "/workspace/repo/.git/config",
            data: Data("[remote \"origin\"]\nurl = https://github.com/acme/widget.git\n".utf8), mode: 0o600))
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-guest-start-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let project = RunsOnProject(name: "widget", sourceFolder: "/local/widget",
                                    placement: .computer(deviceId: computer.deviceId, computerId: computer.computerId,
                                                         guestPath: "/workspace/repo"))
        let prepared = try await GuestDesktopStart.prepare(client: guest, placement: project.placement, project: project,
            prompt: "Fix café & query?", computerName: "Linux dev", settings: ClaudeSSHSettings(home: tempHome))
        let parts = try #require(URLComponents(url: prepared.url, resolvingAgainstBaseURL: false))
        let fields = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let settingsData = try Data(contentsOf: tempHome.appendingPathComponent(".claude/settings.json"))
        let settingsRoot = try #require(try JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let ssh = try #require(settingsRoot["sshConfigs"] as? [[String: Any]])

        #expect(parts.scheme == "claude")
        #expect(parts.host == "code")
        #expect(parts.path == "/new")
        #expect(fields["ssh_host"] == prepared.alias.alias)
        #expect(fields["ssh_folder"] == "/workspace/repo")
        #expect(fields["q"] == "Fix café & query?")
        #expect(prepared.pending.state == .readyInClaude)
        #expect(prepared.pending.prompt == "Fix café & query?")
        #expect(ssh.first?["sshHost"] as? String == prepared.alias.alias)
        #expect(ssh.first?["startDirectory"] == nil)
        #expect(FileManager.default.fileExists(atPath: "/workspace/repo/.git/config") == false)
    }

    @Test func guestCodeFolderScannerReadsWorktreeConfigWithoutNormalizingAgainstHost() async throws {
        let guest = client()
        try await guest.filesWrite(.init(computer: computer, path: "/workspace/repo/.git/config",
            data: Data("[remote \"origin\"]\nurl = git@github.com:acme/widget.git\n".utf8), mode: 0o600))
        let scan = try await GuestCodeFolders(client: guest).scan(computer: computer, roots: ["/workspace"])

        #expect(scan.repos["/workspace/repo"] == ["acme/widget"])
        #expect(scan.cutShort == false)
        #expect(GuestCodeFolders.resolveGuest("../common", from: "/home/guest/repo/.git/worktrees/wt") == "/home/guest/repo/.git/worktrees/common")
        #expect(FileManager.default.fileExists(atPath: "/workspace/repo/.git/config") == false)
    }

    @Test func pendingStartMatcherRequiresOwnerHostIdAndSentPromptInGuestTranscript() {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        let pending = PendingDesktopStart(projectID: UUID(), location: .computer(deviceId: "owner-1", computerId: "computer-1"),
            alias: "ssh-computer-1", folder: "/workspace/repo", prompt: "Fix the bug", openedAt: opened)
        let message = SessionFork.Message(uuid: "message-1", parent: nil, text: "Fix the bug now", cwd: "/workspace/repo",
                                          at: opened.addingTimeInterval(10))
        let evidence = GuestSessionEvidence(computer: computer, cliSessionID: "cli-1", hostSessionID: "local_desktop-1",
            pid: 42, startedAt: 123, renewedAt: 1_800_000_010_000, capabilities: [ClaudePlugin.inboxCapability],
            transcriptMessages: [message])
        let desktop = [DesktopSSHSession(id: "local_desktop-1", alias: "ssh-computer-1", folder: "/workspace/repo")]

        #expect(PendingDesktopStartMatcher.match(pending, desktop: desktop, evidence: [evidence]) == evidence)
        #expect(PendingDesktopStartMatcher.match(pending, desktop: [desktop[0], desktop[0]], evidence: [evidence]) == nil)
        #expect(PendingDesktopStartMatcher.match(pending, desktop: desktop, evidence: []) == nil)
    }

    @MainActor @Test func matchedSessionKeepsGuestIdentityWhenMappedBackToItsRouterProject() {
        let store = Store(engineClient: MockEngineClient())
        store.persists = false
        let source = "/local/widget"
        let project = RunsOnProject(name: "widget", sourceFolder: source,
            placement: .computer(deviceId: computer.deviceId, computerId: computer.computerId, guestPath: "/workspace/repo"))
        let pending = PendingDesktopStart(projectID: project.id,
            location: .computer(deviceId: computer.deviceId, computerId: computer.computerId),
            alias: "ssh-computer-1", folder: "/workspace/repo", prompt: "Fix it", state: .matched,
            desktopSessionID: "local_desktop-1", guestSessionID: "cli-1")
        var state = RouterState()
        state.runsOnProjects = [project]
        state.pendingDesktopStarts = [pending]
        store.router = state
        store.claudeSessions[pending.desktopSessionID!] = ClaudeSession(id: pending.desktopSessionID!, title: "Fix it",
            folder: "/host/mirror/ssh-computer-1", lastActivity: Date(), running: true)

        #expect(store.routerProjectFolder(sessionID: "local_desktop-1") == source)
        #expect(store.routerSessionProject("local_desktop-1").name.contains("/workspace/repo"))
        #expect(store.routerProjectGroupKey(sessionID: "local_desktop-1", folder: "/host/mirror/ssh-computer-1")
                == "guest-project:\(project.id.uuidString):\(pending.location.key):/workspace/repo")
    }

    @Test func localPeerReadersNeverProbeHostPIDsForMatchedGuestSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-peer-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"hostSessionId":"local_guest","sessionId":"cli-1","pid":4242,"name":"Guest"}"#.utf8)
            .write(to: dir.appendingPathComponent("4242.json"))
        try Data(#"{"hostSessionId":"local_host","sessionId":"cli-2","pid":5151,"name":"Local"}"#.utf8)
            .write(to: dir.appendingPathComponent("5151.json"))
        var probed: [Int32] = []
        let alive: (Int32) -> Bool = { probed.append($0); return true }

        let peers = RouterTools.localPeers(dir: dir, excluding: ["local_guest"], alive: alive)
        #expect(peers["local_guest"] == nil)
        #expect(peers["local_host"]?.name == "Local")
        #expect(probed == [5151])
        probed = []
        let cliIDs = RouterTools.cliSessions(dir: dir, excluding: ["local_guest"], alive: alive)
        #expect(cliIDs == ["local_host": ["cli-2"]])
        #expect(probed == [5151])
    }

    @Test func guestTranscriptReaderDropsRangedAndUnfinishedJSONLFragments() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        let cli = "cli-transcript-1"
        let directory = GuestRouterPaths.join(paths.projects, "workspace-repo")
        let head = try JSONSerialization.data(withJSONObject: [
            "type": "user", "uuid": "old", "cwd": "/workspace/repo", "message": ["content": String(repeating: "x", count: 500)],
        ], options: [.sortedKeys])
        let current = try JSONSerialization.data(withJSONObject: [
            "type": "user", "uuid": "current", "cwd": "/workspace/repo", "timestamp": "2026-12-15T16:00:10.000Z",
            "message": ["role": "user", "content": "Current guest message"],
        ], options: [.sortedKeys])
        let partial = Data("{\"type\":\"assistant\",\"message\":{\"content\":[".utf8)
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(directory, "\(cli).jsonl"),
            data: head + Data("\n".utf8) + current + Data("\n".utf8) + partial, mode: 0o600))

        let result = try await GuestTranscripts(client: guest, tailLimit: 300)
            .read(computer: computer, projectsRoot: paths.projects, cliSessionID: cli)
        let snapshot = try #require(result)

        #expect(snapshot.path == GuestRouterPaths.join(directory, "\(cli).jsonl"))
        #expect(snapshot.messages.map(\.uuid) == ["current"])
        #expect(snapshot.messages.first?.cwd == "/workspace/repo")
        #expect(snapshot.size > Int64(snapshot.tail.count))
        #expect(FileManager.default.fileExists(atPath: snapshot.path) == false)
    }

    @MainActor @Test func routerGuestStartPersistsReadyStateBeforeOpenWithoutSendingPrompt() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-router-guest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let engine = engineWithComputer(state: .stopped)
        let store = Store(engineClient: engine)
        store.stateFile = tempHome.appendingPathComponent("state.json")
        store.router.enabled = true
        store.agents.enabled = true
        let source = "/local/widget"
        store.claudeSessions["local_existing"] = ClaudeSession(id: "local_existing", title: "Existing", folder: source,
            lastActivity: Date(), running: false)
        store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computer.computerId,
                                           guestPath: "/workspace/repo"), for: source)
        let guest = MockGuestClient(accounts: [localComputer: account])
        let clockArgv = [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"]
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data("1800000000000".utf8), stderr: Data()), argv: clockArgv)
        var captured: String?
        var openCount = 0
        var sawPersistedPendingStart = false
        store.interceptOpen = { message in
            openCount += 1
            captured = message
            guard let data = try? Data(contentsOf: tempHome.appendingPathComponent("state.json")),
                  let state = Store.decodeState(data) else { return }
            sawPersistedPendingStart = state.router?.pendingDesktopStarts.count == 1
        }
        let tools = RouterTools(store: store)
        tools.guestClient = guest
        tools.guestSSHSettings = ClaudeSSHSettings(home: tempHome)
        tools.beginTurn("Fix the bug in widget")
        defer { GuestRouterRuntime.shared.stopAll() }

        let result = try await tools.startSession(store, project: "widget", title: "Fix it", ticket: tools.ticket())
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let pending = try #require(store.router.pendingDesktopStarts.first)
        let callsBeforeRetry = await guest.execRecords().count
        let retry = try await tools.startSession(store, project: "widget", title: "Fix it", ticket: tools.ticket())
        let retryObject = try #require(try JSONSerialization.jsonObject(with: Data(retry.utf8)) as? [String: Any])
        let guestPaths = try GuestRouterPaths(home: account.home)
        let calls = await guest.callLog()
        let watchLog = calls.filter { $0.hasPrefix("watch:") }

        #expect(sawPersistedPendingStart)
        #expect(engine.inventory.computer(computer.computerId)?.displayState == .running)
        #expect(openCount == 1)
        #expect(captured?.contains("claude://code/new?") == true)
        #expect((retryObject["pendingStart"] as? String) == pending.id.uuidString)
        #expect(store.router.pendingDesktopStarts.count == 1)
        #expect(await guest.execRecords().count == callsBeforeRetry)
        #expect(watchLog.contains { $0.contains(guestPaths.projects) })
        #expect(object["state"] as? String == "ready_in_claude")
        #expect(pending.state == .readyInClaude)
        #expect(pending.guestSessionID == nil)
        #expect(tools.prepared.isEmpty)
        #expect((object["next"] as? String)?.contains("press Send in Claude") == true)
    }

    @MainActor @Test func dispatcherRecordsGuestStartWithoutExpectingLocalPeerPreparation() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-router-dispatch-guest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            GuestRouterRuntime.shared.stopAll()
            try? FileManager.default.removeItem(at: tempHome)
        }

        let store = Store(engineClient: engineWithComputer(state: .running))
        store.stateFile = tempHome.appendingPathComponent("state.json")
        store.router.enabled = true
        store.agents.enabled = true
        let source = "/local/widget"
        store.claudeSessions["local_existing"] = ClaudeSession(id: "local_existing", title: "Existing", folder: source,
            lastActivity: Date(), running: false)
        store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computer.computerId,
                                           guestPath: "/workspace/repo"), for: source)
        var opens = 0
        store.interceptOpen = { _ in opens += 1 }

        let guest = MockGuestClient(accounts: [localComputer: account])
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data("1800000000000".utf8), stderr: Data()),
            argv: [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"])
        let dispatcher = store.routerDispatcher
        dispatcher.configure = { tools in
            tools.guestClient = guest
            tools.guestSSHSettings = ClaudeSSHSettings(home: tempHome)
        }

        let id = try #require(dispatcher.submit("start a new session to fix the bug", context: RouterContext(projects: [source])))
        await waitUntil { store.router.decisions.first(where: { $0.id == id })?.outcome == .done }
        let entry = try #require(store.router.decisions.first(where: { $0.id == id }))

        let prepared = try #require(entry.done.compactMap { item -> (String, String, String)? in
            if case .preparedGuest(let project, let location, let pendingStart) = item { return (project, location, pendingStart) }
            return nil
        }.first)
        #expect(entry.doneLines.allSatisfy { !$0.contains("Not prepared") && !$0.hasPrefix("failed:") })
        #expect(entry.outcome == .done)
        #expect(opens == 1)
        #expect(store.router.pendingDesktopStarts.count == 1)
        #expect(prepared.0 == "widget")
        #expect(prepared.1 == "local/\(computer.computerId)")
        #expect(prepared.2 == store.router.pendingDesktopStarts[0].id.uuidString)
    }

    @Test func guestPresenceRequiresGuestPIDRegistryAndAuthoritativeTranscript() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        let cli = "cli-session-1"
        let pid: Int32 = 42
        let start = Int64(1_800_000_000_000)
        let key = String(repeating: "ab", count: 32)
        try await guest.filesWrite(.init(computer: computer, path: paths.key, data: Data((key + "\n").utf8), mode: 0o600))
        let presence = try JSONSerialization.data(withJSONObject: [
            "state": "live", "sessionId": cli, "pid": pid, "startedAt": 123,
            "keyId": ClaudePlugin.keyID(of: key), "renewedAt": start, "capabilities": [ClaudePlugin.inboxCapability],
        ])
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.presence, cli), data: presence, mode: 0o600))
        let registry = try JSONSerialization.data(withJSONObject: [
            "hostSessionId": "local_desktop-1", "sessionId": cli, "pid": pid, "startedAt": 123,
        ])
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.registry, "42.json"), data: registry, mode: 0o600))
        let transcript = try JSONSerialization.data(withJSONObject: [
            "type": "user", "uuid": "message-1", "cwd": "/workspace/repo", "timestamp": "2026-12-15T16:00:10.000Z",
            "message": ["role": "user", "content": "Fix the bug"],
        ], options: [.sortedKeys]) + Data("\n".utf8)
        try await guest.filesWrite(.init(computer: computer,
            path: GuestRouterPaths.join(GuestRouterPaths.join(paths.projects, "workspace-repo"), "\(cli).jsonl"),
            data: transcript, mode: 0o600))
        let evidence = try await GuestSessionObserver(client: guest).read(computer: computer, paths: paths, guestNowMs: start + 10_000)

        #expect(evidence.count == 1)
        #expect(evidence.first?.cliSessionID == cli)
        #expect(evidence.first?.hostSessionID == "local_desktop-1")
        #expect(evidence.first?.transcriptMessages.first?.text == "Fix the bug")
        await guest.setExecResult(GuestExecResult(exitCode: 1, stdout: Data(), stderr: Data("Operation not permitted".utf8)), argv: ["/bin/kill", "-0", "42"])
        #expect(try await GuestSessionObserver(client: guest).read(computer: computer, paths: paths, guestNowMs: start + 10_000).isEmpty)
    }

    @Test func signedGuestRelayUsesGuestKeyAndPersistsDeliveryState() async throws {
        let guest = client()
        let paths = try GuestRouterPaths(home: account.home)
        let cli = "cli-session-1"
        let nonce = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        let nonceText = nonce.uuidString.lowercased()
        let start: Int64 = 1_800_000_000_000
        let key = String(repeating: "cd", count: 32)
        try await guest.filesWrite(.init(computer: computer, path: paths.key, data: Data(key.utf8), mode: 0o600))
        let presence = try JSONSerialization.data(withJSONObject: [
            "state": "live", "sessionId": cli, "pid": 42, "startedAt": 123,
            "keyId": ClaudePlugin.keyID(of: key), "renewedAt": start, "capabilities": [ClaudePlugin.inboxCapability],
        ])
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.presence, cli), data: presence, mode: 0o600))
        let registry = try JSONSerialization.data(withJSONObject: [
            "hostSessionId": "local_desktop-1", "sessionId": cli, "pid": 42, "startedAt": 123,
        ])
        try await guest.filesWrite(.init(computer: computer, path: GuestRouterPaths.join(paths.registry, "42.json"), data: registry, mode: 0o600))
        let ack = GuestRouterPaths.join(GuestRouterPaths.join(paths.inbox, cli), "\(nonceText).ack")
        try await guest.filesWrite(.init(computer: computer, path: ack, data: Data("ok".utf8), mode: 0o600))
        let clockArgv = [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"]
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data(String(start + 1000).utf8), stderr: Data()), argv: clockArgv)
        let states = GuestRelayStateRecorder()
        let send = GuestRelayDelivery(client: guest, onState: { await states.append($0) })
        let result = try await send.send(body: "Run the checks", to: cli, computer: computer, nonce: nonce,
                                         now: Date(timeIntervalSince1970: Double(start) / 1000))
        let saved = await states.values
        let messagePath = GuestRouterPaths.join(GuestRouterPaths.join(paths.inbox, cli), "\(nonceText).msg")
        let message = try #require(await guest.writeRecords().first(where: { $0.path == messagePath }))

        #expect(result == "ok")
        #expect(String(decoding: message.data, as: UTF8.self).contains("⟦fjord v1 \(cli) \(nonceText)"))
        #expect(saved.first?.state == .inFlight)
        #expect(saved.last?.state == .delivered)
        #expect(saved.allSatisfy { $0.nonce == nonceText })
    }

    @Test func RouterStatePersistsGuestFormsAndRelayReceipts() throws {
        let form = PendingForm(id: "cli-1-100-42", cliSessionID: "cli-1", transcriptPath: "/guest/transcript.jsonl",
            questions: [.init(question: "Deploy?", header: "Ship", multiSelect: false, options: [.init(label: "Yes", description: "")])],
            createdAt: Date(timeIntervalSince1970: 100), pid: 42, toolUseID: "tool-1")
        let pending = GuestPendingForm(computer: computer,
            location: .computer(deviceId: computer.deviceId, computerId: computer.computerId), form: form)
        let receipt = GuestRelayRecord(location: pending.location, sessionID: "cli-1", nonce: "nonce", state: .unconfirmed)
        var state = RouterState()
        state.guestPendingForms = [pending]
        state.pendingGuestDisables = [pending.location]
        GuestRelayLedger.upsert(receipt, into: &state.guestRelayDeliveries)
        let decoded = try JSONDecoder().decode(RouterState.self, from: JSONEncoder().encode(state))

        #expect(decoded.guestPendingForms == [pending])
        #expect(decoded.guestRelayDeliveries == [receipt])
        #expect(decoded.pendingGuestDisables == [pending.location])
    }
}
