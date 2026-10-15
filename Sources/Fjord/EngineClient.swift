import Foundation

enum ComputerRow: Identifiable, Equatable {
    case linux(ApplicationComputer)
    case macos(MacosComputer)

    var id: String {
        switch self {
        case .linux(let computer): computer.id
        case .macos(let computer): computer.id
        }
    }

    var name: String {
        switch self {
        case .linux(let computer): computer.name
        case .macos(let computer): computer.name
        }
    }

    var kind: ComputerKind {
        switch self {
        case .linux: .linux
        case .macos: .macos
        }
    }

    var displayState: ComputerDisplayState { ComputerStateMapping.displayState(for: self) }

    var detail: String? {
        switch self {
        case .linux(let computer):
            if computer.state == .failed { return computer.attention?.message ?? computer.stateDetail }
            return computer.stateDetail == displayState.title ? nil : computer.stateDetail
        case .macos(let computer): return computer.detail
        }
    }

    /// Something to know about the computer that is not a problem (a Mac imported without SecureToken).
    var note: String? {
        switch self {
        case .linux: nil
        case .macos(let computer): computer.note
        }
    }

    var resources: String {
        switch self {
        case .linux(let computer):
            "\(computer.configuration.cpus) CPU · \(computer.configuration.memoryGiB) GB memory"
        case .macos(let computer):
            "\(computer.cpus) CPU · \(computer.memoryGiB) GB memory · \(computer.diskGiB) GB disk"
        }
    }

    var checkpoints: [ComputerCheckpoint] {
        switch self {
        case .linux(let computer): computer.checkpoints ?? []
        case .macos(let computer): computer.checkpoints
        }
    }

    var canStart: Bool { displayState == .stopped || displayState == .failed }
    var canStop: Bool { displayState == .running }
    var canForceStop: Bool { kind == .macos && [.starting, .running, .stopping].contains(displayState) }
    var canDelete: Bool { [.stopped, .failed, .preparing, .copying, .downloading, .installing, .settingUp].contains(displayState) }
    var canShowDisplay: Bool { displayState == .running }
}

enum ComputerDisplayState: Equatable {
    case preparing, copying, downloading, installing, settingUp
    case stopped, starting, running, stopping, failed

    var title: String {
        switch self {
        case .preparing: "Preparing"
        case .copying: "Copying"
        case .downloading: "Downloading"
        case .installing: "Installing"
        case .settingUp: "Setting up"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .failed: "Failed"
        }
    }
}

enum ComputerStateMapping {
    static func displayState(for computer: ComputerRow) -> ComputerDisplayState {
        switch computer {
        case .linux(let row):
            if row.state == .starting && row.stateDetail.localizedCaseInsensitiveContains("stopping") { return .stopping }
            switch row.state {
            case .running: return .running
            case .starting: return .starting
            case .stopped: return .stopped
            case .failed: return .failed
            }
        case .macos(let row):
            switch row.state {
            case .preparing: return .preparing
            case .copying: return .copying
            case .downloading: return .downloading
            case .installing: return .installing
            case .settingUp: return .settingUp
            case .stopped: return .stopped
            case .starting: return .starting
            case .running: return .running
            case .stopping: return .stopping
            case .failed: return .failed
            }
        }
    }
}

/// App presentation projections. The socket path decodes `SiloWireJobProgress` first,
/// then maps it here; the tolerant Codable form also preserves the existing fixture test.
enum JobProgressSource: String, Codable, Equatable { case setup, lifecycle, transfer, backup, push, macos, update }

struct SetupJobProgressData: Codable, Equatable {
    var schemaVersion: Int
    var type: String
    var requestId: String
    var phase: String
    var step: String
    var computer: String? = nil
    var fraction: Double? = nil
    var message: String
    var safeForDisplay: Bool
    var timestamp: String
    var level: String
    var elapsedSeconds: Double
    var downloadedBytes: UInt64? = nil
    var totalBytes: UInt64? = nil
    var failureCode: String? = nil
    var exitCode: Int? = nil
    var diagnostic: String? = nil
    var partial: Bool
}

struct LifecycleJobProgressData: Codable, Equatable {
    var computerId: String
    var action: String
    var step: String
}

struct TransferJobProgressData: Codable, Equatable {
    var id: String
    var computer: String
    var direction: String
    var state: String
    var name: String
    var fileIndex: UInt64
    var fileCount: UInt64
    var bytesDone: UInt64
    var bytesTotal: UInt64
}

struct BackupJobProgressArchive: Codable, Equatable {
    var name: String
    var archivePath: String
    var completedLabel: String
    var size: UInt64
    var destination: String
    var computers: [String]
    var checkpointName: String? = nil
}

struct BackupJobProgressPhase: Codable, Equatable {
    var title: String
    var detail: String
    var tone: String
}

struct BackupJobProgressData: Codable, Equatable {
    var operation: String
    var archive: BackupJobProgressArchive
    var runningNames: [String]
    var targetName: String? = nil
    var progress: UInt8
    var indeterminate: Bool? = nil
    var canCancel: Bool? = nil
    var phases: [BackupJobProgressPhase]
}

struct PushJobProgressData: Codable, Equatable {
    var operationId: String
    var computer: String
    var repositoryPath: String
    var status: String
    var commitCount: Int
    var message: String? = nil
    var target: JSONValue
}

struct MacosJobProgressData: Codable, Equatable {
    var computerId: String
    var state: String
    var progress: Double? = nil
    var detail: String? = nil
    var checkpointOperation: ComputerCheckpointOperation? = nil
}

struct UpdateJobProgressData: Codable, Equatable {
    var phase: String
    var lastChecked: String? = nil
    var retryAction: String? = nil
    var currentVersion: String
    var availableVersion: String? = nil
    var releaseNotes: String? = nil
    var downloadedBytes: UInt64? = nil
    var totalBytes: UInt64? = nil
    var automaticChecks: Bool
    var packageKind: String
    var releaseUrl: String
    var error: String? = nil
    var errorDetails: String? = nil
    var runningComputers: [String]
    var canInstall: Bool
    var installBlockReason: String? = nil
}

enum OperationJobProgressData: Equatable {
    case setup(SetupJobProgressData)
    case lifecycle(LifecycleJobProgressData)
    case transfer(TransferJobProgressData)
    case backup(BackupJobProgressData)
    case push(PushJobProgressData)
    case macos(MacosJobProgressData)
    case update(UpdateJobProgressData)

    var presentationProgress: Double? {
        switch self {
        case .setup(let value): return value.fraction
        case .lifecycle: return nil
        case .transfer(let value):
            guard value.bytesTotal > 0 else { return nil }
            return Double(value.bytesDone) / Double(value.bytesTotal)
        case .backup(let value): return Double(value.progress) / 100
        case .push: return nil
        case .macos(let value): return value.progress
        case .update(let value):
            guard let total = value.totalBytes, total > 0, let done = value.downloadedBytes else { return nil }
            return Double(done) / Double(total)
        }
    }

    var presentationTitle: String? {
        switch self {
        case .setup(let value): return value.message
        case .lifecycle(let value): return "\(value.action.capitalized) · \(value.step)"
        case .transfer(let value): return value.name
        case .backup(let value): return value.phases.last?.detail ?? "Backup"
        case .push(let value): return value.message ?? "Pushing changes"
        case .macos(let value): return value.detail ?? value.state.capitalized
        case .update(let value): return value.error ?? value.phase.capitalized
        }
    }

    var presentationComputerId: String? {
        switch self {
        case .lifecycle(let value): return value.computerId
        case .macos(let value): return value.computerId
        case .setup, .transfer, .backup, .push, .update: return nil
        }
    }
}

struct OperationJobProgress: Codable, Equatable {
    var jobId: String
    var kind: String? = nil
    var computerId: String? = nil
    var source: JobProgressSource
    var data: OperationJobProgressData

    private enum CodingKeys: String, CodingKey { case jobId, kind, computerId, source, data }

