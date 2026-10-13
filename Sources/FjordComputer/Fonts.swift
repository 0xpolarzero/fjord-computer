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
            register(names, in: folder)
            // Made by an earlier launch: what older archives left goes now (a process still running with one of them
            // started before this generation was made).
            sweep(root, keeping: folder)
            return
        }
        // Taking them out failed launch after launch (a full disk, a folder that can't be written): not tried again for
        // this archive, so each launch doesn't read its header for nothing.
        guard failures(root, stamp: stamp) < maxFailures else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: asar), options: .alwaysMapped),
              let files = AsarIndex(data) else { return }
        let fonts = files.entries
            .filter { $0.0.hasPrefix(".vite/renderer/main_window/assets/AnthropicSans-") && $0.0.hasSuffix(".woff2") }
            .map { entry in (name: (entry.0 as NSString).lastPathComponent, bytes: { data.subdata(in: entry.1) }) }
        guard let made = store(fonts, root: root, stamp: stamp), let names = Self.fonts(in: made) else {
            noteFailure(root, stamp: stamp)
            return
        }
        register(names, in: made)
    }

    private static func register(_ names: [String], in folder: URL) {
        for name in names where CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(name) as CFURL, .process, nil) {
            available = true
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

    /// Takes away the generations older than `current` (and what the cache held before generations), and folders left half
    /// made by a launch that stopped: run only once `current` was made by an earlier launch, and a day ago at least, so a
    /// Fjord Computer still running from before it (with an older generation's fonts registered) has long been relaunched.
    static func sweep(_ root: URL, keeping current: URL, now: Date = Date()) {
        let fm = FileManager.default
        func made(_ url: URL) -> Date { ((try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date) ?? .distantPast }
        let since = made(current)
        guard now.timeIntervalSince(since) > sweepAfter else { return }
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name != current.lastPathComponent {
            let url = root.appendingPathComponent(name)
            guard name.hasPrefix("g-") || name.hasPrefix(".making-") || name.hasSuffix(".woff2") || name == "archive.stamp"
                    || name.hasPrefix("failed-") else { continue }
            if made(url) < since { try? fm.removeItem(at: url) }
        }
    }

    /// How long a generation is in use before the older ones go.
    static let sweepAfter: TimeInterval = 86400

    /// How many launches failed to take the fonts out of the archive with `stamp`, at most.
    static let maxFailures = 3

    static func failures(_ root: URL, stamp: String) -> Int {
        let note = root.appendingPathComponent("failed-" + generation(root: root, stamp: stamp).lastPathComponent)
        return (try? String(contentsOf: note, encoding: .utf8)).flatMap { Int($0) } ?? 0
    }

    static func noteFailure(_ root: URL, stamp: String) {
        let note = root.appendingPathComponent("failed-" + generation(root: root, stamp: stamp).lastPathComponent)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? String(failures(root, stamp: stamp) + 1).write(to: note, atomically: true, encoding: .utf8)
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
