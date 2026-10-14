import Foundation

enum ComputerKind: String, Codable, CaseIterable {
    case linux
    case macos

    var title: String { rawValue == "macos" ? "macOS" : "Linux" }
}

enum LinuxComputerState: String, Codable {
    case running, starting, stopped, failed
}

enum MacosComputerState: String, Codable {
    case preparing, copying, downloading, installing
    case settingUp = "setting-up"
    case stopped, starting, running, stopping, failed
}

enum CheckpointScope: String, Codable { case full, disk }
enum CheckpointReason: String, Codable { case manual, beforeRestore = "before-restore" }
enum CheckpointKind: String, Codable { case manual, automatic }
enum CheckpointOperationKind: String, Codable { case capture, restore, fork, delete }
enum CheckpointOperationStatus: String, Codable { case running, failed }

struct DesktopConfiguration: Codable, Equatable {
    var startWithComputer: Bool
    var builtIn: Bool? = nil
}

struct ComputerConfiguration: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var cpus: Int
    var maxCPUs: Int
    var memoryGiB: Int
    var maxMemoryGiB: Int
    var workspaceStorageGiB: Int
    var runtimeStorageGiB: Int
    var desktop: DesktopConfiguration? = nil
}

struct ComputerConfigurationRequest: Codable, Equatable {
    var schemaVersion: Int
    var computers: [ComputerConfiguration]
}

struct ComputerCheckpoint: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var createdAt: String
    var scope: CheckpointScope
    var reason: CheckpointReason
    var kind: CheckpointKind
    var sizeBytes: Int64? = nil
}

struct ComputerCheckpointOperation: Codable, Equatable {
    var kind: CheckpointOperationKind
    var status: CheckpointOperationStatus
    var stage: String
    var error: String? = nil
}

struct PendingCheckpointRestore: Codable, Equatable {
    var checkpointId: String
    var sourceComputer: String? = nil
    var state: CheckpointScope
}

struct UnfinishedRestore: Codable, Equatable {
    var checkpointId: String
    var checkpointName: String? = nil
    var phase: String
}

struct ComputerAttention: Codable, Equatable {
    var level: String
    var message: String
}

struct ApplicationComputer: Codable, Equatable, Identifiable {
    var kind: ComputerKind
    var configuration: ComputerConfiguration
    var purpose: String
    var state: LinuxComputerState
    var stateDetail: String
    var canDismissError: Bool
    var lifecycleFailure: String? = nil
    var lifecycleFailureDiagnostic: String? = nil
    var attention: ComputerAttention? = nil
    var freshness: String
    var settling: Bool? = nil
    var checkpoints: [ComputerCheckpoint]
    var pendingCheckpointRestore: PendingCheckpointRestore? = nil
    var checkpointOperation: ComputerCheckpointOperation? = nil
    var unfinishedRestore: UnfinishedRestore? = nil

    var id: String { configuration.id }
    var name: String { configuration.name }
}

struct MacosTemplateSummary: Codable, Equatable {
    var macosVersion: String
    var build: String
    var current: Bool
}

struct MacosPendingRestore: Codable, Equatable {
    var checkpointId: String
    var memory: Bool
}

struct MacosComputer: Codable, Equatable, Identifiable {
    var kind: ComputerKind
    var id: String
    var name: String
    var cpus: Int
    var memoryGiB: Int
    var diskGiB: Int
    var osVersion: String? = nil
    var state: MacosComputerState
    var progress: Double? = nil
    var detail: String? = nil
    var displayOpen: Bool
    var installed: Bool
    var setupComplete: Bool
    var needsPersonalizing: Bool
    var checkpoints: [ComputerCheckpoint]
    var checkpointOperation: ComputerCheckpointOperation? = nil
    var pendingRestore: MacosPendingRestore? = nil
}

struct ApplicationSource: Codable, Equatable {
    var computers: [ApplicationComputer]
}

struct MacosComputersState: Codable, Equatable {
    var supported: Bool
    var unsupportedReason: String? = nil
    var computers: [MacosComputer]
    var template: MacosTemplateSummary? = nil
    var minDiskGiB: Int
}

struct ComputerInventory: Codable, Equatable {
    var linux: ApplicationSource
    var macos: MacosComputersState

