import CryptoKit
import Foundation

/// App-lifetime guest observers. A tool invocation can finish while a Desktop SSH session is still waiting for the person
/// to send; this object keeps file watches alive and reconciles them with the controller's Desktop metadata.
@MainActor final class GuestRouterRuntime {
    static let shared = GuestRouterRuntime()

    private weak var store: Store?
    private var clients: [String: any GuestClient] = [:]
    private var computers: [String: GuestReference] = [:]
    private var generatedClient: SiloGuestClient?
    private var watchers: [String: Task<Void, Never>] = [:]
    private var leaseChecks: [String: Task<Void, Never>] = [:]
    private var evidence: [String: [GuestSessionEvidence]] = [:]
    private var activeStartKeys: Set<String> = []
    private var operationTails: [String: Task<Void, Never>] = [:]

    private init() {}

    func reserveStart(projectID: UUID, location: SessionLocation, prompt: String) -> String? {
        let material = "\(projectID.uuidString)|\(location.key)|\(prompt)"
        let key = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        guard activeStartKeys.insert(key).inserted else { return nil }
        return key
    }

    func releaseStart(_ key: String) { activeStartKeys.remove(key) }

    /// Makes the target visible to Router-off before any guest file or command can be changed.
    func registerInstallationTarget(store: Store, client: any GuestClient, computer: GuestReference) {
        self.store = store
        clients[computer.key] = client
        computers[computer.key] = computer
    }

    func prepareDesktopStart(client: any GuestClient, placement: ProjectPlacement, project: RunsOnProject,
                            prompt: String, computerName: String, settings: ClaudeSSHSettings,
                            store: Store, computer: GuestReference, generation: UInt64) async throws -> GuestDesktopStart.Prepared {
        registerInstallationTarget(store: store, client: client, computer: computer)
        let allowed: @MainActor @Sendable () -> Bool = { [weak store] in
            guard let store else { return false }
            return store.routerOn && store.routerGeneration == generation
        }
        return try await serialized(computer) { [self] in
            guard allowed() else { throw GuestRouterInstaller.Failure.routerTurnedOff }
            try await applyPendingDisableNow(computer: computer, client: client)
            guard allowed() else { throw GuestRouterInstaller.Failure.routerTurnedOff }
            return try await GuestDesktopStart.prepare(client: client, placement: placement, project: project,
                prompt: prompt, computerName: computerName, settings: settings, activationAllowed: allowed)
        }
    }

    func startWatching(store: Store, client: any GuestClient, computer: GuestReference) async throws {
        registerInstallationTarget(store: store, client: client, computer: computer)
        guard watchers[computer.key] == nil else { return }
        let account = try await client.account(for: computer)
        let paths = try GuestRouterPaths(home: account.home)
        var watchedPaths = [paths.forms, paths.presence, paths.registry]
        if (try? await client.filesList(computer: computer, path: paths.projects)) != nil {
            watchedPaths.append(paths.projects)
        }
        let watch = try await client.filesWatch(computer: computer, paths: watchedPaths)
        try await refresh(computer: computer, client: client, paths: paths)
        watchers[computer.key] = Task { [weak self, weak store] in
            for await _ in watch.events {
                guard !Task.isCancelled, let self, let store else { return }
                do { try await self.refresh(computer: computer, client: client, paths: paths) }
                catch {
                    self.markGuestExecutionInaccessible(computer)
                    store.routerHookError = "Guest Router refresh failed on \(computer.computerId): \(error.localizedDescription)"
                }
            }
        }
        leaseChecks[computer.key] = Task { [weak self, weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let store else { return }
                do { try await self.refresh(computer: computer, client: client, paths: paths) }
                catch {
                    self.markGuestExecutionInaccessible(computer)
                    store.routerHookError = "Guest Router lease check failed on \(computer.computerId): \(error.localizedDescription)"
                }
            }
        }
    }

