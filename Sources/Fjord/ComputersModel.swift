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

@MainActor
@Observable
final class ComputersModel {
    private let client: any EngineClient
    private(set) var inventory: ComputerInventory?
    private(set) var checkpointUsage: [String: CheckpointUsage] = [:]
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var actionError: String?
    private(set) var activeJob: OperationJobProgress?
    private(set) var finishedJobs: [String: OperationJobFinished] = [:]
    private(set) var operationQueue = OperationsList.empty
    private(set) var jobAwaitingAcknowledgement: String?
    private(set) var quitPrompt: ComputerQuitPrompt?
    private(set) var quitError: String?
    private(set) var isQuitWorking = false

    @ObservationIgnored private var subscription: String?
    @ObservationIgnored private var quitHandler: ((ComputerQuitChoice) -> Void)?
    @ObservationIgnored private var jobActions: [String: String] = [:]
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
    @ObservationIgnored private var isRecovering = false
    @ObservationIgnored private var wantsConnection = false

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
            let newSubscription = try await self.client.eventsSubscribe(events: ["computers.*", "checkpoints.*", "operations.*"]) { [weak self] event in
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
        Task { [weak self] in
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

    func resolveQuit(_ choice: ComputerQuitChoice, prompt: ComputerQuitPrompt) async throws {
        switch choice {
        case .cancel:
            return
        case .keepRunning:
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
            try await client.engineDisconnect()
        }
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
        let expected: ComputerConfiguration? = if case .linux(let computer) = row { computer.configuration } else { nil }
        await perform("Delete") { try await self.client.computersDelete(ComputerDeleteRequest(computerId: computerId, expected: expected)) }
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
    func createLinuxComputer() async {
        let id = UUID().uuidString.lowercased()
        let configuration = ComputerConfiguration(id: id, name: "linux-new", cpus: 4, maxCPUs: 12,
                                                  memoryGiB: 8, maxMemoryGiB: 32, workspaceStorageGiB: 64,
                                                  runtimeStorageGiB: 32)
        await perform("Create Linux computer") { try await self.client.computersCreate(.linux(configuration, requestId: id)) }
    }
    func createMacosComputer() async {
        let request = MacosComputerCreateRequest(name: "macos-new", cpus: 4, memoryGiB: 8, diskGiB: 64)
        await perform("Create macOS computer") { try await self.client.computersCreate(.macos(request)) }
    }
    func restoreCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform("Restore checkpoint") { try await self.client.checkpointsRestore(CheckpointRestoreRequest(computerId: computerId, checkpointId: checkpointId)) }
    }
    func forkCheckpoint(_ checkpointId: String, computerId: String, computerName: String) async {
        await perform("Fork checkpoint") {
            try await self.client.checkpointsFork(CheckpointForkRequest(computerId: computerId, checkpointId: checkpointId,
                                                                        newName: "\(computerName)-fork"))
        }
    }
    func deleteCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform("Delete checkpoint") { try await self.client.checkpointsDelete(CheckpointDeleteRequest(computerId: computerId, checkpointId: checkpointId)) }
    }

    private func perform<T>(_ label: String, _ action: () async throws -> T) async {
        actionError = nil
        do {
            let accepted = try await action()
            let jobId: String? = if let job = accepted as? ComputerJob { job.jobId }
                else if let job = accepted as? ComputerCreateResult { job.jobId }
                else { nil }
            guard let jobId else { return }
            jobActions[jobId] = label
            presentJobOutcome(try await waitForFinish(jobId), action: label)
        }
        catch { actionError = error.localizedDescription }
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

    private func receive(_ delivery: EngineEventDelivery, stream: UUID) {
        guard wantsConnection, eventStreamID == stream else { return }
        switch delivery {
        case .disconnected(let reason):
            error = reason
        case .reconnected:
            hasSequence = false
            beginRecovery(invalidated: true)
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
        case .computersChanged(let change):
            stateRevision &+= 1
            if let inventory { self.inventory = inventory.applying(change) }
            error = nil
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
        }
    }

    private func recordFinished(_ result: OperationJobFinished) {
        finishedJobs[result.jobId] = result
        if activeJob?.jobId == result.jobId { activeJob = nil }
        if let action = jobActions[result.jobId] {
            presentJobOutcome(result, action: action)
        } else if let failure = result.error {
            presentJobOutcome(result, action: "Computer operation")
            actionError = "Computer operation failed: \(failure.message)"
        }
    }

    private func presentJobOutcome(_ result: OperationJobFinished, action: String) {
        guard presentedJobOutcomes.insert(result.jobId).inserted else { return }
        guard let failure = result.error else { return }
        actionError = "\(action) failed: \(failure.message)"
        jobAwaitingAcknowledgement = result.jobId
    }

    private func waitForFinish(_ jobId: String) async throws -> OperationJobFinished {
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
                guard revision == recoveryRevision else { continue }

                inventory = inventorySnapshot
                operationQueue = operationsSnapshot
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