    var allComputers: [ComputerRow] {
        (macos.computers.map(ComputerRow.macos) + linux.computers.map(ComputerRow.linux))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func computer(_ id: String) -> ComputerRow? { allComputers.first { $0.id == id } }

    func applying(_ change: ComputersChangedPayload) -> ComputerInventory {
        ComputerInventory(linux: change.linux ?? linux, macos: change.macos ?? macos)
    }

    var runningComputers: [RunningComputer] {
        allComputers.filter { $0.displayState == .running }
            .map { RunningComputer(computerId: $0.id, name: $0.name, kind: $0.kind) }
    }
}

/// Payload for `computers.changed` (05 §4.2 D, 10 §12.2). Only changed platforms are present.
struct ComputersChangedPayload: Codable, Equatable {
    var linux: ApplicationSource? = nil
    var macos: MacosComputersState? = nil
}

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
        case .linux(let computer): computer.checkpoints
        case .macos(let computer): computer.checkpoints
        }
    }

    var canStart: Bool { displayState == .stopped || displayState == .failed }
    var canStop: Bool { displayState == .running }
    var canForceStop: Bool { kind == .macos && [.starting, .running, .stopping].contains(displayState) }
    var canDelete: Bool { [.stopped, .failed, .preparing, .copying, .downloading, .installing, .settingUp].contains(displayState) }
    var canShowDisplay: Bool { kind == .macos && displayState == .running }
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

struct ComputerReference: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
}

struct MacosComputerCreateRequest: Codable, Equatable {
    var name: String
    var cpus: Int
    var memoryGiB: Int
    var diskGiB: Int
}

struct ComputerCreateRequest: Codable, Equatable {
    var kind: ComputerKind
    var configuration: ComputerConfiguration? = nil
    var request: MacosComputerCreateRequest? = nil
    var requestId: String? = nil
    var deviceId: String? = nil

    static func linux(_ configuration: ComputerConfiguration, requestId: String? = nil, deviceId: String? = nil) -> Self {
        Self(kind: .linux, configuration: configuration, request: nil, requestId: requestId, deviceId: deviceId)
    }

    static func macos(_ request: MacosComputerCreateRequest, deviceId: String? = nil) -> Self {
        Self(kind: .macos, configuration: nil, request: request, requestId: nil, deviceId: deviceId)
    }
}

struct ComputerJob: Codable, Equatable { var jobId: String }

struct ComputerCreateResult: Codable, Equatable {
    var jobId: String
    var computer: MacosComputer? = nil
}

struct ComputerDeleteRequest: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
    var expected: ComputerConfiguration? = nil
    var requestId: String? = nil
}

struct CheckpointCreateRequest: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
    var name: String
    var kind: CheckpointKind? = nil
}

struct CheckpointRestoreRequest: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
    var checkpointId: String
}

struct CheckpointForkRequest: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
    var checkpointId: String? = nil
    var newName: String
}

struct CheckpointDeleteRequest: Codable, Equatable {
    var computerId: String
    var deviceId: String? = nil
    var checkpointId: String
}

struct CheckpointUsageEntry: Codable, Equatable {
    var id: String
    var sizeBytes: Int64? = nil
    var usedBy: [String]? = nil
    var deleteBlocker: String? = nil
}

struct CheckpointUsage: Codable, Equatable {
    var totalBytes: Int64?
    var checkpoints: [CheckpointUsageEntry]
}

