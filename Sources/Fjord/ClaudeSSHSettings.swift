import Foundation

/// Serializes Fjord's writes to Claude settings and uses the same read/compute/re-read/atomic-replace rule for both the
/// local PermissionRequest hook and owned Desktop SSH connections.
enum ClaudeSettingsFile {
    enum Failure: LocalizedError, Equatable {
        case invalidJSON(String)
        case notAnObject(String)
        case unreadable(String, String)
        case keptChanging(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let path): "\(path) isn't valid JSON, so Fjord left it alone."
            case .notAnObject(let path): "\(path) doesn't hold a JSON object, so Fjord left it alone."
            case .unreadable(let path, let reason): "Fjord couldn't read \(path): \(reason)"
            case .keptChanging(let path): "\(path) kept changing while Fjord was updating it. Try again."
            }
        }
    }

    static let attempts = 3
    private static let lock = NSRecursiveLock()

    static func modify(settings: URL, backup: URL, beforeReplace: (() -> Void)? = nil,
                       change: (inout [String: Any]) throws -> Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        for _ in 0..<attempts {
            let target = settings.resolvingSymlinksInPath()
            let raw: Data?
            do { raw = try read(settings, targeting: target) }
            catch is TargetChanged { continue }
            var root = try parse(raw, path: settings.path) ?? [:]
            guard try change(&root) else { return }
            var data = try JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(contentsOf: Array("\n".utf8))

            if let raw, !fileManager.fileExists(atPath: backup.path) {
                try PrivateFile.write(raw, to: backup)
            }
            let mode = ((try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
            let temp = try PrivateFile.prepare(data, for: target, mode: mode_t(mode))
            beforeReplace?()
            let unchanged: Bool
            do { unchanged = try read(settings, targeting: target) == raw }
            catch is TargetChanged {
                unlink(temp.path)
                continue
            }
            catch { unlink(temp.path); throw error }
            guard unchanged else {
                unlink(temp.path)
                continue
            }
            try PrivateFile.commit(temp, to: target)
            return
        }
        throw Failure.keptChanging(settings.path)
    }

    private struct TargetChanged: Error {}

    private static func read(_ settings: URL, targeting target: URL? = nil) throws -> Data? {
        var info = stat()
        guard lstat(settings.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw Failure.unreadable(settings.path, String(cString: strerror(errno)))
        }
        let resolved = settings.resolvingSymlinksInPath()
        if let target, resolved != target { throw TargetChanged() }
        do {
            let data = try Data(contentsOf: target ?? resolved)
            if let target, settings.resolvingSymlinksInPath() != target { throw TargetChanged() }
            return data
        }
        catch is TargetChanged { throw TargetChanged() }
        catch { throw Failure.unreadable(settings.path, (error as NSError).localizedDescription) }
    }

    private static func parse(_ raw: Data?, path: String) throws -> [String: Any]? {
        guard let raw else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) else {
            throw Failure.invalidJSON(path)
        }
        guard let root = value as? [String: Any] else { throw Failure.notAnObject(path) }
        return root
    }
}

/// Fjord-owned `sshConfigs` records used by Claude Desktop's documented SSH deep link.
struct ClaudeSSHSettings {
    struct Computer: Equatable {
        var deviceId: String?
        var computerId: String
        var computerName: String
        var ownerName: String
        var alias: String

        var id: String { "fjord-\(deviceId ?? "local")-\(computerId)" }
        var displayName: String { "\(computerName) · \(ownerName)" }

        var json: [String: String] { ["id": id, "name": displayName, "sshHost": alias] }
    }

    var claudeDir: URL
    var settings: URL { claudeDir.appendingPathComponent("settings.json") }
    var backup: URL { claudeDir.appendingPathComponent("settings.json.fjord-backup") }
    var beforeReplace: (() -> Void)?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
    }

    init(claudeDir: URL) { self.claudeDir = claudeDir }

    func install(_ computer: Computer) throws {
        guard !computer.computerId.isEmpty, !computer.alias.isEmpty else { throw Failure.invalidEntry }
        try modify { root in
            var entries = try sshConfigs(root)
            let matches = entries.filter { $0["id"] as? String == computer.id }
            if matches.count == 1, NSDictionary(dictionary: matches[0]).isEqual(to: computer.json) { return false }
            entries.removeAll { $0["id"] as? String == computer.id }
            entries.append(computer.json)
            root["sshConfigs"] = entries
            return true
        }
    }

    func remove(deviceId: String?, computerId: String) throws {
        let id = "fjord-\(deviceId ?? "local")-\(computerId)"
        try modify { root in
            var entries = try sshConfigs(root)
            let kept = entries.filter { $0["id"] as? String != id }
            guard kept.count != entries.count else { return false }
            if kept.isEmpty { root.removeValue(forKey: "sshConfigs") }
            else { root["sshConfigs"] = kept }
            return true
        }
    }

    private func modify(_ change: (inout [String: Any]) throws -> Bool) throws {
        try ClaudeSettingsFile.modify(settings: settings, backup: backup, beforeReplace: beforeReplace, change: change)
    }

    private func sshConfigs(_ root: [String: Any]) throws -> [[String: Any]] {
        guard let raw = root["sshConfigs"] else { return [] }
        guard let array = raw as? [Any] else { throw Failure.incompatible(settings.path, "sshConfigs") }
        var entries: [[String: Any]] = []
        for value in array {
            guard let entry = value as? [String: Any] else { throw Failure.incompatible(settings.path, "sshConfigs[]") }
            entries.append(entry)
        }
        return entries
    }

    enum Failure: LocalizedError, Equatable {
        case invalidEntry
        case incompatible(String, String)

        var errorDescription: String? {
            switch self {
            case .invalidEntry: "The computer connection is incomplete, so Fjord didn't change Claude settings."
            case .incompatible(let path, let key): "In \(path), “\(key)” isn't what Claude Desktop expects, so Fjord left the file alone."
            }
        }
    }
}