    init(jobId: String, kind: String? = nil, computerId: String? = nil, source: JobProgressSource,
         data: OperationJobProgressData) {
        self.jobId = jobId
        self.kind = kind
        self.computerId = computerId
        self.source = source
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(String.self, forKey: .jobId)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        computerId = try container.decodeIfPresent(String.self, forKey: .computerId)
        source = try container.decode(JobProgressSource.self, forKey: .source)
        switch source {
        case .setup: data = .setup(try container.decode(SetupJobProgressData.self, forKey: .data))
        case .lifecycle: data = .lifecycle(try container.decode(LifecycleJobProgressData.self, forKey: .data))
        case .transfer: data = .transfer(try container.decode(TransferJobProgressData.self, forKey: .data))
        case .backup: data = .backup(try container.decode(BackupJobProgressData.self, forKey: .data))
        case .push: data = .push(try container.decode(PushJobProgressData.self, forKey: .data))
        case .macos: data = .macos(try container.decode(MacosJobProgressData.self, forKey: .data))
        case .update: data = .update(try container.decode(UpdateJobProgressData.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(computerId, forKey: .computerId)
        try container.encode(source, forKey: .source)
        switch data {
        case .setup(let value): try container.encode(value, forKey: .data)
        case .lifecycle(let value): try container.encode(value, forKey: .data)
        case .transfer(let value): try container.encode(value, forKey: .data)
        case .backup(let value): try container.encode(value, forKey: .data)
        case .push(let value): try container.encode(value, forKey: .data)
        case .macos(let value): try container.encode(value, forKey: .data)
        case .update(let value): try container.encode(value, forKey: .data)
        }
    }
}

struct OperationJobError: Codable, Equatable, Sendable {
    var code: String
    var message: String

    /// The message to show: a plain-language text for the stable codes Fjord knows, the engine's otherwise.
    var userMessage: String { EngineErrorText.message(code: code, fallback: message) }
}

/// Plain-language texts for the engine's stable error codes.
enum EngineErrorText {
    static func message(code: String, fallback: String) -> String {
        switch code {
        case "not_running": "This computer isn't running. Start it, then try again."
        case "needs_personalizing": "This Mac computer needs personalizing first. Open it and finish its setup, then try again."
        case "setup_incomplete": "This computer's setup isn't finished. Finish setup, then try again."
        case "screen_sharing_unavailable": "Screen sharing isn't available for this computer right now. Try again in a moment."
        case "running_limit": "Too many computers are running at once. Stop one, then try again."
        case "desktop_update_required": "This needs a newer Silo desktop. Use Update desktop, then try again."
        case "permission_denied": "Silo doesn't have permission to do that. Check this Mac's privacy settings, then try again."
        case "output_too_large": "The output was too large to return. Narrow the request or send it to a file."
        case "credential_access_denied": "\(credentialAccessDenied) Use Allow access on the Computers page or in Settings."
        default: fallback
        }
    }

    static let known: Set<String> = ["not_running", "needs_personalizing", "setup_incomplete", "screen_sharing_unavailable",
                                     "running_limit", "desktop_update_required", "permission_denied", "output_too_large",
                                     "credential_access_denied"]
}

struct OperationJobFinished: Codable, Equatable, Sendable {
    var jobId: String
    var result: JSONValue? = nil
    var error: OperationJobError? = nil
}

struct OperationQueueEntry: Codable, Equatable, Identifiable {
    var id: UInt64
    var jobId: String? = nil
    var label: String
    var kind: String
    var computerId: String? = nil
    var computerName: String? = nil
    var sinceMs: UInt64
    var cancellable: Bool
    var expectedMs: UInt64? = nil
    var blockedByHidden: Bool
}

struct OperationsList: Codable, Equatable {
    var running: [OperationQueueEntry]
    var waiting: [OperationQueueEntry]
    var unacknowledgedJobIds: [String]

    static let empty = OperationsList(running: [], waiting: [], unacknowledgedJobIds: [])
}

struct OperationJobOutcome: Codable, Equatable, Sendable {
    var result: JSONValue? = nil
    var error: OperationJobError? = nil
}

struct OperationJobSnapshot: Codable, Equatable, Sendable {
    var jobId: String
    var state: OperationJobState
    var outcome: OperationJobOutcome? = nil

    var finishedEvent: OperationJobFinished {
        OperationJobFinished(jobId: jobId, result: outcome?.result, error: outcome?.error)
    }
}

enum EngineEvent: Equatable {
    case computersChanged(ComputersChangedPayload, deviceId: String? = nil)
    case connectionsDevicesChanged
    case checkpointsChanged(CheckpointsChangedPayload, deviceId: String? = nil)
    case operationsQueueChanged(OperationsList, deviceId: String? = nil)
    case jobProgress(OperationJobProgress, deviceId: String? = nil)
    case jobFinished(OperationJobFinished, deviceId: String? = nil)
    case guestFilesChanged(deviceId: String, payload: SiloWireGuestFilesChangedPayload)
    case settingsChanged(SiloWireSettingsSnapshot)
    case exportsChanged(SiloWireBackupState)
    case viewerPage(SiloWireViewerPageEvent)

    var name: String {
        switch self {
        case .computersChanged: "computers.changed"
        case .connectionsDevicesChanged: "connections.devices.changed"
        case .checkpointsChanged: "checkpoints.changed"
        case .operationsQueueChanged: "operations.queue.changed"
        case .jobProgress: "operations.job.progress"
        case .jobFinished: "operations.job.finished"
        case .guestFilesChanged: "guest.files.changed"
        case .settingsChanged: "settings.changed"
        case .exportsChanged: "exports.changed"
        case .viewerPage: "display.viewer.page"
        }
    }

    /// The same event as a controller's engine relays it from the device that owns the state.
    func relayed(from deviceId: String) -> EngineEvent {
        switch self {
        case .computersChanged(let payload, _): .computersChanged(payload, deviceId: deviceId)
        case .checkpointsChanged(let payload, _): .checkpointsChanged(payload, deviceId: deviceId)
        case .operationsQueueChanged(let list, _): .operationsQueueChanged(list, deviceId: deviceId)
        case .jobProgress(let progress, _): .jobProgress(progress, deviceId: deviceId)
        case .jobFinished(let finished, _): .jobFinished(finished, deviceId: deviceId)
        case .guestFilesChanged(_, let payload): .guestFilesChanged(deviceId: deviceId, payload: payload)
        case .connectionsDevicesChanged, .settingsChanged, .exportsChanged, .viewerPage: self
        }
    }
}

enum EngineEventDelivery: Equatable {
    case event(sequence: UInt64, event: EngineEvent)
    case sequenceAdvanced(sequence: UInt64)
    case reconnected
    case disconnected(String)
}

enum EngineClientError: LocalizedError, Equatable {
    case notFound(String)
    case unsupported(String)
    case invalidAction(String)
    case jobFailed(String)
    /// A stable engine error code with a plain-language message.
    case coded(code: String, message: String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notFound(let message), .unsupported(let message), .invalidAction(let message), .jobFailed(let message): message
        case .coded(let code, let message): EngineErrorText.message(code: code, fallback: message)
        case .unavailable: "No Silo engine is connected."
        }
    }
}

enum ComputerName {
    static let maximumLength = 32

    static func isValid(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard (1...maximumLength).contains(bytes.count), (97...122).contains(bytes[0]) else { return false }
        return bytes.dropFirst().allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    static func unique(_ base: String, among existing: [String]) -> String {
        let slug = normalized(base)
        let used = Set(existing.map { $0.lowercased() })
        var suffixNumber = 1
        while true {
            let suffix = suffixNumber == 1 ? "" : "-\(suffixNumber)"
            let available = max(1, maximumLength - suffix.utf8.count)
            let prefix = String(slug.prefix(available)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let candidate = prefix + suffix
            if isValid(candidate), !used.contains(candidate.lowercased()) { return candidate }
            suffixNumber += 1
        }
    }

    static func uniqueFork(from sourceName: String, among existing: [String]) -> String {
        let slug = normalized(sourceName)
        let used = Set(existing.map { $0.lowercased() })
        var suffixNumber = 1
        while true {
            let suffix = suffixNumber == 1 ? "-fork" : "-fork-\(suffixNumber)"
            let available = max(1, maximumLength - suffix.utf8.count)
            let prefix = String(slug.prefix(available)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let candidate = prefix + suffix
            if isValid(candidate), !used.contains(candidate.lowercased()) { return candidate }
            suffixNumber += 1
        }
    }

    private static func normalized(_ base: String) -> String {
        var result = ""
        for byte in base.lowercased().utf8 {
            if (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 {
                result.append(contentsOf: String(decoding: [byte], as: UTF8.self))
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result.append("-")
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if result.isEmpty { return "computer" }
        if let first = result.utf8.first, !(97...122).contains(first) { return "computer-\(result)" }
        return result
    }
}

/// The Computer tool's boundary. Method names map to the canonical Silo API; `checkpointsList` is a client projection of
/// `computers.list`, because the spec embeds checkpoint records in each computer row and defines no `checkpoints.list` wire method.
@MainActor
protocol EngineClient {
    func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result
    func deviceFactsRead(deviceId: String?) async throws -> DeviceFacts
    func computersList(deviceId: String?) async throws -> ComputerInventory
    func connectionsDevicesList() async throws -> [SiloWireDevice]
    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult
    func computersStart(_ reference: ComputerReference) async throws -> ComputerJob
    func computersStop(_ reference: ComputerReference) async throws -> ComputerJob
    func computersForceStop(_ reference: ComputerReference) async throws
    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob
    func computersConfigurationRead(deviceId: String?) async throws -> ComputerConfigurationRequest
    func checkpointsList(computerId: String, deviceId: String?) async throws -> [ComputerCheckpoint]
    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob
    func checkpointsRestore(_ request: CheckpointRestoreRequest) async throws -> ComputerJob
    func checkpointsFork(_ request: CheckpointForkRequest) async throws -> ComputerJob
    func checkpointsDelete(_ request: CheckpointDeleteRequest) async throws -> ComputerJob
    func displayShow(_ reference: ComputerReference) async throws
    func operationsList(deviceId: String?) async throws -> OperationsList
    func operationsJobGet(jobId: String, deviceId: String?) async throws -> OperationJobSnapshot
    func operationsCancel(jobId: String, deviceId: String?) async throws
    /// `deviceIds` names the connected devices whose events this engine relays, with the source's `deviceId` on each.
    func eventsSubscribe(events: [String], deviceIds: [String],
                         handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String
    func eventsUnsubscribe(subscription: String) async
    func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws
    func engineDisconnect() async throws
}

extension EngineClient {
    func eventsSubscribe(events: [String], handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String {
        try await eventsSubscribe(events: events, deviceIds: [], handler: handler)
    }

    func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result {
        throw EngineClientError.unavailable
    }
}

/// Keeps Computers unavailable in ordinary Fjord launches until a real Silo adapter is connected.
@MainActor
class UnavailableEngineClient: EngineClient {
    private func unavailable<T>() throws -> T { throw EngineClientError.unavailable }

    func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result { throw EngineClientError.unavailable }
    func deviceFactsRead(deviceId: String?) async throws -> DeviceFacts { try unavailable() }
    func computersList(deviceId: String?) async throws -> ComputerInventory { try unavailable() }
    func connectionsDevicesList() async throws -> [SiloWireDevice] { try unavailable() }
    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult { try unavailable() }
    func computersStart(_ reference: ComputerReference) async throws -> ComputerJob { try unavailable() }
    func computersStop(_ reference: ComputerReference) async throws -> ComputerJob { try unavailable() }
    func computersForceStop(_ reference: ComputerReference) async throws { throw EngineClientError.unavailable }
    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob { try unavailable() }
    func computersConfigurationRead(deviceId: String?) async throws -> ComputerConfigurationRequest { try unavailable() }
    func checkpointsList(computerId: String, deviceId: String?) async throws -> [ComputerCheckpoint] { try unavailable() }
    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsRestore(_ request: CheckpointRestoreRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsFork(_ request: CheckpointForkRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsDelete(_ request: CheckpointDeleteRequest) async throws -> ComputerJob { try unavailable() }
    func displayShow(_ reference: ComputerReference) async throws { throw EngineClientError.unavailable }
    func operationsList(deviceId: String?) async throws -> OperationsList { try unavailable() }
    func operationsJobGet(jobId: String, deviceId: String?) async throws -> OperationJobSnapshot { try unavailable() }
    func operationsCancel(jobId: String, deviceId: String?) async throws { throw EngineClientError.unavailable }
    func eventsSubscribe(events: [String], deviceIds: [String],
                         handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String { try unavailable() }
    func eventsUnsubscribe(subscription: String) async {}
    func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws { throw EngineClientError.unavailable }
    func engineDisconnect() async throws {}
}

/// A deterministic in-process client for the first Computers slice and its window shots.
@MainActor
final class MockEngineClient: EngineClient {
    static let devID = "10000000-0000-4000-8000-000000000001"
    static let linuxID = "10000000-0000-4000-8000-000000000002"
    static let startingID = "10000000-0000-4000-8000-000000000003"
    static let failedID = "10000000-0000-4000-8000-000000000004"

    static let demoInventory = ComputerInventory(
        linux: ApplicationSource(computers: [
            ApplicationComputer(
                kind: .linux,
                configuration: ComputerConfiguration(id: linuxID, name: "linux-1", cpus: 4, maxCPUs: 12,
                                                     memoryGiB: 8, maxMemoryGiB: 32, workspaceStorageGiB: 64,
                                                     runtimeStorageGiB: 32, desktop: nil),
                purpose: "Local MicroSandbox", state: .running, stateDetail: "Running", canDismissError: false,
                attention: nil, freshness: "fresh", checkpoints: [], pendingCheckpointRestore: nil,
                checkpointOperation: nil, unfinishedRestore: nil),
            ApplicationComputer(
                kind: .linux,
                configuration: ComputerConfiguration(id: failedID, name: "linux-broken", cpus: 2, maxCPUs: 12,
                                                     memoryGiB: 4, maxMemoryGiB: 32, workspaceStorageGiB: 32,
                                                     runtimeStorageGiB: 16, desktop: nil),
                purpose: "Local MicroSandbox", state: .failed,
                stateDetail: "The MicroSandbox runtime reported a crash.", canDismissError: true,
                attention: ComputerAttention(level: "error", message: "The computer runtime crashed. Restart it to retry."),
                freshness: "fresh", checkpoints: [], pendingCheckpointRestore: nil,
                checkpointOperation: nil, unfinishedRestore: nil),
        ]),
        macos: MacosComputersState(
            supported: true, unsupportedReason: nil,
            computers: [
                MacosComputer(
                    kind: .macos, id: devID, name: "dev", cpus: 8, memoryGiB: 16, diskGiB: 128,
                    osVersion: "macOS 26.6.2 (25G83)", state: .running, progress: nil, detail: nil,
                    displayOpen: false, installed: true, setupComplete: true, needsPersonalizing: false,
                    checkpoints: [
                        ComputerCheckpoint(id: "checkpoint-auto-1", name: "Before run: Refactor checkpoint retention, deleted automatically",
                                           createdAt: "2026-10-13T14:30:00Z", scope: .full, reason: .manual,
                                           kind: .automatic, sizeBytes: 2_755_304_448),
                        ComputerCheckpoint(id: "checkpoint-manual-1", name: "Before the API migration",
                                           createdAt: "2026-10-11T09:00:00Z", scope: .full, reason: .manual,
                                           kind: .manual, sizeBytes: 2_754_990_080),
                    ], checkpointOperation: nil, pendingRestore: nil),
                MacosComputer(
                    kind: .macos, id: startingID, name: "macos-starting", cpus: 4, memoryGiB: 8, diskGiB: 64,
                    osVersion: "macOS 26.6.2 (25G83)", state: .starting, progress: 0.42,
                    detail: "Starting macOS", displayOpen: false, installed: true, setupComplete: true,
                    needsPersonalizing: false, checkpoints: [], checkpointOperation: nil, pendingRestore: nil),
            ],
            template: MacosTemplateSummary(macosVersion: "26.6.2", build: "25G83", current: true), minDiskGiB: 64))

    /// A second Mac for demos and window shots. Its computers reuse the ids of This Mac's (`devID`, `linuxID`), as two engines'
    /// ids do, so the owner is what tells them apart.
    static let remoteDeviceID = "device-studio"
    static let demoRemoteDevice = SiloWireDevice(address: "dev@studio.local", id: remoteDeviceID, name: "Studio Mac")
    static let demoRemoteInventory = ComputerInventory(
        linux: ApplicationSource(computers: [
            ApplicationComputer(
                kind: .linux,
                configuration: ComputerConfiguration(id: linuxID, name: "ci-linux", cpus: 8, maxCPUs: 16,
                                                     memoryGiB: 16, maxMemoryGiB: 64, workspaceStorageGiB: 128,
                                                     runtimeStorageGiB: 32, desktop: nil),
                purpose: "Local MicroSandbox", state: .running, stateDetail: "Running", canDismissError: false,
                attention: nil, freshness: "fresh", checkpoints: [], pendingCheckpointRestore: nil,
                checkpointOperation: nil, unfinishedRestore: nil),
        ]),
        macos: MacosComputersState(
            supported: true, unsupportedReason: nil,
            computers: [
                MacosComputer(
                    kind: .macos, id: devID, name: "studio-dev", cpus: 6, memoryGiB: 12, diskGiB: 96,
                    osVersion: "macOS 26.6.2 (25G83)", state: .stopped, progress: nil, detail: nil,
                    displayOpen: false, installed: true, setupComplete: true, needsPersonalizing: false,
                    checkpoints: [
                        ComputerCheckpoint(id: "checkpoint-studio-1", name: "Clean install",
                                           createdAt: "2026-10-12T10:00:00Z", scope: .full, reason: .manual,
                                           kind: .manual, sizeBytes: 2_100_000_000),
                    ], checkpointOperation: nil, pendingRestore: nil),
            ],
            template: MacosTemplateSummary(macosVersion: "26.6.2", build: "25G83", current: true), minDiskGiB: 64))

    /// Connects `demoRemoteDevice` as an engine of its own with `demoRemoteInventory`.
    @discardableResult
    func connectDemoRemoteDevice() -> MockEngineClient {
        let remote = MockEngineClient(inventory: Self.demoRemoteInventory)
        addPeer(Self.demoRemoteDevice, client: remote)
        return remote
    }

    private(set) var inventory: ComputerInventory
    /// The engine's Keychain items as the mock reports them; `repair` makes the denied ones accessible unless `credentialRepairDeclines`.
    var credentialsStatus = SiloWireCredentialsStatus(deniedCount: 0, items: [])
    var credentialRepairDeclines = false
    var credentialRepairFailure: EngineClientError?
    private(set) var credentialRepairCount = 0
    var connectedDevices: [SiloWireDevice] = []
    var ownerInventories: [String: ComputerInventory] = [:]
    /// Other devices as engines of their own: a call naming one of them by `deviceId` runs on its mock with its own
    /// inventory, jobs and settings (so ids, jobs and secrets are owner-local as on the real engines), and its events
    /// reach the subscribers that asked for that device.
    private(set) var peers: [String: MockEngineClient] = [:]
    private var relay: ((EngineEvent) -> Void)?
    /// The `deviceIds` of each subscribe call, in order.
    private(set) var subscribedDeviceIds: [[String]] = []
    var deviceFacts: DeviceFacts
    private(set) var createRequests: [ComputerCreateRequest] = []
    private(set) var forkRequests: [CheckpointForkRequest] = []
    private(set) var currentProgress: OperationJobProgress?
    private(set) var disconnected = false
    private(set) var disconnectCount = 0
    private(set) var stopRequests: [String] = []
    var stopRefusalIDs: Set<String> = []
    private(set) var deleteRequests: [ComputerDeleteRequest] = []
    var operationQueue = OperationsList.empty
    var dropNextFinishedEvent = false
    private var nextJob = 1
    private var finished: [String: OperationJobFinished] = [:]
    private var subscribers: [String: Subscriber] = [:]
    var suspendNextComputersList = false
    private var computersListContinuation: CheckedContinuation<Void, Never>?
    private var computersListWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var computersListCallCount = 0
    private(set) var operationsListCallCount = 0
    private(set) var jobGetCallCount = 0
    private(set) var cancelRequests: [String] = []
    var suspendNextCancelRequest = false
    private var cancelRequestContinuation: CheckedContinuation<Void, Never>?
    private var cancelRequestWaiters: [CheckedContinuation<Void, Never>] = []
    var suspendNextJobAcknowledge = false
    private var jobAcknowledgeContinuation: CheckedContinuation<Void, Never>?
    private var jobAcknowledgeWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var checkpointRestoreRequests: [CheckpointRestoreRequest] = []
    var suspendNextCheckpointRestore = false
    private var checkpointRestoreContinuation: CheckedContinuation<Void, Never>?
    private var checkpointRestoreWaiters: [CheckedContinuation<Void, Never>] = []
    var suspendNextSubscription = false
    private var subscriptionContinuation: CheckedContinuation<Void, Never>?
    private var subscriptionWaiters: [CheckedContinuation<Void, Never>] = []
    var suspendNextViewerOpen = false
    private var viewerOpenContinuation: CheckedContinuation<Void, Never>?
    private var viewerOpenWaiters: [CheckedContinuation<Void, Never>] = []
    var nextViewerOpenResults: [SiloWireViewerOpenResult] = []
    private(set) var viewerOpenRequests: [String] = []
    private(set) var viewerCloseRequests: [String] = []
    private(set) var subscribeCallCount = 0
    private(set) var unsubscribeCallCount = 0
    private(set) var acknowledgedJobs: [String] = []
    private(set) var checkpointListCallCount = 0
    var nextJobFailure: OperationJobError?
    private(set) var generatedCalls: [String] = []
    private(set) var lastConfigurationChange: SiloWireComputerConfigurationChange?
    private(set) var revokedDeviceIDs: [String] = []
    private(set) var logFollowRequests: [String?] = []
    var nextConnectionRemovalError: String?
    var settingsSnapshot = SiloWireSettingsSnapshot(
        onboardingDraft: .null, revision: 1,
        settings: SiloWireSettingsValues(automaticCheckpointRetentionCount: 3,
                                         startComputersAtLaunch: false, startupComputerIds: []),
        writeProtected: false)
    private var mockGitHubState = SiloWireGitHubState(
        accessEnabled: true, computerOperations: [], computers: [],
        personalToken: SiloWireGitHubPersonalToken(saved: false, state: .disconnected),
        policyRevision: 1, repositoryCatalog: ["fjord/lookout", "fjord/silo"],
        repositoryCatalogStatus: SiloWireGitHubRepositoryCatalogStatus(status: .available), state: .connected)
    private var mockSecrets: [SiloWireSecret] = [
        SiloWireSecret(allowedDomains: ["api.github.com"], computerIds: [devID], id: "secret-demo",
                       name: "GITHUB_TOKEN", pendingComputerIds: [], removing: false, state: .active)
    ]
    private var mockPorts: [String: [SiloWirePublishedPort]] = [:]
    private var mockFileEntries: [String: [String: [SiloWireFileEntry]]] = [:]
    private(set) var uploadRequests: [SiloWireFileUploadParams] = []
    var nextUploadOutcome: SiloWireUploadOutcome?
    private var mockComputerUse: [String: SiloWireComputerUseState] = [:]
    /// Agent tools per computer id; a computer not listed has them ready.
    var mockAgentTools: [String: SiloWireAgentToolsStatus] = [:]
    private(set) var agentToolsSetupRequests: [String] = []
    /// `GuestReference.key` of each agent-tools status read and setup, so tests can see which owner was addressed.
    private(set) var agentToolsStatusRequests: [String] = []
    private(set) var agentToolsSetupKeys: [String] = []
    private(set) var remoteStartRequests: [String] = []
    private var mockExportDestination: String?
    private var mockArchives: [SiloWireArchive] = []
    var mockExportState = SiloWireBackupState(archives: [], availability: .available, snapshotId: "mock-exports")
    private var mockSSHAccess: [String: SiloWireSSHAccessComputer] = [:]
    private var mockConnectionsEnabled = true

    var activeSubscriptionCount: Int { subscribers.count }

    private struct Subscriber {
        var events: [String]
        var deviceIds: [String] = []
        var sequence: UInt64
        var handler: @MainActor (EngineEventDelivery) -> Void
    }

    init() {
        inventory = Self.demoInventory
        deviceFacts = .demo
        currentProgress = Self.demoProgress
    }

    init(inventory: ComputerInventory, deviceFacts: DeviceFacts = .demo) {
        self.inventory = inventory
        self.deviceFacts = deviceFacts
        currentProgress = Self.demoProgress
    }

    /// Connects `client` as the engine of another device: it appears in `connections.devices.list` and answers every
    /// method that names it. Its demo job progress is dropped, so only this device's progress shows.
    func addPeer(_ device: SiloWireDevice, client: MockEngineClient) {
        client.currentProgress = nil
        client.relay = { [weak self] event in self?.publishRelayed(event, from: device.id) }
        peers[device.id] = client
        connectedDevices.removeAll { $0.id == device.id }
        connectedDevices.append(device)
    }

    func removePeer(_ deviceId: String) {
        peers[deviceId]?.relay = nil
        peers[deviceId] = nil
        connectedDevices.removeAll { $0.id == deviceId }
    }

    private func peer(_ deviceId: String?) -> MockEngineClient? { deviceId.flatMap { peers[$0] } }

    private func publishRelayed(_ event: EngineEvent, from deviceId: String) {
        let relayed = event.relayed(from: deviceId)
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id], subscriber.deviceIds.contains(deviceId),
                  Self.matches(relayed.name, requested: subscriber.events) else { continue }
            subscriber.sequence &+= 1
            subscribers[id] = subscriber
            subscriber.handler(.event(sequence: subscriber.sequence, event: relayed))
        }
    }

    /// The owner an engine call names: `nil` for this mock itself.
    private func routedPeer(_ params: some Encodable) -> MockEngineClient? {
        guard !peers.isEmpty, let data = try? JSONEncoder().encode(params),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["deviceId"] as? String else { return nil }
        return peers[id]
    }

    /// Methods whose reach is the controller's own machine, so another device's computer is refused (remote-all.md).
    private static let localOnlyForRemote: Set<String> = [
        "display.show", "display.close", "clipboard.transfer",
    ]

    func deviceFactsRead(deviceId: String? = nil) async throws -> DeviceFacts {
        if let owner = peer(deviceId) { return try await owner.deviceFactsRead() }
        return deviceFacts
    }

    func connectionsDevicesList() async throws -> [SiloWireDevice] { connectedDevices }

    private static var demoProgress: OperationJobProgress {
        OperationJobProgress(jobId: "job:starting-macos-demo", kind: "lifecycle", computerId: startingID,
                             source: .macos,
                             data: .macos(MacosJobProgressData(computerId: startingID, state: "starting", progress: 0.42,
                                                             detail: "Starting macOS")))
    }

    func computersList(deviceId: String? = nil) async throws -> ComputerInventory {
        computersListCallCount += 1
        if let owner = peer(deviceId) { return try await owner.computersList() }
        let snapshot = deviceId.flatMap { ownerInventories[$0] } ?? inventory
        if suspendNextComputersList {
            suspendNextComputersList = false
            await withCheckedContinuation { continuation in
                computersListContinuation = continuation
                computersListWaiters.forEach { $0.resume() }
                computersListWaiters.removeAll()
            }
        }
        return snapshot
    }

    func computersConfigurationRead(deviceId: String? = nil) async throws -> ComputerConfigurationRequest {
        if let owner = peer(deviceId) { return try await owner.computersConfigurationRead() }
        return ComputerConfigurationRequest(schemaVersion: 1, computers: inventory.linux.computers.map(\.configuration))
    }

    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult {
        if let owner = peer(request.deviceId) { return try await owner.computersCreate(request) }
        if request.kind == .macos, let values = request.request {
            try validateComputerName(values.name)
            guard let limits = deviceFacts.macosHostLimits else {
                throw EngineClientError.invalidAction("macOS host limits are unavailable.")
            }
            let maxCpus = max(limits.cpus, 2)
            let maxMemory = max(limits.memory_gib - 4, 4)
            let minDisk = max(32, Int(clamping: inventory.macos.minDiskGiB))
            guard (2...maxCpus).contains(values.cpus) else {
                throw EngineClientError.invalidAction("CPUs must be between 2 and \(maxCpus) on this Mac.")
            }
            guard (4...maxMemory).contains(values.memoryGiB) else {
                throw EngineClientError.invalidAction("Memory must be between 4 and \(maxMemory) GiB on this Mac.")
            }
            guard (minDisk...1024).contains(values.diskGiB) else {
                throw EngineClientError.invalidAction("Disk must be between \(minDisk) and 1024 GiB.")
            }
            createRequests.append(request)
            let jobId = nextJobId()
            let computer = MacosComputer(kind: .macos, id: UUID().uuidString.lowercased(), name: values.name,
                                         cpus: UInt64(values.cpus), memoryGiB: UInt64(values.memoryGiB), diskGiB: UInt64(values.diskGiB),
                                         osVersion: inventory.macos.template.map { "macOS \($0.macosVersion) (\($0.build))" },
                                         state: .preparing, progress: 0.05, detail: "Preparing", displayOpen: false,
                                         installed: false, setupComplete: false, needsPersonalizing: false,
                                         checkpoints: [], checkpointOperation: nil, pendingRestore: nil)
            inventory.macos.computers.append(computer)
            publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
            setProgress(jobId: jobId, computerId: computer.id, state: .preparing, progress: 0.05, detail: "Preparing")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.inventory.macos.computers.contains(where: { $0.id == computer.id }) else { return }
                self.updateMacos(computer.id) { row in
                    row.state = .stopped
                    row.progress = nil
                    row.detail = nil
                    row.installed = true
                    row.setupComplete = true
                }
                self.finish(jobId)
            }
            return ComputerCreateResult(jobId: jobId, computer: computer)
        }
        guard request.kind == .linux, var configuration = request.configuration else {
            throw EngineClientError.invalidAction("The create request does not match its computer kind.")
        }
        try validateComputerName(configuration.name)
        guard let capacity = deviceFacts.deviceCapacity else {
            throw EngineClientError.invalidAction("Host capacity is unavailable.")
        }
        let memoryCapacityGiB = min(capacity.maxMemoryGib, Int(capacity.physicalMemoryBytes / 1_073_741_824))
        guard capacity.logicalCpus > 0, configuration.maxCPUs > 0,
              configuration.maxCPUs <= capacity.logicalCpus,
              (1...configuration.maxCPUs).contains(configuration.cpus) else {
            throw EngineClientError.invalidAction("Linux CPU settings exceed this device's capacity.")
        }
        guard memoryCapacityGiB > 0, configuration.maxMemoryGiB > 0,
              configuration.maxMemoryGiB <= memoryCapacityGiB,
              (1...configuration.maxMemoryGiB).contains(configuration.memoryGiB) else {
            throw EngineClientError.invalidAction("Linux memory settings exceed this device's capacity.")
        }
        createRequests.append(request)
        let jobId = "setup:\(request.requestId ?? UUID().uuidString)"
        if configuration.id.isEmpty { configuration.id = UUID().uuidString.lowercased() }
        let row = ApplicationComputer(kind: .linux, configuration: configuration, purpose: "Local MicroSandbox",
                                      state: .stopped, stateDetail: "Stopped", canDismissError: false,
                                      freshness: "fresh", checkpoints: [])
        inventory.linux.computers.append(row)
        publish(.computersChanged(ComputersChangedPayload(linux: inventory.linux)))
        setProgress(jobId: jobId, computerId: row.id, state: "setting-up", progress: 0.4, detail: "Preparing computer", source: .setup)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.finish(jobId)
        }
        return ComputerCreateResult(jobId: jobId, computer: nil)
    }

    func computersStart(_ reference: ComputerReference) async throws -> ComputerJob {
        if let owner = peer(reference.deviceId) {
            return try await owner.computersStart(ComputerReference(computerId: reference.computerId))
        }
        if let deviceId = reference.deviceId {
            guard var owned = ownerInventories[deviceId], let index = owned.linux.computers.firstIndex(where: { $0.id == reference.computerId }) else {
                throw EngineClientError.notFound("This computer no longer exists.")
            }
            remoteStartRequests.append("\(deviceId)/\(reference.computerId)")
            let jobId = nextJobId()
            owned.linux.computers[index].state = .running
            owned.linux.computers[index].stateDetail = "Running"
            ownerInventories[deviceId] = owned
            finish(jobId)
            return ComputerJob(jobId: jobId)
        }
        let row = try requireComputer(reference.computerId)
        let jobId = nextJobId()
        switch row {
        case .linux:
            updateLinux(reference.computerId) { $0.state = .starting; $0.stateDetail = "Starting" }
            setProgress(jobId: jobId, computerId: reference.computerId, state: "starting", progress: 0.18,
                        detail: "Starting computer", source: .lifecycle, action: "start", step: "boot")
        case .macos:
            updateMacos(reference.computerId) { $0.state = .starting; $0.progress = 0.2; $0.detail = "Starting macOS" }
            setProgress(jobId: jobId, computerId: reference.computerId, state: .starting, progress: 0.2,
                        detail: "Starting macOS")
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            if case .linux = (try? self.requireComputer(reference.computerId)) {
                self.updateLinux(reference.computerId) { $0.state = .running; $0.stateDetail = "Running" }
            } else if case .macos = (try? self.requireComputer(reference.computerId)) {
                self.updateMacos(reference.computerId) { $0.state = .running; $0.progress = nil; $0.detail = nil }
            }
            self.finish(jobId)
        }
        return ComputerJob(jobId: jobId)
    }

    func computersStop(_ reference: ComputerReference) async throws -> ComputerJob {
        if let owner = peer(reference.deviceId) {
            return try await owner.computersStop(ComputerReference(computerId: reference.computerId))
        }
        let row = try requireComputer(reference.computerId)
        guard row.displayState == .running else { throw EngineClientError.invalidAction("This computer isn't running.") }
        let jobId = nextJobId()
        stopRequests.append(reference.computerId)
        switch row {
        case .linux:
            updateLinux(reference.computerId) { $0.state = .starting; $0.stateDetail = "Stopping" }
        case .macos:
            updateMacos(reference.computerId) { $0.state = .stopping; $0.detail = "Stopping macOS" }
            setProgress(jobId: jobId, computerId: reference.computerId, state: .stopping, progress: 0.7,
                        detail: "Stopping macOS")
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.finish(jobId)
            try? await Task.sleep(for: .milliseconds(450))
            if case .linux = (try? self.requireComputer(reference.computerId)) {
                self.updateLinux(reference.computerId) { $0.state = .stopped; $0.stateDetail = "Stopped" }
            } else if case .macos = (try? self.requireComputer(reference.computerId)) {
                if self.stopRefusalIDs.contains(reference.computerId) {
                    self.updateMacos(reference.computerId) { $0.state = .running; $0.detail = nil }
                } else {
                    self.updateMacos(reference.computerId) { $0.state = .stopped; $0.detail = nil }
                }
            }
        }
        return ComputerJob(jobId: jobId)
    }

    func computersForceStop(_ reference: ComputerReference) async throws {
        if let owner = peer(reference.deviceId) {
            return try await owner.computersForceStop(ComputerReference(computerId: reference.computerId))
        }
        guard case .macos = try requireComputer(reference.computerId) else {
            throw EngineClientError.unsupported("Force stop is only available for macOS computers.")
        }
        updateMacos(reference.computerId) { $0.state = .stopped; $0.progress = nil; $0.detail = nil }
    }

    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob {
        if let owner = peer(request.deviceId) { return try await owner.computersDelete(request) }
        let row = try requireComputer(request.computerId)
        deleteRequests.append(request)
        if case .linux(let computer) = row {
            guard let expected = request.expected else {
                throw EngineClientError.invalidAction("Linux computer deletion requires its expected configuration.")
            }
            guard expected == computer.configuration else {
                throw EngineClientError.invalidAction("This computer changed while the delete was waiting.")
            }
        }
        guard row.canDelete else { throw EngineClientError.invalidAction("Stop the computer first.") }
        let jobId = nextJobId()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.removeComputer(request.computerId)
            self.finish(jobId)
        }
        return ComputerJob(jobId: jobId)
    }

    func checkpointsList(computerId: String, deviceId: String? = nil) async throws -> [ComputerCheckpoint] {
        if let owner = peer(deviceId) { return try await owner.checkpointsList(computerId: computerId) }
        checkpointListCallCount += 1
        guard let row = inventory.computer(computerId) else { throw EngineClientError.notFound("This computer no longer exists.") }
        return row.checkpoints
    }

    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob {
        if let owner = peer(request.deviceId) { return try await owner.checkpointsCreate(request) }
        let row = try requireComputer(request.computerId)
        let jobId = nextJobId()
        let checkpoint = ComputerCheckpoint(id: UUID().uuidString.lowercased(), name: request.name,
                                            createdAt: ISO8601DateFormatter().string(from: Date()),
                                            scope: row.displayState == .running ? .full : .disk, reason: .manual,
                                            kind: request.kind ?? .manual, sizeBytes: nil)
        appendCheckpoint(checkpoint, to: request.computerId)
        if case .macos = row {
            setProgress(jobId: jobId, computerId: request.computerId, state: "running", progress: 0.65,
                        detail: "Saving checkpoint", source: .macos)
        }
        scheduleCheckpointFinish(jobId, computerId: request.computerId, after: .milliseconds(350))
        return ComputerJob(jobId: jobId)
    }

    func checkpointsRestore(_ request: CheckpointRestoreRequest) async throws -> ComputerJob {
        if let owner = peer(request.deviceId) { return try await owner.checkpointsRestore(request) }
        checkpointRestoreRequests.append(request)
        if suspendNextCheckpointRestore {
            suspendNextCheckpointRestore = false
            await withCheckedContinuation { continuation in
                checkpointRestoreContinuation = continuation
                checkpointRestoreWaiters.forEach { $0.resume() }
                checkpointRestoreWaiters.removeAll()
            }
        }
        let row = try requireComputer(request.computerId)
        guard row.checkpoints.contains(where: { $0.id == request.checkpointId }) else {
            throw EngineClientError.notFound("This checkpoint no longer exists.")
        }
        let jobId = nextJobId()
        switch row {
        case .linux:
            updateLinux(request.computerId) {
                $0.pendingCheckpointRestore = PendingCheckpointRestore(checkpointId: request.checkpointId,
                                                                       sourceComputer: request.computerId, state: .disk)
            }
        case .macos:
            updateMacos(request.computerId) {
                $0.state = .stopped
                $0.pendingRestore = MacosPendingRestore(checkpointId: request.checkpointId, memory: false)
            }
        }
        scheduleCheckpointFinish(jobId, computerId: request.computerId, after: .milliseconds(400))
        return ComputerJob(jobId: jobId)
    }

    func checkpointsFork(_ request: CheckpointForkRequest) async throws -> ComputerJob {
        if let owner = peer(request.deviceId) { return try await owner.checkpointsFork(request) }
        let source = try requireComputer(request.computerId)
        try validateComputerName(request.newName)
        forkRequests.append(request)
        if let checkpointId = request.checkpointId, !source.checkpoints.contains(where: { $0.id == checkpointId }) {
            throw EngineClientError.notFound("This checkpoint no longer exists.")
        }
        let jobId = nextJobId()
        switch source {
        case .macos(let computer):
            let fork = MacosComputer(kind: .macos, id: UUID().uuidString.lowercased(), name: request.newName,
                                     cpus: computer.cpus, memoryGiB: computer.memoryGiB, diskGiB: computer.diskGiB,
                                     osVersion: computer.osVersion, state: .copying, progress: 0.35, detail: "Copying checkpoint",
                                     displayOpen: false, installed: true, setupComplete: false, needsPersonalizing: true,
                                     checkpoints: [], checkpointOperation: nil,
                                     pendingRestore: request.checkpointId.map { MacosPendingRestore(checkpointId: $0, memory: false) })
            inventory.macos.computers.append(fork)
            publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
            setProgress(jobId: jobId, computerId: request.computerId, state: "running", progress: 0.55,
                        detail: "Copying checkpoint")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.updateMacos(fork.id) { $0.state = .stopped; $0.progress = nil; $0.detail = nil; $0.setupComplete = true; $0.needsPersonalizing = false }
                self.publishCheckpointChange(for: request.computerId)
                self.finish(jobId)
            }
        case .linux(let computer):
            var configuration = computer.configuration
            configuration.id = UUID().uuidString.lowercased()
            configuration.name = request.newName
            let fork = ApplicationComputer(kind: .linux, configuration: configuration, purpose: computer.purpose,
                                           state: .stopped, stateDetail: "Stopped", canDismissError: false,
                                           freshness: "fresh", checkpoints: [])
            inventory.linux.computers.append(fork)
            publish(.computersChanged(ComputersChangedPayload(linux: inventory.linux)))
            scheduleCheckpointFinish(jobId, computerId: request.computerId, after: .milliseconds(400))
        }
        return ComputerJob(jobId: jobId)
    }

    func checkpointsDelete(_ request: CheckpointDeleteRequest) async throws -> ComputerJob {
        if let owner = peer(request.deviceId) { return try await owner.checkpointsDelete(request) }
        let row = try requireComputer(request.computerId)
        guard row.checkpoints.contains(where: { $0.id == request.checkpointId }) else {
            throw EngineClientError.notFound("This checkpoint no longer exists.")
        }
        let jobId = nextJobId()
        removeCheckpoint(request.checkpointId, from: request.computerId)
        scheduleCheckpointFinish(jobId, computerId: request.computerId, after: .milliseconds(250))
        return ComputerJob(jobId: jobId)
    }

    func displayShow(_ reference: ComputerReference) async throws {
        if peer(reference.deviceId) != nil {
            throw EngineClientError.coded(code: "unsupported_remote_operation",
                                          message: "This computer's window opens on the Mac that owns it.")
        }
        guard case .macos = try requireComputer(reference.computerId) else {
            throw EngineClientError.unsupported("A display is only available for a macOS computer.")
        }
        guard case .macos(let row)? = inventory.computer(reference.computerId), row.state == .running else {
            throw EngineClientError.coded(code: "not_running", message: "Start the computer to open its display.")
        }
        updateMacos(reference.computerId) { $0.displayOpen = true }
    }

    func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result {
        generatedCalls.append(call.name)
        if let owner = routedPeer(call.params) {
            if Self.localOnlyForRemote.contains(call.name) {
                throw EngineClientError.coded(code: "unsupported_remote_operation",
                                              message: "\(call.name) is not available for a computer on another Mac yet.")
            }
            return try await owner.invoke(call)
        }
        if call.name == "logs.export", let first = try mockDecode(call.params, as: SiloWireLogsExportParams.self).requests.first,
           let owner = peer(first.deviceId) {
            return try await owner.invoke(call)
        }
        switch call.name {
        case "settings.read":
            return try mockResult(settingsSnapshot, as: Result.self)
        case "settings.update":
            let request = try mockDecode(call.params, as: SiloWireSettingsUpdateParams.self)
            var settings = settingsSnapshot.settings
            if let value = request.patch.automaticCheckpointRetentionCount { settings.automaticCheckpointRetentionCount = value }
            if let value = request.patch.startComputersAtLaunch { settings.startComputersAtLaunch = value }
            if let value = request.patch.startupComputerIds { settings.startupComputerIds = value }
            settingsSnapshot = SiloWireSettingsSnapshot(onboardingDraft: .null, revision: settingsSnapshot.revision + 1,
                                                        settings: settings, writeProtected: false)
            publish(.settingsChanged(settingsSnapshot))
            return try mockResult(settingsSnapshot, as: Result.self)
        case "settings.flush":
            settingsSnapshot.revision &+= 1
            publish(.settingsChanged(settingsSnapshot))
            return try mockResult(SiloNull(), as: Result.self)
        case "activity.setup.read":
            let item = SiloWireComputerConfigurationProgress(computer: "dev", elapsedSeconds: 2, level: "info",
                message: "Computer setup completed", phase: "setup-completed", requestId: "setup-demo",
                safeForDisplay: true, schemaVersion: 1, step: "setup-completed", timestamp: 1,
                type: "computer-configuration")
            return try mockResult([item], as: Result.self)
        case "checkpoints.usage":
            let params = try mockDecode(call.params, as: SiloWireCheckpointUsageParams.self)
            let checkpoints = inventory.computer(params.computerId)?.checkpoints ?? []
            let entries = checkpoints.map {
                SiloWireCheckpointUsageEntry(deleteBlocker: nil, id: $0.id, sizeBytes: $0.sizeBytes, usedBy: nil)
            }
            let total: UInt64? = entries.allSatisfy { $0.sizeBytes != nil }
                ? entries.compactMap(\.sizeBytes).reduce(UInt64(0), +) : nil
            return try mockResult(SiloWireCheckpointUsage(checkpoints: entries, totalBytes: total), as: Result.self)
        case "checkpoints.abandonRestore":
            let params = try mockDecode(call.params, as: SiloWireComputerTargetParams.self)
            if case .linux? = inventory.computer(params.computerId) {
                updateLinux(params.computerId) { $0.pendingCheckpointRestore = nil; $0.unfinishedRestore = nil }
            } else if case .macos? = inventory.computer(params.computerId) {
                updateMacos(params.computerId) { $0.pendingRestore = nil }
            }
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "computers.configuration.change":
            let params = try mockDecode(call.params, as: SiloWireComputerConfigurationChangeParams.self)
            let change = params.change
            lastConfigurationChange = change
            if change.kind == .macosResources {
                guard let id = change.computerId, let cpus = change.cpus, let memory = change.memoryGiB,
                      let expected = change.expected,
                      let computer = inventory.macos.computers.first(where: { $0.id == id }) else {
                    throw EngineClientError.notFound("That Mac computer no longer exists.")
                }
                guard computer.state == .stopped else {
                    throw EngineClientError.coded(code: "changed", message: "Stop the computer before changing its resources.")
                }
                guard expected.cpus == computer.cpus, expected.memoryGiB == computer.memoryGiB,
                      expected.diskGiB == computer.diskGiB else {
                    throw EngineClientError.invalidAction("This computer's resources changed while the edit was waiting.")
                }
                updateMacos(id) { $0.cpus = cpus; $0.memoryGiB = memory }
            } else if let configuration = change.configuration,
                      let index = inventory.linux.computers.firstIndex(where: { $0.id == configuration.id }) {
                if let expected = change.expected,
                   SiloWireConfiguration(inventory.linux.computers[index].configuration) != expected {
                    throw EngineClientError.invalidAction("This computer changed while the edit was waiting.")
                }
                updateLinux(configuration.id) { $0.configuration = configuration }
            }
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "files.list":
            let params = try mockDecode(call.params, as: SiloWireFileListParams.self)
            let baseEntries: [SiloWireFileEntry]
            if params.path == "/" || params.path == "" {
                baseEntries = [SiloWireFileEntry(kind: .folder, name: "Roots", path: "/Roots"),
                               SiloWireFileEntry(kind: .folder, name: "Downloads", path: "/Downloads")]
            } else {
                baseEntries = [SiloWireFileEntry(kind: .folder, name: "Projects", path: params.path + "/Projects"),
                               SiloWireFileEntry(kind: .file, name: "README.md", path: params.path + "/README.md")]
            }
            let entries = baseEntries + (mockFileEntries[params.computerId]?[params.path] ?? [])
            let start = min(Int(clamping: params.offset), entries.count)
            let page = Array(entries.dropFirst(start))
            return try mockResult(SiloWireFileListResult(entries: page, snapshotId: "mock-files"), as: Result.self)
        case "files.upload":
            let params = try mockDecode(call.params, as: SiloWireFileUploadParams.self)
            uploadRequests.append(params)
            let paths = (params.paths ?? []).map { localPath in
                let name = URL(fileURLWithPath: localPath).lastPathComponent
                let parent = params.directory == "/" ? "" : params.directory
                return SiloWireFileEntry(kind: .file, name: name, path: parent + "/" + name)
            }
            let outcome = nextUploadOutcome ?? SiloWireUploadOutcome(names: paths.map(\.name), status: .done)
            nextUploadOutcome = nil
            if outcome.status == .done {
                var existing = mockFileEntries[params.computerId]?[params.directory] ?? []
                for path in paths {
                    existing.removeAll { $0.path == path.path }
                    existing.append(path)
                }
                mockFileEntries[params.computerId, default: [:]][params.directory] = existing
            }
            return try mockResult(mockFeatureJob(result: try mockValue(outcome),
                                                 jobId: "transfer:\(params.transferId)"), as: Result.self)
        case "files.download":
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "network.state":
            let rows = inventory.allComputers.map { row in
                SiloWireNetworkComputer(computer: row.name, computerId: row.id, host: "127.0.0.1",
                                        ports: mockNetworkPorts(computerId: row.id))
            }
            return try mockResult(SiloWireNetworkState(computers: rows), as: Result.self)
        case "network.publish":
            let params = try mockDecode(call.params, as: SiloWireNetworkPublishParams.self)
            guard let row = inventory.computer(params.computerId) else {
                throw EngineClientError.notFound("This computer no longer exists.")
            }
            guard row.kind != .linux || params.port != 6901 else {
                throw EngineClientError.invalidAction("The Linux desktop port stays private behind Open screen.")
            }
            var ports = mockPorts[params.computerId] ?? []
            ports.removeAll { $0.port == params.port }
            ports.append(SiloWirePublishedPort(configured: true, configuredHostPort: params.hostPort,
                                               hostPort: params.hostPort ?? params.port, port: params.port,
                                               scheme: params.scheme, state: .reachable))
            mockPorts[params.computerId] = ports
            return try mockResult(SiloWireNetworkState(computers: [SiloWireNetworkComputer(
                computer: row.name, computerId: params.computerId, host: "127.0.0.1",
                ports: mockNetworkPorts(computerId: params.computerId))]),
                as: Result.self)
        case "network.unpublish":
            let params = try mockDecode(call.params, as: SiloWireNetworkUnpublishParams.self)
            mockPorts[params.computerId, default: []].removeAll { $0.port == params.port }
            let row = inventory.computer(params.computerId)
            return try mockResult(SiloWireNetworkState(computers: [SiloWireNetworkComputer(
                computer: row?.name ?? params.computerId, computerId: params.computerId,
                host: "127.0.0.1", ports: mockNetworkPorts(computerId: params.computerId))]), as: Result.self)
        case "network.open":
            let params = try mockDecode(call.params, as: SiloWireNetworkOpenParams.self)
            guard let port = mockPorts[params.computerId]?.first(where: { $0.port == params.port }),
                  port.state == .reachable else {
                throw EngineClientError.invalidAction("This service is not reachable.")
            }
            guard let scheme = port.scheme else {
                throw EngineClientError.invalidAction("This TCP service is not configured as a website.")
            }
            return try mockResult(SiloWireNetworkOpenResult(url: "\(scheme.rawValue)://127.0.0.1:\(port.hostPort ?? port.port)"),
                                  as: Result.self)
        case "github.state", "github.repositories.refresh", "github.configuration.save", "github.access.set",
             "github.configuration.retry":
            if call.name == "github.configuration.save" {
                let params = try mockDecode(call.params, as: SiloWireGitHubConfigurationSaveParams.self)
                mockGitHubState.computers = params.configuration.computers
                mockGitHubState.policyRevision &+= 1
            } else if call.name == "github.access.set" {
                let params = try mockDecode(call.params, as: SiloWireGitHubAccessSetParams.self)
                mockGitHubState.accessEnabled = params.enabled
            } else if call.name == "github.configuration.retry" {
                let params = try mockDecode(call.params, as: SiloWireGitHubConfigurationRetryParams.self)
                mockGitHubState.computerOperations.removeAll { $0.computerId == params.computerId }
            }
            return try mockResult(mockGitHubState, as: Result.self)
        case "github.connect":
            let jobId = nextJobId()
            mockGitHubState.state = .connecting
            mockGitHubState.pendingAuthorizationUrl = "https://github.com/login/device"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self else { return }
                self.mockGitHubState.state = .connected
                self.mockGitHubState.account = "dev@example.test"
                self.mockGitHubState.pendingAuthorizationUrl = nil
                self.finish(jobId)
            }
            return try mockResult(SiloWireJobStartResult(jobId: jobId), as: Result.self)
        case "github.connect.reopen":
            return try mockResult(SiloWireGitHubRepositoriesManageResult(url: "https://github.com/login"), as: Result.self)
        case "github.repositories.manage":
            return try mockResult(SiloWireGitHubRepositoriesManageResult(url: "https://github.com/settings/installations"), as: Result.self)
        case "github.disconnect":
            mockGitHubState.state = .disconnected
            mockGitHubState.account = nil
            return try mockResult(mockGitHubState, as: Result.self)
        case "github.personalToken.save":
            let params = try mockDecode(call.params, as: SiloWireGitHubPersonalTokenSaveParams.self)
            mockGitHubState.personalToken = SiloWireGitHubPersonalToken(account: params.token.isEmpty ? nil : "dev@example.test",
                saved: !params.token.isEmpty, state: params.token.isEmpty ? .disconnected : .connected)
            if !params.token.isEmpty {
                mockGitHubState.state = .connected
                mockGitHubState.account = "dev@example.test"
            }
            return try mockResult(mockGitHubState, as: Result.self)
        case "github.personalToken.remove":
            mockGitHubState.personalToken = SiloWireGitHubPersonalToken(saved: false, state: .disconnected)
            mockGitHubState.state = .disconnected
            mockGitHubState.account = nil
            return try mockResult(mockGitHubState, as: Result.self)
        case "secrets.list":
            return try mockResult(mockSecrets, as: Result.self)
        case "secrets.save":
            let params = try mockDecode(call.params, as: SiloWireSecretsSaveParams.self)
            let request = params.request
            let id = request.id ?? UUID().uuidString.lowercased()
            let previous = mockSecrets.first { $0.id == id }
            mockSecrets.removeAll { $0.id == id }
            mockSecrets.append(SiloWireSecret(allowedDomains: request.allowedDomains, computerIds: request.computerIds,
                id: id, name: request.name, pendingComputerIds: [], removing: false,
                state: previous?.state ?? .active))
            return try mockResult(mockSecrets, as: Result.self)
        case "secrets.remove":
            let params = try mockDecode(call.params, as: SiloWireSecretIdParams.self)
            mockSecrets.removeAll { $0.id == params.id }
            return try mockResult(mockSecrets, as: Result.self)
        case "secrets.retry":
            return try mockResult(mockSecrets, as: Result.self)
        case "desktop.status":
            let params = try mockDecode(call.params, as: SiloWireComputerTargetParams.self)
            agentToolsStatusRequests.append(GuestReference(deviceId: params.deviceId, computerId: params.computerId).key)
            let agentTools = mockAgentTools[GuestReference(deviceId: params.deviceId, computerId: params.computerId).key]
                ?? mockAgentTools[params.computerId] ?? Self.readyAgentTools
            let status = SiloWireDesktopStatus(agentTools: agentTools, autoStart: false, installed: true,
                state: "running", updateAvailable: false, updateRequired: false)
            return try mockResult(status, as: Result.self)
        case "desktop.action":
            let params = try mockDecode(call.params, as: SiloWireDesktopActionParams.self)
            guard params.action == .setupAgentTools else { return try mockResult(mockFeatureJob(), as: Result.self) }
            agentToolsSetupRequests.append(params.computerId)
            agentToolsSetupKeys.append(GuestReference(deviceId: params.deviceId, computerId: params.computerId).key)
            let jobId = nextJobId()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(40))
                guard let self else { return }
                if self.nextJobFailure == nil {
                    let key = GuestReference(deviceId: params.deviceId, computerId: params.computerId).key
                    if self.mockAgentTools[key] != nil { self.mockAgentTools[key] = Self.readyAgentTools }
                    else { self.mockAgentTools[params.computerId] = Self.readyAgentTools }
                }
                self.finish(jobId)
            }
            return try mockResult(SiloWireJobStartResult(jobId: jobId), as: Result.self)
        case "computerUse.state":
            let params = try mockDecode(call.params, as: SiloWireComputerUseStateParams.self)
            let state = mockComputerUse[params.computerId]
                ?? SiloWireComputerUseState(appliedApproval: .ask, approval: .ask, state: .ready)
            return try mockResult(state, as: Result.self)
        case "computerUse.approval":
            let params = try mockDecode(call.params, as: SiloWireComputerUseApprovalParams.self)
            let state = SiloWireComputerUseState(appliedApproval: params.mode == .auto ? .auto : .ask,
                                                approval: params.mode == .auto ? .auto : .ask,
                                                approvalApply: .applied, state: .ready)
            mockComputerUse[params.computerId] = state
            return try mockResult(state, as: Result.self)
        case "computerUse.setup":
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "logs.query":
            let params = try mockDecode(call.params, as: SiloWireLogsQueryParams.self)
            let row = inventory.computer(params.computerId)
            logFollowRequests.append(params.follow)
            let index = logFollowRequests.count
            let entry = SiloWireLogEntry(computerId: params.computerId, computerName: row?.name ?? params.computerId,
                deviceId: Self.devID, deviceName: "Fjord Mac", id: "log-\(index)",
                line: index == 1 ? "Computer ready" : "New output",
                occurredAt: ISO8601DateFormatter().string(from: Date()), source: "guest")
            return try mockResult(SiloWireLogPage(entries: [entry], newestAvailableTimestamp: entry.occurredAt,
                snapshot: "mock-log-snapshot-\(index)", timestampEstimated: false,
                totalMatches: UInt64(index)), as: Result.self)
        case "logs.export":
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "storage.read":
            return try mockResult(SiloWireStorageState(checkpointCount: 2, history: [],
                runtimeHostBytes: 8_589_934_592, workspaceCapacityBytes: 68_719_476_736,
                workspaceHostBytes: 3_221_225_472, workspaceUsedBytes: 10_737_418_240), as: Result.self)
        case "storage.reclaim":
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "exports.state":
            mockExportState.archives = mockArchives
            mockExportState.destination = mockExportDestination
            return try mockResult(mockExportState, as: Result.self)
        case "exports.destination.set":
            let params = try mockDecode(call.params, as: SiloWireExportDestinationSetParams.self)
            mockExportDestination = params.path
            mockExportState.destination = params.path
            return try mockResult(SiloWireExportDestinationResult(destination: params.path), as: Result.self)
        case "exports.inspect":
            let params = try mockDecode(call.params, as: SiloWireExportInspectParams.self)
            let archive = SiloWireArchive(archivePath: params.archivePath, completedLabel: "Export archive",
                computers: ["linux-1"], destination: URL(fileURLWithPath: params.archivePath).deletingLastPathComponent().path,
                name: URL(fileURLWithPath: params.archivePath).lastPathComponent, size: "1.2 GB")
            let inspection = SiloWireArchiveInspectionResult(archive: archive, valid: true)
            return try mockResult(mockFeatureJob(result: try mockValue(inspection)), as: Result.self)
        case "exports.create":
            let params = try mockDecode(call.params, as: SiloWireExportCreateParams.self)
            let names = params.computerIds.compactMap { inventory.computer($0)?.name }
            let archiveName = "fjord-export-\(UUID().uuidString.prefix(8)).silo-backup"
            mockArchives.insert(SiloWireArchive(archivePath: URL(fileURLWithPath: params.destination)
                .appendingPathComponent(archiveName).path,
                completedLabel: "Exported \(names.joined(separator: ", "))",
                computers: names, destination: params.destination, name: archiveName, size: "1.2 GB"), at: 0)
            if let archive = mockArchives.first {
                storeMockExportResult(archive: archive, operation: .backup, names: names,
                                      title: "Export complete", message: "The archive is ready.")
            }
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "exports.import":
            let params = try mockDecode(call.params, as: SiloWireExportImportParams.self)
            if let source = inventory.allComputers.first(where: { $0.name == params.sourceName })
                ?? inventory.allComputers.first {
                switch source {
                case .linux(var computer):
                    computer.configuration.id = UUID().uuidString.lowercased()
                    computer.configuration.name = params.newName
                    computer.state = .stopped
                    computer.stateDetail = "Stopped"
                    computer.checkpoints = []
                    computer.pendingCheckpointRestore = nil
                    computer.unfinishedRestore = nil
                    inventory.linux.computers.append(computer)
                    publish(.computersChanged(ComputersChangedPayload(linux: inventory.linux)))
                case .macos(var computer):
                    computer.id = UUID().uuidString.lowercased()
                    computer.name = params.newName
                    computer.state = .stopped
                    computer.progress = nil
                    computer.detail = nil
                    computer.displayOpen = false
                    computer.checkpoints = []
                    computer.checkpointOperation = nil
                    computer.pendingRestore = nil
                    inventory.macos.computers.append(computer)
                    publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
                }
            }
            let archive = mockArchives.first { $0.archivePath == params.archivePath }
                ?? SiloWireArchive(archivePath: params.archivePath, completedLabel: "Imported archive",
                                   computers: [params.sourceName ?? "linux-1"], destination: URL(fileURLWithPath: params.archivePath).deletingLastPathComponent().path,
                                   name: URL(fileURLWithPath: params.archivePath).lastPathComponent, size: "1.2 GB")
            storeMockExportResult(archive: archive, operation: .restore, names: [params.newName],
                                  title: "Import complete", message: "\(params.newName) is ready.")
            return try mockResult(mockFeatureJob(), as: Result.self)
        case "exports.acknowledge":
            let params = try mockDecode(call.params, as: SiloWireExportAcknowledgeParams.self)
            let acknowledged = mockExportState.operationId == params.expectedOperationId
                && mockExportState.resultUnseen == true
            if acknowledged {
                mockExportState.resultUnseen = false
                mockExportState.snapshotId = UUID().uuidString
                publish(.exportsChanged(mockExportState))
            }
            return try mockResult(acknowledged, as: Result.self)
        case "exports.dismiss":
            let params = try mockDecode(call.params, as: SiloWireExportDismissParams.self)
            let matchesId = params.expectedOperationId == nil || params.expectedOperationId == mockExportState.operationId
            let dismissed = matchesId && mockExportState.operation == params.expectedOperation.operationClass
                && params.expectedOperation.kind == .result
            if dismissed {
                mockExportState.operation = nil
                mockExportState.operationId = nil
                mockExportState.resultUnseen = nil
                mockExportState.snapshotId = UUID().uuidString
                publish(.exportsChanged(mockExportState))
            }
            return try mockResult(dismissed, as: Result.self)
        case "connections.status":
            return try mockResult(mockConnectionsStatus(), as: Result.self)
        case "connections.devices.list":
            return try mockResult(connectedDevices, as: Result.self)
        case "connections.devices.health":
            let rows = connectedDevices.map { SiloWireDeviceHealth(busy: false, connected: true,
                deviceId: $0.id, lastSeen: ISO8601DateFormatter().string(from: Date())) }
            return try mockResult(SiloWireDeviceHealthResult(devices: rows), as: Result.self)
        case "connections.devices.connect":
            let params = try mockDecode(call.params, as: SiloWireConnectDeviceParams.self)
            if let existing = connectedDevices.first(where: {
                $0.address.caseInsensitiveCompare(params.address) == .orderedSame
            }) {
                guard params.replace == true else {
                    throw EngineClientError.invalidAction("A Mac is already saved at \(existing.address).")
                }
                connectedDevices.removeAll { $0.id == existing.id }
                ownerInventories[existing.id] = nil
            }
            let device = SiloWireDevice(address: params.address, id: UUID().uuidString.lowercased(),
                                        name: params.address.split(separator: "@").last.map(String.init) ?? params.address)
            connectedDevices.append(device)
            ownerInventories[device.id] = inventory
            return try mockResult(device, as: Result.self)
        case "connections.devices.remove":
            let params = try mockDecode(call.params, as: SiloWireDeviceIdParams.self)
            if let error = nextConnectionRemovalError {
                nextConnectionRemovalError = nil
                throw EngineClientError.invalidAction(error)
            }
            revokedDeviceIDs.append(params.deviceId)
            connectedDevices.removeAll { $0.id == params.deviceId }
            ownerInventories[params.deviceId] = nil
            return try mockResult(SiloNull(), as: Result.self)
        case "connections.setEnabled":
            let params = try mockDecode(call.params, as: SiloWireConnectionsSetEnabledParams.self)
            mockConnectionsEnabled = params.enabled
            return try mockResult(mockConnectionsStatus(enabled: params.enabled), as: Result.self)
        case "connections.ssh.authorizationCommand":
            let params = try mockDecode(call.params, as: SiloWireSSHAddressParams.self)
            return try mockResult(SiloWireSSHCommandResult(command: "ssh -o StrictHostKeyChecking=ask -o BatchMode=no -- \(mockShellQuote(params.address)) true"), as: Result.self)
        case "connections.ssh.keySetupCommand":
            let params = try mockDecode(call.params, as: SiloWireSSHAddressParams.self)
            return try mockResult(SiloWireSSHCommandResult(command: "ssh -- \(mockShellQuote(params.address)) 'install-silo-remote-key'"), as: Result.self)
        case "sshAccess.state":
            let computers = inventory.allComputers.map { row in
                mockSSHAccess[row.id] ?? SiloWireSSHAccessComputer(addresses: [], bindAddress: "127.0.0.1",
                    computer: row.name, computerId: row.id, deviceName: "Fjord Mac", enabled: false,
                    keys: [], port: 2222, state: .disabled, user: "dev")
            }
            return try mockResult(SiloWireSSHAccessState(computers: computers), as: Result.self)
        case "sshAccess.save":
            let params = try mockDecode(call.params, as: SiloWireSSHAccessSaveParams.self)
            let row = inventory.computer(params.computerId)
            let state = SiloWireSSHAccessComputer(addresses: params.enabled ? ["127.0.0.1"] : [],
                bindAddress: params.bindAddress, computer: row?.name ?? params.computerId,
                computerId: params.computerId, deviceName: "Fjord Mac", enabled: params.enabled,
                keys: params.keys ?? [], port: params.port, state: params.enabled ? .listening : .disabled, user: "dev")
            mockSSHAccess[params.computerId] = state
            return try mockResult(SiloWireSSHAccessState(computers: inventory.allComputers.map {
                mockSSHAccess[$0.id] ?? SiloWireSSHAccessComputer(addresses: [], bindAddress: "127.0.0.1",
                    computer: $0.name, computerId: $0.id, deviceName: "Fjord Mac", enabled: false,
                    keys: [], port: 2222, state: .disabled, user: "dev")
            }), as: Result.self)
        case "sshAccess.connection":
            let params = try mockDecode(call.params, as: SiloWireSSHAccessConnectionParams.self)
            guard mockSSHAccess[params.computerId]?.enabled == true else {
                throw EngineClientError.invalidAction("Enable SSH access first.")
            }
            let address = params.network == true ? "192.0.2.10" : "127.0.0.1"
            return try mockResult("ssh -i '/tmp/mock-silo-key' -o IdentitiesOnly=yes -p 2222 dev@\(address)",
                                  as: Result.self)
        case "display.viewer.open":
            let params = try mockDecode(call.params, as: SiloWireComputerTargetParams.self)
            viewerOpenRequests.append(params.computerId)
            if suspendNextViewerOpen {
                suspendNextViewerOpen = false
                await withCheckedContinuation { continuation in
                    viewerOpenContinuation = continuation
                    viewerOpenWaiters.forEach { $0.resume() }
                    viewerOpenWaiters.removeAll()
                }
            }
            if !nextViewerOpenResults.isEmpty {
                return try mockResult(nextViewerOpenResults.removeFirst(), as: Result.self)
            }
            let row = inventory.computer(params.computerId)
            return try mockResult(SiloWireViewerOpenResult(connectionId: "viewer-\(params.computerId)",
                cookie: SiloWireViewerCookie(domain: "127.0.0.1", httpOnly: true, name: "silo-viewer",
                                             path: "/", value: "demo"), initScript: "", name: row?.name ?? "Linux computer",
                url: "http://127.0.0.1:5099/"), as: Result.self)
        case "display.viewer.close":
            let params = try mockDecode(call.params, as: SiloWireViewerConnectionParams.self)
            viewerCloseRequests.append(params.connectionId)
            return try mockResult(SiloNull(), as: Result.self)
        case "engine.credentials.status":
            return try mockResult(credentialsStatus, as: Result.self)
        case "engine.credentials.repair":
            credentialRepairCount += 1
            if let failure = credentialRepairFailure { throw failure }
            let declined = credentialRepairDeclines
            let items = credentialsStatus.items.filter { $0.state == .denied }.map {
                SiloWireCredentialRepairItem(computerId: $0.computerId, kind: $0.kind, label: $0.label,
                                             outcome: declined ? .stillDenied : .repaired)
            }
            if !declined {
                credentialsStatus.items = credentialsStatus.items.map { item in
                    var item = item
                    item.state = .accessible
                    return item
                }
                credentialsStatus.deniedCount = 0
            }
            return try mockResult(SiloWireCredentialsRepairResult(items: items, status: credentialsStatus), as: Result.self)
        default:
            throw EngineClientError.unsupported("The mock doesn't implement \(call.name).")
        }
    }

    func operationsList(deviceId: String? = nil) async throws -> OperationsList {
        if let owner = peer(deviceId) { return try await owner.operationsList() }
        operationsListCallCount += 1
        var snapshot = operationQueue
        snapshot.unacknowledgedJobIds = Array(Set(snapshot.unacknowledgedJobIds + Array(finished.keys))).sorted()
        return snapshot
    }

    func operationsJobGet(jobId: String, deviceId: String? = nil) async throws -> OperationJobSnapshot {
        if let owner = peer(deviceId) { return try await owner.operationsJobGet(jobId: jobId) }
        jobGetCallCount += 1
        if let result = finished[jobId] {
            return OperationJobSnapshot(jobId: jobId, state: .finished,
                                        outcome: OperationJobOutcome(result: result.result, error: result.error))
        }
        let waiting = operationQueue.waiting.contains { $0.jobId == jobId }
        return OperationJobSnapshot(jobId: jobId, state: waiting ? .waiting : .running)
    }

    func operationsCancel(jobId: String, deviceId: String? = nil) async throws {
        if let owner = peer(deviceId) { return try await owner.operationsCancel(jobId: jobId) }
        cancelRequests.append(jobId)
        if suspendNextCancelRequest {
            suspendNextCancelRequest = false
            await withCheckedContinuation { continuation in
                cancelRequestContinuation = continuation
                cancelRequestWaiters.forEach { $0.resume() }
                cancelRequestWaiters.removeAll()
            }
        }
        if let index = operationQueue.waiting.firstIndex(where: { $0.jobId == jobId }) {
            operationQueue.waiting.remove(at: index)
        } else if let index = operationQueue.running.firstIndex(where: { $0.jobId == jobId }) {
            guard operationQueue.running[index].cancellable else {
                throw EngineClientError.invalidAction("This operation can't be cancelled.")
            }
            operationQueue.running.remove(at: index)
        } else {
            throw EngineClientError.notFound("This operation is no longer queued.")
        }
        let result = OperationJobFinished(jobId: jobId, error: OperationJobError(code: "cancelled", message: "Cancelled."))
        finished[jobId] = result
        publish(.operationsQueueChanged(operationQueue))
        publish(.jobFinished(result))
    }

    func eventsSubscribe(events: [String], deviceIds: [String],
                         handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String {
        subscribeCallCount += 1
        subscribedDeviceIds.append(deviceIds)
        if suspendNextSubscription {
            suspendNextSubscription = false
            await withCheckedContinuation { continuation in
                subscriptionContinuation = continuation
                subscriptionWaiters.forEach { $0.resume() }
                subscriptionWaiters.removeAll()
            }
        }
        let subscription = UUID().uuidString
        subscribers[subscription] = Subscriber(events: events, deviceIds: deviceIds, sequence: 0, handler: handler)
        if let currentProgress, Self.matches("operations.job.progress", requested: events) {
            deliver(.jobProgress(currentProgress), to: subscription)
        }
        return subscription
    }

    func eventsUnsubscribe(subscription: String) async {
        unsubscribeCallCount += 1
        subscribers[subscription] = nil
    }

    func operationsJobAcknowledge(jobId: String, deviceId: String? = nil) async throws {
        if let owner = peer(deviceId) { return try await owner.operationsJobAcknowledge(jobId: jobId) }
        acknowledgedJobs.append(jobId)
        if suspendNextJobAcknowledge {
            suspendNextJobAcknowledge = false
            await withCheckedContinuation { continuation in
                jobAcknowledgeContinuation = continuation
                jobAcknowledgeWaiters.forEach { $0.resume() }
                jobAcknowledgeWaiters.removeAll()
            }
        }
        finished[jobId] = nil
    }

    func deliver(_ delivery: EngineEventDelivery) {
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id] else { continue }
            let sequence: UInt64?
            switch delivery {
            case .event(let value, _), .sequenceAdvanced(let value): sequence = value
            case .reconnected, .disconnected: sequence = nil
            }
            if let sequence {
                subscriber.sequence = max(subscriber.sequence, sequence)
                subscribers[id] = subscriber
            }
            subscriber.handler(delivery)
        }
    }

    func retainFinishedJob(_ outcome: OperationJobFinished) {
        finished[outcome.jobId] = outcome
        if !operationQueue.unacknowledgedJobIds.contains(outcome.jobId) {
            operationQueue.unacknowledgedJobIds.append(outcome.jobId)
        }
    }

    func replaceInventory(_ inventory: ComputerInventory) {
        self.inventory = inventory
    }

    func publishOperationQueueChange(_ queue: OperationsList) {
        operationQueue = queue
        publish(.operationsQueueChanged(queue))
    }

    func waitForSuspendedComputersList() async {
        if computersListContinuation != nil { return }
        await withCheckedContinuation { computersListWaiters.append($0) }
    }

    func resumeSuspendedComputersList() {
        let continuation = computersListContinuation
        computersListContinuation = nil
        continuation?.resume()
    }

    func waitForSuspendedSubscription() async {
        if subscriptionContinuation != nil { return }
        await withCheckedContinuation { subscriptionWaiters.append($0) }
    }

    func waitForSuspendedViewerOpen() async {
        if viewerOpenContinuation != nil { return }
        await withCheckedContinuation { viewerOpenWaiters.append($0) }
    }

    func resumeSuspendedViewerOpen() {
        let continuation = viewerOpenContinuation
        viewerOpenContinuation = nil
        continuation?.resume()
    }

    func resumeSuspendedSubscription() {
        let continuation = subscriptionContinuation
        subscriptionContinuation = nil
        continuation?.resume()
    }

    func waitForSuspendedCancelRequest() async {
        if cancelRequestContinuation != nil { return }
        await withCheckedContinuation { cancelRequestWaiters.append($0) }
    }

    func waitForSuspendedJobAcknowledge() async {
        if jobAcknowledgeContinuation != nil { return }
        await withCheckedContinuation { jobAcknowledgeWaiters.append($0) }
    }

    func resumeSuspendedJobAcknowledge() {
        let continuation = jobAcknowledgeContinuation
        jobAcknowledgeContinuation = nil
        continuation?.resume()
    }

    func resumeSuspendedCancelRequest() {
        let continuation = cancelRequestContinuation
        cancelRequestContinuation = nil
        continuation?.resume()
    }

    func waitForSuspendedCheckpointRestore() async {
        if checkpointRestoreContinuation != nil { return }
        await withCheckedContinuation { checkpointRestoreWaiters.append($0) }
    }

    func resumeSuspendedCheckpointRestore() {
        let continuation = checkpointRestoreContinuation
        checkpointRestoreContinuation = nil
        continuation?.resume()
    }

    func engineDisconnect() async throws {
        disconnected = true
        disconnectCount += 1
    }

    private func requireComputer(_ id: String) throws -> ComputerRow {
        guard let row = inventory.computer(id) else { throw EngineClientError.notFound("This computer no longer exists.") }
        return row
    }

    private func validateComputerName(_ name: String) throws {
        guard ComputerName.isValid(name) else {
            throw EngineClientError.invalidAction("Computer names must be 1–32 characters and match [a-z][a-z0-9-]*.")
        }
        guard !inventory.allComputers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw EngineClientError.invalidAction("A computer named '\(name)' already exists.")
        }
    }

    private func mockDecode<Encoded: Encodable, Value: Decodable>(_ encoded: Encoded, as type: Value.Type) throws -> Value {
        let data = try JSONEncoder().encode(encoded)
        return try JSONDecoder().decode(type, from: data)
    }

    private func mockResult<Encoded: Encodable, Value: Decodable>(_ encoded: Encoded, as type: Value.Type) throws -> Value {
        let data = try JSONEncoder().encode(encoded)
        return try JSONDecoder().decode(type, from: data)
    }

    private func mockValue<Value: Encodable>(_ value: Value) throws -> SiloJSONValue {
        try JSONDecoder().decode(SiloJSONValue.self, from: JSONEncoder().encode(value))
    }

    private func mockShellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static let readyAgentTools = SiloWireAgentToolsStatus(claudeVersion: "2.1.287", expectedClaudeVersion: "2.1.287",
        expectedNodeVersion: "24.21.0", expectedRecipeVersion: 1, missing: [], nodeVersion: "24.21.0",
        recipeVersion: 1, state: .ready)

    static func agentTools(_ state: SiloWireAgentToolsState) -> SiloWireAgentToolsStatus {
        switch state {
        case .ready: readyAgentTools
        case .missing:
            SiloWireAgentToolsStatus(expectedClaudeVersion: "2.1.287", expectedNodeVersion: "24.21.0",
                expectedRecipeVersion: 1, missing: ["node", "claude"], state: .missing)
        case .outdated:
            SiloWireAgentToolsStatus(claudeVersion: "2.1.250", expectedClaudeVersion: "2.1.287",
                expectedNodeVersion: "24.21.0", expectedRecipeVersion: 2, missing: [], nodeVersion: "24.18.0",
                recipeVersion: 1, state: .outdated)
        }
    }

    private func mockFeatureJob(result: SiloJSONValue? = nil, jobId explicitJobId: String? = nil) -> SiloWireJobStartResult {
        let jobId = explicitJobId ?? nextJobId()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.finish(jobId, result: result)
        }
        return SiloWireJobStartResult(jobId: jobId)
    }

    private func mockConnectionsStatus(enabled: Bool? = nil) -> SiloWireConnectionsStatus {
        SiloWireConnectionsStatus(address: "fjord@fjord-mac.local",
            addresses: [SiloWireDeviceAddress(address: "fjord@fjord-mac.local", kind: .name)],
            deviceId: Self.devID, enabled: enabled ?? mockConnectionsEnabled, name: "Fjord Mac")
    }

    private func mockNetworkPorts(computerId: String) -> [SiloWirePublishedPort] {
        let configured = mockPorts[computerId] ?? []
        guard !configured.contains(where: { $0.port == 3000 }) else { return configured }
        return [SiloWirePublishedPort(configured: false, port: 3000, state: .unpublished)] + configured
    }

    private func nextJobId() -> String {
        defer { nextJob += 1 }
        return "job:\(nextJob)"
    }

    private func setProgress(jobId: String, computerId: String, state: MacosComputerState, progress: Double, detail: String) {
        setProgress(jobId: jobId, computerId: computerId, state: state.rawValue, progress: progress, detail: detail)
    }

    private func setProgress(jobId: String, computerId: String, state: String, progress: Double, detail: String,
                             source: JobProgressSource = .macos, action: String? = nil, step: String? = nil) {
        let data: OperationJobProgressData
        switch source {
        case .setup:
            data = .setup(SetupJobProgressData(schemaVersion: 1, type: "computer-configuration", requestId: jobId,
                                               phase: state, step: step ?? state, computer: computerId, fraction: progress,
                                               message: detail, safeForDisplay: true,
                                               timestamp: ISO8601DateFormatter().string(from: Date()), level: "info",
                                               elapsedSeconds: 0, partial: false))
        case .lifecycle:
            data = .lifecycle(LifecycleJobProgressData(computerId: computerId, action: action ?? "start", step: step ?? state))
        case .transfer:
            data = .transfer(TransferJobProgressData(id: jobId, computer: computerId, direction: "download",
                                                     state: "transferring", name: detail, fileIndex: 0, fileCount: 1,
                                                     bytesDone: 0, bytesTotal: 1))
        case .backup:
            data = .backup(BackupJobProgressData(operation: jobId,
                                                 archive: BackupJobProgressArchive(name: "backup", archivePath: "", completedLabel: "Backup",
                                                                                  size: 0, destination: "", computers: []),
                                                 runningNames: [], progress: UInt8(max(0.0, min(100.0, progress * 100))),
                                                 phases: [BackupJobProgressPhase(title: state, detail: detail, tone: "info")]))
        case .push:
            data = .push(PushJobProgressData(operationId: jobId, computer: computerId, repositoryPath: "", status: "pushing",
                                             commitCount: 0, message: detail, target: .null))
        case .macos:
            data = .macos(MacosJobProgressData(computerId: computerId, state: state, progress: progress, detail: detail))
        case .update:
            data = .update(UpdateJobProgressData(phase: state, currentVersion: "0", automaticChecks: true,
                                                 packageKind: "macos", releaseUrl: "", runningComputers: [], canInstall: false))
        }
        let kind = source == .setup ? "computerConfiguration" : "lifecycle"
        let event = OperationJobProgress(jobId: jobId, kind: kind, computerId: computerId, source: source, data: data)
        currentProgress = event
        publish(.jobProgress(event))
    }

    private func finish(_ jobId: String, result: JSONValue? = nil) {
        let event = OperationJobFinished(jobId: jobId, result: result, error: nextJobFailure)
        nextJobFailure = nil
        finished[jobId] = event
        if currentProgress?.jobId == jobId { currentProgress = nil }
        if dropNextFinishedEvent { dropNextFinishedEvent = false }
        else { publish(.jobFinished(event)) }
    }

    private func scheduleCheckpointFinish(_ jobId: String, computerId: String, after duration: Duration) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self else { return }
            self.publishCheckpointChange(for: computerId)
            self.finish(jobId)
        }
    }

    private func publishCheckpointChange(for computerId: String) {
        guard let row = inventory.computer(computerId) else { return }
        let checkpoints = row.checkpoints
        let sizes = checkpoints.map(\.sizeBytes)
        let total = sizes.allSatisfy { $0 != nil } ? sizes.compactMap { $0 }.reduce(UInt64(0), +) : nil
        let usage = CheckpointUsage(totalBytes: total, checkpoints: checkpoints.map {
            CheckpointUsageEntry(deleteBlocker: nil, id: $0.id, sizeBytes: $0.sizeBytes, usedBy: nil)
        })
        let payload: CheckpointsChangedPayload
        switch row {
        case .linux:
            payload = CheckpointsChangedPayload(linux: inventory.linux, usage: [computerId: usage])
        case .macos:
            payload = CheckpointsChangedPayload(macos: inventory.macos, usage: [computerId: usage])
        }
        publish(.checkpointsChanged(payload))
    }

    /// Publishes an event as given (for tests that need a particular `deviceId`).
    func publishForTests(_ event: EngineEvent) { publish(event) }

    private func publish(_ event: EngineEvent) {
        relay?(event)
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id], Self.matches(event.name, requested: subscriber.events) else { continue }
            subscriber.sequence &+= 1
            subscribers[id] = subscriber
            subscriber.handler(.event(sequence: subscriber.sequence, event: event))
        }
    }

    private func storeMockExportResult(archive: SiloWireArchive, operation: SiloWireBackupOperationKind,
                                       names: [String], title: String, message: String) {
        let result = SiloWireOperationClass(archive: archive, kind: .result, operation: operation,
            runningNames: names, detail: message, message: message, outcome: .success, title: title)
        mockExportState.archives = mockArchives
        mockExportState.destination = mockExportDestination
        mockExportState.operation = result
        mockExportState.operationId = UUID().uuidString
        mockExportState.resultUnseen = true
        mockExportState.snapshotId = UUID().uuidString
        publish(.exportsChanged(mockExportState))
    }

    private func deliver(_ event: EngineEvent, to subscription: String) {
        guard var subscriber = subscribers[subscription], Self.matches(event.name, requested: subscriber.events) else { return }
        subscriber.sequence &+= 1
        subscribers[subscription] = subscriber
        subscriber.handler(.event(sequence: subscriber.sequence, event: event))
    }

    private static func matches(_ name: String, requested: [String]) -> Bool {
        requested.contains { topic in
            topic == name || (topic.hasSuffix(".*") && name.hasPrefix(String(topic.dropLast())))
        }
    }

    private func updateLinux(_ id: String, _ update: (inout ApplicationComputer) -> Void) {
        guard let index = inventory.linux.computers.firstIndex(where: { $0.id == id }) else { return }
        update(&inventory.linux.computers[index])
        publish(.computersChanged(ComputersChangedPayload(linux: inventory.linux)))
    }

    /// Sets the informational note of a macOS computer (a Mac imported without SecureToken).
    func setComputerNote(_ note: String?, for id: String) { updateMacos(id) { $0.note = note } }

    /// The engine refused after an update: a few saved items are blocked until the user allows them.
    func denyCredentials() {
        credentialsStatus = SiloWireCredentialsStatus(deniedCount: 3, items: [
            SiloWireCredentialItem(kind: .githubSignIn, label: "GitHub sign-in", state: .denied),
            SiloWireCredentialItem(kind: .secretsVault, label: "Secrets", state: .denied),
            SiloWireCredentialItem(computerId: Self.devID, kind: .proxyCa,
                                   label: "Network certificate of a macOS computer", state: .denied),
        ])
    }

    private func updateMacos(_ id: String, _ update: (inout MacosComputer) -> Void) {
        guard let index = inventory.macos.computers.firstIndex(where: { $0.id == id }) else { return }
        update(&inventory.macos.computers[index])
        publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
    }

    private func appendCheckpoint(_ checkpoint: ComputerCheckpoint, to id: String) {
        switch try? requireComputer(id) {
        case .linux?: updateLinux(id) {
            var checkpoints = $0.checkpoints ?? []
            checkpoints.insert(checkpoint, at: 0)
            $0.checkpoints = checkpoints
        }
        case .macos?: updateMacos(id) { $0.checkpoints.insert(checkpoint, at: 0) }
        case nil: break
        }
    }

    private func removeCheckpoint(_ checkpointId: String, from id: String) {
        switch try? requireComputer(id) {
        case .linux?: updateLinux(id) { $0.checkpoints?.removeAll { $0.id == checkpointId } }
        case .macos?: updateMacos(id) { $0.checkpoints.removeAll { $0.id == checkpointId } }
        case nil: break
        }
    }

    private func removeComputer(_ id: String) {
        let changedKind = inventory.computer(id)?.kind
        inventory.linux.computers.removeAll { $0.id == id }
        inventory.macos.computers.removeAll { $0.id == id }
        switch changedKind {
        case .linux?: publish(.computersChanged(ComputersChangedPayload(linux: inventory.linux)))
        case .macos?: publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
        case nil: break
        }
    }
}
