import AppKit
import QuartzCore

// The morph between the bar and the app window: the window grows out of the bar's cell when it opens, and shrinks back into
// it when it closes. One borderless overlay covers the screen and hosts a few Core Animation layers (the window's exact
// picture, the bar's, a shadow like the window's own) that the render server moves on a spring at the display's rate; the
// real window waits, invisible, at its frame. At the end of an opening the real window is shown under the identical
// overlay, which goes only once it has been composited, so nothing pops. Reduce Motion gets a short cross-fade of the
// overlay, and a test run no animation at all.

/// Where the bar is, for the morph to start from or end at.
struct BarMorph {
    /// On screen (AppKit coordinates).
    var frame: NSRect
    /// The bar as it looks, when it can be shown (it is on screen).
    var snapshot: NSImage?
    var radius: CGFloat = 18
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
    static let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    /// A window's corner radius when the system does not say.
    static let fallbackRadius: CGFloat = 16

    /// Off under a test: the window opens and closes at once.
    static var enabled = !UnderTest.isRunning
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// `LOOKOUT_SLOW_MORPH=10` runs the morph ten times slower, to look at it.
    static var slowdown: Float {
        ProcessInfo.processInfo.environment["LOOKOUT_SLOW_MORPH"].flatMap(Float.init).map { max($0, 1) } ?? 1
    }

    /// Runs `block` on the screen's next refresh. Replaceable, so a test can step the frames itself.
    static var nextFrame: (NSScreen?, @escaping @MainActor () -> Void) -> Void = { screen, block in FrameTick.next(on: screen, block) }

    /// The window's own corner radius (macOS 26's are larger than before), so nothing changes when the real window takes over.
    static func cornerRadius(of window: NSWindow) -> CGFloat {
        guard let frame = window.contentView?.superview else { return fallbackRadius }
        if frame.layer?.cornerRadius ?? 0 > 0 { return frame.layer?.cornerRadius ?? fallbackRadius }
        let key = "_cornerRadius"
        if frame.responds(to: Selector(key)), let radius = (frame.value(forKey: key) as? NSNumber)?.doubleValue, radius > 0 {
            return CGFloat(radius)
        }
        return fallbackRadius
    }

