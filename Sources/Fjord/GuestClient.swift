import CryptoKit
import Foundation

struct GuestReference: Codable, Equatable, Hashable, Sendable {
    var deviceId: String?
    var computerId: String

    var key: String { "\(deviceId ?? "local")/\(computerId)" }
}

struct GuestAccount: Codable, Equatable, Sendable {
    var home: String
    var uid: UInt32
    var operatingSystem: ComputerKind
    var architecture: String
    var nodeExecutable: String
    var claudeExecutable: String
}

struct GuestSSHAlias: Codable, Equatable, Sendable {
    var alias: String
    var ownerName: String
    var home: String
}

struct GuestExecRequest: Equatable, Sendable {
    var computer: GuestReference
    var argv: [String]
    var cwd: String
    var timeoutSeconds: Int
}

struct GuestExecResult: Equatable, Sendable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data

    var succeeded: Bool { exitCode == 0 }
}

enum GuestFileEntryType: String, Codable, Equatable, Sendable { case file, directory = "dir", link, other }

struct GuestFileEntry: Codable, Equatable, Sendable {
    var name: String
    var type: GuestFileEntryType
    var size: Int64
    var mtimeMs: Int64
}

struct GuestFileReadResult: Equatable, Sendable {
    var data: Data
    var size: Int64
    var mtimeMs: Int64
    var inode: Int64
    var mode: UInt16
}

enum GuestFileReplace: Equatable, Sendable {
    case always
    case never
    /// `nil` means the path must not exist.
    case ifSHA256(String?)
}

struct GuestFileWriteRequest: Equatable, Sendable {
    var computer: GuestReference
    var path: String
    var data: Data
    var mode: UInt16
    var createParents: Bool = true
    var replace: GuestFileReplace = .always
}

struct GuestFileWriteResult: Equatable, Sendable {
    var size: Int64
    var mtimeMs: Int64
    var inode: Int64
}

struct GuestFileEvent: Equatable, Sendable {
    var subscriptionId: String
    var path: String
}

struct GuestFilesWatch: Sendable {
    var subscriptionId: String
    var events: AsyncStream<GuestFileEvent>
}

enum GuestClientFailure: LocalizedError, Equatable {
    case invalidPath(String)
    case notFound(String)
    case notAFile(String)
    case exists(String)
    case changed(String)
    case permissionDenied(String)
    case notRunning(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Guest paths must be absolute: \(path)"
        case .notFound(let path): "Guest file not found: \(path)"
        case .notAFile(let path): "Guest path is not a file: \(path)"
        case .exists(let path): "Guest file already exists: \(path)"
        case .changed(let path): "Guest file changed before Fjord could replace it: \(path)"
        case .permissionDenied(let path): "Guest permission denied: \(path)"
        case .notRunning(let computer): "The computer isn't running: \(computer)"
        case .unavailable(let message): message
        }
    }
}

/// P3 guest calls stay separate until the generated client owns the canonical methods. No method is added to EngineClient.
protocol GuestClient: Sendable {
    func account(for computer: GuestReference) async throws -> GuestAccount
    func filesRead(computer: GuestReference, path: String, offset: Int64?, length: Int?) async throws -> GuestFileReadResult
    func filesList(computer: GuestReference, path: String) async throws -> [GuestFileEntry]
    func filesWrite(_ request: GuestFileWriteRequest) async throws -> GuestFileWriteResult
    func filesRemove(computer: GuestReference, paths: [String]) async throws -> [String]
    func filesWatch(computer: GuestReference, paths: [String]) async throws -> GuestFilesWatch
    func sshAliasEnsure(computer: GuestReference, installInclude: Bool) async throws -> GuestSSHAlias
    func sshAliasRemove(computer: GuestReference) async throws
    func exec(_ request: GuestExecRequest) async throws -> GuestExecResult
}

