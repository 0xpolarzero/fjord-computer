import Foundation

// These names are the Computers feature's client-facing vocabulary. The schema generated
// structs remain the source of truth for their fields and Codable behavior.
typealias ComputerKind = SiloWireComputerKind
typealias LinuxComputerState = SiloWireLinuxComputerState
typealias MacosComputerState = SiloWireMacosComputerState
typealias CheckpointScope = SiloWireCheckpointScope
typealias CheckpointReason = SiloWireCheckpointReason
typealias CheckpointKind = SiloWireCheckpointKind
typealias CheckpointOperationKind = SiloWireOperationKind
typealias CheckpointOperationStatus = SiloWireOperationStatus
typealias DesktopConfiguration = SiloWireDesktopConfiguration
typealias ComputerConfiguration = SiloWireComputerConfiguration
typealias ComputerConfigurationRequest = SiloWireComputerConfigurationRequest
typealias ComputerCheckpoint = SiloWireCheckpoint
typealias ComputerCheckpointOperation = SiloWireOperation
typealias PendingCheckpointRestore = SiloWirePendingRestore
typealias MacosPendingRestore = SiloWirePendingRestore
typealias UnfinishedRestore = SiloWireUnfinishedRestore
typealias ComputerAttention = SiloWireComputerAttention
typealias ApplicationComputer = SiloWireApplicationComputer
typealias MacosTemplateSummary = SiloWireTemplateSummary
typealias MacosComputer = SiloWireMacosComputer
typealias ApplicationSource = SiloWireApplicationSource
typealias MacosComputersState = SiloWireMacosComputersState
typealias ComputerInventory = SiloWireComputersListResult
typealias ComputerReference = SiloWireComputerTargetParams
typealias RemoteLoginStatus = SiloWireRemoteLoginStatus
typealias ComputerJob = SiloWireJobStartResult
typealias ComputerCreateResult = SiloWireComputerCreateResult
typealias ComputerDeleteRequest = SiloWireComputerDeleteParams
typealias CheckpointCreateRequest = SiloWireCheckpointCreateParams
typealias CheckpointRestoreRequest = SiloWireCheckpointTargetParams
typealias CheckpointForkRequest = SiloWireCheckpointForkParams
typealias CheckpointDeleteRequest = SiloWireCheckpointTargetParams
typealias CheckpointUsageEntry = SiloWireCheckpointUsageEntry
typealias CheckpointUsage = SiloWireCheckpointUsage
typealias OperationJobState = SiloWireJobState
typealias JSONValue = SiloJSONValue

// Small UI inputs and limits use Int for arithmetic. SocketEngineClient maps these to
// schema-generated UInt64 wire structs after validating the conversion.
struct MacosComputerCreateRequest: Codable, Equatable {
    var name: String
    var cpus: Int
    var memoryGiB: Int
    var diskGiB: Int
}

struct DeviceCapacity: Codable, Equatable {
    var logicalCpus: Int
    var physicalMemoryBytes: UInt64
    var maxMemoryGib: Int
}

struct MacosHostLimits: Codable, Equatable {
    var cpus: Int
    var memory_gib: Int
}

struct DeviceFacts: Codable, Equatable {
    var deviceCapacity: DeviceCapacity?
    var macosHostLimits: MacosHostLimits?
    var remoteLogin: RemoteLoginStatus

    static let demo = DeviceFacts(
        deviceCapacity: DeviceCapacity(logicalCpus: 16, physicalMemoryBytes: 68_719_476_736, maxMemoryGib: 64),
        macosHostLimits: MacosHostLimits(cpus: 16, memory_gib: 64), remoteLogin: .unknown)
}

extension SiloWireComputerKind: CaseIterable {
    static var allCases: [SiloWireComputerKind] { [.linux, .macos] }
    var title: String { rawValue == "macos" ? "macOS" : "Linux" }
}

extension SiloWireComputerConfiguration: Identifiable {}
extension SiloWireCheckpoint: Identifiable {}
extension SiloWireMacosComputer: Identifiable {}

// Keep existing app call sites readable while constructing the generated schema structs.
extension SiloWireComputerConfiguration {
    init(id: String, name: String, cpus: Int, maxCPUs: Int, memoryGiB: Int, maxMemoryGiB: Int,
         workspaceStorageGiB: Int, runtimeStorageGiB: Int, desktop: DesktopConfiguration? = nil) {
        self.init(cpus: cpus, desktop: desktop, id: id, maxCPUs: maxCPUs, maxMemoryGiB: maxMemoryGiB,
                  memoryGiB: memoryGiB, name: name, runtimeStorageGiB: runtimeStorageGiB,
                  workspaceStorageGiB: workspaceStorageGiB)
    }
}

extension SiloWireComputerConfigurationRequest {
    init(schemaVersion: Int, computers: [ComputerConfiguration]) {
        self.init(computers: computers, schemaVersion: schemaVersion)
    }
}

extension SiloWireCheckpoint {
    init(id: String, name: String, createdAt: String, scope: CheckpointScope, reason: CheckpointReason,
         kind: CheckpointKind, sizeBytes: UInt64? = nil) {
        self.init(createdAt: createdAt, id: id, kind: kind, name: name, reason: reason, scope: scope,
                  sizeBytes: sizeBytes)
    }
}

extension SiloWireTemplateSummary {
    init(macosVersion: String, build: String, current: Bool) {
        self.init(build: build, current: current, macosVersion: macosVersion)
    }
}

