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

    /// Once, at launch, before any view is drawn.
    static func load() {
        guard !available, let data = try? Data(contentsOf: URL(fileURLWithPath: asar), options: .alwaysMapped),
              let files = AsarIndex(data) else { return }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.amontlabs.fjord/fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for (path, range) in files.entries
        where path.hasPrefix(".vite/renderer/main_window/assets/AnthropicSans-") && path.hasSuffix(".woff2") {
            let file = cache.appendingPathComponent((path as NSString).lastPathComponent)
            if !FileManager.default.fileExists(atPath: file.path) { try? data.subdata(in: range).write(to: file) }
            if CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) { available = true }
        }
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
