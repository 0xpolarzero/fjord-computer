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
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var actionError: String?
    private(set) var activeJob: OperationJobProgress?
    private(set) var finishedJobs: [String: OperationJobFinished] = [:]
    private(set) var quitPrompt: ComputerQuitPrompt?
    private(set) var quitError: String?
    private(set) var isQuitWorking = false

    @ObservationIgnored private var subscription: String?
    @ObservationIgnored private var quitHandler: ((ComputerQuitChoice) -> Void)?
    @ObservationIgnored private var finishWaiters: [String: [CheckedContinuation<OperationJobFinished, Never>]] = [:]
    @ObservationIgnored private var connectionTask: Task<Void, Error>?
    @ObservationIgnored private var connectionAttemptID: UUID?
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
                }
            }
            let firstRead = try await self.client.computersList(deviceId: nil)
            if self.inventory == nil { self.inventory = firstRead }
            let newSubscription = try await self.client.eventsSubscribe(events: ["computers.*", "operations.*"]) { [weak self] event in
                self?.receive(event)
            }
            guard self.wantsConnection, self.connectionAttemptID == attemptID else {
                await self.client.eventsUnsubscribe(subscription: newSubscription)
                return
            }
            self.subscription = newSubscription
            // Close the read/subscribe race; sequenced state updates prevent a stale read from winning.
            let secondRead = try await self.client.computersList(deviceId: nil)
            guard self.wantsConnection, self.connectionAttemptID == attemptID else { return }
            self.inventory = secondRead
            self.error = nil
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
        connectionTask?.cancel()
        connectionTask = nil
        isLoading = false
        guard let subscription else { return }
        self.subscription = nil
        await client.eventsUnsubscribe(subscription: subscription)
    }

    func refresh() async throws {
        inventory = try await client.computersList(deviceId: nil)
        error = nil
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
                let finished = await waitForFinish(job.jobId)
                if let failure = finished.error { throw EngineClientError.jobFailed(failure.message) }
            }
            try await waitUntilStopped(Set(prompt.runningComputers.map(\.computerId)))
            try await client.engineDisconnect()
        }
    }

    func start(_ computerId: String) async { await perform { try await self.client.computersStart(ComputerReference(computerId: computerId)) } }
    func stop(_ computerId: String) async { await perform { try await self.client.computersStop(ComputerReference(computerId: computerId)) } }
    func forceStop(_ computerId: String) async {
        actionError = nil
        do { try await client.computersForceStop(ComputerReference(computerId: computerId)) }
        catch { actionError = error.localizedDescription }
    }
    func delete(_ computerId: String) async {
        await perform { try await self.client.computersDelete(ComputerDeleteRequest(computerId: computerId)) }
    }
    func showDisplay(_ computerId: String) async {
        actionError = nil
        do { try await client.displayShow(ComputerReference(computerId: computerId)) }
        catch { actionError = error.localizedDescription }
    }
    func createCheckpoint(for computerId: String) async {
        let name = "Manual checkpoint · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))"
        await perform { try await self.client.checkpointsCreate(CheckpointCreateRequest(computerId: computerId, name: name, kind: .manual)) }
        await loadCheckpoints(for: computerId)
    }
    func createLinuxComputer() async {
        let id = UUID().uuidString.lowercased()
        let configuration = ComputerConfiguration(id: id, name: "linux-new", cpus: 4, maxCPUs: 12,
                                                  memoryGiB: 8, maxMemoryGiB: 32, workspaceStorageGiB: 64,
                                                  runtimeStorageGiB: 32)
        await perform { try await self.client.computersCreate(.linux(configuration, requestId: id)) }
    }
    func createMacosComputer() async {
        let request = MacosComputerCreateRequest(name: "macos-new", cpus: 4, memoryGiB: 8, diskGiB: 64)
        await perform { try await self.client.computersCreate(.macos(request)) }
    }
    func restoreCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform { try await self.client.checkpointsRestore(CheckpointRestoreRequest(computerId: computerId, checkpointId: checkpointId)) }
    }
    func forkCheckpoint(_ checkpointId: String, computerId: String, computerName: String) async {
        await perform {
            try await self.client.checkpointsFork(CheckpointForkRequest(computerId: computerId, checkpointId: checkpointId,
                                                                        newName: "\(computerName)-fork"))
        }
    }
    func deleteCheckpoint(_ checkpointId: String, computerId: String) async {
        await perform { try await self.client.checkpointsDelete(CheckpointDeleteRequest(computerId: computerId, checkpointId: checkpointId)) }
        await loadCheckpoints(for: computerId)
    }

    private func perform<T>(_ action: () async throws -> T) async {
        actionError = nil
        do { _ = try await action() }
        catch { actionError = error.localizedDescription }
    }

    private func receive(_ event: EngineEvent) {
        switch event {
        case .computersChanged(let change):
            if let inventory { self.inventory = inventory.applying(change) }
            error = nil
        case .jobProgress(let progress):
            activeJob = progress
        case .jobFinished(let result):
            finishedJobs[result.jobId] = result
            if activeJob?.jobId == result.jobId { activeJob = nil }
            let waiters = finishWaiters.removeValue(forKey: result.jobId) ?? []
            waiters.forEach { $0.resume(returning: result) }
        }
    }

    private func waitForFinish(_ jobId: String) async -> OperationJobFinished {
        if let finished = finishedJobs[jobId] { return finished }
        return await withCheckedContinuation { continuation in
            finishWaiters[jobId, default: []].append(continuation)
        }
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
