import AppKit
import CoreText
import Foundation

/// Claude's own typeface, Anthropic Sans, read from the Claude app the user has installed (inside its `app.asar`), so
/// Fjord Computer looks like part of it without shipping the font. Registered for this process only; when Claude isn't
/// there or its bundle changes, `available` stays false and Theme falls back to the system font.
enum ClaudeFonts {
    nonisolated(unsafe) private(set) static var available = false

    /// The variable font's named instances: `AnthropicSansVariable-Text<Weight>`.
    static func name(_ weight: String) -> String { "AnthropicSansVariable-Text\(weight)" }

    static let asar = "/Applications/Claude.app/Contents/Resources/app.asar"

    /// Once, at launch, before any view is drawn. The fonts taken out of an archive are kept in a folder of the caches of
    /// their own, named by the archive's stamp (`generation`) and never written again once made whole (`store`): while the
    /// archive is that one, they are registered from there, without reading the archive's header (a few MB of JSON, tens of
    /// milliseconds before the first frame).
    static func load() {
        guard !available, let stamp = archiveStamp(asar) else { return }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.amontlabs.fjord/fonts", isDirectory: true)
        let folder = generation(root: root, stamp: stamp)
        if let names = fonts(in: folder) {
            if register(names, in: folder) {
                // Made by an earlier launch: what older archives left goes now, unless another Fjord Computer runs (it may
                // have registered them).
                sweep(root, keeping: folder, othersRunning: { otherFjordRunning })
                return
            }
        }
        // Not whole (a font gone, or one that doesn't register): put aside, so it is made again in its place.
        setAside(folder, in: root)
        // Taking them out failed launch after launch (a full disk, a folder that can't be written): not tried again for
        // this archive, so each launch doesn't read its header for nothing.
        guard failures(stamp: stamp) < maxFailures else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: asar), options: .alwaysMapped),
              let files = AsarIndex(data) else { return }
        let fonts = files.entries
            .filter { $0.0.hasPrefix(".vite/renderer/main_window/assets/AnthropicSans-") && $0.0.hasSuffix(".woff2") }
            .map { entry in (name: (entry.0 as NSString).lastPathComponent, bytes: { data.subdata(in: entry.1) }) }
        guard let made = store(fonts, root: root, stamp: stamp), let names = Self.fonts(in: made), register(names, in: made) else {
            noteFailure(stamp: stamp)
            return
        }
        clearFailures()
    }

    /// Registers the fonts for this process; whether every one of them took.
    @discardableResult
    private static func register(_ names: [String], in folder: URL) -> Bool {
        var all = true
        for name in names {
            if CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(name) as CFURL, .process, nil) {
                available = true
            } else {
                all = false
            }
        }
        return all
    }

    /// Moves a generation that isn't whole out of the way (`.bad-…`, swept later), so it can be made again.
    static func setAside(_ folder: URL, in root: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        try? fm.moveItem(at: folder, to: root.appendingPathComponent(".bad-\(UUID().uuidString)", isDirectory: true))
    }

    /// Another Fjord Computer is running (the installed app beside a build, say): by bundle id or executable name.
    static var otherFjordRunning: Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let name = Bundle.main.executableURL?.lastPathComponent ?? "FjordComputer"
        let id = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.contains { app in
            app.processIdentifier != me
                && ((id != nil && app.bundleIdentifier == id) || app.executableURL?.lastPathComponent == name)
        }
    }

    /// The folder of the fonts taken out of the archive with `stamp`.
    static func generation(root: URL, stamp: String) -> URL {
        root.appendingPathComponent("g-" + stamp.replacingOccurrences(of: " ", with: "-"), isDirectory: true)
    }

    /// In each generation: the fonts' names, a line each, written last.
    static let manifestName = "fonts.list"

    /// The fonts of a generation made whole; nil when it isn't (none, or one gone).
    static func fonts(in folder: URL) -> [String]? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent(manifestName), encoding: .utf8) else { return nil }
        let names = text.split(separator: "\n").map(String.init)
        let fm = FileManager.default
        guard !names.isEmpty,
              names.allSatisfy({ !$0.contains("/") && fm.fileExists(atPath: folder.appendingPathComponent($0).path) }) else { return nil }
        return names
    }

    /// Writes the fonts into a folder of their own, whole (each written out, then the list of them), and only then puts it
    /// where `generation` looks, in one rename: a launch stopped midway leaves nothing found, and a generation once made is
    /// never written again, so another Fjord Computer running with it (the installed app beside a build) keeps its fonts.
    /// Nil when that failed. One made meanwhile by another process is taken as it is.
    static func store(_ fonts: [(name: String, bytes: () -> Data)], root: URL, stamp: String) -> URL? {
        let fm = FileManager.default
        let folder = generation(root: root, stamp: stamp)
        guard !fonts.isEmpty, (try? fm.createDirectory(at: root, withIntermediateDirectories: true)) != nil else { return nil }
        let making = root.appendingPathComponent(".making-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: making) }
        do {
            try fm.createDirectory(at: making, withIntermediateDirectories: false)
            for font in fonts { try font.bytes().write(to: making.appendingPathComponent(font.name)) }
            try fonts.map(\.name).joined(separator: "\n").write(to: making.appendingPathComponent(manifestName), atomically: false, encoding: .utf8)
            try fm.moveItem(at: making, to: folder)
        } catch {
            return Self.fonts(in: folder) != nil ? folder : nil
        }
        return folder
    }

    /// Takes away the other generations (and what the cache held before generations, and folders left half made or put
    /// aside), only while no other Fjord Computer runs: one that does may have registered them, and keeps reading them.
    /// `othersRunning` is asked only when there is something to take away (the running apps' list, before the first frame,
    /// isn't asked for on every launch).
    static func sweep(_ root: URL, keeping current: URL, othersRunning: () -> Bool) {
        let fm = FileManager.default
        let stale = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { name in
            name != current.lastPathComponent
                && (name.hasPrefix("g-") || name.hasPrefix(".making-") || name.hasPrefix(".bad-") || name.hasSuffix(".woff2")
                    || name == "archive.stamp" || name.hasPrefix("failed-"))
        }
        guard !stale.isEmpty, !othersRunning() else { return }
        for name in stale { try? fm.removeItem(at: root.appendingPathComponent(name)) }
    }

    /// How many launches failed to take the fonts out of the archive with `stamp`, at most.
    static let maxFailures = 3
    /// Where the failures are counted: the defaults, which a cache folder that can't be written doesn't stop.
    static let failuresKey = "ClaudeFontFailures"

    static func failures(stamp: String, defaults: UserDefaults = .standard) -> Int {
        (defaults.dictionary(forKey: failuresKey)?[stamp] as? Int) ?? 0
    }

    /// The fonts were taken out and registered: no failure is counted any more.
    static func clearFailures(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: failuresKey) != nil { defaults.removeObject(forKey: failuresKey) }
    }

    /// Counts a failure for `stamp`; those of other archives are forgotten.
    static func noteFailure(stamp: String, defaults: UserDefaults = .standard) {
        defaults.set([stamp: failures(stamp: stamp, defaults: defaults) + 1], forKey: failuresKey)
    }

    /// The archive's size, inode and modification time (to the nanosecond): another for any other build of the app.
    static func archiveStamp(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return "\(info.st_size) \(info.st_ino) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
    }
}

/// An Electron `app.asar`'s file table: a pickled JSON header, then the files back to back.
struct AsarIndex {
    var entries: [(String, Range<Int>)] = []

    init?(_ data: Data) {
        guard data.count > 16 else { return nil }
        func u32(_ at: Int) -> Int { data.subdata(in: at..<at + 4).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) } }
        let headerSize = u32(4), jsonLength = u32(12)
        guard 16 + jsonLength <= data.count,
              let header = try? JSONSerialization.jsonObject(with: data.subdata(in: 16..<16 + jsonLength)) as? [String: Any]
        else { return nil }
        let base = 8 + headerSize
        func walk(_ node: [String: Any], _ prefix: String) {
            for (name, value) in node["files"] as? [String: Any] ?? [:] {
                guard let entry = value as? [String: Any] else { continue }
                let path = prefix.isEmpty ? name : prefix + "/" + name
                if entry["files"] != nil {
                    walk(entry, path)
                } else if entry["unpacked"] as? Bool != true, let offset = Int(entry["offset"] as? String ?? ""),
                          let size = (entry["size"] as? NSNumber)?.intValue, base + offset + size <= data.count {
                    entries.append((path, base + offset..<base + offset + size))
                }
            }
        }
        walk(header, "")
    }
}