    func stopAll() {
        for task in watchers.values { task.cancel() }
        for task in leaseChecks.values { task.cancel() }
        watchers.removeAll()
        leaseChecks.removeAll()
        clients.removeAll()
        computers.removeAll()
        evidence.removeAll()
        guard let store else { return }
        store.routerFormsLoaded = false
        var state = store.router
        state.guestPendingForms = []
        store.router = state
    }

    /// Restores guest clients and watches from saved placements and matched starts after the local Router starts.
    func rehydrate(store: Store, client override: (any GuestClient)? = nil) async {
        self.store = store
        let router = store.router
        var locations = router.pendingGuestDisables
        if store.routerOn {
            locations += router.runsOnProjects.map { $0.placement.location }
            locations += router.pendingDesktopStarts.map(\.location)
            locations += router.guestRelayDeliveries.map(\.location)
            locations += router.guestPendingForms.map(\.location)
        }
        for location in Set(locations).sorted(by: { $0.key < $1.key }) {
            guard case .computer(let deviceId, let computerId) = location else { continue }
            let computer = GuestReference(deviceId: deviceId, computerId: computerId)
            guard let client = override ?? guestClient(for: location) else { continue }
            registerInstallationTarget(store: store, client: client, computer: computer)
            if store.routerOn {
                do { try await startWatching(store: store, client: client, computer: computer) }
                catch {
                    markGuestExecutionInaccessible(computer)
                    store.routerHookError = "Guest Router reconnect is pending for \(computer.computerId): \(error.localizedDescription)"
                }
            } else if store.router.pendingGuestDisables.contains(location) {
                do { try await applyPendingDisable(computer: computer, client: client) }
                catch { store.routerHookError = "Guest Router disable is pending for \(computer.computerId): \(error.localizedDescription)" }
            }
        }
    }

