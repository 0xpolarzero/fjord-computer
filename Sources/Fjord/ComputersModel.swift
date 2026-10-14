import Foundation
import Observation

struct RunningComputer: Equatable, Identifiable {
    var computerId: String
    var name: String
    var kind: ComputerKind
    var id: String { computerId }
}

struct ComputerQuitPrompt: Equatable {
    var runningComputers: [RunningComputer]
    var inspectionError: String? = nil

    var message: String {
        if let inspectionError {
            return "Fjord couldn't check whether any computers are running. \(inspectionError)"
        }
        let names = runningComputers.map(\.name).joined(separator: ", ")
        return "Quit Fjord? \(runningComputers.count) computers are running: \(names)."
    }

    static func make(inventory: ComputerInventory) -> ComputerQuitPrompt? {
        let running = inventory.runningComputers
        guard !running.isEmpty else { return nil }
        return ComputerQuitPrompt(runningComputers: running)
    }

    static func checkFailed(_ error: String) -> ComputerQuitPrompt {
        ComputerQuitPrompt(runningComputers: [], inspectionError: error)
    }
}

enum ComputerQuitChoice: Equatable { case cancel, keepRunning, stopAndQuit }

struct ComputerUploadContext: Equatable {
    var computerId: String
    var directory: String
    var paths: [String]
}

struct ComputerUploadConflict: Equatable, Identifiable {
    var jobId: String
    var computerId: String
    var directory: String
    var paths: [String]
    var names: [String]
    var id: String { jobId }
}

struct ComputerUploadNotice: Equatable, Identifiable {
    var jobId: String
    var computerId: String
    var message: String
    var id: String { jobId }
}

@MainActor
@Observable
final class ComputersModel {
    let client: any EngineClient
    private(set) var inventory: ComputerInventory?
    private(set) var remoteOwnerInventories: [ComputerOwnerInventory] = []
    private(set) var placementError: String?
    var placementOwners: [ComputerOwnerInventory] {
        (inventory.map { [ComputerOwnerInventory.local($0)] } ?? []) + remoteOwnerInventories
    }
    var placementOptions: [ComputerPlacementOption] { placementOwners.flatMap(\.options) }
    var checkpointUsage: [String: CheckpointUsage] = [:]
    private(set) var isLoading = false
    private(set) var error: String?
    var actionError: String?
    private(set) var activeJob: OperationJobProgress?
    private(set) var finishedJobs: [String: OperationJobFinished] = [:]
    private(set) var operationQueue = OperationsList.empty
    private(set) var jobAwaitingAcknowledgement: String?
    var uploadConflicts: [ComputerUploadConflict] = []
    var uploadNotices: [ComputerUploadNotice] = []
    private(set) var quitPrompt: ComputerQuitPrompt?
    private(set) var quitError: String?
    private(set) var isQuitWorking = false
    var selectedDetailSection: ComputerDetailSection = .overview
    var createSheetKind: ComputerKind?
    var isCreatePresented = false
    var hostFacts: DeviceFacts?
    var engineSettings: SiloWireSettingsSnapshot?
    var setupActivity: [SiloWireComputerConfigurationProgress] = []
    var fileLists: [String: SiloWireFileListResult] = [:]
    var filePaths: [String: String] = [:]
    var networkByComputer: [String: SiloWireNetworkComputer] = [:]
    var sshAccessByComputer: [String: SiloWireSSHAccessComputer] = [:]
    var githubState: SiloWireGitHubState?
    var secrets: [SiloWireSecret] = []
    var computerUseByComputer: [String: SiloWireComputerUseState] = [:]
    var logsByComputer: [String: SiloWireLogPage] = [:]
    var storageByComputer: [String: SiloWireStorageState] = [:]
    var exportState: SiloWireBackupState?
    var archiveInspection: SiloWireArchiveInspectionResult?
    var connectionsStatus: SiloWireConnectionsStatus?
    var connectionHealth: [String: SiloWireDeviceHealth] = [:]
    var connectionDevices: [SiloWireDevice] = []
    var pendingViewer: SiloWireViewerOpenResult?
    var viewerScripts: [String: String] = [:]

