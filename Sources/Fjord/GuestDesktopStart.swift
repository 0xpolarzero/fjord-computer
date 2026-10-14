import Foundation

/// The supported one-click path for a computer project. Desktop receives a prefilled task and remains responsible for
/// asking about SSH and letting the person send it.
enum GuestDesktopStart {
    enum Failure: LocalizedError, Equatable {
        case computerFolderRequired
        case invalidLink
        var errorDescription: String? {
            switch self {
            case .computerFolderRequired: "Choose an absolute folder in the computer before starting a session."
            case .invalidLink: "Fjord couldn't build Claude's SSH session link."
            }
        }
    }

    struct Prepared: Equatable, Sendable {
        var pending: PendingDesktopStart
        var url: URL
        var alias: GuestSSHAlias
    }

    static func prepare(client: any GuestClient, placement: ProjectPlacement, project: RunsOnProject,
                        prompt: String, computerName: String,
                        settings: ClaudeSSHSettings = ClaudeSSHSettings(), now: Date = Date(),
                        activationAllowed: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Prepared {
        guard case .computer(let deviceId, let computerId, let rawFolder) = placement else { throw Failure.computerFolderRequired }
        let folder = try GuestFolderPath.validate(rawFolder)
        let computer = GuestReference(deviceId: deviceId, computerId: computerId)
        // Explicitly validate in the guest filesystem. Empty directories are valid; no controller path API touches it.
        _ = try await client.filesList(computer: computer, path: folder)
        _ = try await GuestRouterInstaller(client: client).install(computer: computer, activationAllowed: activationAllowed)
        guard await activationAllowed() else {
            try? await GuestRouterInstaller(client: client).disable(computer: computer)
            throw GuestRouterInstaller.Failure.routerTurnedOff
        }
        let alias = try await client.sshAliasEnsure(computer: computer, installInclude: true)
        try settings.install(.init(deviceId: deviceId, computerId: computerId, computerName: computerName,
                                   ownerName: alias.ownerName, alias: alias.alias))
        guard let url = deepLink(alias: alias.alias, folder: folder, prompt: prompt) else { throw Failure.invalidLink }
        let pending = PendingDesktopStart(projectID: project.id,
            location: .computer(deviceId: deviceId, computerId: computerId), alias: alias.alias, folder: folder,
            prompt: prompt, openedAt: now, state: .readyInClaude)
        return Prepared(pending: pending, url: url, alias: alias)
    }

    static func deepLink(alias: String, folder: String, prompt: String) -> URL? {
        guard let folder = try? GuestFolderPath.validate(folder), !alias.isEmpty,
              var components = URLComponents(string: "claude://code/new") else { return nil }
        components.queryItems = [URLQueryItem(name: "ssh_host", value: alias),
                                 URLQueryItem(name: "ssh_folder", value: folder),
                                 URLQueryItem(name: "q", value: prompt)]
        return components.url
    }

    static func reopen(_ pending: PendingDesktopStart) -> URL? {
        deepLink(alias: pending.alias, folder: pending.folder, prompt: pending.prompt)
    }
}

/// Guest evidence is separate from the Desktop session id. A matcher can mark a pending start only with an unambiguous
/// same-owner host id and a live plugin presence joined to the guest registry.
struct GuestSessionEvidence: Equatable, Sendable {
    var computer: GuestReference
    var cliSessionID: String
    var hostSessionID: String
    var pid: Int32
    var startedAt: Int64?
    var renewedAt: Int64
    var capabilities: [String]
    var transcriptMessages: [SessionFork.Message]
    var transcript: GuestTranscriptSnapshot? = nil
}

/// Guest execution is authoritative for the session body; the local SSH mirror supplies only Desktop metadata.
struct GuestExecutionState: Equatable {
    enum Availability: Equatable { case live, dead, inaccessible }