extension SiloWireMacosComputer {
    init(kind: ComputerKind, id: String, name: String, cpus: UInt64, memoryGiB: UInt64, diskGiB: UInt64,
         osVersion: String? = nil, state: MacosComputerState, progress: Double? = nil, detail: String? = nil,
         note: String? = nil, displayOpen: Bool, installed: Bool, setupComplete: Bool, needsPersonalizing: Bool,
         checkpoints: [ComputerCheckpoint], checkpointOperation: ComputerCheckpointOperation? = nil,
         pendingRestore: MacosPendingRestore? = nil) {
        self.init(checkpointOperation: checkpointOperation, checkpoints: checkpoints, cpus: cpus, detail: detail,
                  diskGiB: diskGiB, displayOpen: displayOpen, id: id, installed: installed, kind: kind,
                  memoryGiB: memoryGiB, name: name, needsPersonalizing: needsPersonalizing, note: note, osVersion: osVersion,
                  pendingRestore: pendingRestore, progress: progress, setupComplete: setupComplete, state: state)
    }
}

extension SiloWireMacosComputersState {
    init(supported: Bool, unsupportedReason: String? = nil, computers: [MacosComputer],
         template: MacosTemplateSummary? = nil, minDiskGiB: Int) {
        self.init(computers: computers, minDiskGiB: UInt64(max(0, minDiskGiB)), supported: supported,
                  template: template, unsupportedReason: unsupportedReason)
    }
}

extension SiloWireComputerCreateResult {
    init(jobId: String, computer: MacosComputer? = nil) {
        self.init(computer: computer, jobId: jobId)
    }
}

extension SiloWireCheckpointCreateParams {
    init(computerId: String, name: String, kind: CheckpointKind? = nil, deviceId: String? = nil) {
        self.init(computerId: computerId, deviceId: deviceId, kind: kind, name: name)
    }
}

extension SiloWireCheckpointTargetParams {
    init(computerId: String, checkpointId: String, deviceId: String? = nil) {
        self.init(checkpointId: checkpointId, computerId: computerId, deviceId: deviceId)
    }
}

extension SiloWireCheckpointForkParams {
    init(computerId: String, deviceId: String? = nil, checkpointId: String? = nil, newName: String) {
        self.init(checkpointId: checkpointId, computerId: computerId, deviceId: deviceId, newName: newName)
    }
}

extension SiloWireCheckpointUsageEntry {
    init(id: String, sizeBytes: UInt64? = nil, usedBy: [String]? = nil, deleteBlocker: String? = nil) {
        self.init(deleteBlocker: deleteBlocker, id: id, sizeBytes: sizeBytes, usedBy: usedBy)
    }
}

extension SiloWireCheckpointUsage {
    init(totalBytes: UInt64? = nil, checkpoints: [CheckpointUsageEntry]) {
        self.init(checkpoints: checkpoints, totalBytes: totalBytes)
    }
}

extension SiloWireApplicationComputer {
    var id: String { configuration.id }
    var name: String { configuration.name }

    // Mock and UI-created rows use a small presentation initializer; the generated schema
    // fields that the first Computers slice does not populate get empty/null defaults.
    init(kind: ComputerKind, configuration: ComputerConfiguration, purpose: String,
         state: LinuxComputerState, stateDetail: String, canDismissError: Bool,
         lifecycleFailure: String? = nil, lifecycleFailureDiagnostic: String? = nil,
         attention: ComputerAttention? = nil, freshness: String, settling: Bool? = nil,
         checkpoints: [ComputerCheckpoint] = [], pendingCheckpointRestore: PendingCheckpointRestore? = nil,
         checkpointOperation: ComputerCheckpointOperation? = nil, unfinishedRestore: UnfinishedRestore? = nil) {
        self.init(attention: attention, canDismissError: canDismissError,
                  checkpointOperation: checkpointOperation, checkpoints: checkpoints,
                  configuration: configuration, files: [], freshness: SiloWireFreshness(rawValue: freshness) ?? .fresh,
                  githubRepositories: [], kind: kind, lifecycleFailure: lifecycleFailure,
                  lifecycleFailureDiagnostic: lifecycleFailureDiagnostic, logs: [],
                  pendingCheckpointRestore: pendingCheckpointRestore, pendingSecretRevocations: nil,
                  ports: [], purpose: purpose, repositories: [], secretNames: [], settling: settling,
                  state: state, stateDetail: stateDetail, unfinishedRestore: unfinishedRestore)
    }
}

extension SiloWireApplicationSource {
    init(computers: [ApplicationComputer]) {
        self.init(activities: [], computerConfigurationOperation: nil, computers: computers,
                  deviceCapacity: nil, github: .null, repositoryPushOperations: [], runtimeRepair: nil,
                  secrets: [])
    }
}

extension SiloWireComputerAttention {
    init(level: String, message: String) {
        self.init(level: SiloWireAttentionLevel(rawValue: level) ?? .warning, message: message)
    }
}

extension SiloWireComputersListResult {
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

/// Event projection around the generated state payload types. The schema permits only
/// the platform that changed to be present.
struct ComputersChangedPayload: Codable, Equatable {
    var linux: ApplicationSource?
    var macos: MacosComputersState?

    init(linux: ApplicationSource? = nil, macos: MacosComputersState? = nil) {
        self.linux = linux
        self.macos = macos
    }
}

/// Checkpoint event payload details are still open JSON in the schema, so this remains a
/// small app projection while all nested canonical computer records use generated types.
struct CheckpointsChangedPayload: Codable, Equatable {
    var linux: ApplicationSource? = nil
    var macos: MacosComputersState? = nil
    var usage: [String: CheckpointUsage]? = nil
}

/// App action input. The socket adapter maps it to the schema-generated create params.
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