/// Full checkpoint-domain state carried by `checkpoints.changed` (05 catalogue, 20 §4.3).
struct CheckpointsChangedPayload: Codable, Equatable {
    var linux: ApplicationSource? = nil
    var macos: MacosComputersState? = nil
    var usage: [String: CheckpointUsage]? = nil
}

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
        case .setup(let value): value.fraction
        case .lifecycle: nil
        case .transfer(let value): value.bytesTotal == 0 ? nil : Double(value.bytesDone) / Double(value.bytesTotal)
        case .backup(let value): Double(value.progress) / 100
        case .push: nil
        case .macos(let value): value.progress
        case .update(let value):
            guard let total = value.totalBytes, total > 0, let done = value.downloadedBytes else { return nil }
            Double(done) / Double(total)
        }
    }

    var presentationTitle: String? {
        switch self {
        case .setup(let value): value.message
        case .lifecycle(let value): "\(value.action.capitalized) · \(value.step)"
        case .transfer(let value): value.name
        case .backup(let value): value.phases.last?.detail ?? "Backup"
        case .push(let value): value.message ?? "Pushing changes"
        case .macos(let value): value.detail ?? value.state.capitalized
        case .update(let value): value.error ?? value.phase.capitalized
        }
    }

    var presentationComputerId: String? {
        switch self {
        case .lifecycle(let value): value.computerId
        case .macos(let value): value.computerId
        case .setup, .transfer, .backup, .push, .update: nil
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

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct OperationJobError: Codable, Equatable {
    var code: String
    var message: String
}

struct OperationJobFinished: Codable, Equatable {
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

enum OperationJobState: String, Codable { case waiting, running, finished }

struct OperationJobOutcome: Codable, Equatable {
    var result: JSONValue? = nil
    var error: OperationJobError? = nil
}

struct OperationJobSnapshot: Codable, Equatable {
    var jobId: String
    var state: OperationJobState
    var outcome: OperationJobOutcome? = nil

    var finishedEvent: OperationJobFinished {
        OperationJobFinished(jobId: jobId, result: outcome?.result, error: outcome?.error)
    }
}

enum EngineEvent: Equatable {
    case computersChanged(ComputersChangedPayload)
    case checkpointsChanged(CheckpointsChangedPayload)
    case operationsQueueChanged(OperationsList)
    case jobProgress(OperationJobProgress)
    case jobFinished(OperationJobFinished)

    var name: String {
        switch self {
        case .computersChanged: "computers.changed"
        case .checkpointsChanged: "checkpoints.changed"
        case .operationsQueueChanged: "operations.queue.changed"
        case .jobProgress: "operations.job.progress"
        case .jobFinished: "operations.job.finished"
        }
    }
}

enum EngineEventDelivery: Equatable {
    case event(sequence: UInt64, event: EngineEvent)
    case reconnected
    case disconnected(String)
}

enum EngineClientError: LocalizedError, Equatable {
    case notFound(String)
    case unsupported(String)
    case invalidAction(String)
    case jobFailed(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notFound(let message), .unsupported(let message), .invalidAction(let message), .jobFailed(let message): message
        case .unavailable: "No Silo engine is connected."
        }
    }
}

/// The Computer tool's boundary. Method names map to the canonical Silo API; `checkpointsList` is a client projection of
/// `computers.list`, because the spec embeds checkpoint records in each computer row and defines no `checkpoints.list` wire method.
@MainActor
protocol EngineClient {
    func computersList(deviceId: String?) async throws -> ComputerInventory
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
    func eventsSubscribe(events: [String], handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String
    func eventsUnsubscribe(subscription: String) async
    func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws
    func engineDisconnect() async throws
}

/// Keeps Computers unavailable in ordinary Fjord launches until a real Silo adapter is connected.
@MainActor
final class UnavailableEngineClient: EngineClient {
    private func unavailable<T>() throws -> T { throw EngineClientError.unavailable }

    func computersList(deviceId: String?) async throws -> ComputerInventory { try unavailable() }
    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult { try unavailable() }
    func computersStart(_ reference: ComputerReference) async throws -> ComputerJob { try unavailable() }
    func computersStop(_ reference: ComputerReference) async throws -> ComputerJob { try unavailable() }
    func computersForceStop(_ reference: ComputerReference) async throws { try unavailable() }
    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob { try unavailable() }
    func computersConfigurationRead(deviceId: String?) async throws -> ComputerConfigurationRequest { try unavailable() }
    func checkpointsList(computerId: String, deviceId: String?) async throws -> [ComputerCheckpoint] { try unavailable() }
    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsRestore(_ request: CheckpointRestoreRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsFork(_ request: CheckpointForkRequest) async throws -> ComputerJob { try unavailable() }
    func checkpointsDelete(_ request: CheckpointDeleteRequest) async throws -> ComputerJob { try unavailable() }
    func displayShow(_ reference: ComputerReference) async throws { try unavailable() }
    func operationsList(deviceId: String?) async throws -> OperationsList { try unavailable() }
    func operationsJobGet(jobId: String, deviceId: String?) async throws -> OperationJobSnapshot { try unavailable() }
    func eventsSubscribe(events: [String], handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String { try unavailable() }
    func eventsUnsubscribe(subscription: String) async {}
    func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws { try unavailable() }
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

    private(set) var inventory: ComputerInventory
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
    var suspendNextSubscription = false
    private var subscriptionContinuation: CheckedContinuation<Void, Never>?
    private var subscriptionWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var subscribeCallCount = 0
    private(set) var unsubscribeCallCount = 0
    private(set) var acknowledgedJobs: [String] = []
    private(set) var checkpointListCallCount = 0
    var nextJobFailure: OperationJobError?

    var activeSubscriptionCount: Int { subscribers.count }

    private struct Subscriber {
        var events: [String]
        var sequence: UInt64
        var handler: @MainActor (EngineEventDelivery) -> Void
    }

    init() {
        inventory = Self.demoInventory
        currentProgress = Self.demoProgress
    }

    init(inventory: ComputerInventory) {
        self.inventory = inventory
        currentProgress = Self.demoProgress
    }

    private static var demoProgress: OperationJobProgress {
        OperationJobProgress(jobId: "job:starting-macos-demo", kind: "lifecycle", computerId: startingID,
                             source: .macos,
                             data: .macos(MacosJobProgressData(computerId: startingID, state: "starting", progress: 0.42,
                                                             detail: "Starting macOS")))
    }

    func computersList(deviceId: String? = nil) async throws -> ComputerInventory {
        computersListCallCount += 1
        let snapshot = inventory
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
        ComputerConfigurationRequest(schemaVersion: 1, computers: inventory.linux.computers.map(\.configuration))
    }

    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult {
        let jobId = request.kind == .linux ? "setup:\(request.requestId ?? UUID().uuidString)" : nextJobId()
        if request.kind == .macos, let values = request.request {
            let computer = MacosComputer(kind: .macos, id: UUID().uuidString.lowercased(), name: values.name,
                                         cpus: values.cpus, memoryGiB: values.memoryGiB, diskGiB: values.diskGiB,
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
        guard case .macos = try requireComputer(reference.computerId) else {
            throw EngineClientError.unsupported("Force stop is only available for macOS computers.")
        }
        updateMacos(reference.computerId) { $0.state = .stopped; $0.progress = nil; $0.detail = nil }
    }

    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob {
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
        checkpointListCallCount += 1
        guard let row = inventory.computer(computerId) else { throw EngineClientError.notFound("This computer no longer exists.") }
        return row.checkpoints
    }

    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob {
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
        let source = try requireComputer(request.computerId)
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
        guard case .macos = try requireComputer(reference.computerId) else {
            throw EngineClientError.unsupported("A display is only available for a macOS computer.")
        }
        guard case .macos(let row)? = inventory.computer(reference.computerId), row.state == .running else {
            throw EngineClientError.invalidAction("Start the computer to open its display.")
        }
        updateMacos(reference.computerId) { $0.displayOpen = true }
    }

    func operationsList(deviceId: String? = nil) async throws -> OperationsList {
        operationsListCallCount += 1
        var snapshot = operationQueue
        snapshot.unacknowledgedJobIds = Array(Set(snapshot.unacknowledgedJobIds + Array(finished.keys))).sorted()
        return snapshot
    }

    func operationsJobGet(jobId: String, deviceId: String? = nil) async throws -> OperationJobSnapshot {
        jobGetCallCount += 1
        if let result = finished[jobId] {
            return OperationJobSnapshot(jobId: jobId, state: .finished,
                                        outcome: OperationJobOutcome(result: result.result, error: result.error))
        }
        let waiting = operationQueue.waiting.contains { $0.jobId == jobId }
        return OperationJobSnapshot(jobId: jobId, state: waiting ? .waiting : .running)
    }

    func eventsSubscribe(events: [String], handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String {
        subscribeCallCount += 1
        if suspendNextSubscription {
            suspendNextSubscription = false
            await withCheckedContinuation { continuation in
                subscriptionContinuation = continuation
                subscriptionWaiters.forEach { $0.resume() }
                subscriptionWaiters.removeAll()
            }
        }
        let subscription = UUID().uuidString
        subscribers[subscription] = Subscriber(events: events, sequence: 0, handler: handler)
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
        acknowledgedJobs.append(jobId)
        finished[jobId] = nil
    }

    func deliver(_ delivery: EngineEventDelivery) {
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id] else { continue }
            if case .event(let sequence, _) = delivery {
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

    func resumeSuspendedSubscription() {
        let continuation = subscriptionContinuation
        subscriptionContinuation = nil
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

    private func finish(_ jobId: String) {
        let event = OperationJobFinished(jobId: jobId, result: nil, error: nextJobFailure)
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
        let total = sizes.allSatisfy { $0 != nil } ? sizes.compactMap { $0 }.reduce(Int64(0), +) : nil
        let usage = CheckpointUsage(totalBytes: total, checkpoints: checkpoints.map {
            CheckpointUsageEntry(id: $0.id, sizeBytes: $0.sizeBytes)
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

    private func publish(_ event: EngineEvent) {
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id], Self.matches(event.name, requested: subscriber.events) else { continue }
            subscriber.sequence &+= 1
            subscribers[id] = subscriber
            subscriber.handler(.event(sequence: subscriber.sequence, event: event))
        }
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

    private func updateMacos(_ id: String, _ update: (inout MacosComputer) -> Void) {
        guard let index = inventory.macos.computers.firstIndex(where: { $0.id == id }) else { return }
        update(&inventory.macos.computers[index])
        publish(.computersChanged(ComputersChangedPayload(macos: inventory.macos)))
    }

    private func appendCheckpoint(_ checkpoint: ComputerCheckpoint, to id: String) {
        switch try? requireComputer(id) {
        case .linux?: updateLinux(id) { $0.checkpoints.insert(checkpoint, at: 0) }
        case .macos?: updateMacos(id) { $0.checkpoints.insert(checkpoint, at: 0) }
        case nil: break
        }
    }

    private func removeCheckpoint(_ checkpointId: String, from id: String) {
        switch try? requireComputer(id) {
        case .linux?: updateLinux(id) { $0.checkpoints.removeAll { $0.id == checkpointId } }
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