/// Deterministic guest filesystem and call recorder for Router feature tests and window shots.
actor MockGuestClient: GuestClient {
    private struct File: Sendable {
        var data: Data
        var mode: UInt16
        var mtimeMs: Int64
        var inode: Int64
    }
    private struct Watcher {
        var computer: GuestReference
        var paths: [String]
        var continuation: AsyncStream<GuestFileEvent>.Continuation
    }

    private var accounts: [String: GuestAccount]
    private var aliases: [String: GuestSSHAlias] = [:]
    private var files: [String: File] = [:]
    private var watchers: [String: Watcher] = [:]
    private var nextInode: Int64 = 1
    private var nextTime: Int64 = 1_800_000_000_000
    private var recordedWrites: [GuestFileWriteRequest] = []
    private var recordedRemovals: [(GuestReference, [String])] = []
    private var recordedExecs: [GuestExecRequest] = []
    private var operationLog: [String] = []
    private var execResults: [String: GuestExecResult] = [:]
    private var readFailures: [String: [GuestClientFailure]] = [:]
    private var postAdmissionWriteFailures: [String: GuestClientFailure] = [:]
    private var pausedExecs: Set<String> = []
    private var blockedExecs: Set<String> = []
    private var execPauseWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var execResumeWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var execResumeRequests: Set<String> = []
    var execResult = GuestExecResult(exitCode: 0, stdout: Data("v20.11.0\n".utf8), stderr: Data())

    init(accounts: [GuestReference: GuestAccount] = [:]) {
        var values: [String: GuestAccount] = [:]
        for (reference, account) in accounts { values[reference.key] = account }
        self.accounts = values
    }

    func account(for computer: GuestReference) throws -> GuestAccount {
        guard let value = accounts[computer.key] else { throw GuestClientFailure.unavailable("No mock account for \(computer.key)") }
        return value
    }

    func register(_ account: GuestAccount, for computer: GuestReference) { accounts[computer.key] = account }

    func filesRead(computer: GuestReference, path: String, offset: Int64? = nil, length: Int? = nil) throws -> GuestFileReadResult {
        let path = try Self.absolute(path)
        operationLog.append("read:\(path)")
        let key = Self.fileKey(computer, path)
        if var failures = readFailures[key], !failures.isEmpty {
            let failure = failures.removeFirst()
            readFailures[key] = failures
            throw failure
        }
        guard let file = files[key] else { throw GuestClientFailure.notFound(path) }
        let start = max(0, min(Int64(file.data.count), offset ?? 0))
        let end = min(Int64(file.data.count), start + Int64(max(0, length ?? file.data.count)))
        return GuestFileReadResult(data: file.data.subdata(in: Int(start)..<Int(end)), size: Int64(file.data.count),
                                   mtimeMs: file.mtimeMs, inode: file.inode, mode: file.mode)
    }

    func filesList(computer: GuestReference, path: String) throws -> [GuestFileEntry] {
        let root = try Self.absolute(path).trimmingTrailingSlash
        let prefix = root == "/" ? "/" : root + "/"
        var entries: [String: GuestFileEntry] = [:]
        for (key, file) in files where key.hasPrefix(computer.key + ":") {
            let filePath = String(key.dropFirst(computer.key.count + 1))
            guard filePath.hasPrefix(prefix) else { continue }
            let remainder = filePath.dropFirst(prefix.count)
            guard !remainder.isEmpty else { continue }
            let name = String(remainder.split(separator: "/", omittingEmptySubsequences: true).first ?? "")
            guard !name.isEmpty else { continue }
            let isDirectory = remainder.contains("/")
            let entry = GuestFileEntry(name: name, type: isDirectory ? .directory : .file,
                                       size: isDirectory ? 0 : Int64(file.data.count), mtimeMs: file.mtimeMs)
            if let existing = entries[name], existing.type == .directory { continue }
            entries[name] = entry
        }
        return entries.values.sorted { $0.name < $1.name }
    }

    func filesWrite(_ request: GuestFileWriteRequest) throws -> GuestFileWriteResult {
        let path = try Self.absolute(request.path)
        operationLog.append("write:\(path)")
        let key = Self.fileKey(request.computer, path)
        let existing = files[key]
        switch request.replace {
        case .always: break
        case .never:
            if existing != nil { throw GuestClientFailure.exists(path) }
        case .ifSHA256(let expected):
            guard Self.sha256(existing?.data) == expected else { throw GuestClientFailure.changed(path) }
        }
        _ = try account(for: request.computer)
        recordedWrites.append(request)
        nextTime += 1
        let inode = existing?.inode ?? nextInode
        if existing == nil { nextInode += 1 }
        files[key] = File(data: request.data, mode: request.mode, mtimeMs: nextTime, inode: inode)
        publish(computer: request.computer, path: path)
        if let failure = postAdmissionWriteFailures.removeValue(forKey: key) { throw failure }
        return GuestFileWriteResult(size: Int64(request.data.count), mtimeMs: nextTime, inode: inode)
    }

    func filesRemove(computer: GuestReference, paths: [String]) throws -> [String] {
        _ = try account(for: computer)
        var removed: [String] = []
        for raw in paths {
            let path = try Self.absolute(raw)
            let key = Self.fileKey(computer, path)
            if files.removeValue(forKey: key) != nil { publish(computer: computer, path: path) }
            removed.append(path)
        }
        recordedRemovals.append((computer, removed))
        return removed
    }

    func filesWatch(computer: GuestReference, paths: [String]) throws -> GuestFilesWatch {
        _ = try account(for: computer)
        let id = UUID().uuidString.lowercased()
        let normalized = try paths.map(Self.absolute)
        operationLog.append("watch:\(normalized.joined(separator: ","))")
        let stream = AsyncStream<GuestFileEvent> { continuation in
            watchers[id] = Watcher(computer: computer, paths: normalized, continuation: continuation)
            continuation.onTermination = { @Sendable _ in Task { await self.removeWatcher(id) } }
        }
        return GuestFilesWatch(subscriptionId: id, events: stream)
    }

    func sshAliasEnsure(computer: GuestReference, installInclude: Bool) throws -> GuestSSHAlias {
        _ = installInclude
        guard accounts[computer.key] != nil else { throw GuestClientFailure.unavailable("No mock account for \(computer.key)") }
        if let found = aliases[computer.key] { return found }
        let result = GuestSSHAlias(alias: "ssh-\(computer.computerId)", ownerName: computer.deviceId ?? "This Mac",
                                   home: accounts[computer.key]!.home)
        aliases[computer.key] = result
        return result
    }

    func sshAliasRemove(computer: GuestReference) { aliases[computer.key] = nil }

    func exec(_ request: GuestExecRequest) async throws -> GuestExecResult {
        _ = try account(for: request.computer)
        recordedExecs.append(request)
        let key = request.argv.joined(separator: "\u{1f}")
        if pausedExecs.remove(key) != nil {
            blockedExecs.insert(key)
            execPauseWaiters.removeValue(forKey: key)?.resume()
            if execResumeRequests.remove(key) == nil {
                await withCheckedContinuation { execResumeWaiters[key] = $0 }
            }
            blockedExecs.remove(key)
        }
        return execResults[key] ?? execResult
    }

    func setExecResult(_ result: GuestExecResult, argv: [String]) {
        execResults[argv.joined(separator: "\u{1f}")] = result
    }

    func failNextRead(computer: GuestReference, path: String, with failure: GuestClientFailure) {
        readFailures[Self.fileKey(computer, path), default: []].append(failure)
    }

    func failNextWriteAfterAdmission(computer: GuestReference, path: String, with failure: GuestClientFailure) {
        postAdmissionWriteFailures[Self.fileKey(computer, path)] = failure
    }

    func pauseNextExec(argv: [String]) { pausedExecs.insert(argv.joined(separator: "\u{1f}")) }

    func waitForExecPause(argv: [String]) async {
        let key = argv.joined(separator: "\u{1f}")
        guard !blockedExecs.contains(key) else { return }
        await withCheckedContinuation { execPauseWaiters[key] = $0 }
    }

    func resumeExec(argv: [String]) {
        let key = argv.joined(separator: "\u{1f}")
        if let waiter = execResumeWaiters.removeValue(forKey: key) { waiter.resume() }
        else { execResumeRequests.insert(key) }
    }

    func writeRecords() -> [GuestFileWriteRequest] { recordedWrites }
    func removalRecords() -> [(GuestReference, [String])] { recordedRemovals }
    func execRecords() -> [GuestExecRequest] { recordedExecs }
    func callLog() -> [String] { operationLog }
    func filesSnapshot(for computer: GuestReference) -> [String: Data] {
        let prefix = computer.key + ":"
        return Dictionary(uniqueKeysWithValues: files.compactMap { key, file in
            key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), file.data) : nil
        })
    }

    private func removeWatcher(_ id: String) { watchers[id] = nil }

    private func publish(computer: GuestReference, path: String) {
        for (id, watcher) in watchers where watcher.computer == computer && watcher.paths.contains(where: {
            path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/")
        }) {
            watcher.continuation.yield(GuestFileEvent(subscriptionId: id, path: path))
        }
    }

    private static func absolute(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw GuestClientFailure.invalidPath(path) }
        return path
    }

    private static func fileKey(_ computer: GuestReference, _ path: String) -> String { computer.key + ":" + path }

    private static func sha256(_ data: Data?) -> String? {
        guard let data else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var trimmingTrailingSlash: String { count > 1 && hasSuffix("/") ? String(dropLast()) : self }
}
