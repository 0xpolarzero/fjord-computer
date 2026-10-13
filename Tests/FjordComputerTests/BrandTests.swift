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
}