    @ObservationIgnored private var subscription: String?
    @ObservationIgnored private var quitHandler: ((ComputerQuitChoice) -> Void)?
    @ObservationIgnored private var quitResolutionTask: Task<Void, Never>?
    @ObservationIgnored var jobActions: [String: String] = [:]
    @ObservationIgnored var uploadContexts: [String: ComputerUploadContext] = [:]
    @ObservationIgnored private var presentedJobOutcomes: Set<String> = []
    @ObservationIgnored private var connectionTask: Task<Void, Error>?
    @ObservationIgnored private var connectionAttemptID: UUID?
    @ObservationIgnored private var eventStreamID: UUID?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryID: UUID?
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var hasSequence = false
    @ObservationIgnored private var recoveryRevision: UInt64 = 0
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var bufferedEvents: [(UInt64, EngineEvent)] = []
    @ObservationIgnored var reservedNames: Set<String> = []
    @ObservationIgnored private var isRecovering = false
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var ownerRefreshID: UUID?
    @ObservationIgnored var prepareComputerRemoval: (@MainActor (ComputerRow) async throws -> Void)?
    @ObservationIgnored var computerRemovalCompleted: (@MainActor (ComputerRow) -> Void)?

    init(client: any EngineClient, initialInventory: ComputerInventory? = nil) {
        self.client = client
        inventory = initialInventory
    }

    func connect() async throws {
        wantsConnection = true
        if let connectionTask {
            try await connectionTask.value
            return
        }
        guard subscription == nil else {
            try await refresh()
            return
        }
        let attemptID = UUID()
        connectionAttemptID = attemptID
        isLoading = true
        let task = Task { @MainActor in
            defer {
                if self.connectionAttemptID == attemptID {
                    self.connectionAttemptID = nil
                    self.connectionTask = nil
                    self.isLoading = false
                    if self.subscription == nil { self.eventStreamID = nil }
                }
            }
            let firstRead = try await self.client.computersList(deviceId: nil)
            if self.inventory == nil {
                self.inventory = firstRead
                self.stateRevision &+= 1
            }
            self.sequence = 0
            self.hasSequence = true
            self.eventStreamID = attemptID
            let newSubscription = try await self.client.eventsSubscribe(events: ["computers.*", "checkpoints.*", "operations.*", "connections.devices.changed", "settings.changed", "exports.changed", "display.viewer.page"]) { [weak self] event in
                self?.receive(event, stream: attemptID)
            }
            guard self.wantsConnection, self.connectionAttemptID == attemptID else {
                self.eventStreamID = nil
                await self.client.eventsUnsubscribe(subscription: newSubscription)
                return
            }
            self.subscription = newSubscription
            // Re-read after subscribing, but do not let a response that crossed an event replace newer state.
            let inventoryRevision = self.stateRevision
            let secondRead = try await self.client.computersList(deviceId: nil)
            guard self.wantsConnection, self.connectionAttemptID == attemptID else { return }
            if self.stateRevision == inventoryRevision {
                self.inventory = secondRead
                self.stateRevision &+= 1
                self.error = nil
            }
            let operationsRevision = self.stateRevision
            let operations = try await self.client.operationsList(deviceId: nil)
            guard self.wantsConnection, self.connectionAttemptID == attemptID else { return }
            if self.stateRevision == operationsRevision {
                self.operationQueue = operations
                self.stateRevision &+= 1
                await self.recoverOutstandingJobs(operations.unacknowledgedJobIds)
            } else {
                self.beginRecovery(invalidated: true)
            }
            await self.refreshRemoteOwnerInventories()
        }
        connectionTask = task
        try await task.value
    }

    func activate() async {
        do { try await connect() }
        catch { if wantsConnection { self.error = error.localizedDescription } }
    }

    func deactivate() async {
        wantsConnection = false
        connectionAttemptID = nil
        eventStreamID = nil
        connectionTask?.cancel()
        connectionTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryID = nil
        isRecovering = false
        bufferedEvents.removeAll()
        isLoading = false
        guard let subscription else { return }
        self.subscription = nil
        await client.eventsUnsubscribe(subscription: subscription)
    }

    func refresh() async throws {
        let revision = stateRevision
        let latest = try await client.computersList(deviceId: nil)
        if stateRevision == revision {
            inventory = latest
            stateRevision &+= 1
            error = nil
        }
    }

    /// Loads the local picker inventory and each currently connected remote owner's inventory. Results stay scoped by
    /// owner because computer ids are not globally unique.
    func refreshPlacementInventories() async {
        let revision = stateRevision
        do {
            let latest = try await client.computersList(deviceId: nil)
            if stateRevision == revision {
                inventory = latest
                stateRevision &+= 1
            }
            await refreshRemoteOwnerInventories()
        } catch {
            placementError = error.localizedDescription
            remoteOwnerInventories = []
        }
    }

