import AppKit
import Observation
import OSLog
import QuartzCore
import SwiftUI

// Captures of glass (docs/design/fjord/glass-plan.md §5.6). `cacheDisplay` and `CALayer.render(in:)` leave glass out of a
// picture altogether (§11, S4), so while the app window is captured for the morph its small glass piece (the
// Router's composer) draws their opaque-mode fills instead, and is in the picture from its first frame. The sidebar keeps
// its glass (left out of the picture anyway): its place is cleared out of the picture after it is taken
// (`AppTransition.punch`), for the morph's G2 to show through. The flag is turned on, the root drawn, the picture taken,
// the flag turned off and the root drawn again, all in one turn of the main run loop with no `CATransaction.flush` inside:
// the only state the turn's commit sends to the render server is the restored one, so the stand-ins are never on screen.
//
// The flag belongs to the window's root, not to the shared `Chrome`: a capture redraws nothing outside that window. The
// bar has none: on glass the morph takes no picture of it.

/// One root's capture flag: on only while a picture of that root is taken (see `around`).
@MainActor @Observable
final class GlassCapture {
    /// The root's glass pieces draw their stand-ins.
    private(set) var on = false

    /// Sets the flag with no animation: a stand-in never fades in or out.
    func set(_ value: Bool) {
        guard value != on else { return }
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) { on = value }
    }

    /// `draw` (the capture) with the root's glass pieces drawn as stand-ins, all in this turn: the flag on, the root laid
    /// out and drawn (`settle`), the picture taken, the flag off, the root laid out and drawn again. With no glass on screen
    /// (`glass` false) only `draw` runs. Signposted ("Capture flag on", "Capture flag off", category "morph").
    func around<T>(glass: Bool, settle: () -> Void, _ draw: () -> T) -> T {
        Self.sequence(glass: glass, set: { self.set($0) }, settle: settle, draw: draw)
    }

    /// The sequence `around` runs, with its steps given (tests record their order).
    static func sequence<T>(glass: Bool, set: (Bool) -> Void, settle: () -> Void, draw: () -> T) -> T {
        guard glass else { return draw() }
        let signposter = MorphSignposts.signposter
        let on = signposter.beginInterval("Capture flag on")
        set(true)
        settle()
        signposter.endInterval("Capture flag on", on)
        let picture = draw()
        let off = signposter.beginInterval("Capture flag off")
        set(false)
        settle()
        signposter.endInterval("Capture flag off", off)
        return picture
    }

    /// Whether the app's chrome draws glass now, so a capture has stand-ins to swap in.
    static var chromeIsGlass: Bool { Chrome.glassAvailable && Chrome.shared.mode == .glass }

    /// Lays `host` (a hosting view) out and draws `window` in this turn, with the flag's change taken in: the host is
    /// marked for layout so `layoutSubtreeIfNeeded` runs its update whatever SwiftUI scheduled.
    static func settle(host: NSView?, root: NSView, window: NSWindow?) {
        host?.needsLayout = true
        root.layoutSubtreeIfNeeded()
        if let window { window.displayIfNeeded() } else { root.displayIfNeeded() }
    }
}

extension EnvironmentValues {
    /// The capture flag of the root this view is in (nil: none, as in a shot or a test drawing a piece alone).
    @Entry var glassCapture: GlassCapture? = nil
}

/// How a glass piece draws: its material, its opaque fill, and the opaque mode's hairline.
struct GlassLook: Equatable {
    var glass: Bool
    var fill: Bool
    var hairline: Bool

    /// The piece's look: opaque mode draws its fill and hairline (`hairline` says whether it has one); glass draws glass
    /// alone; glass under a capture its stand-in, its opaque fill without the hairline.
    static func of(glass: Bool, capturing: Bool, hairline: Bool = false) -> GlassLook {
        guard glass else { return GlassLook(glass: false, fill: true, hairline: hairline) }
        guard capturing else { return GlassLook(glass: true, fill: false, hairline: false) }
        return GlassLook(glass: false, fill: true, hairline: false)
    }
}

// MARK: The morph's glass (M1)

/// The geometry and timing of the morph's glass shapes (glass-plan §5.6, M1): G1 grows from the bar's cell to the window,
/// G2 stands for the inset sidebar's glass under the window's picture.
@MainActor
enum GlassMorph {
    /// The inset sidebar's frame in a window of `size` (AppKit coordinates, origin at the window's bottom left): the rail's
    /// starts under the header's line.
    static func sidebarFrame(windowSize size: NSSize, collapsed: Bool) -> NSRect {
        let inset = WindowChrome.inset
        return NSRect(x: inset, y: inset, width: WindowChrome.panelWidth(collapsed: collapsed),
                      height: max(0, size.height - WindowChrome.panelTop(collapsed: collapsed) - inset))
    }

    /// The sidebar's corner radius: concentric with the window's (its radius less the inset), never under the minimum.
    static func sidebarRadius(windowRadius: CGFloat) -> CGFloat {
        max(windowRadius - WindowChrome.inset, WindowChrome.minimumRadius)
    }

    /// `piece` (in the window's own coordinates) where it is when the window's rect is `rect`: scaled with it, so it sits
    /// where it belongs in the window's frame at the end and moves in step with it on the way.
    static func scaled(_ piece: NSRect, window: NSSize, in rect: NSRect) -> NSRect {
        guard window.width > 0, window.height > 0 else { return NSRect(origin: rect.origin, size: .zero) }
        let sx = rect.width / window.width, sy = rect.height / window.height
        return NSRect(x: rect.minX + piece.minX * sx, y: rect.minY + piece.minY * sy,
                      width: piece.width * sx, height: piece.height * sy)
    }

    /// A corner radius scaled as `scaled` scales its piece (by the smaller of the two scales), never past half its side.
    static func scaledRadius(_ radius: CGFloat, piece: NSSize, window: NSSize, in rect: NSRect) -> CGFloat {
        guard window.width > 0, window.height > 0 else { return 0 }
        let scale = min(rect.width / window.width, rect.height / window.height)
        return max(0, min(radius * scale, piece.width * scale / 2, piece.height * scale / 2))
    }

    /// The critically damped spring's progress at `u` of its settling time, `omegaT` being its natural frequency times that
    /// time: 1 − (1 + ωt)·e^(−ωt).
    static func springProgress(_ u: Double, omegaT: Double = settledOmegaT) -> Double {
        let x = omegaT * min(max(u, 0), 1)
        return 1 - (1 + x) * exp(-x)
    }

    /// ωt at which a critically damped spring is within 0.1% of its end: the glass morph's length is this over ω.
    static let settledOmegaT: Double = 9.23

    /// The critically damped spring as one cubic curve (within 3% of it all the way): what `NSAnimationContext` can run on
    /// the glass, and every layer of the glass morph runs too, so the glass and the window's picture move in lockstep.
    static let controlPoints: (Float, Float, Float, Float) = (0.29, 0.48, 0.04, 1)
    static var curve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: controlPoints.0, controlPoints.1, controlPoints.2, controlPoints.3)
    }

    /// The glass morph's length for `spring` (critically damped): its settling time, ωt = `settledOmegaT`.
    static func duration(_ spring: AppTransition.Spring) -> TimeInterval {
        settledOmegaT / Double(spring.stiffness).squareRoot()
    }
}
