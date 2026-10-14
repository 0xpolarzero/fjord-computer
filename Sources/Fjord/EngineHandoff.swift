import Darwin
import Foundation

// The engine update handoff, from Fjord's side (design/p2 section 3; decisions A-1 and A-6).
//
// When the bundled silod is newer than the engine that is running, Fjord is the package coordinator:
// it holds the exclusive flock on <engine dir>/installer.lock for the whole handoff, has the engine save and hold its
// running computers (`engine.update.prepare`), has it release them and exit (`engine.shutdown {reason: "update"}`),
// points the LaunchAgent at the new silod, starts it, and checks that the saved computers came back. Before the
// engine has exited, any failure calls `engine.update.abort`, which resumes the exact held computers.

/// Where the handoff is, for the Computers tool.
enum EngineHandoffPhase: Equatable {
    case locking
    case saving
    case stopping
    case swapping
    case starting
    case verifying

    var message: String {
        switch self {
        case .locking: "Getting ready to update the Silo engine…"
        case .saving: "Saving running computers…"
        case .stopping: "Stopping the old Silo engine…"
        case .swapping: "Switching to the new Silo engine…"
        case .starting: "Starting the new Silo engine…"
        case .verifying: "Resuming computers…"
        }
    }
}

/// The exclusive claim on `installer.lock`; dropping it (or the process dying) lets go.
@MainActor
protocol EngineInstallLockHolding: AnyObject {
    func release()
}

@MainActor
protocol EngineInstallLocking {
    func acquire(engineDirectory: URL) throws -> any EngineInstallLockHolding
}

enum EngineInstallLockError: LocalizedError, Equatable {
    /// Another coordinator (Silo.app, or a second Fjord) holds the lock.
    case heldElsewhere
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .heldElsewhere: "Another app is already updating the Silo engine."
        case .failed(let reason): "Fjord couldn't take the Silo engine's install lock: \(reason)"
        }
    }
}

/// The real lock: `flock(LOCK_EX | LOCK_NB)` on a 0600 file, opened without following symlinks and not inherited by children.
@MainActor
struct FlockEngineInstallLock: EngineInstallLocking {
    static let fileName = "installer.lock"

    func acquire(engineDirectory: URL) throws -> any EngineInstallLockHolding {
        do {
            try FileManager.default.createDirectory(at: engineDirectory, withIntermediateDirectories: true)
        } catch {
            throw EngineInstallLockError.failed(error.localizedDescription)
        }
        let path = engineDirectory.appendingPathComponent(Self.fileName).path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw EngineInstallLockError.failed(String(cString: strerror(errno))) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(descriptor)
            if reason == EWOULDBLOCK { throw EngineInstallLockError.heldElsewhere }
            throw EngineInstallLockError.failed(String(cString: strerror(reason)))
        }
        return FlockHolding(descriptor: descriptor)
    }

    @MainActor
    private final class FlockHolding: EngineInstallLockHolding {
        private var descriptor: Int32

        init(descriptor: Int32) { self.descriptor = descriptor }

        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }
}

/// Tells whether something still listens on the engine socket (the old engine has exited once nothing does).
@MainActor
protocol EngineProcessProbing {
    func isListening() -> Bool
}

@MainActor
struct SocketEngineProbe: EngineProcessProbing {
    let socketPath: String

    func isListening() -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return true }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return true }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, length) == 0 }
        }
    }
}

/// How long each wait of the handoff polls. Tests use zero delays.
struct EngineHandoffTiming {
    var pollNanoseconds: UInt64
    var jobPolls: Int
    var exitPolls: Int
    var startPolls: Int
    var resumePolls: Int

    static let production = EngineHandoffTiming(pollNanoseconds: 500_000_000, jobPolls: 960, exitPolls: 240,
                                               startPolls: 120, resumePolls: 240)
    static let immediate = EngineHandoffTiming(pollNanoseconds: 0, jobPolls: 5, exitPolls: 5, startPolls: 5, resumePolls: 5)
}