    private func refreshRemoteOwnerInventories() async {
        let attempt = UUID()
        ownerRefreshID = attempt
        do {
            let devices = try await client.connectionsDevicesList()
            var groups: [ComputerOwnerInventory] = []
            var failedOwners: [String] = []
            for device in devices {
                guard ownerRefreshID == attempt else { return }
                do {
                    let latest = try await client.computersList(deviceId: device.id)
                    groups.append(.remote(device, inventory: latest))
                } catch {
                    failedOwners.append(device.name)
                }
            }
            guard ownerRefreshID == attempt else { return }
            remoteOwnerInventories = groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            placementError = failedOwners.isEmpty ? nil : "Couldn't load computers from: \(failedOwners.joined(separator: ", "))."
        } catch {
            guard ownerRefreshID == attempt else { return }
            remoteOwnerInventories = []
            placementError = error.localizedDescription
        }
    }

    func loadCheckpoints(for computerId: String) async {
        do {
            let checkpoints = try await client.checkpointsList(computerId: computerId, deviceId: nil)
            guard var inventory else { return }
            if let index = inventory.linux.computers.firstIndex(where: { $0.id == computerId }) {
                inventory.linux.computers[index].checkpoints = checkpoints
            } else if let index = inventory.macos.computers.firstIndex(where: { $0.id == computerId }) {
                inventory.macos.computers[index].checkpoints = checkpoints
            }
            self.inventory = inventory
        } catch { actionError = error.localizedDescription }
    }

    func presentQuitPrompt(_ prompt: ComputerQuitPrompt, onResolved: ((ComputerQuitChoice) -> Void)? = nil) {
        quitPrompt = prompt
        quitError = nil
        quitHandler = onResolved
    }

