import AppKit
import OSLog
import QuartzCore
import SwiftUI

// The morph between the bar and the app window: the window grows out of the bar's cell when it opens, and shrinks back into
// it when it closes. One borderless overlay covers the morph and hosts a few Core Animation layers (the window's exact
// picture, the bar's, a shadow like the window's own) that the render server moves on a spring at the display's rate; the
// real window waits, invisible, at its frame. At the end of an opening the real window is shown under the identical
// overlay, which goes only once it has been composited, so nothing pops. Reduce Motion gets a short cross-fade of the
// overlay, and a test run no animation at all.
//
// An opening moves first and draws after: the morph starts on the picture kept from the last close (or the window's bare
// surface), with nothing captured, and its first frame is flushed to the render server (submitted, not yet proven drawn)
// before the window's content is built, a turn later; a fresh picture then replaces it, in place before the real window
// takes over.
//
// Each step is a signpost interval (subsystem com.amontlabs.fjord, category "morph"), to see in Instruments where an
// opening's time goes: the request to the first flush, bringing the window in, each capture and picture installed, the
// handoff, and the overlay going; on glass, inside each capture, the capture flag's two passes ("Capture flag on", "Capture
// flag off": the stand-ins drawn, then the glass restored) and the sidebar's ground taken out ("Unblend sidebar"). G1, G2
// and their hosts are made once, at idle with the overlay (`prepareOverlay`), and taken up by each glass morph, so a morph
// makes no view before its first frame.
//
// On glass (macOS 26, `Chrome.Mode.glass`) the morph starts as the bar's glass (docs/design/fjord/glass-plan.md §5.6, M1).
// The overlay holds, bottom to top: the shadow; G1, a glass shape (`NSGlassEffectView`) growing from the bar's cell to the
// window's frame and corners, moved by `NSAnimationContext` and `animator()` (the one way that moved glass without a
// dropped frame, §11 S5); the window-shaped `s1` container, fading in over the second half; G2, a glass shape at the inset
// sidebar's frame riding the container's opacity, so it samples `s1` as the real sidebar does; and the window's picture,
// whole, in a clip of the window's shape. The window's captures draw the small glass pieces (the nav capsule, the
// composer) as their opaque fills (`GlassCapture`), and the window's ground is taken out of the sidebar's rounded rect
// after the picture is taken (`punch`, colour-to-alpha), so the picture shows G2 through where the sidebar is with the
// sidebar's rows, icons and counts still on it. Every layer runs the same curve as the glass (the springs as one cubic,
// `GlassMorph.curve`), so the glass and the picture move in lockstep. No picture of the bar is taken: G1 is its glass.
// Closing mirrors it, G1 fading into the bar's glass as the bar fades in beneath. Reduce Motion: the cross-fade at the
// window's frame, G2 and the picture fading with the container. Opaque mode and macOS 14 and 15: the morph above,
// unchanged.

/// The morph's signposts.
enum MorphSignposts {
    static let signposter = OSSignposter(subsystem: InboxLog.subsystem, category: "morph")
}

/// Where the bar is, for the morph to start from or end at.
struct BarMorph {
    /// On screen (AppKit coordinates).
    var frame: NSRect
    /// The bar as it looks, when it can be shown (it is on screen).
    var snapshot: NSImage?
    /// The cell the window grows out of (the one clicked, else the GitHub mark's); nil: derived from the bar's frame.
    var cell: NSRect?
    var cellRadius: CGFloat = 10

    /// The cell's place on screen.
    var cellFrame: NSRect {
        if let cell { return cell }
        let side = min(36, frame.width, frame.height)
        return NSRect(x: frame.minX + (frame.width - side) / 2, y: frame.maxY - side - 4, width: side, height: side)
    }
}

@MainActor
enum AppTransition {
    /// The bar's own fade-in on a close (the morph's overlay shrinks over it).
    static let duration: TimeInterval = 0.38
    static let reducedDuration: TimeInterval = 0.15
    /// A fresh picture fading in over another (or over the bare surface) during an opening.
    static let pictureFade: TimeInterval = 0.12
    static let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    /// A window's corner radius when the system does not say.
    static let fallbackRadius: CGFloat = 16
    static let shadowRadius: CGFloat = 22
    static let shadowOffset = CGSize(width: 0, height: -10)
    /// The handoff's shadow mask already keeps this much room. Keep the same envelope around every pose: over eight blur
    /// radii beyond the downward offset, rather than treating a blur radius as its cutoff.
    static let shadowRoom: CGFloat = 200

    /// Off under a test: the window opens and closes at once.
    static var enabled = !UnderTest.isRunning
    /// The glass morph (M1) may run: off under a test (whose morphs check today's layers) unless the test turns it on.
    static var glassMorph = !UnderTest.isRunning
    /// The morph that runs now is the glass one: allowed, and the chrome draws glass.
    static var usesGlass: Bool { glassMorph && GlassCapture.chromeIsGlass }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// `FJORD_SLOW_MORPH=10` runs the morph ten times slower, to look at it.
    static var slowdown: Float {
        ProcessInfo.processInfo.environment["FJORD_SLOW_MORPH"].flatMap(Float.init).map { max($0, 1) } ?? 1
    }

    /// Runs `block` once the screen has refreshed `count` times, on one display link. Replaceable, so a test can step the
    /// frames itself.
    static var nextFrames: (NSScreen?, Int, @escaping @MainActor () -> Void) -> Void = { screen, count, block in
        FrameTick.wait(count, on: screen, block)
    }

    /// Runs `block` on the screen's next refresh.
    static func nextFrame(_ screen: NSScreen?, _ block: @escaping @MainActor () -> Void) { nextFrames(screen, 1, block) }
    /// Submits an opening's first frame to the render server before its window is built: the motion goes ahead of the
    /// heavy work rather than waiting behind it. Replaceable, so a test can see when it happens.
    static var flushInitial: () -> Void = { CATransaction.flush() }
    /// Runs `block` on the main queue's next turn (after the current one has committed). Replaceable, as `nextFrame`.
    static var nextTurn: (@escaping @MainActor () -> Void) -> Void = { block in
        DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
    }

    /// Whether `window` has the keyboard (its buttons in colour). Replaceable, so a test can have a key window.
    static var isKey: (NSWindow) -> Bool = { $0.isKeyWindow }
    /// Whether `window` is in the Dock. Replaceable, as `isKey` (a window under test does not minimize at once).
    static var isMiniaturized: (NSWindow) -> Bool = { $0.isMiniaturized }

    /// The window's own corner radius (macOS 26's are larger than before), so nothing changes when the real window takes over.
    /// In full screen it has none.
    static func cornerRadius(of window: NSWindow) -> CGFloat {
        if window.styleMask.contains(.fullScreen) { return 0 }
        guard let frame = window.contentView?.superview else { return fallbackRadius }
        if frame.layer?.cornerRadius ?? 0 > 0 { return frame.layer?.cornerRadius ?? fallbackRadius }
        let key = "_cornerRadius"
        if frame.responds(to: Selector(key)), let radius = (frame.value(forKey: key) as? NSNumber)?.doubleValue, radius > 0 {
            return CGFloat(radius)
        }
        return fallbackRadius
    }

