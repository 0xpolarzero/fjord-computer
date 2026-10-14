import Foundation
import Testing
@testable import Fjord

/// Router "Runs on" for a computer owned by another device: every step addresses the owner by deviceId, and a computer
/// with the same id on This Mac is never touched.
@MainActor
@Suite(.serialized, .ownGuestRuntime) struct RunsOnRemoteTests {
    private let deviceID = "device-2"
    private let computerID = "10000000-0000-4000-8000-0000000000b7"
    private var remote: GuestReference { GuestReference(deviceId: deviceID, computerId: computerID) }
    private var local: GuestReference { GuestReference(deviceId: nil, computerId: computerID) }
    private var account: GuestAccount {
        GuestAccount(home: "/home/guest", uid: 1001, operatingSystem: .linux, architecture: "aarch64",
                     nodeExecutable: "/usr/bin/node", claudeExecutable: "/home/guest/.local/bin/claude")
    }

    private func row(_ name: String, state: LinuxComputerState) -> ApplicationComputer {
        ApplicationComputer(kind: .linux,
            configuration: ComputerConfiguration(id: computerID, name: name, cpus: 2, maxCPUs: 8, memoryGiB: 4,
                maxMemoryGiB: 16, workspaceStorageGiB: 32, runtimeStorageGiB: 16),
            purpose: "Always-on", state: state, stateDetail: state.rawValue.capitalized, canDismissError: false, freshness: "fresh")
    }

    /// This Mac has a stopped computer under `computerID`; the second device has its own, also stopped, under the same id.
    private func engine(remoteState: LinuxComputerState = .stopped) -> MockEngineClient {
        var localInventory = MockEngineClient.demoInventory
        localInventory.linux.computers.append(row("local-twin", state: .stopped))
        let engine = MockEngineClient(inventory: localInventory)
        var owned = MockEngineClient.demoInventory
        owned.linux.computers = [row("always-on", state: remoteState)]
        engine.connectedDevices = [SiloWireDevice(address: "me@host-2", id: deviceID, name: "Host 2")]
        engine.ownerInventories[deviceID] = owned
        return engine
    }

    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-runson-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func startingARemoteSessionAddressesTheOwnerEverywhere() async throws {
        let tempHome = try home()
        defer { GuestRouterRuntime.shared.stopAll(); try? FileManager.default.removeItem(at: tempHome) }
        let engine = engine()
        let store = Store(engineClient: engine)
        store.stateFile = tempHome.appendingPathComponent("state.json")
        store.router.enabled = true
        store.agents.enabled = true
        let source = "/local/widget"
        store.claudeSessions["local_existing"] = ClaudeSession(id: "local_existing", title: "Existing", folder: source,
            lastActivity: Date(), running: false)
        await store.computers.refreshPlacementInventories()
        store.setRunsOnPlacement(.computer(deviceId: deviceID, computerId: computerID, guestPath: "/workspace/repo"), for: source)
        engine.mockAgentTools["\(deviceID)/\(computerID)"] = MockEngineClient.agentTools(.missing)

        let guest = MockGuestClient(accounts: [remote: account, local: account])
        let clockArgv = [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"]
        await guest.setExecResult(GuestExecResult(exitCode: 0, stdout: Data("1800000000000".utf8), stderr: Data()), argv: clockArgv)
        var opened: String?
        store.interceptOpen = { opened = $0 }
        let tools = RouterTools(store: store)
        tools.guestClient = guest
        tools.guestSSHSettings = ClaudeSSHSettings(home: tempHome)
        tools.beginTurn("Fix the bug in widget")

        let result = try await tools.startSession(store, project: "widget", title: "Fix it", ticket: tools.ticket())
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])

        // The owner's computer was started and set up; the same-id computer here was left alone.
        #expect(engine.remoteStartRequests == ["\(deviceID)/\(computerID)"])
        #expect(engine.inventory.computer(computerID)?.displayState == .stopped)
        #expect(engine.agentToolsStatusRequests.allSatisfy { $0 == "\(deviceID)/\(computerID)" })
        #expect(engine.agentToolsSetupKeys == ["\(deviceID)/\(computerID)"])

        // The remote alias, the sshConfigs entry, and the install all went through the owner's reference.
        let calls = await guest.callLog()
        #expect(calls.contains("ssh-alias:ensure:\(remote.key)"))
        #expect(!calls.contains("ssh-alias:ensure:\(local.key)"))
        let alias = "silo-remote-\(deviceID)-\(computerID)"
        let settings = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: ClaudeSSHSettings(home: tempHome).settings)) as? [String: Any])
        let entries = try #require(settings["sshConfigs"] as? [[String: String]])
        #expect(entries.map { $0["id"] } == ["fjord-\(deviceID)-\(computerID)"])
        #expect(entries.first?["sshHost"] == alias)
        let paths = try GuestRouterPaths(home: account.home)
        #expect(await guest.filesSnapshot(for: remote)[paths.hook] != nil)
        #expect(await guest.filesSnapshot(for: remote)[paths.key] != nil)
        #expect(await guest.filesSnapshot(for: local).isEmpty)
        #expect(await guest.writeRecords().allSatisfy { $0.computer == remote })
        #expect(await guest.execRecords().allSatisfy { $0.computer == remote })

        #expect(object["state"] as? String == "ready_in_claude")
        #expect(opened?.contains(alias) == true)
        let pending = try #require(store.router.pendingDesktopStarts.first)
        #expect(pending.location == .computer(deviceId: deviceID, computerId: computerID))
        #expect(pending.alias == alias)
    }

    @Test func placementIsKeyedByDeviceAndComputer() throws {
        let store = Store(engineClient: MockEngineClient())
        store.persists = false
        store.setRunsOnPlacement(.computer(deviceId: deviceID, computerId: computerID, guestPath: "/a"), for: "/src/one")
        store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computerID, guestPath: "/b"), for: "/src/two")
        let one = store.runsOnProject(for: "/src/one").placement
        let two = store.runsOnProject(for: "/src/two").placement
        #expect(one.location != two.location)
        #expect(one.location == .computer(deviceId: deviceID, computerId: computerID))
        #expect(two.location == .computer(deviceId: nil, computerId: computerID))
        #expect(remote.key != local.key)
    }

    @Test func aRunningRemoteComputerIsNotStartedAgain() async throws {
        let engine = engine(remoteState: .running)
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        let row = try await model.ensureRemoteRunning(deviceId: deviceID, computerId: computerID)
        #expect(row.name == "always-on")
        #expect(engine.remoteStartRequests.isEmpty)
    }

    @Test func aComputerGoneFromItsOwnerFailsInsteadOfFallingBackToTheLocalOne() async throws {
        let engine = engine()
        engine.ownerInventories[deviceID]?.linux.computers = []
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        await #expect(throws: (any Error).self) {
            _ = try await model.ensureRemoteRunning(deviceId: deviceID, computerId: computerID)
        }
        #expect(engine.remoteStartRequests.isEmpty)
        #expect(engine.inventory.computer(computerID)?.displayState == .stopped)
    }

    @Test func remoteAgentToolsStatusAndSetupCarryTheDeviceId() async throws {
        let engine = engine(remoteState: .running)
        engine.mockAgentTools["\(deviceID)/\(computerID)"] = MockEngineClient.agentTools(.missing)
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        try await model.ensureAgentTools(remote, kind: .linux, computerName: "always-on")
        #expect(engine.agentToolsSetupKeys == ["\(deviceID)/\(computerID)"])
        #expect(model.agentTools(for: remote)?.state == .ready)
        #expect(model.agentTools(for: local) == nil)
    }
}