    var cliSessionID: String
    var availability: Availability
    /// `nil` means an inaccessible guest has not supplied enough evidence to replace the last known value.
    var isRunning: Bool?
    var activity: ClaudeActivity?
}

struct DesktopSSHSession: Equatable, Sendable {
    var id: String
    var alias: String
    var folder: String
}

enum PendingDesktopStartMatcher {
    /// Returns a match only when the pending start and the Desktop SSH session both identify exactly one live guest
    /// presence. Repeated paths on different computers remain distinct through `SessionLocation`.
    static func match(_ pending: PendingDesktopStart, desktop: [DesktopSSHSession], evidence: [GuestSessionEvidence],
                      allowEditedPrompt: Bool = false) -> GuestSessionEvidence? {
        guard case .computer(let deviceId, let computerId) = pending.location else { return nil }
        let owners = desktop.filter { $0.alias == pending.alias && $0.folder == pending.folder }
        guard owners.count == 1 else { return nil }
        let candidates = evidence.filter { $0.computer.deviceId == deviceId && $0.computer.computerId == computerId
            && $0.hostSessionID == owners[0].id && $0.capabilities.contains(ClaudePlugin.inboxCapability)
            && $0.transcriptMessages.contains(where: { message in
                guard let at = message.at, at >= pending.openedAt, message.cwd == pending.folder else { return false }
                return pending.prompt.isEmpty || allowEditedPrompt || message.text.contains(pending.prompt)
            }) }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

extension Store {
    /// Called after a guest watcher update and a Desktop metadata refresh. The pair is persisted only after an
    /// unambiguous host-session id and a transcript message confirm this exact prepared start.
    @discardableResult
    func reconcileDesktopStart(_ pendingID: UUID, desktop: [DesktopSSHSession], evidence: [GuestSessionEvidence],
                               allowEditedPrompt: Bool = false) -> Bool {
        var state = router
        guard let index = state.pendingDesktopStarts.firstIndex(where: { $0.id == pendingID }),
              state.pendingDesktopStarts[index].state == .readyInClaude else { return false }
        let claimed = Set(state.pendingDesktopStarts.enumerated().compactMap { otherIndex, other in
            otherIndex != index && other.state == .matched ? other.desktopSessionID : nil
        })
        let available = desktop.filter { !claimed.contains($0.id) }
        guard let match = PendingDesktopStartMatcher.match(state.pendingDesktopStarts[index], desktop: available,
                                                             evidence: evidence, allowEditedPrompt: allowEditedPrompt) else { return false }
        state.pendingDesktopStarts[index].state = .matched
        state.pendingDesktopStarts[index].desktopSessionID = match.hostSessionID
        state.pendingDesktopStarts[index].guestSessionID = match.cliSessionID
        router = state
        return true
    }
}

/// Watches guest presence and registry folders. File-watch notifications are hints; each event causes a full bounded
/// read and guest PID check so an SSH mirror or controller PID never establishes liveness.
struct GuestSessionObserver: Sendable {
    var client: any GuestClient

    func watch(computer: GuestReference) async throws -> (GuestFilesWatch, [GuestSessionEvidence]) {
        let account = try await client.account(for: computer)
        let paths = try GuestRouterPaths(home: account.home)
        let watch = try await client.filesWatch(computer: computer, paths: [paths.presence, paths.registry])
        return (watch, try await read(computer: computer, paths: paths))
    }

    func read(computer: GuestReference, paths: GuestRouterPaths, guestNowMs: Int64? = nil) async throws -> [GuestSessionEvidence] {
        let keyFile: GuestFileReadResult
        do { keyFile = try await client.filesRead(computer: computer, path: paths.key, offset: nil, length: nil) }
        catch GuestClientFailure.notFound(_) { return [] }
        guard let key = String(data: keyFile.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return [] }
        let expectedKeyID = ClaudePlugin.keyID(of: key)
        let presenceFiles: [GuestFileEntry]
        let registries: [GuestFileEntry]
        do { presenceFiles = try await client.filesList(computer: computer, path: paths.presence) }
        catch GuestClientFailure.notFound(_) { return [] }
        do { registries = try await client.filesList(computer: computer, path: paths.registry) }
        catch GuestClientFailure.notFound(_) { return [] }
        let nowMs: Int64
        if let guestNowMs { nowMs = guestNowMs }
        else { nowMs = try await GuestClock.sampleMilliseconds(client: client, computer: computer) }
        var registryByPID: [Int32: (host: String, cli: String, startedAt: Int64?)] = [:]
        for entry in registries where entry.type == .file && entry.name.hasSuffix(".json") {
            let path = GuestRouterPaths.join(paths.registry, entry.name)
            guard let data = try? await client.filesRead(computer: computer, path: path, offset: nil, length: nil).data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = object["sessionId"] as? String,
                  let host = object["hostSessionId"] as? String,
                  let pid = (object["pid"] as? NSNumber)?.int32Value ?? Int32(entry.name.dropLast(5)) else { continue }
            registryByPID[pid] = (host, session, (object["startedAt"] as? NSNumber)?.int64Value)
        }
        var found: [GuestSessionEvidence] = []
        for entry in presenceFiles where entry.type == .file && !entry.name.hasPrefix(".") {
            let path = GuestRouterPaths.join(paths.presence, entry.name)
            guard let data = try? await client.filesRead(computer: computer, path: path, offset: nil, length: nil).data,
                  let value = try? JSONDecoder().decode(ClaudePlugin.Presence.self, from: data), value.state == "live",
                  let cli = value.sessionId, cli == entry.name, let pid = value.pid,
                  let renewed = value.renewedAt, abs(Double(nowMs) - Double(renewed)) < ClaudePlugin.lease * 1000,
                  value.keyId == expectedKeyID, registryByPID[pid]?.cli == cli,
                  registryByPID[pid]?.startedAt == value.startedAt else { continue }
            let alive: Bool
            do {
                let result = try await client.exec(GuestExecRequest(computer: computer, argv: ["/bin/kill", "-0", String(pid)],
                                                                      cwd: paths.home, timeoutSeconds: 2))
                alive = result.succeeded
            } catch GuestClientFailure.permissionDenied(_) { continue }
            guard alive else { continue }
            let transcript = try await GuestTranscripts(client: client).read(computer: computer,
                projectsRoot: paths.projects, cliSessionID: cli)
            let messages = transcript?.messages ?? []
            found.append(GuestSessionEvidence(computer: computer, cliSessionID: cli, hostSessionID: registryByPID[pid]?.host ?? "",
                                               pid: pid, startedAt: value.startedAt, renewedAt: renewed,
                                               capabilities: value.capabilities ?? [], transcriptMessages: messages,
                                               transcript: transcript))
        }
        return found
    }
}