    func disableAll() {
        let targets = computers.compactMap { key, computer -> (GuestReference, any GuestClient)? in
            clients[key].map { (computer, $0) }
        }
        if let store {
            var state = store.router
            let knownLocations = state.runsOnProjects.map { $0.placement.location }
                + state.pendingDesktopStarts.map(\.location)
                + targets.map { SessionLocation.computer(deviceId: $0.0.deviceId, computerId: $0.0.computerId) }
            for location in Set(knownLocations) where location != .thisMac {
                if !state.pendingGuestDisables.contains(location) { state.pendingGuestDisables.append(location) }
            }
            store.router = state
        }
        stopAll()
        Task { @MainActor [weak self, weak store] in
            for (computer, client) in targets {
                do {
                    guard let self else { return }
                    try await self.serialized(computer) { [self] in
                        try await GuestRouterInstaller(client: client).disable(computer: computer)
                        self.clearPendingDisable(computer)
                    }
                } catch {
                    store?.routerHookError = "Guest Router disable is pending for \(computer.computerId): \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reconciles a previously failed Router-off while the guest is reachable, before a new install can begin.
    func applyPendingDisable(computer: GuestReference, client: any GuestClient) async throws {
        try await serialized(computer) { [self] in
            try await applyPendingDisableNow(computer: computer, client: client)
        }
    }

    private func applyPendingDisableNow(computer: GuestReference, client: any GuestClient) async throws {
        let location = SessionLocation.computer(deviceId: computer.deviceId, computerId: computer.computerId)
        guard store?.router.pendingGuestDisables.contains(location) == true else { return }
        try await GuestRouterInstaller(client: client).disable(computer: computer)
        clearPendingDisable(computer)
    }

    private func serialized<T: Sendable>(_ computer: GuestReference,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        let key = computer.key
        let previous = operationTails[key]
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        operationTails[key] = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }

    func reconcileDesktopMetadata() {
        guard let store else { return }
        for pending in store.router.pendingDesktopStarts where pending.state == .readyInClaude {
            let candidates = store.claudeSessions.values.compactMap { session -> DesktopSSHSession? in
                guard !session.isArchived, let alias = session.sshHost, let folder = session.folder, folder == pending.folder,
                      session.lastActivity >= pending.openedAt else { return nil }
                return DesktopSSHSession(id: session.id, alias: alias, folder: folder)
            }
            _ = store.reconcileDesktopStart(pending.id, desktop: candidates, evidence: evidence[pending.location.key] ?? [])
        }
    }

    func selectableDesktopSessions(for pendingID: UUID) -> [ClaudeSession] {
        guard let store, let pending = store.router.pendingDesktopStarts.first(where: {
            $0.id == pendingID && $0.state == .readyInClaude
        }) else { return [] }
        let claimed = Set(store.router.pendingDesktopStarts.compactMap { start in
            start.state == .matched ? start.desktopSessionID : nil
        })
        return store.claudeSessions.values.filter { session in
            !session.isArchived && !claimed.contains(session.id) && session.sshHost == pending.alias
                && session.folder == pending.folder && session.lastActivity >= pending.openedAt
        }.sorted { $0.lastActivity > $1.lastActivity }
    }

    @discardableResult
    func selectDesktopSession(_ desktopSessionID: String, for pendingID: UUID) -> Bool {
        guard let store, let pending = store.router.pendingDesktopStarts.first(where: {
            $0.id == pendingID && $0.state == .readyInClaude
        }), let session = selectableDesktopSessions(for: pendingID).first(where: { $0.id == desktopSessionID }),
              let alias = session.sshHost, let folder = session.folder else { return false }
        let desktop = DesktopSSHSession(id: session.id, alias: alias, folder: folder)
        return store.reconcileDesktopStart(pending.id, desktop: [desktop],
            evidence: evidence[pending.location.key] ?? [], allowEditedPrompt: true)
    }

    func answer(_ guestForm: GuestPendingForm, answers: [String: String], cardID: String) async throws {
        guard let store, let client = clients[guestForm.computer.key] else { throw FormWriter.Cancelled() }
        let generation = store.routerGeneration
        try await GuestForms(client: client).answer(guestForm, answers: answers) { [weak store] in
            guard let store, store.routerOn, store.routerGeneration == generation,
                  let card = store.router.cards.first(where: { $0.id == cardID }), card.isOpen,
                  let current = store.guestPendingForm(for: card) else { return false }
            return current.form.id == guestForm.form.id && current.form.toolUseID == guestForm.form.toolUseID
        }
    }

    func answer(_ guestForm: GuestPendingForm, plan decision: PendingForm.PlanDecision, cardID: String) async throws {
        guard let store, let client = clients[guestForm.computer.key] else { throw FormWriter.Cancelled() }
        let generation = store.routerGeneration
        try await GuestForms(client: client).answer(guestForm, plan: decision) { [weak store] in
            guard let store, store.routerOn, store.routerGeneration == generation,
                  let card = store.router.cards.first(where: { $0.id == cardID }), card.isOpen,
                  let current = store.guestPendingForm(for: card) else { return false }
            return current.form.id == guestForm.form.id && current.form.toolUseID == guestForm.form.toolUseID
        }
    }

    func deliver(_ signedText: String, to cliSessionID: String, computer: GuestReference,
                 decisionID: UUID? = nil, hostSessionID: String? = nil, body: String? = nil,
                 gate: (@MainActor @Sendable () -> String?)? = nil) async throws -> String {
        guard let store, let client = clients[computer.key] else { throw GuestClientFailure.notRunning(computer.key) }
        let callback: @MainActor @Sendable (GuestRelayRecord) async -> Void = { [weak store] record in
            store?.saveGuestRelayState(record)
        }
        return try await GuestRelayInbox(client: client, onState: callback)
            .deliver(signedText, to: cliSessionID, computer: computer, decisionID: decisionID,
                     hostSessionID: hostSessionID, body: body, gate: gate)
    }

    /// Reconciles the exact signed payload saved before its first guest inbox write.
    func retry(_ record: GuestRelayRecord) async throws -> String {
        guard record.state == .inFlight || record.state == .unconfirmed,
              let signedPayload = record.signedPayload,
              case .computer(let deviceId, let computerId) = record.location,
              let store, let client = clients[GuestReference(deviceId: deviceId, computerId: computerId).key] else {
            throw GuestClientFailure.unavailable("This guest delivery has no retryable payload or connected client")
        }
        let computer = GuestReference(deviceId: deviceId, computerId: computerId)
        let callback: @MainActor @Sendable (GuestRelayRecord) async -> Void = { [weak store] updated in
            store?.saveGuestRelayState(updated)
        }
        let gate: @MainActor @Sendable () -> String? = { [weak store] in
            store?.routerOn == true ? nil : "The Router is off"
        }
        return try await GuestRelayInbox(client: client, onState: callback)
            .deliver(signedPayload, to: record.sessionID, computer: computer, now: record.createdAt,
                     decisionID: record.decisionID, hostSessionID: record.hostSessionID, body: record.body, gate: gate)
    }

    func location(for desktopSessionID: String) -> SessionLocation? {
        store?.router.pendingDesktopStarts.first { $0.desktopSessionID == desktopSessionID && $0.state == .matched }?.location
    }

    func guestSessionID(for desktopSessionID: String) -> String? {
        store?.router.pendingDesktopStarts.first { $0.desktopSessionID == desktopSessionID && $0.state == .matched }?.guestSessionID
    }

    func location(forGuestSessionID cliSessionID: String) -> SessionLocation? {
        store?.router.pendingDesktopStarts.first { $0.guestSessionID == cliSessionID && $0.state == .matched }?.location
    }

    func supportsAbort(forGuestSessionID cliSessionID: String) -> Bool {
        guard let pending = store?.router.pendingDesktopStarts.first(where: {
            $0.guestSessionID == cliSessionID && $0.state == .matched
        }), let desktopID = pending.desktopSessionID else { return false }
        return evidence[pending.location.key]?.contains {
            $0.hostSessionID == desktopID && $0.cliSessionID == cliSessionID
                && $0.capabilities.contains(ClaudePlugin.abortCapability)
        } == true
    }

    func guestReference(for desktopSessionID: String) -> GuestReference? {
        guard case .computer(let deviceId, let computerId)? = location(for: desktopSessionID) else { return nil }
        return GuestReference(deviceId: deviceId, computerId: computerId)
    }

    func guestClient(for desktopSessionID: String) -> (any GuestClient)? {
        guard let reference = guestReference(for: desktopSessionID) else { return nil }
        return clients[reference.key]
    }

    func guestClient(for location: SessionLocation) -> (any GuestClient)? {
        guard case .computer(let deviceId, let computerId) = location else { return nil }
        let computer = GuestReference(deviceId: deviceId, computerId: computerId)
        if let client = clients[computer.key] { return client }
        guard let store, let engine = store.engineClient as? SocketEngineClient else { return nil }
        let client = generatedClient ?? SiloGuestClient(engine: engine)
        generatedClient = client
        registerInstallationTarget(store: store, client: client, computer: computer)
        return client
    }

    func guestFolder(for desktopSessionID: String) -> String? {
        store?.router.pendingDesktopStarts.first {
            $0.desktopSessionID == desktopSessionID && $0.state == .matched
        }?.folder
    }

    func transcript(for desktopSessionID: String) -> GuestTranscriptSnapshot? {
        guard let pending = store?.router.pendingDesktopStarts.first(where: {
            $0.desktopSessionID == desktopSessionID && $0.state == .matched
        }), let cli = pending.guestSessionID else { return nil }
        return evidence[pending.location.key]?.first { $0.hostSessionID == desktopSessionID && $0.cliSessionID == cli }?.transcript
    }

    private func refresh(computer: GuestReference, client: any GuestClient, paths: GuestRouterPaths) async throws {
        guard let store else { return }
        let forms = try await GuestForms(client: client).read(computer: computer, paths: paths)
        let current = forms.values.sorted { $0.form.id < $1.form.id }
        if current != store.router.guestPendingForms {
            var state = store.router
            state.guestPendingForms.removeAll { $0.computer == computer }
            state.guestPendingForms.append(contentsOf: current)
            store.router = state
        }
        store.routerFormsLoaded = true
        evidence[computer.key] = try await GuestSessionObserver(client: client).read(computer: computer, paths: paths)
        reconcileDesktopMetadata()
        applyGuestEvidenceToStore()
    }

    private func applyGuestEvidenceToStore() {
        guard let store else { return }
        var sessions = store.claudeSessions
        var activities = store.claudeActivity
        var tasks = store.claudeTasks
        var changedSessions = false
        var changedActivities = false
        var changedTasks = false
        for pending in store.router.pendingDesktopStarts where pending.state == .matched {
            guard let desktopID = pending.desktopSessionID, let cli = pending.guestSessionID else { continue }
            guard let evidence = evidence[pending.location.key]?.first(where: {
                      $0.hostSessionID == desktopID && $0.cliSessionID == cli
                  }) else {
                store.guestExecutionStates[desktopID] = GuestExecutionState(cliSessionID: cli,
                    availability: .dead, isRunning: false, activity: nil)
                if var session = sessions[desktopID], session.running || session.cliID != cli {
                    session.running = false
                    session.cliID = cli
                    sessions[desktopID] = session
                    changedSessions = true
                }
                if activities[desktopID] != nil { activities[desktopID] = nil; changedActivities = true }
                if tasks[desktopID] != nil { tasks[desktopID] = nil; changedTasks = true }
                continue
            }
            guard let transcript = evidence.transcript else {
                store.guestExecutionStates[desktopID] = inaccessibleState(for: desktopID, cliID: cli, in: store)
                continue
            }
            let activity = transcript.activity
            let running = !Claude.transcriptEndedTurn(tail: transcript.tail)
            store.guestExecutionStates[desktopID] = GuestExecutionState(cliSessionID: cli,
                availability: .live, isRunning: running, activity: activity)
            if var session = sessions[desktopID] {
                if session.running != running || session.cliID != cli {
                    session.running = running
                    session.cliID = cli
                    sessions[desktopID] = session
                    changedSessions = true
                }
            }
            if let activity {
                if activities[desktopID] != activity { activities[desktopID] = activity; changedActivities = true }
            } else if activities[desktopID] != nil {
                activities[desktopID] = nil
                changedActivities = true
            }
        }
        if changedSessions { store.claudeSessions = sessions }
        if changedActivities { store.claudeActivity = activities }
        if changedTasks { store.claudeTasks = tasks }
        if changedSessions || changedActivities || changedTasks { store.feedRouter() }
    }

    private func markGuestExecutionInaccessible(_ computer: GuestReference) {
        guard let store else { return }
        for pending in store.router.pendingDesktopStarts where pending.state == .matched && pending.location.key == computer.key {
            guard let desktopID = pending.desktopSessionID, let cliID = pending.guestSessionID else { continue }
            store.guestExecutionStates[desktopID] = inaccessibleState(for: desktopID, cliID: cliID, in: store)
        }
    }

    private func inaccessibleState(for desktopID: String, cliID: String, in store: Store) -> GuestExecutionState {
        let previous = store.guestExecutionStates[desktopID]
        return GuestExecutionState(cliSessionID: cliID, availability: .inaccessible,
            isRunning: previous?.isRunning ?? store.claudeSessions[desktopID]?.running,
            activity: previous?.activity ?? store.claudeActivity[desktopID])
    }

    private func clearPendingDisable(_ computer: GuestReference) {
        guard let store else { return }
        let location = SessionLocation.computer(deviceId: computer.deviceId, computerId: computer.computerId)
        var state = store.router
        let kept = state.pendingGuestDisables.filter { $0 != location }
        guard kept.count != state.pendingGuestDisables.count else { return }
        state.pendingGuestDisables = kept
        store.router = state
    }
}