enum EngineHandoffOutcome: Equatable {
    /// The new engine serves, and these computers were saved and have come back (`missing` have not, yet).
    case completed(version: String, resumed: [String], missing: [String])
    /// The lock showed another installer, or the engine is already as new as the bundle. Nothing was touched.
    case notNeeded(reason: String)
    /// Stopped before the old engine left: it was told to abort and still serves its computers.
    case blocked(reason: String)
    /// The old engine left but the new one didn't come up cleanly. Releasing the lock lets any engine that starts restore
    /// the saved computers.
    case failed(reason: String)
}

@MainActor
final class EngineHandoff {
    private let lock: any EngineInstallLocking
    private let service: any EngineAgentServicing
    private let connector: any EngineSocketConnecting
    private let probe: any EngineProcessProbing
    private let engineDirectory: URL
    private let timing: EngineHandoffTiming

    init(engineDirectory: URL, lock: any EngineInstallLocking, service: any EngineAgentServicing,
         connector: any EngineSocketConnecting, probe: any EngineProcessProbing,
         timing: EngineHandoffTiming = .production) {
        self.engineDirectory = engineDirectory
        self.lock = lock
        self.service = service
        self.connector = connector
        self.probe = probe
        self.timing = timing
    }

    /// Runs the handoff to the bundled engine. `engineStopped` is called once the old engine has gone, so the caller drops
    /// its client.
    func run(bundledVersion: String, phase: (EngineHandoffPhase) -> Void, engineStopped: () -> Void) async -> EngineHandoffOutcome {
        guard let candidate = EngineVersion(bundledVersion) else {
            return .blocked(reason: "The bundled Silo engine reported an invalid version.")
        }

        // 1. The install lock, for the whole handoff.
        phase(.locking)
        let held: any EngineInstallLockHolding
        do { held = try lock.acquire(engineDirectory: engineDirectory) }
        catch { return .notNeeded(reason: error.localizedDescription) }
        defer { held.release() }

        // Compare again under the lock: another app may have updated the engine since we looked.
        let current: EngineConnection
        do { current = try await connector.connect() }
        catch { return .blocked(reason: "The Silo engine stopped answering before it could be updated.") }
        guard let running = EngineVersion(current.version), running < candidate else {
            return .notNeeded(reason: "The Silo engine is already at version \(current.version).")
        }
        let client = current.client

        // 2. Save and hold the running computers.
        phase(.saving)
        var resuming: [SiloWireResumingComputer] = []
        do {
            let started = try await client.invoke(SiloGeneratedMethods.engineUpdatePrepare(SiloWireEmptyParams()))
            let prepared: SiloWireEngineUpdatePrepareFinishedResult = try await finishedResult(of: started.jobId, client: client)
            resuming = prepared.resuming
        } catch {
            return await abort(client: client, because: error)
        }

        // 3. Have it release the saved computers and exit. After this the old engine cannot be asked to resume them.
        phase(.stopping)
        do {
            let _: SiloWireJobStartResult = try await client.invoke(SiloGeneratedMethods.engineShutdown(
                SiloWireEngineShutdownParams(deadlineMs: nil, reason: .update, stopComputers: false)))
        } catch {
            return await abort(client: client, because: error)
        }
        guard await waitUntil(polls: timing.exitPolls, { !probe.isListening() }) else {
            return await abort(client: client, because: HandoffError("The old Silo engine didn't exit."))
        }
        try? await client.engineDisconnect()
        engineStopped()

        // 4. Point the LaunchAgent at the new silod: unregister and register again, which also starts it.
        phase(.swapping)
        do {
            switch service.status() {
            case .enabled, .requiresApproval: try await service.unregister()
            default: break
            }
            try service.register()
        } catch {
            return .failed(reason: "The Silo engine was saved, but Fjord couldn't register the new engine: \(error.localizedDescription)")
        }
        switch service.status() {
        case .requiresApproval:
            return .failed(reason: "The Silo engine was saved. macOS needs your approval in Login Items before the new engine can start.")
        case .enabled: break
        default:
            return .failed(reason: "The Silo engine was saved, but macOS didn't enable the new engine.")
        }

        // 5. Start it and handshake.
        phase(.starting)
        var fresh: EngineConnection?
        _ = await waitUntil(polls: timing.startPolls) {
            fresh = try? await connector.connect()
            return fresh != nil
        }
        guard let fresh else {
            return .failed(reason: "The new Silo engine didn't answer. Your computers stay saved and come back when it starts.")
        }
        guard let started = EngineVersion(fresh.version), started >= candidate else {
            return .failed(reason: "The Silo engine that started is version \(fresh.version), not \(bundledVersion).")
        }

        // 6. The saved set came back?
        phase(.verifying)
        var missing = resuming.map(\.id)
        if !missing.isEmpty {
            _ = await waitUntil(polls: timing.resumePolls) {
                guard let inventory = try? await fresh.client.computersList(deviceId: nil) else { return false }
                missing = resuming.map(\.id).filter { id in
                    inventory.computer(id).map { ComputerStateMapping.displayState(for: $0) != .running } ?? true
                }
                return missing.isEmpty
            }
        }
        let names = Dictionary(resuming.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return .completed(version: fresh.version,
                          resumed: resuming.map(\.id).filter { !missing.contains($0) }.map { names[$0] ?? $0 },
                          missing: missing.map { names[$0] ?? $0 })
    }

    // MARK: Pieces

    private struct HandoffError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Resumes the exact held computers; the old engine keeps serving.
    private func abort(client: any EngineClient, because cause: Error) async -> EngineHandoffOutcome {
        let reason = cause.localizedDescription
        do {
            let _: SiloNull = try await client.invoke(SiloGeneratedMethods.engineUpdateAbort(SiloWireEmptyParams()))
            return .blocked(reason: reason)
        } catch {
            return .blocked(reason: "\(reason) Fjord also couldn't abort the update (\(error.localizedDescription)); the engine resumes the computers on its own when the install lock is released.")
        }
    }

    /// Polls a job until it finishes, then decodes its result.
    private func finishedResult<Result: Decodable & Sendable>(of jobId: String, client: any EngineClient) async throws -> Result {
        for _ in 0..<timing.jobPolls {
            let snapshot = try await client.operationsJobGet(jobId: jobId, deviceId: nil)
            if snapshot.state == .finished {
                try? await client.operationsJobAcknowledge(jobId: jobId, deviceId: nil)
                if let error = snapshot.outcome?.error { throw HandoffError(error.userMessage) }
                guard let result = snapshot.outcome?.result else { throw HandoffError("The Silo engine finished without a result.") }
                return try JSONDecoder().decode(Result.self, from: JSONEncoder().encode(result))
            }
            await pause()
        }
        throw HandoffError("The Silo engine took too long to save the running computers.")
    }

    private func waitUntil(polls: Int, _ condition: () async -> Bool) async -> Bool {
        for _ in 0..<max(polls, 1) {
            if await condition() { return true }
            await pause()
        }
        return false
    }

    private func pause() async {
        if timing.pollNanoseconds > 0 { try? await Task.sleep(nanoseconds: timing.pollNanoseconds) }
        else { await Task.yield() }
    }
}

/// A Fjord update that carries a different silod leaves this mark before it swaps the app in, so the new Fjord's first
/// launch connects to the old engine and runs the handoff, without waiting for Computers to be opened.
enum EngineHandoffMarker {
    static let key = "fjord.engineHandoffPending"

    static func set(_ defaults: UserDefaults = .standard) { defaults.set(true, forKey: key) }
    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    /// Reads and clears the mark.
    static func take(_ defaults: UserDefaults = .standard) -> Bool {
        let pending = defaults.bool(forKey: key)
        if pending { clear(defaults) }
        return pending
    }

    /// The engine version inside an app bundle (the one Fjord ships, or a staged update), if it has one.
    static func engineVersion(in app: URL) -> String? {
        let path = "Contents/Resources/SiloEngineDistribution/Silo Engine.app/Contents/Resources/engine-manifest.json"
        struct Manifest: Decodable { let engineVersion: String }
        guard let data = try? Data(contentsOf: app.appendingPathComponent(path)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        return manifest.engineVersion
    }
}
