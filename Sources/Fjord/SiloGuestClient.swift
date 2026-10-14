import Foundation

/// Adapts the generated Silo guest methods to Router's guest filesystem and process boundary.
actor SiloGuestClient: GuestClient {
    private struct Watcher {
        var computer: GuestReference
        var paths: [String]
        var guestSubscriptionID: String
        var eventSubscriptionID: String?
        var continuation: AsyncStream<GuestFileEvent>.Continuation
    }

    private let engine: SocketEngineClient
    private var watchers: [UUID: Watcher] = [:]

    init(engine: SocketEngineClient) { self.engine = engine }

    func account(for computer: GuestReference) async throws -> GuestAccount {
        let wire = try await engine.guestAccount(SiloWireGuestAccountParams(computerId: computer.computerId,
                                                                            deviceId: computer.deviceId))
        guard let uid = UInt32(exactly: wire.uid), wire.home.hasPrefix("/"), !wire.home.contains("\0") else {
            throw GuestClientFailure.unavailable("Silo returned an invalid guest account.")
        }
        let command = "# fjord-account-probe\nprivate_node=\"$HOME/.local/share/fjord/runtime/node-\(GuestNodeRuntime.version)/bin/node\"; node=\"$(command -v node || true)\"; [ ! -x \"$private_node\" ] || node=\"$private_node\"; printf 'node=%s\\nclaude=%s\\nos=%s\\narch=%s\\n' \"$node\" \"$(command -v claude || true)\" \"$(uname -s)\" \"$(uname -m)\""
        let probe = try await engine.guestExec(Self.execParams(computer: computer,
            argv: ["/bin/sh", "-lc", command], cwd: wire.home, timeoutSeconds: 15))
        guard probe.exitCode == 0, let output = String(bytes: Self.data(probe.stdout), encoding: .utf8) else {
            throw GuestClientFailure.unavailable("Fjord couldn't inspect Node, Claude Code, and the guest architecture.")
        }
        let values = Dictionary(output.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            guard let equals = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<equals]), String(line[line.index(after: equals)...]))
        }, uniquingKeysWith: { _, newest in newest })
        guard let nodeValue = values["node"],
              let claude = values["claude"], claude.hasPrefix("/"),
              let system = values["os"], let architecture = values["arch"], !architecture.isEmpty else {
            throw GuestClientFailure.unavailable("The guest needs Git and Claude Code on its account PATH.")
        }
        let node = nodeValue.hasPrefix("/") ? nodeValue : ""
        let operatingSystem: ComputerKind
        switch system {
        case "Linux": operatingSystem = .linux
        case "Darwin": operatingSystem = .macos
        default: throw GuestClientFailure.unavailable("Unsupported guest operating system: \(system)")
        }
        return GuestAccount(home: wire.home, uid: uid, operatingSystem: operatingSystem, architecture: architecture,
                           nodeExecutable: node, claudeExecutable: claude)
    }

    func exec(_ request: GuestExecRequest) async throws -> GuestExecResult {
        let wire = try await engine.guestExec(Self.execParams(computer: request.computer, argv: request.argv,
            cwd: request.cwd, timeoutSeconds: request.timeoutSeconds))
        return GuestExecResult(exitCode: wire.exitCode ?? -1, stdout: Self.data(wire.stdout), stderr: Self.data(wire.stderr))
    }

    func execStart(_ request: GuestExecStartRequest) async throws -> String {
        guard let retainOutputBytes = UInt64(exactly: request.retainOutputBytes) else {
            throw GuestClientFailure.unavailable("The requested guest job output limit is invalid.")
        }
        let wire = try await engine.guestExecStart(SiloWireGuestExecStartParams(argv: request.argv,
            computerId: request.computer.computerId, cwd: request.cwd, deviceId: request.computer.deviceId,
            retainOutputBytes: retainOutputBytes, stdinOpen: false))
        return wire.jobId
    }

    func execGet(jobId: String, sinceSequence: UInt64) async throws -> GuestExecJobResult {
        let wire = try await engine.guestExecGet(SiloWireGuestExecGetParams(jobId: jobId, sinceSeq: sinceSequence))
        var stdout = Data()
        var stderr = Data()
        var nextSequence = sinceSequence
        for output in wire.output.sorted(by: { $0.seq < $1.seq }) {
            if output.stream == .stdout { stdout.append(Self.data(output.data)) }
            else { stderr.append(Self.data(output.data)) }
            nextSequence = max(nextSequence, output.seq &+ 1)
        }
        let state: GuestExecJobState = switch wire.state {
        case .running: .running
        case .exited: .exited
        case .cancelled: .cancelled
        case .lost: .lost
        }
        return GuestExecJobResult(state: state, exitCode: wire.exitCode, stdout: stdout, stderr: stderr,
                                  nextSequence: nextSequence)
    }

    func filesRead(computer: GuestReference, path: String, offset: Int64?, length: Int?) async throws -> GuestFileReadResult {
        try Self.validate(path)
        let wireOffset: UInt64?
        if let offset {
            guard let value = UInt64(exactly: offset) else { throw GuestClientFailure.invalidPath(path) }
            wireOffset = value
        } else { wireOffset = nil }
        let wireLength: UInt64?
        if let length {
            guard let value = UInt64(exactly: length) else { throw GuestClientFailure.invalidPath(path) }
            wireLength = value
        } else { wireLength = nil }
        let wire = try await engine.guestFilesRead(SiloWireGuestFilesReadParams(computerId: computer.computerId,
            deviceId: computer.deviceId, length: wireLength, offset: wireOffset, path: path))
        guard let mode = UInt16(exactly: wire.mode) else { throw GuestClientFailure.unavailable("Silo returned an invalid guest file mode.") }
        return GuestFileReadResult(data: Self.data(wire.data), size: try Self.int64(wire.size),
            mtimeMs: try Self.int64(wire.mtimeMs), inode: try Self.int64(wire.inode), mode: mode)
    }

    func filesList(computer: GuestReference, path: String) async throws -> [GuestFileEntry] {
        try Self.validate(path)
        let wire = try await engine.guestFilesList(SiloWireGuestFilesListParams(computerId: computer.computerId,
            deviceId: computer.deviceId, path: path))
        return try wire.entries.map { entry in
            GuestFileEntry(name: entry.name, type: Self.entryType(entry.type), size: try Self.int64(entry.size),
                           mtimeMs: try Self.int64(entry.mtimeMs))
        }
    }

    func filesWrite(_ request: GuestFileWriteRequest) async throws -> GuestFileWriteResult {
        try Self.validate(request.path)
        let replace: SiloWireGuestFileReplace
        let expectedSha256: String?
        switch request.replace {
        case .always: replace = .always; expectedSha256 = nil
        case .never: replace = .never; expectedSha256 = nil
        case .ifSHA256(let hash): replace = .ifSha256; expectedSha256 = hash
        }
        let wire = try await engine.guestFilesWrite(SiloWireGuestFilesWriteParams(computerId: request.computer.computerId,
            createParents: request.createParents, data: request.data.map(Int.init), deviceId: request.computer.deviceId,
            expectedSha256: expectedSha256, mode: Int(request.mode), path: request.path, replace: replace))
        return GuestFileWriteResult(size: try Self.int64(wire.size), mtimeMs: try Self.int64(wire.mtimeMs),
                                    inode: try Self.int64(wire.inode))
    }

    func filesRemove(computer: GuestReference, paths: [String]) async throws -> [String] {
        try paths.forEach(Self.validate)
        let wire = try await engine.guestFilesRemove(SiloWireGuestFilesRemoveParams(computerId: computer.computerId,
            deviceId: computer.deviceId, paths: paths))
        return wire.removed
    }

    func filesWatch(computer: GuestReference, paths: [String]) async throws -> GuestFilesWatch {
        try paths.forEach(Self.validate)
        let wire = try await engine.guestFilesWatch(SiloWireGuestFilesWatchParams(computerId: computer.computerId,
            deviceId: computer.deviceId, paths: paths))
        let id = UUID()
        let pair = AsyncStream<GuestFileEvent>.makeStream()
        watchers[id] = Watcher(computer: computer, paths: paths, guestSubscriptionID: wire.subscriptionId,
                               eventSubscriptionID: nil, continuation: pair.continuation)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeWatcher(id) } }
        do {
            let eventSubscription = try await engine.eventsSubscribe(events: ["guest.files.changed"]) { [weak self] delivery in
                Task { await self?.receive(delivery, watcherID: id) }
            }
            guard var watcher = watchers[id] else {
                await engine.eventsUnsubscribe(subscription: eventSubscription)
                throw CancellationError()
            }
            watcher.eventSubscriptionID = eventSubscription
            watchers[id] = watcher
            return GuestFilesWatch(subscriptionId: wire.subscriptionId, events: pair.stream)
        } catch {
            await removeWatcher(id)
            throw error
        }
    }

    func sshAliasEnsure(computer: GuestReference, installInclude: Bool) async throws -> GuestSSHAlias {
        let wire = try await engine.guestSSHAliasEnsure(SiloWireGuestSshAliasEnsureParams(computerId: computer.computerId,
            deviceId: computer.deviceId, installInclude: installInclude, path: nil))
        return GuestSSHAlias(alias: wire.alias, ownerName: wire.user, home: wire.home)
    }

    func sshAliasRemove(computer: GuestReference) async throws {
        try await engine.guestSSHAliasRemove(SiloWireComputerTargetParams(computerId: computer.computerId,
                                                                            deviceId: computer.deviceId))
    }

    private func receive(_ delivery: EngineEventDelivery, watcherID: UUID) async {
        guard let watcher = watchers[watcherID] else { return }
        switch delivery {
        case .event(_, .guestFilesChanged(_, let payload)) where payload.subscriptionId == watcher.guestSubscriptionID:
            watcher.continuation.yield(GuestFileEvent(subscriptionId: payload.subscriptionId, path: payload.path))
        case .disconnected:
            if let path = watcher.paths.first {
                watcher.continuation.yield(GuestFileEvent(subscriptionId: watcher.guestSubscriptionID, path: path))
            }
        case .reconnected:
            await reattach(watcherID)
        default:
            break
        }
    }

    private func reattach(_ id: UUID) async {
        guard var watcher = watchers[id] else { return }
        do {
            let result = try await engine.guestFilesWatch(SiloWireGuestFilesWatchParams(computerId: watcher.computer.computerId,
                deviceId: watcher.computer.deviceId, paths: watcher.paths))
            watcher.guestSubscriptionID = result.subscriptionId
            watchers[id] = watcher
        } catch {
            // Keep the event consumer alive; the runtime's periodic lease read will surface the inaccessible guest.
            return
        }
        if let path = watcher.paths.first {
            watcher.continuation.yield(GuestFileEvent(subscriptionId: watcher.guestSubscriptionID, path: path))
        }
    }

    private func removeWatcher(_ id: UUID) async {
        guard let watcher = watchers.removeValue(forKey: id) else { return }
        if let eventSubscription = watcher.eventSubscriptionID {
            await engine.eventsUnsubscribe(subscription: eventSubscription)
        }
    }

    private static func execParams(computer: GuestReference, argv: [String], cwd: String, timeoutSeconds: Int) -> SiloWireGuestExecParams {
        let milliseconds = UInt64(max(1, timeoutSeconds)).multipliedReportingOverflow(by: 1_000)
        return SiloWireGuestExecParams(argv: argv, guestExecParamsAs: nil, computerId: computer.computerId, cwd: cwd,
            deviceId: computer.deviceId, env: nil, maxOutputBytes: nil, stdin: nil,
            timeoutMs: milliseconds.overflow ? UInt64.max : milliseconds.partialValue)
    }

    private static func validate(_ path: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw GuestClientFailure.invalidPath(path) }
    }

    private static func int64(_ value: UInt64) throws -> Int64 {
        guard let value = Int64(exactly: value) else { throw GuestClientFailure.unavailable("Silo returned a guest file value outside Int64.") }
        return value
    }

    private static func data(_ bytes: [Int]) -> Data { Data(bytes.map { UInt8(truncatingIfNeeded: $0) }) }

    private static func entryType(_ value: SiloWireGuestFileKind) -> GuestFileEntryType {
        switch value {
        case .file: .file
        case .dir: .directory
        case .link: .link
        case .other: .other
        }
    }
}
