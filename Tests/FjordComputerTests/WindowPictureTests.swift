import AppKit
import Testing
@testable import FjordComputer

/// The window's kept picture: the glance that says whether it is still the window, and what may stand in for what.
@MainActor @Suite struct WindowPictureTests {
    private typealias Glance = AppTransition.Glance

    private func glance(_ width: Int, _ height: Int, _ change: [(Int, UInt8)] = []) -> Glance {
        var pixels = [UInt8](repeating: 100, count: width * height * 4)
        for (at, value) in change { pixels[at] = value }
        return Glance(width: width, height: height, pixels: pixels)
    }

    @Test func aGlanceDiffersByTheShareOfPixelsMovedMoreThanTwoLevels() {
        let base = glance(10, 10)
        #expect(base.difference(from: base) == 0 && base.same(as: base))
        // Two levels in a channel is noise; three is a change, counted once per pixel whatever its channels.
        #expect(glance(10, 10, [(0, 102), (5, 98)]).difference(from: base) == 0)
        #expect(glance(10, 10, [(0, 103), (1, 90), (8, 97)]).difference(from: base) == 0.02)
        #expect(!glance(10, 10, [(0, 103)]).same(as: base))
        // Another size, or nothing to compare with, is no match at all.
        #expect(glance(10, 9).difference(from: base) == 1 && !base.same(as: nil) && !base.within(1, of: nil))
    }

    @Test func aGlanceStopsCountingPastItsLimit() {
        let base = glance(10, 10)
        let moved = glance(10, 10, (0..<10).map { ($0 * 4, 200) })
        #expect(moved.difference(from: base) == 0.1)
        // Past 3 of 100 the count stops: the share is only known to be over the limit.
        let stopped = moved.difference(from: base, limit: 0.03)
        #expect(stopped > 0.03 && stopped < 0.1)
        #expect(moved.within(0.1, of: base) && !moved.within(0.05, of: base))
    }

    /// A capture's cost is the longest of the last few at that size and scale, so one slow capture keeps the next from being
    /// let in on a mean; a size never taken is guessed from the others by pixels, and with none from a pessimistic prior.
    @Test func aCapturesCostIsItsRecentWorst() {
        var costs = AppTransition.CaptureCosts()
        let size = NSSize(width: 1000, height: 500)
        let prior = costs.estimate(size: size, pixelScale: 2)
        #expect(abs(prior - 1000 * 500 * 4 * AppTransition.CaptureCosts.prior) < 1e-9 && prior > 0.1)
        for cost in [0.06, 0.52, 0.06, 0.07] { costs.record(cost, size: size, pixelScale: 2) }
        #expect(costs.estimate(size: size, pixelScale: 2) == 0.52)
        // Five more and the slow one is out of the window.
        for _ in 0..<5 { costs.record(0.065, size: size, pixelScale: 2) }
        #expect(costs.estimate(size: size, pixelScale: 2) == 0.065)
        // At 1x, a quarter of the pixels: a quarter of the cost until one is measured.
        #expect(abs(costs.estimate(size: size, pixelScale: 1) - 0.065 / 4) < 1e-9)
        costs.record(0.03, size: size, pixelScale: 1)
        #expect(costs.estimate(size: size, pixelScale: 1) == 0.03)
        // Twice the size: the highest guess of the others (the 1x one's, 0.03 × 8, over the 2x one's, 0.065 × 2).
        #expect(abs(costs.estimate(size: NSSize(width: 2000, height: 500), pixelScale: 2) - 0.24) < 1e-9)
    }
}

extension WindowSeams {
    /// What a kept picture may stand in for: only the window it was taken of, as it was then.
    @MainActor @Suite(.hostsWindows) struct KeptPictureFits {
        @Test func aPictureFitsOnlyTheSizeScaleMorphAppearanceAndSidebarItWasTakenWith() throws {
            _ = NSApplication.shared
            let window = ScaledWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 100, height: 80)),
                                      styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.scale = 2
            window.appearance = NSAppearance(named: .darkAqua)
            let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let sidebar = NSRect(x: 8, y: 8, width: 40, height: 64)
            let picture = AppTransition.Picture(image: try #require(bitmap.makeImage()), frame: window.frame, scale: 2,
                                                destination: .settings, glass: true, appearance: .darkAqua,
                                                sidebar: sidebar)
            #expect(picture.fits(window, glass: true, sidebar: sidebar))
            // The sidebar folded since, the other morph, light mode, another scale or size: none stands in.
            #expect(!picture.fits(window, glass: true, sidebar: nil))
            #expect(!picture.fits(window, glass: false, sidebar: sidebar))
            window.appearance = NSAppearance(named: .aqua)
            #expect(!picture.fits(window, glass: true, sidebar: sidebar))
            window.appearance = NSAppearance(named: .darkAqua)
            window.scale = 1
            #expect(!picture.fits(window, glass: true, sidebar: sidebar))
            window.scale = 2
            window.setContentSize(NSSize(width: 101, height: 80))
            #expect(!picture.fits(window, glass: true, sidebar: sidebar))
        }
    }
}

@MainActor
private final class ScaledWindow: AwayWindow {
    var scale: CGFloat = 1
    override var backingScaleFactor: CGFloat { scale }
}