    /// How many pictures of a window were taken (the tests count them).
    private(set) static var captures = 0

    /// A place in a window's picture whose ground is taken out: the inset sidebar's rounded rect (window coordinates),
    /// which the glass morph's G2 shows through, under the sidebar's labels.
    struct Hole: Equatable {
        var rect: NSRect
        var radius: CGFloat
    }

    /// The window's pixels as they are now: its whole frame (title bar and buttons included) at the screen's scale. With
    /// the window's capture flag (`capture`) and glass on, its small glass pieces are drawn as their stand-ins for the
    /// picture and restored, in this turn (`GlassCapture.around`); the ground is then taken out of `hole` (`punch`).
    static func snapshot(of window: NSWindow, capture: GlassCapture? = nil, hole: Hole? = nil) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0 else { return nil }
        captures += 1
        let signpost = MorphSignposts.signposter.beginInterval("Capture")
        defer { MorphSignposts.signposter.endInterval("Capture", signpost) }
        let glass = GlassCapture.chromeIsGlass
        let cleared = glass ? hole : nil
        let draw = { () -> CGImage? in
            // With alpha whatever the window's opacity, where there is a hole: its ground must come out clear, not black.
            let made = cleared != nil ? alphaRep(for: view) : view.bitmapImageRepForCachingDisplay(in: view.bounds)
            guard let rep = made else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let cleared { punch(rep, cleared) }
            return rep.cgImage
        }
        if let capture, glass {
            // The capture itself still runs on the theme frame; the flag is the content's root's.
            return capture.around(glass: true,
                                  settle: { GlassCapture.settle(host: window.contentView, root: view, window: window) },
                                  draw)
        }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return draw()
    }

    /// A bitmap to cache `view`'s display in, at its backing scale, with an alpha channel, in the colour space the view's
    /// own would have (a P3 display's included), so the picture matches the live window.
    private static func alphaRep(for view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        if rep.hasAlpha { return rep }
        guard let alpha = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // Retagged before anything is drawn: the pixels are converted to that space as they are drawn.
        let tagged = alpha.colorSpace == rep.colorSpace ? alpha : (alpha.retagging(with: rep.colorSpace) ?? alpha)
        tagged.size = rep.size
        return tagged
    }

    /// Takes the window's ground out of `hole` (in points, the rep's `size`) in `rep`, keeping what is drawn over it: the
    /// sidebar's rows, icons and counts stay, with their exact edges, and the ground between them goes transparent, so G2
    /// shows through it with the labels already on it. Untouched outside the shape (the sidebar's, continuous corners).
    /// The ground is read from the picture itself, just right of the hole, in the bitmap's own colour space. A bitmap
    /// other than 8-bit RGBA, or no opaque ground to read, has the hole cleared whole instead.
    static func punch(_ rep: NSBitmapImageRep, _ hole: Hole) {
        guard rep.hasAlpha, rep.size.width > 0, rep.size.height > 0 else { return }
        let signpost = MorphSignposts.signposter.beginInterval("Unblend sidebar")
        defer { MorphSignposts.signposter.endInterval("Unblend sidebar", signpost) }
        if unblend(rep, hole) { return }
        clear(rep, hole)
    }

    /// Clears `hole` out of `rep` whole: transparent there, untouched elsewhere. Drawn in the bitmap's own pixels whatever
    /// scale its context starts with.
    private static func clear(_ rep: NSBitmapImageRep, _ hole: Hole) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = context.cgContext
        cg.saveGState()
        cg.concatenate(cg.ctm.inverted())
        cg.scaleBy(x: CGFloat(rep.pixelsWide) / rep.size.width, y: CGFloat(rep.pixelsHigh) / rep.size.height)
        cg.setBlendMode(.clear)
        cg.addPath(RoundedRectangle(cornerRadius: hole.radius, style: .continuous).path(in: hole.rect).cgPath)
        cg.fillPath()
        cg.restoreGState()
        context.flushGraphics()
    }

    /// Colour-to-alpha over the ground in `hole`, in one pass over the hole's pixels; false when `rep` isn't 8-bit RGBA,
    /// premultiplied and chunky, or has no opaque ground beside the hole (nothing is changed then).
    ///
    /// Each pixel is taken as something over the ground `b` (a pixel not opaque is first put over `b`), and is given the
    /// least alpha that explains it: per channel |c − b| / (1 − b) where c is above b, |c − b| / b where below, the largest
    /// of the three, 0…1. Its colour is then b + (c − b) / alpha, stored premultiplied as c − b·(1 − alpha): the ground
    /// comes out clear, a solid glyph as it was, an anti-aliased edge as the glyph's colour at partial alpha. Where the
    /// shape's own edge covers a pixel in part, the result is mixed with the pixel as it was by that coverage.
    private static func unblend(_ rep: NSBitmapImageRep, _ hole: Hole) -> Bool {
        let format = rep.bitmapFormat
        guard rep.bitsPerSample == 8, rep.samplesPerPixel == 4, rep.bitsPerPixel == 32, !rep.isPlanar,
              rep.colorSpace.colorSpaceModel == .rgb,
              format.isDisjoint(with: [.alphaNonpremultiplied, .floatingPointSamples,
                                       .sixteenBitLittleEndian, .thirtyTwoBitLittleEndian,
                                       .sixteenBitBigEndian, .thirtyTwoBitBigEndian]),
              let data = rep.bitmapData else { return false }
        let width = rep.pixelsWide, height = rep.pixelsHigh, rowBytes = rep.bytesPerRow
        let sx = CGFloat(width) / rep.size.width, sy = CGFloat(height) / rep.size.height
        // Byte offsets of r, g, b and alpha in a pixel.
        let (ri, gi, bi, ai) = format.contains(.alphaFirst) ? (1, 2, 3, 0) : (0, 1, 2, 3)
        // Pixel rows count from the top, points from the bottom.
        func offset(_ x: Int, _ yUp: Int) -> Int { (height - 1 - yUp) * rowBytes + x * 4 }

        // The ground: the commonest opaque pixel of five down a column 2pt right of the hole.
        let sampleX = Int(((hole.rect.maxX + 2) * sx).rounded(.down))
        guard sampleX >= 0, sampleX < width else { return false }
        var samples: [UInt32] = []
        for step in 1...5 {
            let y = Int(((hole.rect.minY + hole.rect.height * CGFloat(step) / 6) * sy).rounded(.down))
            guard y >= 0, y < height else { continue }
            let at = offset(sampleX, y)
            guard data[at + ai] == 255 else { continue }
            samples.append(UInt32(data[at + ri]) << 16 | UInt32(data[at + gi]) << 8 | UInt32(data[at + bi]))
        }
        guard let ground = samples.max(by: { a, b in
            samples.lazy.filter { $0 == a }.count < samples.lazy.filter { $0 == b }.count
        }) else { return false }
        let gr = UInt8(ground >> 16 & 0xFF), gg = UInt8(ground >> 8 & 0xFF), gb = UInt8(ground & 0xFF)

        // The hole's pixels, and the shape's coverage of each (anti-aliased at its edge), drawn once.
        let x0 = max(0, Int((hole.rect.minX * sx).rounded(.down)))
        let x1 = min(width, Int((hole.rect.maxX * sx).rounded(.up)))
        let y0 = max(0, Int((hole.rect.minY * sy).rounded(.down)))
        let y1 = min(height, Int((hole.rect.maxY * sy).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return true }
        let maskWidth = x1 - x0, maskHeight = y1 - y0
        guard let mask = CGContext(data: nil, width: maskWidth, height: maskHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let coverage = mask.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        let maskRowBytes = mask.bytesPerRow
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))
        mask.translateBy(x: CGFloat(-x0), y: CGFloat(-y0))
        mask.scaleBy(x: sx, y: sy)
        mask.setFillColor(gray: 1, alpha: 1)
        mask.addPath(RoundedRectangle(cornerRadius: hole.radius, style: .continuous).path(in: hole.rect).cgPath)
        mask.fillPath()

        let b = (Float(gr) / 255, Float(gg) / 255, Float(gb) / 255)
        // Per channel, 1 / the room above the ground and 1 / the room below it (0 where there is none: no c lies there).
        func reach(_ ground: Float) -> (up: Float, down: Float) {
            (ground < 1 ? 1 / (1 - ground) : 0, ground > 0 ? 1 / ground : 0)
        }
        let rr = reach(b.0), rg = reach(b.1), rb = reach(b.2)
        func spread(_ c: Float, _ ground: Float, _ reach: (up: Float, down: Float)) -> Float {
            c > ground ? (c - ground) * reach.up : (ground - c) * reach.down
        }
        for yUp in y0..<y1 {
            let row = data + (height - 1 - yUp) * rowBytes
            let maskRow = coverage + (y1 - 1 - yUp) * maskRowBytes
            for x in x0..<x1 {
                let m = maskRow[x - x0]
                if m == 0 { continue }
                let p = row + x * 4
                let a8 = p[ai]
                let out: (Float, Float, Float, Float)
                if a8 == 255, p[ri] == gr, p[gi] == gg, p[bi] == gb {
                    out = (0, 0, 0, 0)
                } else {
                    // Put over the ground (premultiplied), then unblend.
                    let a = Float(a8) / 255, rest = 1 - a
                    let c = (Float(p[ri]) / 255 + b.0 * rest, Float(p[gi]) / 255 + b.1 * rest,
                             Float(p[bi]) / 255 + b.2 * rest)
                    let alpha = min(1, max(spread(c.0, b.0, rr), spread(c.1, b.1, rg), spread(c.2, b.2, rb)))
                    let keep = 1 - alpha
                    out = (min(alpha, max(0, c.0 - b.0 * keep)), min(alpha, max(0, c.1 - b.1 * keep)),
                           min(alpha, max(0, c.2 - b.2 * keep)), alpha)
                }
                if m == 255 {
                    p[ri] = UInt8(out.0 * 255 + 0.5)
                    p[gi] = UInt8(out.1 * 255 + 0.5)
                    p[bi] = UInt8(out.2 * 255 + 0.5)
                    p[ai] = UInt8(out.3 * 255 + 0.5)
                } else {
                    // The shape's edge: as the clear fill did, by its coverage.
                    let cover = Float(m) / 255, stay = (1 - cover) / 255
                    p[ri] = UInt8(min(255, (Float(p[ri]) * stay + out.0 * cover) * 255 + 0.5))
                    p[gi] = UInt8(min(255, (Float(p[gi]) * stay + out.1 * cover) * 255 + 0.5))
                    p[bi] = UInt8(min(255, (Float(p[bi]) * stay + out.2 * cover) * 255 + 0.5))
                    p[ai] = UInt8(min(255, (Float(a8) * stay + out.3 * cover) * 255 + 0.5))
                }
            }
        }
        return true
    }

    /// What the glass morph needs of the window beyond its frame: its capture flag, and its inset sidebar's frame in the
    /// window (nil: none, as during the onboarding).
    struct GlassWindow {
        var capture: GlassCapture?
        var sidebar: NSRect?

        /// The hole a glass morph's picture of a window with corners of `radius` leaves where the sidebar is (nil: today's
        /// morph, or no sidebar).
        @MainActor func hole(glass: Bool, radius: CGFloat) -> Hole? {
            guard glass, let sidebar else { return nil }
            return Hole(rect: sidebar, radius: GlassMorph.sidebarRadius(windowRadius: radius))
        }
    }

    /// An overlay for `window` (laid out at its frame) on the window's picture as it is now, ready to show; nil when there
    /// is nothing to draw. `glass`: the glass morph (M1).
    static func makeRun(for window: NSWindow, bar: BarMorph?, glassWindow: GlassWindow = GlassWindow(),
                        glass: Bool? = nil) -> Run? {
        let isGlass = glass ?? usesGlass
        let radius = cornerRadius(of: window)
        guard let image = snapshot(of: window, capture: glassWindow.capture,
                                   hole: glassWindow.hole(glass: isGlass, radius: radius)),
              let screen = window.screen ?? NSScreen.main else { return nil }
        return Run(window: window, image: image, imageIsKey: isKey(window), screen: screen, bar: bar,
                   radius: radius, glassWindow: glassWindow, glass: isGlass)
    }

    /// An overlay for `window` with nothing captured: on `image` (a picture kept from before), else on the window's bare
    /// surface until `refresh` brings one.
    static func makeRun(for window: NSWindow, image: CGImage?, bar: BarMorph?, glassWindow: GlassWindow = GlassWindow(),
                        glass: Bool? = nil) -> Run? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        // A picture kept was taken at a close, with the window key.
        return Run(window: window, image: image, imageIsKey: image != nil, screen: screen, bar: bar,
                   radius: cornerRadius(of: window), glassWindow: glassWindow, glass: glass ?? usesGlass)
    }

    /// The window's picture at its last close, taken while it had the keyboard (its buttons in colour, as the real window
    /// shows them once it is key): the next opening starts on it. Only one taken at a close will do: a picture taken out
    /// of sight has the grey buttons of a window in the background.
    struct Picture {
        var image: CGImage
        var frame: NSRect
        var scale: CGFloat
        /// What it shows: another place opening draws a fresh picture over it.
        var destination: AppDestination
        /// Taken for the glass morph (its sidebar cleared, its small glass pieces opaque): only that morph may use it.
        var glass = false

        /// Whether it can stand for `window` as it opens: the same size, at the scale a picture of it would be taken at now
        /// (the window's own, as `scale` is: a window off every screen keeps that of the last one it was on, which need not
        /// be the main screen's).
        @MainActor func fits(_ window: NSWindow) -> Bool {
            fits(window, glass: AppTransition.usesGlass)
        }

        /// `fits`, for a morph that is the glass one (`glass`) or not: a picture taken for the other never stands in.
        @MainActor func fits(_ window: NSWindow, glass: Bool) -> Bool {
            frame.size == window.frame.size && scale == window.backingScaleFactor && self.glass == glass
        }
    }

    /// Fixed for a whole run, including reversals. Bounds and position use the same monotone spring, so the union of the
    /// two ends also contains every intermediate pose. The bar's whole picture needs room, not just its starting cell.
    struct OverlayGeometry {
        let frame: NSRect

        init(window: NSRect, bar: BarMorph?, screen: NSRect, scale: CGFloat) {
            var bounds = window
            if let bar { bounds = bounds.union(bar.frame).union(bar.cellFrame) }
            bounds = bounds.insetBy(dx: -shadowRoom, dy: -shadowRoom)
            let x = floor((bounds.minX - screen.minX) * scale) / scale + screen.minX
            let y = floor((bounds.minY - screen.minY) * scale) / scale + screen.minY
            let right = ceil((bounds.maxX - screen.minX) * scale) / scale + screen.minX
            let top = ceil((bounds.maxY - screen.minY) * scale) / scale + screen.minY
            let visible = NSRect(x: x, y: y, width: right - x, height: top - y).intersection(screen)
            // An away test window without a bar has no pixels on this screen. Keep a valid host all the same.
            frame = visible.isEmpty ? screen : visible
        }

        func local(_ rect: NSRect) -> CGRect { rect.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        func screen(_ rect: CGRect) -> NSRect { rect.offsetBy(dx: frame.minX, dy: frame.minY) }
    }

    enum ScreenIdentity: Equatable {
        case display(UInt32)
        case screen(ObjectIdentifier)

        init(_ screen: NSScreen) {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                self = .display(number.uint32Value)
            } else {
                self = .screen(ObjectIdentifier(screen))
            }
        }
    }

    /// Kept on the same display, resized between runs. Screen identity is separate from the frame: equal bounds (and
    /// especially equal away frames under test) do not mean the same display.
    @MainActor final class OverlayCache {
        private var screen: ScreenIdentity?
        private var overlay: NSWindow?
        /// The glass morph's views, made once and taken up by each glass morph (whatever the display).
        private var pieces: GlassPieces?

        /// The glass morph's views, made the first time they are asked for.
        @available(macOS 26, *)
        fileprivate func glassPieces() -> GlassPieces {
            if let pieces { return pieces }
            let made = GlassPieces()
            pieces = made
            return made
        }

        /// The window made ahead of a first morph (its frame is set again when one starts); one on screen is left alone.
        func prepare(on screen: ScreenIdentity, frame: NSRect) -> NSWindow {
            if let overlay, overlay.isVisible { return overlay }
            return window(on: screen, frame: frame)
        }

        func window(on screen: ScreenIdentity, frame: NSRect) -> NSWindow {
            let placed = UnderTest.isRunning ? NSRect(origin: UnderTest.away, size: frame.size) : frame
            if let overlay, self.screen == screen {
                if overlay.frame != placed { overlay.setFrame(placed, display: false) }
                return overlay
            }
            overlay?.orderOut(nil)
            let window = AwayWindow(contentRect: placed, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.animationBehavior = .none
            self.screen = screen
            overlay = window
            return window
        }
    }

    private static let sharedOverlay = OverlayCache()

    /// Make the shared overlay at idle, without showing it or disturbing a morph already on screen.
    @discardableResult
    static func prepareOverlay(on screen: NSScreen) -> NSWindow {
        if usesGlass, #available(macOS 26, *) { _ = sharedOverlay.glassPieces() }
        return sharedOverlay.prepare(on: ScreenIdentity(screen), frame: screen.frame)
    }

    /// Where the layers are, and how they look.
    struct Pose: Equatable {
        /// The window-shaped clip, on screen (AppKit coordinates).
        var rect: NSRect
        var radius: CGFloat
        var window: Float = 1
        var bar: Float = 0
        var shadow: Float = 1
        var container: Float = 1
        /// G1's opacity (the glass morph only).
        var glass: Float = 1

        /// The pose's own shadow, from the shadow layer's opacity as drawn: that is the pose's shadow times its container's
        /// (see `containers(set:)`), which an animation from this pose multiplies by the container again.
        static func shadow(drawn: Float, container: Float) -> Float {
            container > 0.001 ? min(1, drawn / container) : 0
        }
    }

    struct Spring {
        var stiffness: CGFloat
        var damping: CGFloat
        /// Critically damped: no overshoot to see. Stiff, so the window is there soon (settled in 0.4 s).
        static let opening = Spring(stiffness: 600, damping: 49)
        static let closing = Spring(stiffness: 400, damping: 40)
    }

    /// A morph in progress. `end` takes the overlay away at once.
    @MainActor
    final class Run {
        let overlay: NSWindow
        let geometry: OverlayGeometry
        private let screen: NSScreen
        private let host: NSView
        private let root = CALayer()
        private let shadow = CALayer()
        private let container = CALayer()
        private let windowLayer = CALayer()
        private let barLayer = CALayer()
        /// The glass morph's pieces (M1); nil: today's morph.
        private let glass: GlassPieces?
        /// The window's capture flag, for the pictures taken of it.
        private let capture: GlassCapture?
        /// The window's inset sidebar (window coordinates), cleared out of its pictures on glass.
        private let sidebar: NSRect?
        /// The real window's frame and the bar's, on screen.
        let windowFrame: NSRect
        let windowRadius: CGFloat
        let bar: BarMorph?
        private(set) var ended = false
        /// The pose the latest animation started from.
        private(set) var startPose: Pose?
        private var token = 0
        private var completion: (() -> Void)?
        /// The window's picture shown, if any yet.
        private(set) var image: CGImage?
        /// Whether that picture was taken while the window had the keyboard (its buttons as the real window will show them).
        private(set) var imageIsKey: Bool
        /// The place that picture shows, as its window says (nil: none, or not known).
        var shows: AppDestination?
        /// When the animation under way has settled (media time): the overlay does not go before.
        private var settlesAt: CFTimeInterval = 0
        /// The opening has handed over: its picture is gone and the real window's live pixels show (the overlay's shadow
        /// may still be fading). Nothing is left to turn round: a close starts from the window as it is.
        private(set) var handedOver = false
        /// When the fresh picture fading in over the last is in (media time): the overlay lets go of it no sooner.
        private var fadeEnds: CFTimeInterval = 0
        /// A fresh picture is still fading in over the last.
        var isFadingPicture: Bool { windowLayer.animation(forKey: kCATransition) != nil }
        /// Whether this is the glass morph (M1).
        var isGlass: Bool { glass != nil }

        fileprivate init(window: NSWindow, image: CGImage?, imageIsKey: Bool, screen: NSScreen, bar: BarMorph?,
                         radius: CGFloat, glassWindow: GlassWindow, glass useGlass: Bool) {
            self.screen = screen
            self.bar = bar
            self.image = image
            self.imageIsKey = imageIsKey
            capture = glassWindow.capture
            sidebar = glassWindow.sidebar
            windowFrame = window.frame
            windowRadius = radius
            let scale = screen.backingScaleFactor
            geometry = OverlayGeometry(window: window.frame, bar: bar, screen: screen.frame, scale: scale)
            overlay = AppTransition.sharedOverlay.window(on: ScreenIdentity(screen), frame: geometry.frame)
            // Above the window, and above the bar (floating) which fades in or out beneath.
            overlay.level = NSWindow.Level(rawValue: max(window.level.rawValue, NSWindow.Level.floating.rawValue) + 1)
            let bounds = NSRect(origin: .zero, size: geometry.frame.size)
            var pieces: GlassPieces?
            if useGlass, #available(macOS 26, *) { pieces = AppTransition.sharedOverlay.glassPieces() }
            glass = pieces
            if let pieces {
                // The views made once (`prepareOverlay`), taken up by this morph: its layers in their hosts.
                host = pieces.host
                pieces.adopt(by: self, bounds: bounds, window: window.frame.size, radius: radius,
                             sidebar: glassWindow.sidebar, shadow: shadow, container: container, picture: windowLayer)
            } else {
                host = NSView(frame: bounds)
                root.frame = host.bounds
                root.speed = 1 / AppTransition.slowdown
                host.layer = root
                host.wantsLayer = true
            }
            overlay.contentView = host

            root.contentsScale = scale
            shadow.contentsScale = scale
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowRadius = AppTransition.shadowRadius
            shadow.shadowOffset = AppTransition.shadowOffset
            shadow.shadowOpacity = 0
            container.masksToBounds = true
            container.cornerCurve = .continuous
            container.backgroundColor = NSColor(CDS.Surface.s1).cgColor
            container.contentsScale = scale
            windowLayer.contents = image
            windowLayer.contentsScale = scale
            windowLayer.contentsGravity = .resize
            windowLayer.bounds = CGRect(origin: .zero, size: windowFrame.size)
            windowLayer.opacity = 0
            if pieces == nil {
                root.addSublayer(shadow)
                root.addSublayer(container)
                container.addSublayer(windowLayer)
            }
            if let bar, let cg = bar.snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                barLayer.contents = cg
                barLayer.contentsScale = scale
                barLayer.contentsGravity = .resize
                barLayer.bounds = CGRect(origin: .zero, size: bar.frame.size)
                barLayer.position = local(bar.frame).center
                barLayer.opacity = 0
                if let pieces { pieces.pictureRoot.addSublayer(barLayer) } else { root.addSublayer(barLayer) }
            }
            pieces?.clip.contentsScale = scale
            container.opacity = 0
            apply(Pose(rect: windowFrame, radius: radius, window: 1, bar: 0, shadow: 0, container: 0, glass: 0))
        }

        /// A screen rect in the overlay's layer coordinates.
        private func local(_ rect: NSRect) -> CGRect {
            geometry.local(rect)
        }

        /// The overlay, in front of the screen.
        func show() {
            overlay.orderFrontRegardless()
        }

        /// A newer picture of the window (it was built, or its content changed since): the same frame. `crossFade`: the
        /// picture shown is another (none, or another place's), so the new one fades in over it rather than popping in.
        func refresh(_ window: NSWindow, crossFade: Bool = false) {
            let hole = GlassWindow(sidebar: sidebar).hole(glass: isGlass, radius: windowRadius)
            guard let image = AppTransition.snapshot(of: window, capture: capture, hole: hole) else { return }
            self.image = image
            imageIsKey = AppTransition.isKey(window)
            let signpost = MorphSignposts.signposter.beginInterval("Install picture")
            defer { MorphSignposts.signposter.endInterval("Install picture", signpost) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            windowLayer.removeAnimation(forKey: kCATransition)
            fadeEnds = 0
            if crossFade {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = AppTransition.pictureFade
                windowLayer.add(fade, forKey: kCATransition)
                fadeEnds = CACurrentMediaTime() + AppTransition.pictureFade * Double(AppTransition.slowdown)
            }
            windowLayer.contents = image
            CATransaction.commit()
        }

        // MARK: Poses

        /// Sets every layer to `pose`, with no animation.
        private func apply(_ pose: Pose) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containers(set: pose)
            CATransaction.commit()
        }

        /// The layers moved with the window's shape: the container and the shadow, and on glass the picture's clip.
        private var shaped: [CALayer] { glass.map { [container, shadow, $0.clip] } ?? [container, shadow] }

        /// `glassFrames` false: the glass shapes stay where they are (a motion moves them after).
        private func containers(set pose: Pose, glassFrames: Bool = true) {
            // The handoff's cut-out (see `letGo`) is no part of any pose: the whole shadow shows again.
            shadow.mask = nil
            let rect = local(pose.rect)
            for layer in shaped {
                layer.bounds = CGRect(origin: .zero, size: rect.size)
                layer.position = rect.center
            }
            container.cornerRadius = pose.radius
            container.opacity = pose.container
            windowLayer.position = CGPoint(x: rect.width / 2, y: rect.height / 2)
            windowLayer.opacity = pose.window
            barLayer.opacity = pose.bar
            shadow.shadowPath = Self.path(rect.size, pose.radius)
            shadow.shadowOpacity = pose.shadow * pose.container
            shadow.opacity = 1
            glass?.set(pose, local: rect, frames: glassFrames)
        }

        fileprivate static func path(_ size: CGSize, _ radius: CGFloat) -> CGPath {
            let r = min(radius, size.width / 2, size.height / 2)
            return CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: r, cornerHeight: r, transform: nil)
        }

        /// How the layers look now, mid-flight included (the render server's own values).
        var pose: Pose {
            guard let c = container.presentation(), let s = shadow.presentation() else {
                return Pose(rect: windowFrame, radius: windowRadius)
            }
            let rect = CGRect(x: c.position.x - c.bounds.width / 2, y: c.position.y - c.bounds.height / 2,
                              width: c.bounds.width, height: c.bounds.height)
            return Pose(rect: geometry.screen(rect), radius: c.cornerRadius,
                        window: windowLayer.presentation()?.opacity ?? windowLayer.opacity,
                        bar: barLayer.presentation()?.opacity ?? barLayer.opacity,
                        shadow: Pose.shadow(drawn: s.shadowOpacity, container: c.opacity),
                        container: c.opacity,
                        glass: glass?.opacity ?? 1)
        }

        /// The poses the two ends of a morph have.
        var windowPose: Pose { Pose(rect: windowFrame, radius: windowRadius) }
        /// The bar's cell: today's morph starts on the bar's picture over an `s1` cell; the glass morph on G1 alone, which
        /// comes in at once over the bar's own glass.
        private var cellPose: Pose? {
            guard let bar else { return nil }
            if isGlass {
                return Pose(rect: bar.cellFrame, radius: bar.cellRadius, window: 0, bar: 1, shadow: 0, container: 0, glass: 0)
            }
            return Pose(rect: bar.cellFrame, radius: bar.cellRadius, window: 0, bar: 1, shadow: 0, container: 1)
        }

        // MARK: Opening and closing

        /// The overlay shows the window as it is (the real one is about to go): nothing changes on screen.
        func present() {
            apply(Pose(rect: windowFrame, radius: windowRadius, window: 1, bar: 0, shadow: 1, container: 1))
            show()
        }

        /// On screen: shown, or on its way to hidden (a close under way).
        private var showing: Bool {
            overlay.isVisible && (container.opacity > 0 || !(container.animationKeys() ?? []).isEmpty)
        }

        /// Grows from where the overlay is now (or the bar's cell, when it was not showing) to the window. `done` runs once
        /// it is there (not if another animation takes over first). The caller flushes it (`AppTransition.flushInitial`).
        func open(reduced: Bool, done: @escaping () -> Void) {
            let wasShowing = showing
            show()
            // Not showing: the start is set here, and taken as it is (its layers are not on screen yet, so they have no
            // presentation to read it from).
            guard !reduced, let cell = cellPose else {
                let hidden = Pose(rect: windowFrame, radius: windowRadius, window: 1, bar: 0, shadow: 1, container: 0, glass: 0)
                if !wasShowing { apply(hidden) }
                fade(to: 1, from: wasShowing ? nil : hidden, done: done)
                return
            }
            if !wasShowing { apply(cell) }
            // The handoff starts two refreshes before the spring settles: the real window is composited by then, and the
            // overlay over it stays until it has.
            play(to: windowPose, from: wasShowing ? nil : cell, spring: .opening,
                 opacities: isGlass ? .glassOpening : .opening, lead: 2 * frameDuration, done: done)
        }

        /// One refresh of the overlay's screen.
        private var frameDuration: TimeInterval { 1 / Double(max(screen.maximumFramesPerSecond, 60)) }

        /// Shrinks from where the overlay is now to the bar's cell.
        func close(reduced: Bool, done: @escaping () -> Void) {
            if !showing { present() }
            defer {
                // Submitted to the render server within the turn's own transaction, before whatever else the turn does
                // (the real window going): the overlay is drawn as soon as the server can.
                CATransaction.flush()
            }
            guard !reduced, let cell = cellPose else {
                fade(to: 0, done: done)
                return
            }
            var end = cell
            end.window = 0
            end.bar = 0
            end.shadow = 0
            end.container = 0
            end.glass = 0
            play(to: end, spring: .closing, opacities: isGlass ? .glassClosing : .closing, lead: 0, done: done)
        }

        /// A cross-fade of the overlay alone, at the window's frame, from `start` (else from where it is now). On glass G1
        /// stays out of it, and the picture's clip and G2 fade with the container.
        private func fade(to opacity: Float, from start: Pose? = nil, done: @escaping () -> Void) {
            var from = start ?? pose
            from.rect = windowFrame
            from.glass = 0
            var end = windowPose
            end.container = opacity
            end.glass = 0
            token += 1
            let mine = token
            // A handoff under way is called off.
            endHandoffSignpost()
            startPose = from
            completion = done
            settlesAt = CACurrentMediaTime() + AppTransition.reducedDuration * Double(AppTransition.slowdown)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            removeMotion()
            containers(set: end)
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from.container
            a.toValue = opacity
            a.duration = AppTransition.reducedDuration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            container.add(a, forKey: "opacity")
            glass?.fade(a, to: opacity)
            let s = CABasicAnimation(keyPath: "shadowOpacity")
            s.fromValue = from.shadow * from.container
            s.toValue = end.shadow * end.container
            s.duration = AppTransition.reducedDuration
            s.timingFunction = a.timingFunction
            shadow.add(s, forKey: "shadowOpacity")
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated { self?.finishAnimation(mine) }
            }
            CATransaction.commit()
        }

        /// When each layer's opacity moves, as fractions of the spring's duration: (start, length).
        struct Opacities {
            var bar: (Double, Double)
            var window: (Double, Double)
            var shadow: (Double, Double)
            var container: (Double, Double)
            /// G1's (the glass morph only); G2 rides the container's.
            var glass: (Double, Double) = (0, 0)
            static let opening = Opacities(bar: (0, 0.4), window: (0.08, 0.5), shadow: (0, 0.5), container: (0, 0.1))
            static let closing = Opacities(bar: (0, 0.3), window: (0.1, 0.4), shadow: (0, 0.45), container: (0.45, 0.4))
            /// The glass morph: G1 comes in at once over the bar's glass; the picture as today; the container (with G2 and
            /// the shadow) over the second half, so the first shows the bar's glass growing.
            static let glassOpening = Opacities(bar: (0, 0.4), window: (0.08, 0.5), shadow: (0.45, 0.45),
                                                container: (0.45, 0.45), glass: (0, 0.1))
            /// Its mirror: the container goes first, the window shrinking as glass, G1 fading into the bar's glass at the end.
            static let glassClosing = Opacities(bar: (0, 0.3), window: (0.05, 0.4), shadow: (0, 0.45),
                                                container: (0.1, 0.45), glass: (0.7, 0.3))
        }

        /// The length of the motion for `spring`: its settling time; on glass, the critically damped spring's as one curve
        /// (`GlassMorph`), which the glass can run.
        func motionLength(_ spring: Spring) -> TimeInterval {
            if isGlass { return GlassMorph.duration(spring) }
            let total = CASpringAnimation(keyPath: "x")
            total.stiffness = spring.stiffness
            total.damping = spring.damping
            return total.settlingDuration
        }

        /// From `start` (else from where the layers are now). `lead`: how long before the spring settles `done` runs.
        private func play(to end: Pose, from start: Pose? = nil, spring: Spring, opacities: Opacities, lead: TimeInterval,
                          done: @escaping () -> Void) {
            let from = start ?? pose
            token += 1
            let mine = token
            // A handoff under way is called off.
            endHandoffSignpost()
            startPose = from
            completion = done
            let fromRect = local(from.rect)
            let toRect = local(end.rect)
            let length = motionLength(spring)
            let glassCurve = isGlass ? GlassMorph.curve : nil
            // Every animation starts at this one time: fades timed against the spring stay where they belong on it.
            let start = CACurrentMediaTime()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            removeMotion()
            containers(set: end, glassFrames: false)
            // The glass shapes start where the layers do (a reversal included); they move once this is committed.
            glass?.setFrames(from, local: fromRect)
            func add(_ layer: CALayer, _ key: String, _ a: Any, _ b: Any) {
                let animation: CABasicAnimation
                if let glassCurve {
                    // On glass every layer runs the glass's curve, so the picture and the glass move in lockstep.
                    animation = CABasicAnimation(keyPath: key)
                    animation.timingFunction = glassCurve
                    animation.duration = length
                } else {
                    let s = CASpringAnimation(keyPath: key)
                    s.mass = 1
                    s.stiffness = spring.stiffness
                    s.damping = spring.damping
                    s.initialVelocity = 0
                    s.duration = s.settlingDuration
                    animation = s
                }
                animation.fromValue = a
                animation.toValue = b
                animation.beginTime = layer.convertTime(start, from: nil)
                animation.fillMode = .backwards
                layer.add(animation, forKey: key)
            }
            for layer in shaped {
                add(layer, "bounds", NSValue(rect: CGRect(origin: .zero, size: fromRect.size)),
                           NSValue(rect: CGRect(origin: .zero, size: toRect.size)))
                add(layer, "position", NSValue(point: fromRect.center), NSValue(point: toRect.center))
            }
            add(container, "cornerRadius", from.radius, end.radius)
            if let clip = glass?.clip { add(clip, "cornerRadius", from.radius, end.radius) }
            add(shadow, "shadowPath", Self.path(fromRect.size, from.radius), Self.path(toRect.size, end.radius))
            add(windowLayer, "position", NSValue(point: CGPoint(x: fromRect.width / 2, y: fromRect.height / 2)),
                       NSValue(point: CGPoint(x: toRect.width / 2, y: toRect.height / 2)))
            func fadeLayer(_ layer: CALayer, _ key: String, _ a: Float, _ b: Float, _ window: (Double, Double)) {
                guard a != b else { return }
                let o = CABasicAnimation(keyPath: key)
                o.fromValue = a
                o.toValue = b
                o.duration = length * window.1
                o.beginTime = layer.convertTime(start, from: nil) + length * window.0
                o.fillMode = .backwards
                o.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(o, forKey: key)
            }
            fadeLayer(barLayer, "opacity", from.bar, end.bar, opacities.bar)
            fadeLayer(windowLayer, "opacity", from.window, end.window, opacities.window)
            fadeLayer(shadow, "shadowOpacity", from.shadow * from.container, end.shadow * end.container, opacities.shadow)
            fadeLayer(container, "opacity", from.container, end.container, opacities.container)
            if let glass {
                if let g1 = glass.g1.layer { fadeLayer(g1, "opacity", from.glass, end.glass, opacities.glass) }
                // G2 rides the container: it comes with the `s1` it samples.
                if let g2 = glass.g2.layer { fadeLayer(g2, "opacity", from.container, end.container, opacities.container) }
            }
            CATransaction.commit()
            // Out of the transaction above, whose actions are off: the glass moves by its views' own animations.
            glass?.animate(to: end, local: toRect, duration: length, curve: GlassMorph.curve)
            // The layers run at 1/slowdown; `lead` is in real refreshes.
            let real = length * Double(AppTransition.slowdown)
            settlesAt = start + real
            let wait = max(0, real - lead - (CACurrentMediaTime() - start))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                MainActor.assumeIsolated { self?.finishAnimation(mine) }
            }
        }

        /// Every animation of the layers taken off but a fresh picture fading in over the last, which carries on under the
        /// new motion (cut, it would snap to its end).
        private func removeMotion() {
            for layer in [container, shadow, barLayer] { layer.removeAllAnimations() }
            for key in windowLayer.animationKeys() ?? [] where key != kCATransition { windowLayer.removeAnimation(forKey: key) }
            glass?.stop()
        }

        private func finishAnimation(_ mine: Int) {
            guard mine == token, !ended, let done = completion else { return }
            completion = nil
            done()
        }

        /// Jumps to the end of the animation under way and tells whoever waits (a test, or a window that must not wait).
        func complete() {
            guard let done = completion else { return }
            completion = nil
            token += 1
            settlesAt = 0
            fadeEnds = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [container, shadow, windowLayer, barLayer] { layer.removeAllAnimations() }
            glass?.stop()
            CATransaction.commit()
            done()
        }

        // MARK: Handoff

        /// Shows the real window under the overlay, then lets the overlay go once the window has been composited (two
        /// refreshes later), its shadow giving way to the window's own. `reveal` makes the real window visible; `finished`
        /// runs when the overlay is gone.
        func handoff(reveal: @escaping () -> Void, finished: @escaping () -> Void) {
            handoffSignpost = MorphSignposts.signposter.beginInterval("Handoff")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            reveal()
            CATransaction.commit()
            CATransaction.flush()
            let screen = self.screen
            // Another animation taking over (a close) calls the handoff off.
            let mine = token
            AppTransition.nextFrames(screen, 2) { [weak self] in
                guard let self, !self.ended, self.token == mine else { return }
                self.letGoWhenStill(mine, finished: finished)
            }
        }

        /// Lets go once the spring is still (the handoff starts ahead of its end) and the overlay shows the window's exact
        /// picture: a fresh one still fading in over the last (taken late, or asked for since) is let finish, rather than
        /// snapping to its end as the picture goes.
        private func letGoWhenStill(_ mine: Int, finished: @escaping () -> Void) {
            let wait = max(settlesAt, fadeEnds) - CACurrentMediaTime()
            guard wait > 0 else { return letGo(mine, finished: finished) }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.ended, self.token == mine else { return }
                    self.letGoWhenStill(mine, finished: finished)
                }
            }
        }

        /// How long the overlay's shadow takes to give way to the window's own at the handoff.
        static let shadowHandoff: TimeInterval = 0.1

        /// The window's picture goes at once (the real window under it has the same pixels, and its own are live), the
        /// overlay's shadow gives way to the window's own, then the overlay goes. On glass G1, G2 and the picture's clip go
        /// with the container: the real sidebar replaces G2 on the same `s1`.
        private func letGo(_ mine: Int, finished: @escaping () -> Void) {
            handedOver = true
            endHandoffSignpost()
            let going = MorphSignposts.signposter.beginInterval("Overlay going")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.opacity = 0
            glass?.hide()
            // A layer's shadow is drawn under its shape too: only what lies outside the window may show now.
            let mask = CAShapeLayer()
            mask.frame = shadow.bounds
            let around = CGMutablePath()
            around.addRect(shadow.bounds.insetBy(dx: -AppTransition.shadowRoom, dy: -AppTransition.shadowRoom))
            around.addPath(Self.path(shadow.bounds.size, container.cornerRadius))
            mask.path = around
            mask.fillRule = .evenOdd
            shadow.mask = mask
            shadow.shadowOpacity = 0
            let fade = CABasicAnimation(keyPath: "shadowOpacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Self.shadowHandoff
            shadow.add(fade, forKey: "handoff")
            CATransaction.commit()
            // The layers run at 1/slowdown: the overlay goes once the fade is over as it is seen.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shadowHandoff * Double(AppTransition.slowdown)) { [weak self] in
                MainActor.assumeIsolated {
                    MorphSignposts.signposter.endInterval("Overlay going", going)
                    guard let self, self.token == mine else { return }
                    self.end()
                    finished()
                }
            }
        }

        /// The handoff under way, if any: its signpost interval ends as the overlay lets go (or the run ends first).
        private var handoffSignpost: OSSignpostIntervalState?

        private func endHandoffSignpost() {
            guard let handoffSignpost else { return }
            MorphSignposts.signposter.endInterval("Handoff", handoffSignpost)
            self.handoffSignpost = nil
        }

        func end() {
            guard !ended else { return }
            ended = true
            endHandoffSignpost()
            completion = nil
            token += 1
            // The glass views are shared too: a newer glass morph may have taken them up.
            if let glass {
                guard glass.owner === self else { return }
                glass.owner = nil
            }
            // The overlay is shared: a newer morph may have it already.
            guard overlay.contentView === host else { return }
            overlay.orderOut(nil)
            overlay.contentView = nil
        }
    }

    /// The glass morph's pieces (M1): G1 and G2, the layers' hosts between them, and the picture's clip. Made once and
    /// taken up by each glass morph (`adopt`), which puts its own layers in the hosts.
    @MainActor
    fileprivate final class GlassPieces {
        /// The overlay's content: bottom to top, the shadow's host, G1, the container's host, G2, the picture's host.
        let host = NSView()
        /// G1: the bar's glass growing into the window.
        let g1: NSView
        /// G2: the inset sidebar's glass, under the window's picture (hidden when the window has no sidebar).
        let g2: NSView
        /// The window-shaped clip the picture is drawn in, above G2 (the container is below it).
        let clip = CALayer()
        private let shadowRoot = CALayer()
        private let containerRoot = CALayer()
        let pictureRoot = CALayer()
        private let hosts: [NSView]
        /// The morph using them now: only it may take the overlay away.
        weak var owner: Run?
        /// The window's size, and its sidebar's frame and radius in it, for the morph using them.
        private var window = NSSize.zero
        private var sidebar: NSRect?
        private var sidebarRadius: CGFloat = 0

        @available(macOS 26, *)
        init() {
            let g1 = NSGlassEffectView(frame: .zero)
            g1.wantsLayer = true
            self.g1 = g1
            let g2 = NSGlassEffectView(frame: .zero)
            g2.wantsLayer = true
            self.g2 = g2
            hosts = [NSView(), NSView(), NSView()]
            clip.masksToBounds = true
            clip.cornerCurve = .continuous
            pictureRoot.addSublayer(clip)
            // Layer-backed, its layers in layer-hosting views between the glass views (a layer-hosting view takes no
            // subviews).
            host.wantsLayer = true
            for (view, layer) in zip(hosts, [shadowRoot, containerRoot, pictureRoot]) {
                view.layer = layer
                view.wantsLayer = true
            }
            host.addSubview(hosts[0])
            host.addSubview(g1)
            host.addSubview(hosts[1])
            host.addSubview(g2)
            host.addSubview(hosts[2])
        }

        /// Taken up by `run`: sized to its overlay, its layers in the hosts (the last morph's let go), the window's
        /// sidebar for G2, every animation of the last morph taken off.
        func adopt(by run: Run, bounds: NSRect, window: NSSize, radius: CGFloat, sidebar: NSRect?, shadow: CALayer,
                   container: CALayer, picture: CALayer) {
            owner = run
            self.window = window
            self.sidebar = sidebar
            sidebarRadius = GlassMorph.sidebarRadius(windowRadius: radius)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stop()
            for layer in [shadowRoot, containerRoot, clip] {
                layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            }
            pictureRoot.sublayers?.filter { $0 !== clip }.forEach { $0.removeFromSuperlayer() }
            host.frame = bounds
            host.layer?.speed = 1 / AppTransition.slowdown
            for view in hosts {
                view.frame = bounds
                view.layer?.frame = bounds
            }
            shadowRoot.addSublayer(shadow)
            containerRoot.addSublayer(container)
            clip.addSublayer(picture)
            g2.isHidden = sidebar == nil
            CATransaction.commit()
        }

        /// G1's opacity now (the render server's value mid-flight).
        var opacity: Float { g1.layer?.presentation()?.opacity ?? Float(g1.alphaValue) }

        /// G2's frame for the window-shaped rect `rect` (overlay coordinates), and its radius.
        private func sidebarPlace(in rect: CGRect) -> (frame: NSRect, radius: CGFloat)? {
            guard let sidebar else { return nil }
            return (GlassMorph.scaled(sidebar, window: window, in: rect),
                    GlassMorph.scaledRadius(sidebarRadius, piece: sidebar.size, window: window, in: rect))
        }

        /// Every piece at `pose` (its rect `rect` in overlay coordinates), with no animation.
        func set(_ pose: Pose, local rect: CGRect, frames: Bool = true) {
            if frames { setFrames(pose, local: rect) }
            g1.alphaValue = CGFloat(pose.glass)
            g2.alphaValue = CGFloat(pose.container)
            clip.opacity = 1
            clip.cornerRadius = pose.radius
        }

        /// The glass shapes at `pose`, with no animation.
        func setFrames(_ pose: Pose, local rect: CGRect) {
            g1.frame = rect
            Self.round(g1, pose.radius, animated: false)
            if let place = sidebarPlace(in: rect) {
                g2.frame = place.frame
                Self.round(g2, place.radius, animated: false)
            }
        }

        /// The glass shapes moved to `pose` by their views' animations (S5's method (b)), on `curve` over `duration`.
        func animate(to pose: Pose, local rect: CGRect, duration: TimeInterval, curve: CAMediaTimingFunction) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = curve
                context.allowsImplicitAnimation = false
                self.g1.animator().frame = rect
                Self.round(self.g1, pose.radius, animated: true)
                if let place = self.sidebarPlace(in: rect) {
                    self.g2.animator().frame = place.frame
                    Self.round(self.g2, place.radius, animated: true)
                }
            }
        }

        /// The cross-fade's opacity `animation` on the picture's clip and G2 too (Reduce Motion), to `opacity`.
        func fade(_ animation: CABasicAnimation, to opacity: Float) {
            clip.opacity = opacity
            clip.add(animation, forKey: "opacity")
            g2.alphaValue = CGFloat(opacity)
            g2.layer?.add(animation, forKey: "opacity")
        }

        /// Every animation of the pieces taken off: they stay at their model values.
        func stop() {
            clip.removeAllAnimations()
            g1.layer?.removeAllAnimations()
            g2.layer?.removeAllAnimations()
        }

        /// Gone at once (the handoff): the real window shows under the overlay.
        func hide() {
            stop()
            clip.opacity = 0
            g1.alphaValue = 0
            g2.alphaValue = 0
        }

        private static func round(_ view: NSView, _ radius: CGFloat, animated: Bool) {
            guard #available(macOS 26, *), let glass = view as? NSGlassEffectView else { return }
            if animated { glass.animator().cornerRadius = radius } else { glass.cornerRadius = radius }
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// A few display refreshes, waited for on one display link.
@MainActor
final class FrameTick: NSObject {
    private static var live: Set<FrameTick> = []
    private var link: CADisplayLink?
    private var block: (@MainActor () -> Void)?
    private var left = 1
    private var fallback: DispatchWorkItem?

    static func wait(_ count: Int, on screen: NSScreen?, _ block: @escaping @MainActor () -> Void) {
        let tick = FrameTick()
        tick.block = block
        tick.left = max(count, 1)
        live.insert(tick)
        if let screen {
            let link = screen.displayLink(target: tick, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            tick.link = link
        }
        // A display that is asleep gives no refresh: do not wait for them for ever. Called off once they came.
        let fallback = DispatchWorkItem { MainActor.assumeIsolated { tick.finish() } }
        tick.fallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(tick.left), execute: fallback)
    }

    @objc private func fire() {
        left -= 1
        if left <= 0 { finish() }
    }

    private func finish() {
        fallback?.cancel()
        fallback = nil
        link?.invalidate()
        link = nil
        FrameTick.live.remove(self)
        let run = block
        block = nil
        run?()
    }
}
