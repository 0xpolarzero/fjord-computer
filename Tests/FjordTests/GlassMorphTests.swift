import AppKit
import SwiftUI
import Testing
@testable import Fjord

/// The glass morph (glass-plan §5.6, M1) and the capture flag: the flag's in-turn sequence, what each glass piece draws
/// while its root is captured, and the morph's geometry and timing.
@MainActor @Suite struct GlassMorphTests {
    // MARK: The capture flag

    @Test func onGlassTheFlagIsOnForTheCaptureOnlyAndTheRootIsDrawnEachWay() {
        var steps: [String] = []
        let picture = GlassCapture.sequence(glass: true, set: { steps.append($0 ? "on" : "off") },
                                            settle: { steps.append("settle") }, draw: { steps.append("draw"); return 7 })
        #expect(picture == 7)
        #expect(steps == ["on", "settle", "draw", "off", "settle"])
    }

    /// A close's capture turns the flag off without drawing the root again: the window goes out of sight in that turn.
    @Test func aCloseRestoresTheFlagWithoutDrawingTheRootAgain() {
        var steps: [String] = []
        _ = GlassCapture.sequence(glass: true, set: { steps.append($0 ? "on" : "off") }, settle: { steps.append("settle") },
                                  draw: { steps.append("draw") }, restoreLater: true)
        #expect(steps == ["on", "settle", "draw", "off"])
    }

    @Test func withNoGlassOnlyTheCaptureRuns() {
        var steps: [String] = []
        let picture = GlassCapture.sequence(glass: false, set: { steps.append($0 ? "on" : "off") },
                                            settle: { steps.append("settle") }, draw: { steps.append("draw"); return 1 })
        #expect(picture == 1 && steps == ["draw"])
    }

    @Test func theFlagIsOnDuringTheCaptureAndOffAfter() {
        let capture = GlassCapture()
        var during: Bool?
        capture.around(glass: true, settle: {}) { during = capture.on }
        #expect(during == true && !capture.on)
        capture.around(glass: false, settle: {}) { during = capture.on }
        #expect(during == false && !capture.on)
    }

    // MARK: Which pieces swap