    /// The window's pixels as they are now: its whole frame (title bar and buttons included) at the screen's scale.
    static func snapshot(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0 else { return nil }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// An overlay for `window` (laid out at its frame), ready to show; nil when there is nothing to draw.
    static func makeRun(for window: NSWindow, bar: BarMorph?) -> Run? {
        guard let image = snapshot(of: window), let screen = window.screen ?? NSScreen.main else { return nil }
        return Run(window: window, image: image, screen: screen, bar: bar, radius: cornerRadius(of: window))
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
    }

    struct Spring {
        var stiffness: CGFloat
        var damping: CGFloat
        /// Critically damped: no overshoot to see.
        static let opening = Spring(stiffness: 340, damping: 36.8)
        static let closing = Spring(stiffness: 400, damping: 40)
    }

    /// A morph in progress. `end` takes the overlay away at once.
    @MainActor
    final class Run {
        let overlay: NSWindow
        private let screen: NSScreen
        private let root = CALayer()
        private let shadow = CALayer()
        private let container = CALayer()
        private let windowLayer = CALayer()
        private let barLayer = CALayer()
        /// The real window's frame and the bar's, on screen.
        let windowFrame: NSRect
        let windowRadius: CGFloat
        let bar: BarMorph?
        private(set) var ended = false
        /// The pose the latest animation started from.
        private(set) var startPose: Pose?
        private var token = 0
        private var completion: (() -> Void)?

        fileprivate init(window: NSWindow, image: CGImage, screen: NSScreen, bar: BarMorph?, radius: CGFloat) {
            self.screen = screen
            self.bar = bar
            windowFrame = window.frame
            windowRadius = radius
            let scale = window.backingScaleFactor
            overlay = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = false
            overlay.ignoresMouseEvents = true
            overlay.isReleasedWhenClosed = false
            // Above the window, and above the bar (floating) which fades in or out beneath.
            overlay.level = NSWindow.Level(rawValue: max(window.level.rawValue, NSWindow.Level.floating.rawValue) + 1)
            overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            overlay.animationBehavior = .none
            // A test run's overlay covers no screen (its layers are laid out on `screen` all the same).
            if UnderTest.isRunning { overlay.setFrameOrigin(UnderTest.away) }
            let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            root.frame = host.bounds
            root.speed = 1 / AppTransition.slowdown
            host.layer = root
            host.wantsLayer = true
            overlay.contentView = host

            root.contentsScale = scale
            shadow.contentsScale = scale
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowRadius = 22
            shadow.shadowOffset = CGSize(width: 0, height: -10)
            shadow.shadowOpacity = 0
            root.addSublayer(shadow)
            container.masksToBounds = true
            container.cornerCurve = .continuous
            container.backgroundColor = NSColor(CDS.Surface.s1).cgColor
            container.contentsScale = scale
            root.addSublayer(container)
            windowLayer.contents = image
            windowLayer.contentsScale = scale
            windowLayer.contentsGravity = .resize
            windowLayer.bounds = CGRect(origin: .zero, size: windowFrame.size)
            windowLayer.opacity = 0
            container.addSublayer(windowLayer)
            if let bar, let cg = bar.snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                barLayer.contents = cg
                barLayer.contentsScale = scale
                barLayer.contentsGravity = .resize
                barLayer.bounds = CGRect(origin: .zero, size: bar.frame.size)
                barLayer.position = local(bar.frame).center
                barLayer.opacity = 0
                root.addSublayer(barLayer)
            }
            container.opacity = 0
            apply(Pose(rect: windowFrame, radius: radius, window: 1, bar: 0, shadow: 0, container: 0))
        }

        /// A screen rect in the overlay's layer coordinates.
        private func local(_ rect: NSRect) -> CGRect {
            rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        }

        /// The overlay, in front of the screen.
        func show() {
            overlay.orderFrontRegardless()
        }

        /// A newer picture of the window (the content changed since): the same frame.
        func refresh(_ window: NSWindow) {
            guard let image = AppTransition.snapshot(of: window) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
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

        private func containers(set pose: Pose) {
            let rect = local(pose.rect)
            for layer in [container, shadow] {
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
        }

        private static func path(_ size: CGSize, _ radius: CGFloat) -> CGPath {
            let r = min(radius, size.width / 2, size.height / 2)
            return CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: r, cornerHeight: r, transform: nil)
        }

        /// How the layers look now, mid-flight included (the render server's own values).
        var pose: Pose {
            guard let c = container.presentation(), let s = shadow.presentation() else {
                return Pose(rect: windowFrame, radius: windowRadius)
            }
            let origin = CGPoint(x: c.position.x - c.bounds.width / 2 + screen.frame.minX,
                                 y: c.position.y - c.bounds.height / 2 + screen.frame.minY)
            return Pose(rect: NSRect(origin: origin, size: c.bounds.size), radius: c.cornerRadius,
                        window: windowLayer.presentation()?.opacity ?? windowLayer.opacity,
                        bar: barLayer.presentation()?.opacity ?? barLayer.opacity,
                        shadow: s.shadowOpacity,
                        container: c.opacity)
        }

        /// The poses the two ends of a morph have.
        var windowPose: Pose { Pose(rect: windowFrame, radius: windowRadius) }
        private var cellPose: Pose? {
            guard let bar else { return nil }
            return Pose(rect: bar.cellFrame, radius: bar.cellRadius, window: 0, bar: 1, shadow: 0, container: 1)
        }

        // MARK: Opening and closing

        /// The overlay shows the window as it is (the real one is about to go): nothing changes on screen.
        func present() {
            apply(Pose(rect: windowFrame, radius: windowRadius, window: 1, bar: 0, shadow: 1, container: 1))
            show()
        }

        private var showing: Bool { overlay.isVisible && container.opacity > 0 }

        /// Grows from where the overlay is now (or the bar's cell, when it was not showing) to the window. `done` runs once
        /// it is there (not if another animation takes over first).
        func open(reduced: Bool, done: @escaping () -> Void) {
            let wasShowing = showing
            show()
            guard !reduced, let cell = cellPose else {
                if !wasShowing { apply(Pose(rect: windowFrame, radius: windowRadius, window: 1, bar: 0, shadow: 1, container: 0)) }
                fade(to: 1, done: done)
                return
            }
            if !wasShowing { apply(cell) }
            play(to: windowPose, spring: .opening, opacities: .opening, done: done)
        }

        /// Shrinks from where the overlay is now to the bar's cell.
        func close(reduced: Bool, done: @escaping () -> Void) {
            if !showing { present() }
            guard !reduced, let cell = cellPose else {
                fade(to: 0, done: done)
                return
            }
            var end = cell
            end.window = 0
            end.bar = 0
            end.shadow = 0
            end.container = 0
            play(to: end, spring: .closing, opacities: .closing, done: done)
        }

        /// A cross-fade of the overlay alone, at the window's frame.
        private func fade(to opacity: Float, done: @escaping () -> Void) {
            var from = pose
            from.rect = windowFrame
            var end = windowPose
            end.container = opacity
            token += 1
            let mine = token
            startPose = from
            completion = done
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [container, shadow, windowLayer, barLayer] { layer.removeAllAnimations() }
            containers(set: end)
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from.container
            a.toValue = opacity
            a.duration = AppTransition.reducedDuration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            container.add(a, forKey: "opacity")
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
            static let opening = Opacities(bar: (0, 0.4), window: (0.08, 0.5), shadow: (0, 0.5), container: (0, 0.1))
            static let closing = Opacities(bar: (0, 0.3), window: (0.1, 0.4), shadow: (0, 0.45), container: (0.45, 0.4))
        }

        private func play(to end: Pose, spring: Spring, opacities: Opacities, done: @escaping () -> Void) {
            let from = pose
            token += 1
            let mine = token
            startPose = from
            completion = done
            let fromRect = local(from.rect)
            let toRect = local(end.rect)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [container, shadow, windowLayer, barLayer] { layer.removeAllAnimations() }
            containers(set: end)
            func add(_ layer: CALayer, _ key: String, _ a: Any, _ b: Any) {
                let s = CASpringAnimation(keyPath: key)
                s.mass = 1
                s.stiffness = spring.stiffness
                s.damping = spring.damping
                s.initialVelocity = 0
                s.fromValue = a
                s.toValue = b
                s.duration = s.settlingDuration
                layer.add(s, forKey: key)
            }
            let total = CASpringAnimation(keyPath: "x")
            total.stiffness = spring.stiffness
            total.damping = spring.damping
            let length = total.settlingDuration
            for layer in [container, shadow] {
                add(layer, "bounds", NSValue(rect: CGRect(origin: .zero, size: fromRect.size)),
                           NSValue(rect: CGRect(origin: .zero, size: toRect.size)))
                add(layer, "position", NSValue(point: fromRect.center), NSValue(point: toRect.center))
            }
            add(container, "cornerRadius", from.radius, end.radius)
            add(shadow, "shadowPath", Self.path(fromRect.size, from.radius), Self.path(toRect.size, end.radius))
            add(windowLayer, "position", NSValue(point: CGPoint(x: fromRect.width / 2, y: fromRect.height / 2)),
                       NSValue(point: CGPoint(x: toRect.width / 2, y: toRect.height / 2)))
            func fadeLayer(_ layer: CALayer, _ key: String, _ a: Float, _ b: Float, _ window: (Double, Double)) {
                guard a != b else { return }
                let o = CABasicAnimation(keyPath: key)
                o.fromValue = a
                o.toValue = b
                o.duration = length * window.1
                o.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + length * window.0
                o.fillMode = .backwards
                o.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(o, forKey: key)
            }
            fadeLayer(barLayer, "opacity", from.bar, end.bar, opacities.bar)
            fadeLayer(windowLayer, "opacity", from.window, end.window, opacities.window)
            fadeLayer(shadow, "shadowOpacity", from.shadow * from.container, end.shadow * end.container, opacities.shadow)
            fadeLayer(container, "opacity", from.container, end.container, opacities.container)
            // The completion rides on the spring that ends last.
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated { self?.finishAnimation(mine) }
            }
            CATransaction.commit()
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
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [container, shadow, windowLayer, barLayer] { layer.removeAllAnimations() }
            CATransaction.commit()
            done()
        }

        // MARK: Handoff

        /// Shows the real window under the overlay, then lets the overlay go once the window has been composited (two
        /// refreshes later), its shadow giving way to the window's own. `reveal` makes the real window visible; `finished`
        /// runs when the overlay is gone.
        func handoff(reveal: @escaping () -> Void, finished: @escaping () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            reveal()
            CATransaction.commit()
            CATransaction.flush()
            let screen = self.screen
            // Another animation taking over (a close) calls the handoff off.
            let mine = token
            AppTransition.nextFrame(screen) { [weak self] in
                AppTransition.nextFrame(screen) { [weak self] in
                    guard let self, !self.ended, self.token == mine else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.shadow.shadowOpacity = 0
                    let fade = CABasicAnimation(keyPath: "shadowOpacity")
                    fade.fromValue = 1
                    fade.toValue = 0
                    fade.duration = 0.1
                    self.shadow.add(fade, forKey: "handoff")
                    CATransaction.commit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.token == mine else { return }
                            self.end()
                            finished()
                        }
                    }
                }
            }
        }

        func end() {
            guard !ended else { return }
            ended = true
            completion = nil
            token += 1
            overlay.orderOut(nil)
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// One display refresh, waited for.
@MainActor
private final class FrameTick: NSObject {
    private static var live: Set<FrameTick> = []
    private var link: CADisplayLink?
    private var block: (@MainActor () -> Void)?

    static func next(on screen: NSScreen?, _ block: @escaping @MainActor () -> Void) {
        let tick = FrameTick()
        tick.block = block
        live.insert(tick)
        if let screen {
            let link = screen.displayLink(target: tick, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            tick.link = link
        }
        // A display that is asleep gives no refresh: do not wait for one for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { tick.finish() } }
    }

    @objc private func fire() { finish() }

    private func finish() {
        link?.invalidate()
        link = nil
        FrameTick.live.remove(self)
        let run = block
        block = nil
        run?()
    }
}
