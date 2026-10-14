import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite(.serialized) struct EngineHandoffTests {
    @Test func theHandoffRunsInTheOrderTheEngineNeedsAndHoldsTheLockThroughout() async {
        let rig = Rig(resuming: [(MockEngineClient.linuxID, "linux-1")])

        await rig.launcher.inspect()
        #expect(rig.launcher.updateStartsAutomatically)
        await rig.launcher.continueUpdateIfAutomatic()

        // inspect() connects once; the handoff connects again under the lock, then to the started engine; the launcher
        // adopts the new engine once the lock is released.
        #expect(rig.log.events == [
            "connect", "lock", "connect", "prepare", "job", "shutdown", "probe", "unregister", "register", "connect",
            "unlock", "connect",
        ])
        #expect(rig.launcher.update == .completed(resumed: ["linux-1"], missing: []))
        #expect(rig.launcher.state == .connected(version: "1.2.0", source: .fjordAgent))
        #expect(rig.launcher.client != nil)
        #expect(!rig.log.events.contains("abort"))
    }

    @Test func aSavedComputerThatHasNotComeBackIsNamed() async {
        let rig = Rig(resuming: [(MockEngineClient.failedID, "linux-broken")])

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(rig.launcher.update == .completed(resumed: [], missing: ["linux-broken"]))
    }

    @Test func aRefusedPrepareAbortsAndTheOldEngineKeepsServing() async {
        let rig = Rig(prepareError: "A computer can't be saved.")

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(rig.log.events.contains("abort"))
        #expect(!rig.log.events.contains("shutdown"))
        #expect(!rig.log.events.contains("unregister") && !rig.log.events.contains("register"))
        #expect(rig.log.events.last == "unlock")
        #expect(rig.launcher.client != nil)
        #expect(rig.launcher.state == .connected(version: "1.1.0", source: .fjordAgent))
        #expect(rig.launcher.update == .blocked("A computer can't be saved."))
    }

    @Test func aFailedShutdownAbortsBeforeAnythingIsSwapped() async {
        let rig = Rig(shutdownFails: true)

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(rig.log.events.contains("abort"))
        #expect(!rig.log.events.contains("register"))
        guard case .blocked = rig.launcher.update else { Issue.record("\(rig.launcher.update)"); return }
        #expect(rig.launcher.client != nil)
    }

    @Test func anEngineThatNeverExitsIsAbortedToo() async {
        let rig = Rig(exits: false)

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(rig.log.events.contains("abort"))
        #expect(!rig.log.events.contains("register"))
        guard case .blocked = rig.launcher.update else { Issue.record("\(rig.launcher.update)"); return }
    }

    @Test func anInstallerHoldingTheLockLeavesTheEngineAlone() async {
        let rig = Rig(lockError: EngineInstallLockError.heldElsewhere)

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(!rig.log.events.contains("prepare"))
        #expect(rig.launcher.update == .blocked(EngineInstallLockError.heldElsewhere.localizedDescription))
        #expect(rig.launcher.client != nil)
    }

    @Test func anEngineThatAnotherAppAlreadyUpdatedNeedsNoHandoff() async {
        let rig = Rig(connections: [.old, .new, .new])

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(!rig.log.events.contains("prepare"))
        #expect(rig.launcher.update == .none)
        #expect(rig.launcher.state == .connected(version: "1.2.0", source: .fjordAgent))
    }

    @Test func aFailedRegistrationAfterTheSwapIsReportedWithoutAbortAndReleasesTheLock() async {
        let rig = Rig(registerFails: true)

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(!rig.log.events.contains("abort"))
        #expect(rig.log.events.last == "unlock")
        guard case .failed(let reason) = rig.launcher.update else { Issue.record("\(rig.launcher.update)"); return }
        #expect(reason.contains("saved"))
        #expect(rig.launcher.client == nil)
        #expect(rig.launcher.state == .failed(reason))
    }

    @Test func aNewEngineThatNeverAnswersLeavesTheComputersSavedAndReleasesTheLock() async {
        let rig = Rig(connections: [.old, .old, .none])

        await rig.launcher.inspect()
        await rig.launcher.updateEngine()

        #expect(rig.log.events.last == "unlock")
        guard case .failed(let reason) = rig.launcher.update else { Issue.record("\(rig.launcher.update)"); return }
        #expect(reason.contains("saved"))
    }

    @Test func updatingDoesNotStartByItselfWhenFjordsAgentIsNotRegistered() async {
        let rig = Rig(status: .notRegistered)

        await rig.launcher.inspect()
        await rig.launcher.continueUpdateIfAutomatic()

        #expect(!rig.log.events.contains("lock"))
        #expect(rig.launcher.update == .available(current: "1.1.0", bundled: "1.2.0"))

        await rig.launcher.updateEngine()
        #expect(rig.log.events.contains("register"))
        #expect(rig.launcher.update == .completed(resumed: [], missing: []))
    }

    @Test func aBlockedUpdateCanBeTriedAgain() async {
        let rig = Rig(prepareError: "A computer can't be saved.", connections: [.old, .old])
        await rig.launcher.inspect()
        await rig.launcher.updateEngine()
        #expect(rig.launcher.update == .blocked("A computer can't be saved."))

        rig.engine.prepareError = nil
        rig.connector.append(.old, .new, .new)
        await rig.launcher.updateEngine()

        #expect(rig.launcher.update == .completed(resumed: [], missing: []))
    }

    @Test func theRealLockIsExclusiveAndLetsGoOnRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-lock-\(UUID().uuidString)/engine")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let lock = FlockEngineInstallLock()

        let first = try lock.acquire(engineDirectory: directory)
        #expect(throws: EngineInstallLockError.heldElsewhere) { _ = try lock.acquire(engineDirectory: directory) }
        first.release()
        let second = try lock.acquire(engineDirectory: directory)
        second.release()

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("installer.lock").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    // MARK: Fakes

    private enum Link { case old, new, none }

    @MainActor private final class Log { var events: [String] = [] }

    @MainActor private final class Rig {
        let log = Log()
        let engine: FakeEngine
        let service: FakeService
        let connector: FakeConnector
        let launcher: EngineLauncher

        init(resuming: [(String, String)] = [], prepareError: String? = nil, shutdownFails: Bool = false, exits: Bool = true,
             lockError: Error? = nil, registerFails: Bool = false, status: EngineAgentStatus = .enabled,
             connections: [Link] = [.old, .old, .new, .new]) {
            let probe = FakeProbe(log: log)
            engine = FakeEngine(log: log)
            engine.resuming = resuming.map { SiloWireResumingComputer(id: $0.0, name: $0.1) }
            engine.prepareError = prepareError
            engine.shutdownFails = shutdownFails
            engine.onShutdown = { probe.listening = !exits }
            service = FakeService(log: log, status: status, registerFails: registerFails)
            connector = FakeConnector(log: log, engine: engine)
            connector.append(contentsOf: connections)
            let handoff = EngineHandoff(engineDirectory: URL(fileURLWithPath: "/nonexistent/engine"),
                                        lock: FakeLock(log: log, error: lockError), service: service, connector: connector,
                                        probe: probe, timing: .immediate)
            launcher = EngineLauncher(candidateVersion: "1.2.0", candidateBuild: "silo-new", service: service,
                                      connector: connector, handoff: handoff)
        }
    }

    @MainActor private final class FakeEngine: UnavailableEngineClient {
        let log: Log
        var resuming: [SiloWireResumingComputer] = []
        var prepareError: String?
        var shutdownFails = false
        var onShutdown: () -> Void = {}

        init(log: Log) { self.log = log }

        private func encoded<Result: Decodable>(_ value: some Encodable, as _: Result.Type) throws -> Result {
            try JSONDecoder().decode(Result.self, from: JSONEncoder().encode(value))
        }

        override func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
            _ call: SiloGeneratedMethodCall<Params, Result>
        ) async throws -> Result {
            switch call.name {
            case "engine.update.prepare":
                log.events.append("prepare")
                return try encoded(SiloWireJobStartResult(jobId: "prepare-job"), as: Result.self)
            case "engine.shutdown":
                log.events.append("shutdown")
                let params = try encoded(call.params, as: SiloWireEngineShutdownParams.self)
                #expect(params.reason == .update && !params.stopComputers)
                if shutdownFails { throw EngineClientError.coded(code: "busy", message: "The engine is busy.") }
                onShutdown()
                return try encoded(SiloWireJobStartResult(jobId: "shutdown-job"), as: Result.self)
            case "engine.update.abort":
                log.events.append("abort")
                return try encoded(SiloNull(), as: Result.self)
            default:
                throw EngineClientError.unavailable
            }
        }

        override func operationsJobGet(jobId: String, deviceId: String?) async throws -> OperationJobSnapshot {
            log.events.append("job")
            if let prepareError {
                return OperationJobSnapshot(jobId: jobId, state: .finished,
                                            outcome: OperationJobOutcome(error: OperationJobError(code: "update_blocked", message: prepareError)))
            }
            let result = try JSONDecoder().decode(SiloJSONValue.self, from: JSONEncoder().encode(
                SiloWireEngineUpdatePrepareFinishedResult(resuming: resuming)))
            return OperationJobSnapshot(jobId: jobId, state: .finished, outcome: OperationJobOutcome(result: result))
        }

        override func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws {}

        override func computersList(deviceId: String?) async throws -> ComputerInventory { MockEngineClient.demoInventory }
    }

    @MainActor private final class FakeLock: EngineInstallLocking {
        let log: Log
        let error: Error?
        init(log: Log, error: Error?) { self.log = log; self.error = error }

        func acquire(engineDirectory: URL) throws -> any EngineInstallLockHolding {
            if let error { throw error }
            log.events.append("lock")
            return Holding(log: log)
        }

        @MainActor private final class Holding: EngineInstallLockHolding {
            let log: Log
            init(log: Log) { self.log = log }
            func release() { log.events.append("unlock") }
        }
    }

    @MainActor private final class FakeService: EngineAgentServicing {
        let log: Log
        var current: EngineAgentStatus
        let registerFails: Bool
        init(log: Log, status: EngineAgentStatus, registerFails: Bool) {
            self.log = log
            current = status
            self.registerFails = registerFails
        }

        func status() -> EngineAgentStatus { current }
        func register() throws {
            log.events.append("register")
            if registerFails { throw EngineClientError.invalidAction("macOS refused.") }
            current = .enabled
        }
        func unregister() async throws {
            log.events.append("unregister")
            current = .notRegistered
        }
        func openSystemSettings() {}
    }

    @MainActor private final class FakeProbe: EngineProcessProbing {
        let log: Log
        var listening = true
        init(log: Log) { self.log = log }
        func isListening() -> Bool { log.events.append("probe"); return listening }
    }

    @MainActor private final class FakeConnector: EngineSocketConnecting {
        let log: Log
        let engine: FakeEngine
        private var links: [Link] = []
        init(log: Log, engine: FakeEngine) { self.log = log; self.engine = engine }

        func append(_ more: Link...) { links.append(contentsOf: more) }
        func append(contentsOf more: [Link]) { links.append(contentsOf: more) }

        func connect() async throws -> EngineConnection {
            log.events.append("connect")
            guard !links.isEmpty else { throw EngineClientError.unavailable }
            switch links.removeFirst() {
            case .old: return EngineConnection(client: engine, version: "1.1.0", build: "silo-old", source: .fjordAgent)
            case .new: return EngineConnection(client: engine, version: "1.2.0", build: "silo-new", source: .fjordAgent)
            case .none: throw EngineClientError.unavailable
            }
        }
    }
}
