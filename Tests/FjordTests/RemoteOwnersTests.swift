import Foundation
import Testing
@testable import Fjord

/// Triage runs, the Computers page's references and the computer-removal hooks for computers owned by another device:
/// every call names the owner, and a computer with the same id on This Mac is never read, started or cleaned up instead.
@MainActor
@Suite(.serialized) struct RemoteOwnersTests {
    private let deviceID = "device-2"
    private let computerID = "10000000-0000-4000-8000-0000000000c9"
    private var remote: GuestReference { GuestReference(deviceId: deviceID, computerId: computerID) }
    private var local: GuestReference { GuestReference.thisMac(computerID) }
    private var account: GuestAccount {
        GuestAccount(home: "/home/silo", uid: 1000, operatingSystem: .linux, architecture: "aarch64",
                     nodeExecutable: "/usr/bin/node", claudeExecutable: "/usr/local/bin/claude")
    }

    private func row(_ name: String, state: LinuxComputerState) -> ApplicationComputer {
        ApplicationComputer(kind: .linux,
            configuration: ComputerConfiguration(id: computerID, name: name, cpus: 2, maxCPUs: 8, memoryGiB: 4,
                maxMemoryGiB: 16, workspaceStorageGiB: 32, runtimeStorageGiB: 16),
            purpose: "Always-on", state: state, stateDetail: state.rawValue.capitalized, canDismissError: false, freshness: "fresh")
    }

    private func engine(remoteComputer: Bool = true) -> MockEngineClient {
        var localInventory = MockEngineClient.demoInventory
        localInventory.linux.computers.append(row("local-twin", state: .stopped))
        let engine = MockEngineClient(inventory: localInventory)
        var owned = MockEngineClient.demoInventory
        owned.linux.computers = remoteComputer ? [row("always-on", state: .stopped)] : []
        engine.connectedDevices = [SiloWireDevice(address: "me@host-2", id: deviceID, name: "Host 2")]
        engine.ownerInventories[deviceID] = owned
        return engine
    }

    private func settings() -> RunInComputerSettings {
        RunInComputerSettings(deviceID: deviceID, computerID: computerID, computerName: "always-on",
                              workspaceRoot: "/workspace", promptTemplate: "Fix {title} in {repo} by {author}",
                              model: nil, effort: nil, permissionMode: .default, allowedTools: [], recordProof: false)
    }

    private func record(_ settings: RunInComputerSettings, thing: Thing) throws -> ComputerRunRecord {
        let id = UUID()
        return ComputerRunRecord(id: id, categoryID: UUID(), actionID: UUID(), thingID: thing.id, triggerKey: "enter",
            settings: settings, repo: thing.repo, repositoryPath: try settings.repositoryPath(repo: thing.repo),
            branch: ComputerRunPrompt.branch(task: thing.title, runID: id), taskTitle: thing.title,
            prompt: ComputerRunPrompt.render(settings.promptTemplate, thing: thing))
    }

    @Test func triageRunStartsTheOwnersComputerAndLeavesTheSameIdLocalOneAlone() async throws {
        let engine = engine()
        let guest = MockGuestClient(accounts: [local: account])
        let thing = InboxFixture.pr(42)
        let placement = settings()
        let coordinator = ComputerRunCoordinator(engine: engine, guest: guest, authorization: .qualified,
            checkpointRetentionCount: 3, secretAssignment: true, githubRepository: true)

        // The owner's computer is started, then the run stops at the guest account: only the local twin has one.
        await #expect(throws: (any Error).self) {
            _ = try await coordinator.run(try record(placement, thing: thing), settings: placement, thing: thing) { _ in true }
        }
        #expect(engine.remoteStartRequests == ["\(deviceID)/\(computerID)"])
        #expect(engine.ownerInventories[deviceID]?.computer(computerID)?.displayState == .running)
        #expect(engine.inventory.computer(computerID)?.displayState == .stopped)
        #expect(await guest.execRecords().isEmpty)
    }

    @Test func triageRunFailsWhenTheComputerIsGoneFromItsOwnerEvenIfThisMacHasOneWithTheSameId() async throws {
        let engine = engine(remoteComputer: false)
        let guest = MockGuestClient(accounts: [local: account, remote: account])
        let thing = InboxFixture.pr(42)
        let placement = settings()
        let coordinator = ComputerRunCoordinator(engine: engine, guest: guest, authorization: .qualified,
            checkpointRetentionCount: 3, secretAssignment: true, githubRepository: true)

        do {
            _ = try await coordinator.run(try record(placement, thing: thing), settings: placement, thing: thing) { _ in true }
            Issue.record("the run used a computer that its owner no longer has")
        } catch let failure as ComputerRunFailure {
            guard case .computerUnavailable(let detail) = failure else { Issue.record("wrong failure \(failure)"); return }
            #expect(detail.contains("always-on"))
            #expect(detail.contains(deviceID))
        }
        #expect(engine.remoteStartRequests.isEmpty)
        #expect(engine.inventory.computer(computerID)?.displayState == .stopped)
        #expect(await guest.callLog().isEmpty)
    }

    @Test func reattachingKeepsTheRecordedOwnerRegardlessOfTheRuleNow() async throws {
        let guest = MockGuestClient(accounts: [local: account, remote: account])
        await guest.setExecJobResult(.init(state: .exited, exitCode: 0,
            stdout: Data(#"{"type":"result","result":"Done","is_error":false}"#.utf8), stderr: Data(), nextSequence: 1),
            jobId: "job-on-owner")
        let thing = InboxFixture.pr(42)
        var running = try record(settings(), thing: thing)
        running.phase = .running
        running.execJobID = "job-on-owner"
        // The rule has since moved to This Mac; the saved record still names the owner.
        var moved = settings()
        moved.deviceID = nil
        #expect(moved.target == local)
        let coordinator = ComputerRunCoordinator(engine: engine(), guest: guest, authorization: .blocked("closed"))
        let result = try await coordinator.reattach(running) { _ in true }

        #expect(result.deviceID == deviceID)
        #expect(await guest.execGetRequests().map(\.computer) == [remote])
        #expect(await guest.execStartRecords().isEmpty)
    }

    @Test func removingAThisMacComputerLeavesTheSameIdComputerOnAnotherDeviceAlone() async throws {
        let engine = engine()
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        var removed: [GuestReference] = []
        model.prepareComputerRemoval = { removed.append($0) }
        model.computerRemovalCompleted = { removed.append($0) }
        // The local twin is stopped, so it can be deleted.
        await model.delete(.thisMac(computerID))
        #expect(removed == [local, local])
        #expect(engine.ownerInventories[deviceID]?.computer(computerID) != nil)

        let store = Store(engineClient: engine)
        store.persists = false
        store.setRunsOnPlacement(.computer(deviceId: deviceID, computerId: computerID, guestPath: "/a"), for: "/src/one")
        store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computerID, guestPath: "/b"), for: "/src/two")
        GuestRouterRuntime.shared.computerRemoved(store: store, computer: local)
        defer { GuestRouterRuntime.shared.stopAll() }
        #expect(store.runsOnProject(for: "/src/one").placement.location == .computer(deviceId: deviceID, computerId: computerID))
        if case .computer = store.runsOnProject(for: "/src/two").placement.location { Issue.record("the local placement stayed") }
    }
}
