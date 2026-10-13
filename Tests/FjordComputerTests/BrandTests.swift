import AppKit
import SwiftUI
import Testing
@testable import FjordComputer

/// The look follows the Mac's appearance as it's drawn, so switching light and dark needs no relaunch.
@Suite struct BrandTests {
    private func resolved(_ color: Color, in name: NSAppearance.Name) -> NSColor? {
        var out: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance { out = NSColor(color).usingColorSpace(.sRGB) }
        return out
    }

    private func luminance(_ c: NSColor) -> CGFloat { 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent }

    @Test func textAndGroundSwapWithTheAppearance() throws {
        let text = try #require(resolved(CDS.Text.primary, in: .darkAqua)), lightText = try #require(resolved(CDS.Text.primary, in: .aqua))
        let ground = try #require(resolved(CDS.Surface.s1, in: .darkAqua)), lightGround = try #require(resolved(CDS.Surface.s1, in: .aqua))
        #expect(luminance(text) > 0.8 && luminance(ground) < 0.15)
        #expect(luminance(lightText) < 0.15 && luminance(lightGround) > 0.85)
    }

    @Test func aCardsTintIsPaleOnLightAndTransparentOnDark() throws {
        let wash = Brand.wash(CDS.Fill.warning, 0.15)
        let light = try #require(resolved(wash, in: .aqua)), dark = try #require(resolved(wash, in: .darkAqua))
        #expect(light.alphaComponent == 1 && luminance(light) > 0.8)
        #expect(abs(dark.alphaComponent - 0.15) < 0.01)
    }
}

/// Claude's fonts are registered from the cache while the archive they were taken from is the same one.
@Suite struct ClaudeFontCache {
    @Test func theCacheStandsOnlyForTheArchiveItWasTakenFromAndWithAllItsFonts() throws {
        let dir = TempDir()
        let archive = dir.path("app.asar"), cache = dir.path("fonts")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: archive)
        let stamp = try #require(ClaudeFonts.archiveStamp(archive.path))
        #expect(ClaudeFonts.archiveStamp(dir.path("missing").path) == nil)
        #expect(ClaudeFonts.cached(in: cache, stamp: stamp) == nil)
        try Data().write(to: cache.appendingPathComponent("A.woff2"))
        try ([stamp, "A.woff2", "B.woff2"]).joined(separator: "\n")
            .write(to: cache.appendingPathComponent(ClaudeFonts.stampName), atomically: true, encoding: .utf8)
        // One of its fonts gone: taken out of the archive again.
        #expect(ClaudeFonts.cached(in: cache, stamp: stamp) == nil)
        try Data().write(to: cache.appendingPathComponent("B.woff2"))
        #expect(ClaudeFonts.cached(in: cache, stamp: stamp) == ["A.woff2", "B.woff2"])
        // Another build of the app: another archive.
        try Data("another".utf8).write(to: archive)
        #expect(ClaudeFonts.archiveStamp(archive.path) != stamp)
        #expect(ClaudeFonts.cached(in: cache, stamp: try #require(ClaudeFonts.archiveStamp(archive.path))) == nil)
    }

    @Test func fontsTakenOutOfAnArchiveReplaceWhatWasCutShortAndTheOldOnesGo() throws {
        let dir = TempDir()
        let cache = dir.path("fonts")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // A write cut short of A, and B and an old build's font from before.
        try Data("A".utf8).write(to: cache.appendingPathComponent("A.woff2"))
        try Data("bbbb".utf8).write(to: cache.appendingPathComponent("B.woff2"))
        try Data("old".utf8).write(to: cache.appendingPathComponent("Old.woff2"))
        var read: [String] = []
        func font(_ name: String, _ text: String) -> (name: String, size: Int, bytes: () -> Data) {
            (name, text.utf8.count, { read.append(name); return Data(text.utf8) })
        }
        let names = ClaudeFonts.cache([font("A.woff2", "aaaa"), font("B.woff2", "bbbb")], in: cache, stamp: "s1")
        #expect(names == ["A.woff2", "B.woff2"])
        #expect(try Data(contentsOf: cache.appendingPathComponent("A.woff2")) == Data("aaaa".utf8))
        // Whole already: not taken out again.
        #expect(read == ["A.woff2"])
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("Old.woff2").path))
        #expect(ClaudeFonts.cached(in: cache, stamp: "s1") == ["A.woff2", "B.woff2"])
        // One that can't be written: nothing is noted, so they are taken out again next launch.
        let readOnly = dir.path("readonly")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        chmod(readOnly.path, 0o500)
        defer { chmod(readOnly.path, 0o755) }
        ClaudeFonts.cache([font("A.woff2", "aaaa")], in: readOnly, stamp: "s2")
        #expect(ClaudeFonts.cached(in: readOnly, stamp: "s2") == nil)
    }
}

/// Claude's spark is made off the main thread and published once made.
@MainActor @Suite struct ClaudeMarkWarming {
    @Test func theSparkIsPublishedOnceMadeOffTheMainThread() async {
        ClaudeMark.warm()
        for _ in 0..<400 where !ClaudeMark.state.done { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(ClaudeMark.state.done)
        #expect((ClaudeMark.state.image == nil) == (ClaudeMark.image == nil))
        // Asked again: nothing more is made.
        ClaudeMark.warm()
        #expect(ClaudeMark.state.done)
    }
}