    /// The small pieces (nav capsule, composer) draw their fill under a capture; the sidebar never reads the flag, so it
    /// keeps its glass (`PanelMaterial(standsIn: false)`).
    @Test func aPieceDrawsItsFillOnlyOnGlassUnderACapture() {
        // Opaque mode: the fill, and the hairline where the piece has one, capture or not.
        for capturing in [false, true] {
            #expect(GlassLook.of(glass: false, capturing: capturing, hairline: true)
                    == GlassLook(glass: false, fill: true, hairline: true))
            #expect(GlassLook.of(glass: false, capturing: capturing) == GlassLook(glass: false, fill: true, hairline: false))
        }
        #expect(GlassLook.of(glass: true, capturing: false, hairline: true) == GlassLook(glass: true, fill: false, hairline: false))
        #expect(GlassLook.of(glass: true, capturing: true, hairline: true) == GlassLook(glass: false, fill: true, hairline: false))
    }

    // MARK: The sidebar's hole

    /// The sidebar's rounded rect comes out clear and nothing else changes, at 2x as at 1x (the rect is in points).
    @Test(arguments: [1, 2]) func thePunchedPictureIsClearInsideTheSidebarOnly(scale: Int) throws {
        let size = NSSize(width: 200, height: 120)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200 * scale, pixelsHigh: 120 * scale,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.red.setFill()
        // Larger than the bitmap whatever scale its context starts with: every pixel opaque.
        NSRect(x: 0, y: 0, width: 10_000, height: 10_000).fill()
        NSGraphicsContext.restoreGraphicsState()
        let hole = AppTransition.Hole(rect: NSRect(x: 8, y: 8, width: 60, height: 104), radius: 8)
        AppTransition.punch(rep, hole)
        // `colorAt` counts pixels from the top: the hole is symmetric top to bottom, so it reads the same.
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            rep.colorAt(x: Int(x * CGFloat(scale)), y: Int(y * CGFloat(scale)))?.alphaComponent ?? -1
        }
        #expect(alpha(38, 60) == 0)
        #expect(alpha(10, 60) == 0 && alpha(66, 60) == 0 && alpha(38, 10) == 0 && alpha(38, 110) == 0)
        #expect(alpha(4, 60) == 1 && alpha(72, 60) == 1 && alpha(150, 60) == 1 && alpha(38, 4) == 1 && alpha(38, 116) == 1)
        // The corner itself stays (rounded, not square).
        #expect(alpha(8.5, 8.5) == 1)
    }

    /// In the hole the ground goes clear and what is drawn over it stays: a solid glyph pixel as it was, an anti-aliased
    /// one as the glyph's colour at partial alpha. Outside the hole, and in its rounded corner, nothing changes.
    @Test(arguments: [1, 2]) func theHoleKeepsTheSidebarsLabelsOverAClearGround(scale: Int) throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200 * scale, pixelsHigh: 120 * scale,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 200, height: 120)
        #expect(rep.bitmapFormat.isDisjoint(with: [.alphaFirst, .alphaNonpremultiplied, .floatingPointSamples]))
        let data = try #require(rep.bitmapData)
        // Pixels in points from the bottom, as the hole is; rows in memory from the top.
        func at(_ x: CGFloat, _ y: CGFloat) -> Int {
            (rep.pixelsHigh - 1 - Int(y * CGFloat(scale))) * rep.bytesPerRow + Int(x * CGFloat(scale)) * 4
        }
        func set(_ x: CGFloat, _ y: CGFloat, _ pixel: [UInt8]) { for i in 0..<4 { data[at(x, y) + i] = pixel[i] } }
        func pixel(_ x: CGFloat, _ y: CGFloat) -> [Int] { (0..<4).map { Int(data[at(x, y) + $0]) } }
        let ground: [UInt8] = [240, 236, 232, 255]
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide { for i in 0..<4 { data[y * rep.bytesPerRow + x * 4 + i] = ground[i] } }
        }
        // A solid black glyph pixel, and (0, 90, 200) at half coverage over the ground.
        set(30, 60, [0, 0, 0, 255])
        set(40, 60, [120, 163, 216, 255])
        // Outside the hole: a glyph pixel in the page, which stays as it is.
        set(150, 30, [0, 0, 0, 255])
        let hole = AppTransition.Hole(rect: NSRect(x: 8, y: 8, width: 60, height: 104), radius: 8)
        AppTransition.punch(rep, hole)

        #expect(pixel(38, 30) == [0, 0, 0, 0] && pixel(10, 60) == [0, 0, 0, 0] && pixel(38, 110) == [0, 0, 0, 0])
        #expect(pixel(30, 60) == [0, 0, 0, 255])
        let mid = pixel(40, 60)
        #expect(abs(mid[3] - 128) <= 1)
        // Unpremultiplied, it is the glyph's colour.
        let colour = (0..<3).map { Double(mid[$0]) * 255 / Double(mid[3]) }
        for (got, want) in zip(colour, [0.0, 90, 200]) { #expect(abs(got - want) <= 3) }
        #expect(pixel(4, 60) == [240, 236, 232, 255] && pixel(150, 60) == [240, 236, 232, 255])
        #expect(pixel(38, 4) == [240, 236, 232, 255] && pixel(38, 116) == [240, 236, 232, 255])
        #expect(pixel(150, 30) == [0, 0, 0, 255])
        // The rounded corner, outside the shape.
        #expect(pixel(8.5, 8.5) == [240, 236, 232, 255] && pixel(67.5, 111.5) == [240, 236, 232, 255])
    }

    /// A bitmap other than 8-bit RGBA has the hole cleared whole, as before.
    @Test func anotherFormatHasTheHoleClearedWhole() throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120,
                                                bitsPerSample: 16, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 200, height: 120)
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 10_000, height: 10_000).fill()
        NSColor.black.setFill()
        NSRect(x: 30, y: 58, width: 4, height: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        AppTransition.punch(rep, AppTransition.Hole(rect: NSRect(x: 8, y: 8, width: 60, height: 104), radius: 8))
        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
        #expect(alpha(31, 60) == 0 && alpha(38, 60) == 0)
        #expect(alpha(4, 60) == 1 && alpha(150, 60) == 1)
    }

    @Test func aWindowWithoutASidebarOrNotOnGlassHasNoHole() {
        let sidebar = NSRect(x: 8, y: 8, width: 240, height: 584)
        #expect(AppTransition.GlassWindow(sidebar: sidebar).hole(glass: true, radius: 16)
                == AppTransition.Hole(rect: sidebar, radius: 8))
        #expect(AppTransition.GlassWindow(sidebar: sidebar).hole(glass: false, radius: 16) == nil)
        #expect(AppTransition.GlassWindow(sidebar: nil).hole(glass: true, radius: 16) == nil)
    }

    /// A picture kept from a close stands in only for the same morph: one taken for glass (its sidebar cleared) never
    /// opens an opaque morph, nor the other way round.
    @Test func aKeptPictureFitsOnlyTheMorphItWasTakenFor() throws {
        let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 100, height: 80)),
                                styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for glass in [false, true] {
            let picture = AppTransition.Picture(image: try #require(bitmap.makeImage()), frame: window.frame,
                                                scale: window.backingScaleFactor, destination: .settings, glass: glass)
            #expect(picture.fits(window, glass: glass))
            #expect(!picture.fits(window, glass: !glass))
        }
    }

    // MARK: Geometry

    @Test func theSidebarsFrameAndRadiusAreTheInsetPanels() {
        let size = NSSize(width: 1180, height: 760)
        #expect(GlassMorph.sidebarFrame(windowSize: size, collapsed: false)
                == NSRect(x: 8, y: 8, width: AppRootView.sidebarWidth, height: 744))
        // The rail starts under the header's line: 760 less its 48 and the bottom inset.
        #expect(GlassMorph.sidebarFrame(windowSize: size, collapsed: true)
                == NSRect(x: 8, y: 8, width: AppSidebar.railWidth, height: 704))
        #expect(GlassMorph.sidebarRadius(windowRadius: 16) == 8)
        #expect(GlassMorph.sidebarRadius(windowRadius: 26) == 18)
        // Full screen (no radius) and small radii keep the floor.
        #expect(GlassMorph.sidebarRadius(windowRadius: 0) == WindowChrome.minimumRadius)
        #expect(GlassMorph.sidebarRadius(windowRadius: 10) == WindowChrome.minimumRadius)
    }

    @Test func g2IsTheSidebarAtTheWindowsRectAndScalesWithIt() {
        let window = NSSize(width: 1000, height: 600)
        let sidebar = NSRect(x: 8, y: 8, width: 240, height: 584)
        let frame = NSRect(x: 300, y: 200, width: 1000, height: 600)
        #expect(GlassMorph.scaled(sidebar, window: window, in: frame) == sidebar.offsetBy(dx: 300, dy: 200))
        #expect(GlassMorph.scaledRadius(8, piece: sidebar.size, window: window, in: frame) == 8)
        let half = NSRect(x: 100, y: 50, width: 500, height: 300)
        #expect(GlassMorph.scaled(sidebar, window: window, in: half) == NSRect(x: 104, y: 54, width: 120, height: 292))
        #expect(GlassMorph.scaledRadius(8, piece: sidebar.size, window: window, in: half) == 4)
        // A cell-sized rect: the radius never passes half the shape's side.
        let cell = NSRect(x: 0, y: 0, width: 40, height: 4)
        #expect(GlassMorph.scaledRadius(100, piece: sidebar.size, window: window, in: cell) <= 240 * 0.04 / 2)
        #expect(GlassMorph.scaled(sidebar, window: .zero, in: frame).size == .zero)
    }

    // MARK: Timing

    @Test func bothSpringsAreCriticallyDamped() {
        for spring in [AppTransition.Spring.opening, .closing] {
            let critical = 2 * spring.stiffness.squareRoot()
            #expect(abs(spring.damping - critical) / critical < 0.01)
        }
    }

    /// The glass's curve stands for the critically damped spring within 3% all the way, and starts and ends where it does.
    @Test func theGlassCurveFollowsTheSpring() {
        let (x1, y1, x2, y2) = GlassMorph.controlPoints
        func bezier(_ u: Double) -> Double {
            func point(_ s: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
            }
            var lo = 0.0, hi = 1.0
            for _ in 0..<60 {
                let s = (lo + hi) / 2
                if point(s, Double(x1), Double(x2)) < u { lo = s } else { hi = s }
            }
            return point((lo + hi) / 2, Double(y1), Double(y2))
        }
        var worst = 0.0
        for i in 0...200 {
            let u = Double(i) / 200
            worst = max(worst, abs(bezier(u) - GlassMorph.springProgress(u)))
        }
        #expect(worst < 0.03)
        #expect(GlassMorph.springProgress(0) == 0 && GlassMorph.springProgress(1) > 0.998)
        #expect(y2 == 1 && y1 <= 1)
    }

    @Test func theGlassMorphLastsTheSpringsSettlingTime() {
        #expect(abs(GlassMorph.duration(.opening) - 9.23 / 946.0.squareRoot()) < 0.0001)
        #expect(abs(GlassMorph.duration(.closing) - 9.23 / 946.0.squareRoot()) < 0.0001)
        // The bar's own fade on a close lasts as long as the close, glass or not.
        #expect(abs(AppTransition.duration - GlassMorph.duration(.closing)) < 0.005)
        // About 0.30 s each way.
        #expect(abs(GlassMorph.duration(.opening) - 0.30) < 0.005 && abs(GlassMorph.duration(.closing) - 0.30) < 0.005)
    }

    /// Opening: G1 in at once, the container (and G2 with it) over the second half, in before the handoff; closing: the
    /// container goes first, G1 last, into the bar's glass.
    @Test func theGlassMorphsFadesAreOrderedAsThePlanSays() {
        typealias O = AppTransition.Run.Opacities
        let open = O.glassOpening
        #expect(open.glass.0 == 0 && open.glass.1 <= 0.1)
        #expect(open.container.0 >= 0.4 && open.container.0 + open.container.1 <= 0.95)
        #expect(open.shadow == open.container)
        let close = O.glassClosing
        #expect(close.container.0 + close.container.1 <= close.glass.0)
        #expect(close.glass.0 + close.glass.1 <= 1)
        #expect(close.window.0 + close.window.1 <= close.container.0 + close.container.1)
        // Today's morph has no glass to fade.
        #expect(O.opening.glass == (0, 0) && O.closing.glass == (0, 0))
    }
}

