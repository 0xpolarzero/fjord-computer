import CryptoKit
import Foundation

/// App-lifetime guest observers. A tool invocation can finish while a Desktop SSH session is still waiting for the person
/// to send; this object keeps file watches alive and reconciles them with the controller's Desktop metadata.
@MainActor final class GuestRouterRuntime {
    static let shared = GuestRouterRuntime()

    private weak var store: Store?
    private var clients: [String: any GuestClient] = [:]
    private var computers: [String: GuestReference] = [:]
    private var watchers: [String: Task<Void, Never>] = [:]
    private var leaseChecks: [String: Task<Void, Never>] = [:]
    private var evidence: [String: [GuestSessionEvidence]] = [:]
    private var activeStartKeys: Set<String> = []

    private init() {}

    func reserveStart(projectID: UUID, location: SessionLocation, prompt: String) -> String? {
        let material = "\(projectID.uuidString)|\(location.key)|\(prompt)"
        let key = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        guard activeStartKeys.insert(key).inserted else { return nil }
        return key
    }

    func releaseStart(_ key: String) { activeStartKeys.remove(key) }

    func startWatching(store: Store, client: any GuestClient, computer: GuestReference) async throws {
        self.store = store
        clients[computer.key] = client
        computers[computer.key] = computer
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
                catch { store.routerHookError = "Guest Router refresh failed on \(computer.computerId): \(error.localizedDescription)" }
            }
        }
        leaseChecks[computer.key] = Task { [weak self, weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let store else { return }
                do { try await self.refresh(computer: computer, client: client, paths: paths) }
                catch { store.routerHookError = "Guest Router lease check failed on \(computer.computerId): \(error.localizedDescription)" }
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
                    try await GuestRouterInstaller(client: client).disable(computer: computer)
                    self?.clearPendingDisable(computer)
                } catch {
                    store?.routerHookError = "Guest Router disable is pending for \(computer.computerId): \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reconciles a previously failed Router-off while the guest is reachable, before a new install can begin.
    func applyPendingDisable(computer: GuestReference, client: any GuestClient) async throws {
        let location = SessionLocation.computer(deviceId: computer.deviceId, computerId: computer.computerId)
        guard store?.router.pendingGuestDisables.contains(location) == true else { return }
        try await GuestRouterInstaller(client: client).disable(computer: computer)
        clearPendingDisable(computer)
    }

    func reconcileDesktopMetadata() {
        guard let store else { return }
        for pending in store.router.pendingDesktopStarts where pending.state == .readyInClaude {
            let candidates = store.claudeSessions.values.compactMap { session -> DesktopSSHSession? in
                guard !session.isArchived, let folder = session.folder, folder == pending.folder,
                      session.lastActivity >= pending.openedAt else { return nil }
                return DesktopSSHSession(id: session.id, alias: pending.alias, folder: folder)
            }
            _ = store.reconcileDesktopStart(pending.id, desktop: candidates, evidence: evidence[pending.location.key] ?? [])
        }
    }

    func answer(_ guestForm: GuestPendingForm, answers: [String: String], cardID: String) async throws {
        guard let store, let client = clients[guestForm.computer.key] else { throw FormWriter.Cancelled() }
        try await GuestForms(client: client).answer(guestForm, answers: answers) { [weak store] in
            guard let store, let card = store.router.cards.first(where: { $0.id == cardID }), card.isOpen,
                  let current = store.guestPendingForm(for: card) else { return false }
            return current.form.id == guestForm.form.id && current.form.toolUseID == guestForm.form.toolUseID
        }
    }

    func answer(_ guestForm: GuestPendingForm, plan decision: PendingForm.PlanDecision, cardID: String) async throws {
        guard let store, let client = clients[guestForm.computer.key] else { throw FormWriter.Cancelled() }
        try await GuestForms(client: client).answer(guestForm, plan: decision) { [weak store] in
            guard let store, let card = store.router.cards.first(where: { $0.id == cardID }), card.isOpen,
                  let current = store.guestPendingForm(for: card) else { return false }
            return current.form.id == guestForm.form.id && current.form.toolUseID == guestForm.form.toolUseID
        }
    }

    func deliver(_ signedText: String, to cliSessionID: String, computer: GuestReference,
                 gate: (@MainActor @Sendable () -> String?)? = nil) async throws -> String {
        guard let store, let client = clients[computer.key] else { throw GuestClientFailure.notRunning(computer.key) }
        let callback: @MainActor @Sendable (GuestRelayRecord) async -> Void = { [weak store] record in
            store?.saveGuestRelayState(record)
        }
        return try await GuestRelayInbox(client: client, onState: callback)
            .deliver(signedText, to: cliSessionID, computer: computer, gate: gate)
    }

    func location(for desktopSessionID: String) -> SessionLocation? {
        store?.router.pendingDesktopStarts.first { $0.desktopSessionID == desktopSessionID && $0.state == .matched }?.location
    }

    func guestSessionID(for desktopSessionID: String) -> String? {
        store?.router.pendingDesktopStarts.first { $0.desktopSessionID == desktopSessionID && $0.state == .matched }?.guestSessionID
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
        return clients[GuestReference(deviceId: deviceId, computerId: computerId).key]
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
        var changedSessions = false
        var changedActivities = false
        for pending in store.router.pendingDesktopStarts where pending.state == .matched {
            guard let desktopID = pending.desktopSessionID, let cli = pending.guestSessionID,
                  let evidence = evidence[pending.location.key]?.first(where: {
                      $0.hostSessionID == desktopID && $0.cliSessionID == cli
                  }) else { continue }
            if var session = sessions[desktopID] {
                if !session.running || session.cliID != cli {
                    session.running = true
                    session.cliID = cli
                    sessions[desktopID] = session
                    changedSessions = true
                }
            }
            if let activity = evidence.transcript?.activity {
                if activities[desktopID] != activity { activities[desktopID] = activity; changedActivities = true }
            } else if activities[desktopID] != nil {
                activities[desktopID] = nil
                changedActivities = true
            }
        }
        if changedSessions { store.claudeSessions = sessions }
        if changedActivities { store.claudeActivity = activities }
        if changedSessions || changedActivities { store.feedRouter() }
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