    func chooseQuit(_ choice: ComputerQuitChoice) {
        guard let prompt = quitPrompt, !isQuitWorking else { return }
        if choice == .cancel {
            quitPrompt = nil
            quitError = nil
            let handler = quitHandler
            quitHandler = nil
            handler?(.cancel)
            return
        }
        isQuitWorking = true
        quitError = nil
        quitResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.resolveQuit(choice, prompt: prompt)
                self.isQuitWorking = false
                self.quitPrompt = nil
                let handler = self.quitHandler
                self.quitHandler = nil
                handler?(choice)
            } catch {
                self.isQuitWorking = false
                self.quitError = error.localizedDescription
            }
        }
    }

    func waitForQuitResolution() async {
        await quitResolutionTask?.value
    }

    func resolveQuit(_ choice: ComputerQuitChoice, prompt: ComputerQuitPrompt) async throws {
        switch choice {
        case .cancel:
            return
        case .keepRunning:
            try await flushEngineSettings()
            try await client.engineDisconnect()
        case .stopAndQuit:
            guard prompt.inspectionError == nil else {
                throw EngineClientError.invalidAction("Refresh the computer list before stopping computers.")
            }
            for computer in prompt.runningComputers {
                let job = try await client.computersStop(ComputerReference(computerId: computer.computerId))
                let finished = try await waitForFinish(job.jobId)
                if let failure = finished.error { throw EngineClientError.jobFailed(failure.message) }
            }
            try await waitUntilStopped(Set(prompt.runningComputers.map(\.computerId)))
            try await flushEngineSettings()
            try await client.engineDisconnect()
        }
    }

    private func flushEngineSettings() async throws {
        let _: SiloNull = try await client.invoke(SiloGeneratedMethods.settingsFlush(SiloWireEmptyParams()))
    }

    func start(_ computerId: String) async { await perform("Start") { try await self.client.computersStart(ComputerReference(computerId: computerId)) } }
    func stop(_ computerId: String) async { await perform("Stop") { try await self.client.computersStop(ComputerReference(computerId: computerId)) } }
    func forceStop(_ computerId: String) async {
        actionError = nil
        do { try await client.computersForceStop(ComputerReference(computerId: computerId)) }
        catch { actionError = error.localizedDescription }
    }
    func delete(_ computerId: String) async {
        guard let row = inventory?.computer(computerId) else {
            actionError = EngineClientError.notFound("This computer no longer exists.").localizedDescription
            return
        }
        if let prepareComputerRemoval {
            do { try await prepareComputerRemoval(row) }
            catch { actionError = error.localizedDescription; return }
        }
        let expected: ComputerConfiguration? = if case .linux(let computer) = row { computer.configuration } else { nil }
        let deleted = await perform("Delete") {
            try await self.client.computersDelete(ComputerDeleteRequest(computerId: computerId, expected: expected))
        }
        if deleted { computerRemovalCompleted?(row) }
    }
    func showDisplay(_ computerId: String) async {
        actionError = nil
        do { try await client.displayShow(ComputerReference(computerId: computerId)) }
        catch { actionError = error.localizedDescription }
    }
    func createCheckpoint(for computerId: String) async {
        let name = "Manual checkpoint · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))"
        await perform("Create checkpoint") { try await self.client.checkpointsCreate(CheckpointCreateRequest(computerId: computerId, name: name, kind: .manual)) }
    }
    func restoreCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform("Restore checkpoint") { try await self.client.checkpointsRestore(CheckpointRestoreRequest(computerId: computerId, checkpointId: checkpointId)) }
    }
    func forkCheckpoint(_ checkpointId: String, computerId: String, computerName: String) async {
        do {
            let current = try await inventoryForCreation()
            let name = reserveForkName(from: computerName, in: current)
            defer { reservedNames.remove(name.lowercased()) }
            await perform("Fork checkpoint") {
                try await self.client.checkpointsFork(CheckpointForkRequest(computerId: computerId, checkpointId: checkpointId,
                                                                            newName: name))
            }
        } catch { actionError = error.localizedDescription }
    }
    func deleteCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform("Delete checkpoint") { try await self.client.checkpointsDelete(CheckpointDeleteRequest(computerId: computerId, checkpointId: checkpointId)) }
    }

    @discardableResult
    func perform<T>(_ label: String, _ action: () async throws -> T) async -> Bool {
        actionError = nil
        do {
            let accepted = try await action()
            let jobId: String? = if let job = accepted as? ComputerJob { job.jobId }
                else if let job = accepted as? ComputerCreateResult { job.jobId }
                else if let job = accepted as? SiloWireJobStartResult { job.jobId }
                else { nil }
            guard let jobId else { return false }
            jobActions[jobId] = label
            let outcome = try await waitForFinish(jobId)
            presentJobOutcome(outcome, action: label)
            let hasUnresolvedUploadOutcome = label == "Upload files"
                && (uploadConflicts.contains { $0.jobId == jobId } || uploadNotices.contains { $0.jobId == jobId })
            if outcome.error == nil && !hasUnresolvedUploadOutcome {
                try await acknowledgeConsumedJob(jobId)
                uploadContexts[jobId] = nil
            }
            let uploadWasCancelled = label == "Upload files" && uploadNotices.contains { $0.jobId == jobId }
            return outcome.error == nil && !hasUnresolvedUploadOutcome && !uploadWasCancelled
        }
        catch { actionError = error.localizedDescription; return false }
    }

    func inventoryForCreation() async throws -> ComputerInventory {
        let revision = stateRevision
        let latest = try await client.computersList(deviceId: nil)
        guard stateRevision == revision else { return inventory ?? latest }
        inventory = latest
        stateRevision &+= 1
        error = nil
        return latest
    }

    func reserveName(_ base: String, in inventory: ComputerInventory) -> String {
        let existing = inventory.allComputers.map(\.name) + Array(reservedNames)
        let name = ComputerName.unique(base, among: existing)
        reservedNames.insert(name.lowercased())
        return name
    }

    func reserveForkName(from sourceName: String, in inventory: ComputerInventory) -> String {
        let existing = inventory.allComputers.map(\.name) + Array(reservedNames)
        let name = ComputerName.uniqueFork(from: sourceName, among: existing)
        reservedNames.insert(name.lowercased())
        return name
    }

    func acknowledgePresentedJob(_ jobId: String) async {
        guard jobAwaitingAcknowledgement == jobId else { return }
        do {
            try await client.operationsJobAcknowledge(jobId: jobId, deviceId: nil)
            finishedJobs[jobId] = nil
            jobActions[jobId] = nil
            jobAwaitingAcknowledgement = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    func acknowledgeConsumedJob(_ jobId: String) async throws {
        try await client.operationsJobAcknowledge(jobId: jobId, deviceId: nil)
        finishedJobs[jobId] = nil
        jobActions[jobId] = nil
        if jobAwaitingAcknowledgement == jobId { jobAwaitingAcknowledgement = nil }
    }

    var pendingUploadConflict: ComputerUploadConflict? { uploadConflicts.first }

    func uploadConflict(for computerId: String) -> ComputerUploadConflict? {
        uploadConflicts.first { $0.computerId == computerId }
    }

    func uploadNotice(for computerId: String) -> ComputerUploadNotice? {
        uploadNotices.first { $0.computerId == computerId }
    }

    func cancelJob(_ jobId: String) async {
        actionError = nil
        do {
            try await client.operationsCancel(jobId: jobId, deviceId: nil)
            let revision = stateRevision
            let latest = try await client.operationsList(deviceId: nil)
            if stateRevision == revision {
                operationQueue = latest
                stateRevision &+= 1
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func receive(_ delivery: EngineEventDelivery, stream: UUID) {
        guard wantsConnection, eventStreamID == stream else { return }
        switch delivery {
        case .disconnected(let reason):
            error = reason
        case .reconnected:
            hasSequence = false
            beginRecovery(invalidated: true)
        case .sequenceAdvanced(let next):
            if hasSequence {
                guard next > sequence else { return }
                if next != sequence &+ 1 {
                    sequence = next
                    beginRecovery(invalidated: true)
                    return
                }
            } else {
                hasSequence = true
            }
            sequence = next
        case .event(let next, let event):
            if hasSequence {
                guard next > sequence else { return }
                if next != sequence &+ 1 {
                    sequence = next
                    bufferedEvents.append((next, event))
                    beginRecovery(invalidated: true)
                    return
                }
            } else {
                hasSequence = true
            }
            sequence = next
            if isRecovering {
                bufferedEvents.append((next, event))
                return
            }
            apply(event)
        }
    }

    private func apply(_ event: EngineEvent) {
        switch event {
        case .computersChanged(let change, let deviceId):
            stateRevision &+= 1
            if let deviceId, let index = remoteOwnerInventories.firstIndex(where: { $0.deviceId == deviceId }) {
                remoteOwnerInventories[index].inventory = remoteOwnerInventories[index].inventory.applying(change)
            } else if let inventory {
                self.inventory = inventory.applying(change)
            }
            error = nil
        case .connectionsDevicesChanged:
            Task { @MainActor [weak self] in await self?.refreshRemoteOwnerInventories() }
        case .checkpointsChanged(let change):
            stateRevision &+= 1
            if let inventory {
                self.inventory = inventory.applying(ComputersChangedPayload(linux: change.linux, macos: change.macos))
            }
            if let usage = change.usage { checkpointUsage.merge(usage) { _, next in next } }
        case .operationsQueueChanged(let queue):
            stateRevision &+= 1
            operationQueue = queue
        case .jobProgress(let progress):
            activeJob = progress
        case .jobFinished(let result):
            recordFinished(result)
        case .guestFilesChanged:
            break
        case .viewerPage(let page):
            viewerScripts[page.connectionId] = page.script
        case .settingsChanged(let snapshot):
            engineSettings = snapshot
        case .exportsChanged(let snapshot):
            exportState = snapshot
        }
    }

    private func recordFinished(_ result: OperationJobFinished) {
        finishedJobs[result.jobId] = result
        if activeJob?.jobId == result.jobId { activeJob = nil }
        if result.error?.code == "cancelled" {
            jobAwaitingAcknowledgement = result.jobId
            return
        }
        if let action = jobActions[result.jobId] {
            presentJobOutcome(result, action: action)
        } else if let failure = result.error {
            presentJobOutcome(result, action: "Computer operation")
            actionError = "Computer operation failed: \(failure.message)"
        }
    }

    func presentJobOutcome(_ result: OperationJobFinished, action: String) {
        guard presentedJobOutcomes.insert(result.jobId).inserted else { return }
        if action == "Upload files", result.error == nil, let upload = decodeUploadOutcome(result.result) {
            switch upload.status {
            case .conflict:
                if let context = uploadContexts[result.jobId] {
                    uploadConflicts.removeAll { $0.jobId == result.jobId }
                    uploadConflicts.append(ComputerUploadConflict(jobId: result.jobId,
                        computerId: context.computerId, directory: context.directory, paths: context.paths,
                        names: upload.names ?? []))
                    actionError = nil
                } else {
                    if let names = upload.names, !names.isEmpty {
                        actionError = "Upload paused because these files already exist: \(names.joined(separator: ", "))."
                    } else {
                        actionError = "Upload paused because files with those names already exist."
                    }
                }
            case .cancelled:
                if let context = uploadContexts[result.jobId] {
                    uploadNotices.removeAll { $0.jobId == result.jobId }
                    uploadNotices.append(ComputerUploadNotice(jobId: result.jobId,
                        computerId: context.computerId, message: "Upload cancelled."))
                    actionError = nil
                } else {
                    actionError = "Upload cancelled."
                }
            case .done:
                break
            }
            return
        }
        guard let failure = result.error else { return }
        actionError = "\(action) failed: \(failure.message)"
        jobAwaitingAcknowledgement = result.jobId
    }

    private func decodeUploadOutcome(_ value: JSONValue?) -> SiloWireUploadOutcome? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(SiloWireUploadOutcome.self, from: data)
    }

    func waitForFinish(_ jobId: String) async throws -> OperationJobFinished {
        while true {
            if let finished = finishedJobs[jobId] { return finished }
            let snapshot = try await client.operationsJobGet(jobId: jobId, deviceId: nil)
            if snapshot.state == .finished {
                let result = snapshot.finishedEvent
                recordFinished(result)
                return result
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func beginRecovery(invalidated: Bool) {
        if invalidated { recoveryRevision &+= 1 }
        isRecovering = true
        guard recoveryTask == nil else { return }
        let recoveryID = UUID()
        self.recoveryID = recoveryID
        recoveryTask = Task { @MainActor [weak self] in
            await self?.recoverDomainState(id: recoveryID)
        }
    }

    private func recoverDomainState(id: UUID) async {
        defer {
            if recoveryID == id {
                isRecovering = false
                recoveryTask = nil
                recoveryID = nil
            }
        }
        while recoveryID == id, wantsConnection, subscription != nil, !Task.isCancelled {
            let revision = recoveryRevision
            do {
                let inventorySnapshot = try await client.computersList(deviceId: nil)
                guard recoveryID == id, wantsConnection, subscription != nil, !Task.isCancelled else { return }
                let operationsSnapshot = try await client.operationsList(deviceId: nil)
                guard recoveryID == id, wantsConnection, subscription != nil, !Task.isCancelled else { return }
                let settingsSnapshot: SiloWireSettingsSnapshot?
                if engineSettings == nil { settingsSnapshot = nil }
                else { settingsSnapshot = try? await client.invoke(SiloGeneratedMethods.settingsRead(SiloWireEmptyParams())) }
                guard recoveryID == id, wantsConnection, subscription != nil, !Task.isCancelled else { return }
                guard revision == recoveryRevision else { continue }

                inventory = inventorySnapshot
                operationQueue = operationsSnapshot
                if let settingsSnapshot { engineSettings = settingsSnapshot }
                stateRevision &+= 1
                error = nil
                let events = bufferedEvents.sorted { $0.0 < $1.0 }
                bufferedEvents.removeAll()
                events.forEach { apply($0.1) }
                await recoverOutstandingJobs(operationsSnapshot.unacknowledgedJobIds)
                guard recoveryID == id, wantsConnection, subscription != nil, !Task.isCancelled else { return }
                guard revision == recoveryRevision else { continue }
                let lateEvents = bufferedEvents.sorted { $0.0 < $1.0 }
                bufferedEvents.removeAll()
                lateEvents.forEach { apply($0.1) }
                if revision == recoveryRevision { return }
            } catch {
                self.error = error.localizedDescription
                if revision == recoveryRevision { return }
            }
        }
    }

    private func recoverOutstandingJobs(_ jobIds: [String]) async {
        for jobId in jobIds {
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await client.operationsJobGet(jobId: jobId, deviceId: nil)
                guard snapshot.state == .finished else { continue }
                recordFinished(snapshot.finishedEvent)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func waitForRecovery() async {
        await recoveryTask?.value
    }

    func waitUntilStopped(_ computerIds: Set<String>, timeout: Duration = .seconds(20)) async throws {
        guard !computerIds.isEmpty else { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            var allStopped = true
            for id in computerIds {
                guard let row = inventory?.computer(id) else { continue }
                switch row.displayState {
                case .stopped:
                    continue
                case .stopping:
                    allStopped = false
                default:
                    let detail = row.detail ?? "The stop request for \(row.name) was refused; it is still \(row.displayState.title.lowercased())."
                    throw EngineClientError.jobFailed(detail)
                }
            }
            if allStopped { return }
            guard clock.now < deadline else {
                throw EngineClientError.jobFailed("The computers did not stop before the deadline. You can keep Fjord open and try again.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