extension WindowSeams {
    /// The glass morph's overlay: G1 under the container, G2 over it, the picture on top; the glass moved to the window on
    /// an opening, G1 kept out of Reduce Motion's fade.
    @MainActor
    @Suite(.hostsWindows) struct GlassMorphOverlayTests {
        private func makeRun(sidebar: NSRect?) throws -> (run: AppTransition.Run, window: NSWindow)? {
            guard #available(macOS 26, *) else { return nil }
            _ = NSApplication.shared
            let screen = try #require(NSScreen.main)
            let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 600, height: 400)),
                                    styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let bar = BarMorph(frame: NSRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 46, height: 200))
            let run = try #require(AppTransition.makeRun(for: window, picture: nil, bar: bar,
                                                         glassWindow: .init(sidebar: sidebar), glass: true))
            return (run, window)
        }

        private static let sidebar = NSRect(x: 8, y: 8, width: 240, height: 384)

        /// The flag's change is taken in by a hosting view within the turn: the capture sees the stand-in, and the root is back
        /// as it was before the turn ends. Another root's flag is never touched.
        @Test func aHostingViewTakesTheFlagInWithinTheTurn() {
            _ = NSApplication.shared
            let capture = GlassCapture()
            let other = GlassCapture()
            let seen = Seen()
            let otherSeen = Seen()
            let host = NSHostingView(rootView: Probe(seen: seen).environment(\.glassCapture, capture))
            let otherHost = NSHostingView(rootView: Probe(seen: otherSeen).environment(\.glassCapture, other))
            let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 40, height: 40)),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            host.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            otherHost.frame = NSRect(x: 20, y: 0, width: 20, height: 20)
            root.addSubview(host)
            root.addSubview(otherHost)
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            #expect(seen.values.last == false)
            let otherBodies = otherSeen.values.count
            var during: Bool?
            capture.around(glass: true, settle: { GlassCapture.settle(host: host, root: host, window: window) }) {
                during = seen.values.last
            }
            #expect(during == true)
            #expect(seen.values.last == false && !capture.on)
            #expect(otherSeen.values.count == otherBodies && !other.on)
        }

        @Test func theOverlayStacksTheGlassBetweenItsLayers() throws {
            guard #available(macOS 26, *), let made = try makeRun(sidebar: Self.sidebar) else { return }
            defer { made.run.end(); made.window.close() }
            #expect(made.run.isGlass)
            let views = try #require(made.run.overlay.contentView?.subviews)
            #expect(views.count == 5)
            #expect(views[1] is NSGlassEffectView && views[3] is NSGlassEffectView)
            #expect(!(views[0] is NSGlassEffectView) && !(views[2] is NSGlassEffectView) && !(views[4] is NSGlassEffectView))
        }

        @Test func noSidebarNoG2() throws {
            guard #available(macOS 26, *), let made = try makeRun(sidebar: nil) else { return }
            defer { made.run.end(); made.window.close() }
            let views = try #require(made.run.overlay.contentView?.subviews)
            #expect(views.count == 5 && views[3].isHidden && !views[1].isHidden)
        }

        /// The glass views are made once: the next glass morph takes up the same ones, and an older morph's end leaves the
        /// newer one's overlay alone.
        @Test func theGlassViewsAreTakenUpByEachMorph() throws {
            guard #available(macOS 26, *), let first = try makeRun(sidebar: Self.sidebar) else { return }
            let views = try #require(first.run.overlay.contentView?.subviews)
            defer { first.window.close() }
            let second = try #require(try makeRun(sidebar: nil))
            defer { second.run.end(); second.window.close() }
            let again = try #require(second.run.overlay.contentView?.subviews)
            #expect(again.count == views.count && zip(again, views).allSatisfy { $0 === $1 })
            #expect(again[3].isHidden)
            second.run.show()
            first.run.end()
            #expect(second.run.overlay.isVisible && second.run.overlay.contentView?.subviews.count == 5)
        }

        @Test(arguments: [false, true]) func aCloseResumesTheRetainedGlassPicturesHandoffOpacity(reduced: Bool) throws {
            guard #available(macOS 26, *), let made = try makeRun(sidebar: Self.sidebar) else { return }
            let run = made.run, nextFrames = AppTransition.nextFrames
            AppTransition.nextFrames = { _, _, done in done() }
            defer { run.end(); made.window.close(); AppTransition.nextFrames = nextFrames }
            let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let picture = AppTransition.Picture(image: try #require(bitmap.makeImage()), frame: made.window.frame,
                                                scale: made.window.backingScaleFactor, destination: .settings,
                                                glass: true, sidebar: Self.sidebar)
            run.install(picture)
            run.open(reduced: false) {}
            run.complete()
            run.handoff(fading: true, reveal: {}, finished: {})
            #expect(run.isGlass && run.image === picture.image && run.fadingContent)
            let views = try #require(run.overlay.contentView?.subviews)
            let container = try #require(views[2].layer?.sublayers?.first)
            let clip = try #require(views[4].layer?.sublayers?.first)
            let image = try #require(clip.sublayers?.first)
            let fading = [container, clip, try #require(views[1].layer), try #require(views[3].layer)]
            defer { for layer in fading { layer.speed = 1; layer.timeOffset = 0 } }
            // Freeze the actual handoff animations at half time, with model opacity zero and presentation opacity half.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in fading {
                let animation = try #require(layer.animation(forKey: "handoff")?.copy() as? CAAnimation)
                animation.beginTime = 1
                layer.speed = 0
                layer.timeOffset = 1 + animation.duration / 2
                layer.add(animation, forKey: "handoff")
            }
            CATransaction.commit()
            CATransaction.flush()
            let drawn = try #require(clip.presentation()?.opacity)
            #expect(clip.opacity == 0 && abs(drawn - 0.5) < 0.001)
            run.resume()
            run.close(reduced: reduced) {}
            #expect(run.image === picture.image && abs((run.startPose?.window ?? 1) - drawn) < 0.001)
            // The resumed picture starts at the same visible opacity, whether the fade lives on its clip or image.
            let clipStart = (clip.animation(forKey: "opacity") as? CABasicAnimation)?.fromValue as? Float ?? clip.opacity
            let imageStart = (image.animation(forKey: "opacity") as? CABasicAnimation)?.fromValue as? Float ?? image.opacity
            #expect(abs(clipStart * imageStart - drawn) < 0.001)
            #expect(abs((run.startPose?.container ?? 1) - 0.5) < 0.001)
            #expect(abs((run.startPose?.glass ?? 1) - (reduced ? 0 : 0.5)) < 0.001)
        }

        @Test func anOpeningStartsAsGlassAtTheBarsCell() throws {
            guard #available(macOS 26, *), let made = try makeRun(sidebar: Self.sidebar) else { return }
            let run = made.run
            defer { run.end(); made.window.close() }
            var done = false
            run.open(reduced: false) { done = true }
            #expect(run.startPose?.rect == run.bar?.cellFrame && run.startPose?.glass == 0 && run.startPose?.container == 0)
            run.complete()
            let views = try #require(run.overlay.contentView?.subviews)
            #expect(done && views[1].alphaValue == 1 && views[3].alphaValue == 1)
        }

        /// Reduce Motion: the shapes sit at the window's frame and the sidebar's (set, not animated), G1 out of the fade.
        @Test func reduceMotionFadesWithoutG1() throws {
            guard #available(macOS 26, *), let made = try makeRun(sidebar: Self.sidebar) else { return }
            let run = made.run
            defer { run.end(); made.window.close() }
            run.open(reduced: true) {}
            let views = try #require(run.overlay.contentView?.subviews)
            let local = run.geometry.local(made.window.frame)
            #expect(views[1].alphaValue == 0 && views[1].frame == local)
            #expect(views[3].frame == Self.sidebar.offsetBy(dx: local.minX, dy: local.minY))
            run.complete()
            #expect(views[3].alphaValue == 1)
        }
    }
}

@MainActor private final class Seen { var values: [Bool] = [] }

/// Records the capture flag each time its body runs.
private struct Probe: View {
    let seen: Seen
    @Environment(\.glassCapture) private var capture

    var body: some View {
        seen.values.append(capture?.on == true)
        return Color.clear.frame(width: 20, height: 20)
    }
}
