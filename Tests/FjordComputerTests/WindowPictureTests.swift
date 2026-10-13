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

    /// A picture is the window's when drawn alike; forgiven a small difference only when nothing was typed, clicked, asked
    /// or synced since (the window's own noise); stale otherwise, or for another place, or with nothing to compare.
    @Test func aPicturesFreshnessWeighsItsPixelsAgainstWhatHappenedSince() throws {
        let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let base = glance(20, 20)
        let marks = AppTransition.Marks(changes: 3, inbox: 1, inboxDisplay: 0, router: 7)
        let picture = AppTransition.Picture(image: try #require(bitmap.makeImage()), frame: .zero, scale: 2,
                                            destination: .router, glance: base, marks: marks)
        func fresh(_ now: Glance?, _ marks: AppTransition.Marks = marks, _ place: AppDestination = .router,
                   tolerance: Double = 0.005) -> AppTransition.Freshness {
            AppTransition.freshness(of: picture, glance: now, marks: marks, destination: place, tolerance: tolerance)
        }
        let speck = glance(20, 20, [(0, 200)])  // one pixel of 400: 0.25%
        #expect(fresh(base) == .same)
        #expect(fresh(speck) == .cosmetic)
        // A key typed (or a sync) since: not forgiven.
        var typed = marks
        typed.changes += 1
        #expect(fresh(speck, typed) == .stale && fresh(base, typed) == .same)
        // Tighter for an opening, and never for another place or nothing to compare.
        #expect(fresh(speck, tolerance: 0.001) == .stale)
        #expect(fresh(base, marks, .settings) == .stale && fresh(nil) == .stale)
    }

    @Test func newerGlancesRaiseTheEstimateOfAlreadyMeasuredPictures() {
        typealias Costs = AppTransition.CaptureCosts
        var costs = Costs()
        let size = NSSize(width: 1000, height: 500)
        for scale: CGFloat in [0.5, 1, 2] {
            costs.record(0.01, size: size, pixelScale: scale, page: "router", at: 0)
        }
        for at in [1.0, 2.0] {
            costs.record(0.04, size: size, pixelScale: AppTransition.glanceScale, page: "router", at: at)
        }
        for scale: CGFloat in [0.5, 1, 2] {
            let floor = 0.04 * pow(Double(scale / AppTransition.glanceScale), 2 * Costs.growth)
            #expect(costs.estimate(size: size, pixelScale: scale, page: "router", at: 2) >= floor)
        }
    }

    @Test func aSlowCaptureCountsForAMinuteRegardlessOfHowManyFollow() {
        var costs = AppTransition.CaptureCosts()
        let size = NSSize(width: 1000, height: 500)
        costs.record(0.52, size: size, pixelScale: 1, page: "router", at: 0)
        for at in 1...10 {
            costs.record(0.01, size: size, pixelScale: 1, page: "router", at: Double(at))
        }
        #expect(costs.estimate(size: size, pixelScale: 1, page: "router", at: 59.999) == 0.52)
        #expect(costs.estimate(size: size, pixelScale: 1, page: "router", at: 60) == 0.01)
    }

    /// A capture's cost is the longest in the last minute on that page at that size and scale, so one slow capture keeps the
    /// next from being let in on a mean, until it is a minute old; another page is its own (a heavy one at the same size
    /// is not let in on a light one's costs); a scale never drawn there is guessed from those drawn (a glance) and with
    /// none from a pessimistic prior; a full picture is never guessed under the latest soft one times its pixels.
    @Test func aCapturesCostIsItsPagesRecentWorst() {
        typealias Costs = AppTransition.CaptureCosts
        var costs = Costs()
        let size = NSSize(width: 1000, height: 500)
        let prior = costs.estimate(size: size, pixelScale: 2, page: "router", at: 0)
        #expect(abs(prior - 1000 * 500 * 4 * Costs.prior) < 1e-9)
        for (n, cost) in [0.06, 0.52, 0.06, 0.07].enumerated() {
            costs.record(cost, size: size, pixelScale: 2, page: "router", at: Double(n))
        }
        #expect(costs.estimate(size: size, pixelScale: 2, page: "router", at: 10) == 0.52)
        // A minute on, the slow one no longer counts.
        costs.record(0.065, size: size, pixelScale: 2, page: "router", at: 63.5)
        #expect(costs.estimate(size: size, pixelScale: 2, page: "router", at: 63.5) == 0.065)
        // Another page at the same size: nothing known there but the prior.
        #expect(costs.estimate(size: size, pixelScale: 2, page: "settings", at: 62) == prior)
        // A glance drawn there: the other scales follow from it, less than in proportion to their pixels.
        costs.record(0.004, size: size, pixelScale: 0.25, page: "settings", at: 62)
        let soft = costs.estimate(size: size, pixelScale: 1, page: "settings", at: 62)
        #expect(abs(soft - 0.004 * pow(16, Costs.growth)) < 1e-9)
        // A soft picture measured: a full one is never guessed under it times the pixels.
        costs.record(0.02, size: size, pixelScale: 1, page: "settings", at: 63)
        #expect(costs.estimate(size: size, pixelScale: 2, page: "settings", at: 63) >= 0.08)
        // Keys are bounded: the stalest goes.
        for n in 0..<40 { costs.record(0.01, size: size, pixelScale: 1, page: "p\(n)", at: 100 + Double(n)) }
        #expect(costs.estimate(size: size, pixelScale: 2, page: "p0", at: 140) == prior)
        #expect(costs.estimate(size: size, pixelScale: 1, page: "p39", at: 140) == 0.01)
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

        /// Without glass the morph lasts as long as with it, and as the bar's fade on a close: 0.30 s, not Core Animation's
        /// 0.35 s settling time.
        @Test func theMorphWithoutGlassLastsAsLongAsTheBarsFade() throws {
            _ = NSApplication.shared
            let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 400, height: 300)),
                                    styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let run = try #require(AppTransition.makeRun(for: window, picture: nil, bar: nil, glass: false))
            defer { run.end() }
            #expect(!run.isGlass && run.motionLength(.closing) == GlassMorph.duration(.closing))
            #expect(abs(run.motionLength(.closing) - AppTransition.duration) < 0.005)
        }
    }
}

@MainActor
private final class ScaledWindow: AwayWindow {
    var scale: CGFloat = 1
    override var backingScaleFactor: CGFloat { scale }
}
