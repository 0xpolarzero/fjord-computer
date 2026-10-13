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

    /// Once, at launch, before any view is drawn. The fonts taken out of the archive are kept in the caches folder, with the
    /// archive's stamp (`stampName`): while the archive is the one they came from, they are registered from there, without
    /// reading the archive's header (a few MB of JSON, tens of milliseconds before the first frame).
    static func load() {
        guard !available, let stamp = archiveStamp(asar) else { return }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.amontlabs.fjord/fonts", isDirectory: true)
        if let names = cached(in: cache, stamp: stamp) {
            for name in names where CTFontManagerRegisterFontsForURL(cache.appendingPathComponent(name) as CFURL, .process, nil) {
                available = true
            }
            return
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: asar), options: .alwaysMapped),
              let files = AsarIndex(data) else { return }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var names: [String] = []
        for (path, range) in files.entries
        where path.hasPrefix(".vite/renderer/main_window/assets/AnthropicSans-") && path.hasSuffix(".woff2") {
            let name = (path as NSString).lastPathComponent
            let file = cache.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: file.path) { try? data.subdata(in: range).write(to: file) }
            if CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) { available = true }
            names.append(name)
        }
        // Only an archive whose fonts are all there is noted: one written in part is taken out again next launch.
        if !names.isEmpty, names.allSatisfy({ FileManager.default.fileExists(atPath: cache.appendingPathComponent($0).path) }) {
            try? ([stamp] + names).joined(separator: "\n").write(to: cache.appendingPathComponent(stampName), atomically: true, encoding: .utf8)
        }
    }

    /// Beside the cached fonts: the archive's stamp they were taken from, then their names, a line each.
    static let stampName = "archive.stamp"

    /// The archive's size, inode and modification time (to the nanosecond): another for any other build of the app.
    static func archiveStamp(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return "\(info.st_size) \(info.st_ino) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
    }

    /// The names of the fonts cached from the archive with `stamp`, when every one of them is there; nil otherwise.
    static func cached(in cache: URL, stamp: String) -> [String]? {
        guard let text = try? String(contentsOf: cache.appendingPathComponent(stampName), encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").map(String.init)
        guard lines.first == stamp, lines.count > 1 else { return nil }
        let names = Array(lines.dropFirst())
        let fm = FileManager.default
        return names.allSatisfy { !$0.contains("/") && fm.fileExists(atPath: cache.appendingPathComponent($0).path) } ? names : nil
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
