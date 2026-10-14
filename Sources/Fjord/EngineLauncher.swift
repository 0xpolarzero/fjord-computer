import Foundation
import Darwin
import Observation
import ServiceManagement

enum EngineAgentStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

@MainActor
protocol EngineAgentServicing {
    func status() -> EngineAgentStatus
    func register() throws
    func openSystemSettings()
}

@MainActor
struct SystemEngineAgentService: EngineAgentServicing {
    private let plistName = "org.silo.preview.engine.plist"

    func status() -> EngineAgentStatus {
        switch SMAppService.agent(plistName: plistName).status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    func register() throws {
        try SMAppService.agent(plistName: plistName).register()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct EngineConnection {
    let client: any EngineClient
    let version: String
    let build: String?
    let source: EngineConnectionSource
}

@MainActor
protocol EngineSocketConnecting {
    func connect() async throws -> EngineConnection
}

@MainActor
struct SocketEngineConnector: EngineSocketConnecting {
    private let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func connect() async throws -> EngineConnection {
        let client = SocketEngineClient(path: socketPath)
        _ = try await client.connect()
        let engineState: SiloWireEngineState = try await client.invoke(
            SiloGeneratedMethods.engineState(SiloWireEmptyParams()))
        guard !engineState.sessionEnding, !engineState.shuttingDown else {
            throw EngineClientError.unavailable
        }
        let update = try await client.updatesState()
        let recordURL = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
            .appendingPathComponent("engine-owner.json")
        let record = try? JSONDecoder().decode(EngineOwnerRecord.self, from: Data(contentsOf: recordURL))
        return EngineConnection(client: client, version: update.currentVersion, build: record?.engineBuild,
                                source: Self.source(record: record, mainBundleURL: Bundle.main.bundleURL))
    }

    private struct EngineOwnerRecord: Decodable {
        let channelIdentifier: String
        let engineBuild: String
        let pid: Int32
    }

    private static func source(record: EngineOwnerRecord?, mainBundleURL: URL) -> EngineConnectionSource {
        guard let record, record.pid > 0 else { return .sharedEngine }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid_t(record.pid), pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0, let executable = buffer.withUnsafeBufferPointer({ pointer in
            pointer.baseAddress.map(String.init(cString:))
        }) else { return .sharedEngine }

        let bundlePath = mainBundleURL.standardizedFileURL.path
        let executablePath = URL(fileURLWithPath: executable).standardizedFileURL.path
        return executablePath.hasPrefix(bundlePath + "/") ? .fjordAgent : .sharedEngine
    }
}

struct EngineVersion: Comparable, Equatable {
    private enum Identifier: Equatable {
        case numeric(UInt64)
        case text(String)
    }

    private let major: UInt64
    private let minor: UInt64
    private let patch: UInt64
    private let prerelease: [Identifier]

    init?(_ value: String) {
        let parts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2, let versionText = parts.first, !versionText.isEmpty else { return nil }
        if parts.count == 2, !Self.validIdentifiers(String(parts[1]), allowLeadingZeroes: true) { return nil }

        let versionParts = versionText.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let coreText = versionParts.first else { return nil }
        let core = coreText.split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.number(core[0]),
              let minor = Self.number(core[1]),
              let patch = Self.number(core[2]) else { return nil }

        var prerelease: [Identifier] = []
        if versionParts.count == 2 {
            let values = versionParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !values.isEmpty else { return nil }
            for value in values {
                guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
                if value.allSatisfy(\.isNumber) {
                    guard value == "0" || value.first != "0", let number = UInt64(value) else { return nil }
                    prerelease.append(.numeric(number))
                } else {
                    prerelease.append(.text(String(value)))
                }
            }
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    static func < (lhs: EngineVersion, rhs: EngineVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (left, right) {
            case (.numeric(let a), .numeric(let b)): return a < b
            case (.numeric, .text): return true
            case (.text, .numeric): return false
            case (.text(let a), .text(let b)): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func number(_ value: Substring) -> UInt64? {
        guard !value.isEmpty, value == "0" || value.first != "0",
              value.allSatisfy(\.isNumber) else { return nil }
        return UInt64(value)
    }

    private static func validIdentifiers(_ value: String, allowLeadingZeroes: Bool) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
            !identifier.isEmpty
                && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                && (allowLeadingZeroes || !identifier.allSatisfy(\.isNumber) || identifier == "0" || identifier.first != "0")
        }
    }
}

enum EngineConnectionSource: Equatable {
    case fjordAgent
    case sharedEngine
}

enum EngineLaunchState: Equatable {
    case unchecked
    case checking
    case enableRequired
    case registering
    case awaitingApproval
    case waitingForEngine
    case connected(version: String, source: EngineConnectionSource)
    case updateBlocked(current: String, bundled: String, reason: String)
    case missingBundle
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .registering, .waitingForEngine: true
        default: false
        }
    }

    var message: String {
        switch self {
        case .unchecked, .checking: "Checking for the Silo engine…"
        case .enableRequired: "Enable the Silo engine to manage computers on this Mac. Fjord will register its LaunchAgent only after you choose Enable."
        case .registering: "Registering the Silo engine with macOS…"
        case .awaitingApproval: "macOS needs your approval before the Silo engine can run. Open Login Items in System Settings and allow it."
        case .waitingForEngine: "Waiting for the Silo engine to start…"
        case .connected(let version, let source):
            source == .sharedEngine
                ? "Connected to the shared Silo engine, version \(version)."
                : "Connected to the Silo engine, version \(version)."
        case .updateBlocked(_, _, let reason), .failed(let reason): reason
        case .missingBundle: "The Silo engine bundle is missing. Reinstall Fjord to add it."
        }
    }
}

@MainActor
@Observable
final class EngineLauncher {
    @ObservationIgnored private let service: any EngineAgentServicing
    @ObservationIgnored private let connector: any EngineSocketConnecting
    @ObservationIgnored private let candidateVersion: String?
    @ObservationIgnored private let candidateBuild: String?
    @ObservationIgnored private let pollDelaysNanoseconds: [UInt64]
    @ObservationIgnored private var operationInFlight = false
    @ObservationIgnored private(set) var client: (any EngineClient)?
    private(set) var state: EngineLaunchState = .unchecked

    var isConnected: Bool {
        if case .connected = state { return client != nil }
        return false
    }

    convenience init(socketPath: String) {
        let candidate = Self.embeddedCandidate()
        self.init(candidateVersion: candidate?.version, candidateBuild: candidate?.build,
                  service: SystemEngineAgentService(), connector: SocketEngineConnector(socketPath: socketPath),
                  pollDelaysNanoseconds: [0, 250_000_000, 500_000_000, 1_000_000_000, 1_000_000_000])
    }

    convenience init(candidateVersion: String, candidateBuild: String = "test-build",
                     service: any EngineAgentServicing, connector: any EngineSocketConnecting,
                     pollDelaysNanoseconds: [UInt64] = [0]) {
        self.init(candidateVersion: Optional(candidateVersion), candidateBuild: Optional(candidateBuild),
                  service: service, connector: connector, pollDelaysNanoseconds: pollDelaysNanoseconds)
    }

    private init(candidateVersion: String?, candidateBuild: String?, service: any EngineAgentServicing,
                 connector: any EngineSocketConnecting, pollDelaysNanoseconds: [UInt64]) {
        self.candidateVersion = candidateVersion
        self.candidateBuild = candidateBuild
        self.service = service
        self.connector = connector
        self.pollDelaysNanoseconds = pollDelaysNanoseconds
    }

    func inspect() async {
        guard !operationInFlight else { return }
        operationInFlight = true
        defer { operationInFlight = false }
        guard candidateVersion != nil else { state = .missingBundle; return }

        state = .checking
        if let running = try? await connector.connect() {
            adopt(running)
            return
        }
        switch service.status() {
        case .notRegistered: state = .enableRequired
        case .requiresApproval: state = .awaitingApproval
        case .notFound: state = .missingBundle
        case .enabled: await waitForEngine()
        case .unknown: state = .failed("macOS returned an unknown LaunchAgent status.")
        }
    }

    /// Called only from the visible Enable button. `inspect()` never registers the service.
    func enable() async {
        guard !operationInFlight else { return }
        operationInFlight = true
        defer { operationInFlight = false }
        guard candidateVersion != nil else { state = .missingBundle; return }

        state = .checking
        if let running = try? await connector.connect() {
            adopt(running)
            return
        }

        switch service.status() {
        case .requiresApproval:
            state = .awaitingApproval
            return
        case .notFound:
            state = .missingBundle
            return
        case .unknown:
            state = .failed("macOS returned an unknown LaunchAgent status.")
            return
        case .notRegistered:
            state = .registering
            do {
                try service.register()
            } catch {
                switch service.status() {
                case .requiresApproval: state = .awaitingApproval
                case .enabled: await waitForEngine()
                case .notFound: state = .missingBundle
                case .unknown: state = .failed(error.localizedDescription)
                case .notRegistered: state = .failed(error.localizedDescription)
                }
                return
            }
        case .enabled:
            break
        }

        switch service.status() {
        case .requiresApproval: state = .awaitingApproval
        case .notFound: state = .missingBundle
        case .unknown: state = .failed("macOS returned an unknown LaunchAgent status.")
        case .notRegistered: state = .failed("macOS did not register the Silo LaunchAgent.")
        case .enabled: await waitForEngine()
        }
    }

    func openApprovalSettings() {
        guard state == .awaitingApproval else { return }
        service.openSystemSettings()
    }

    private func waitForEngine() async {
        state = .waitingForEngine
        var lastFailure = "macOS enabled the LaunchAgent, but the engine did not complete its socket handshake."
        for delay in pollDelaysNanoseconds {
            if delay > 0 {
                do { try await Task.sleep(nanoseconds: delay) }
                catch { state = .enableRequired; return }
            }
            do {
                let running = try await connector.connect()
                adopt(running)
                return
            } catch {
                lastFailure = error.localizedDescription
            }
        }
        state = .failed(lastFailure)
    }

    private func adopt(_ running: EngineConnection) {
        guard let candidateVersion, let candidate = EngineVersion(candidateVersion),
              let current = EngineVersion(running.version) else {
            client = nil
            state = .failed("The bundled or running engine reported an invalid SemVer version.")
            return
        }
        if current < candidate {
            client = nil
            state = .updateBlocked(current: running.version, bundled: candidateVersion,
                                   reason: "Fjord includes Silo \(candidateVersion), but version \(running.version) is running. Fjord left it running until its computers can be saved and resumed safely during an update.")
            return
        }
        if current == candidate, let candidateBuild,
           running.build.map({ $0 != candidateBuild }) ?? true {
            client = nil
            state = .updateBlocked(current: running.version, bundled: candidateVersion,
                                   reason: "A different build of Silo \(candidateVersion) already owns this Mac. Fjord left it running to protect its computers.")
            return
        }
        client = running.client
        state = .connected(version: running.version, source: running.source)
    }

    private static func embeddedCandidate() -> (version: String, build: String)? {
        let path = "Contents/Resources/SiloEngineDistribution/Silo Engine.app/Contents/Resources/engine-manifest.json"
        let url = Bundle.main.bundleURL.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(EngineManifest.self, from: data) else { return nil }
        return (manifest.engineVersion, manifest.engineBuild)
    }

    private struct EngineManifest: Decodable {
        let engineVersion: String
        let engineBuild: String
    }
}
