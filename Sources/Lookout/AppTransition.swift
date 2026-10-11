import AppKit
import QuartzCore

// The morph between the bar and the app window: the window grows out of the bar's cell when it opens, and shrinks back into
// it when it closes. One borderless overlay covers the screen and hosts a few Core Animation layers (the window's exact
// picture, the bar's, a shadow like the window's own) that the render server moves on a spring at the display's rate; the
// real window waits, invisible, at its frame. At the end of an opening the real window is shown under the identical
// overlay, which goes only once it has been composited, so nothing pops. Reduce Motion gets a short cross-fade of the
// overlay, and a test run no animation at all.
//
// An opening moves first and draws after: the morph starts on the picture kept from the last close (or the window's bare
// surface), with nothing captured, and is on screen before the window's content is built; a fresh picture replaces it a
// turn later, and is in place before the real window takes over.

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
    /// A fresh picture fading in over another (or over the bare surface) during an opening.
    static let pictureFade: TimeInterval = 0.12
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

    /// Runs `block` once the screen has refreshed `count` times, on one display link. Replaceable, so a test can step the
    /// frames itself.
    static var nextFrames: (NSScreen?, Int, @escaping @MainActor () -> Void) -> Void = { screen, count, block in
        FrameTick.wait(count, on: screen, block)
    }

    /// Runs `block` on the screen's next refresh.
    static func nextFrame(_ screen: NSScreen?, _ block: @escaping @MainActor () -> Void) { nextFrames(screen, 1, block) }
    /// Runs `block` on the main queue's next turn (after the current one has committed). Replaceable, as `nextFrame`.
    static var nextTurn: (@escaping @MainActor () -> Void) -> Void = { block in
        DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
    }

    /// Whether `window` has the keyboard (its buttons in colour). Replaceable, so a test can have a key window.
    static var isKey: (NSWindow) -> Bool = { $0.isKeyWindow }
    /// Whether `window` is in the Dock. Replaceable, as `isKey` (a window under test does not minimize at once).
    static var isMiniaturized: (NSWindow) -> Bool = { $0.isMiniaturized }

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

    /// How many pictures of a window were taken (the tests count them).
    private(set) static var captures = 0

    /// The window's pixels as they are now: its whole frame (title bar and buttons included) at the screen's scale.
    static func snapshot(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0 else { return nil }
        captures += 1
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// An overlay for `window` (laid out at its frame) on the window's picture as it is now, ready to show; nil when there
    /// is nothing to draw.
    static func makeRun(for window: NSWindow, bar: BarMorph?) -> Run? {
        guard let image = snapshot(of: window), let screen = window.screen ?? NSScreen.main else { return nil }
        return Run(window: window, image: image, imageIsKey: isKey(window), screen: screen, bar: bar,
                   radius: cornerRadius(of: window))
    }

    /// An overlay for `window` with nothing captured: on `image` (a picture kept from before), else on the window's bare
    /// surface until `refresh` brings one.
    static func makeRun(for window: NSWindow, image: CGImage?, bar: BarMorph?) -> Run? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        // A picture kept was taken at a close, with the window key.
        return Run(window: window, image: image, imageIsKey: image != nil, screen: screen, bar: bar,
                   radius: cornerRadius(of: window))
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

        /// Whether it can stand for `window` as it opens: the same size, at the scale a picture of it would be taken at now
        /// (the window's own, as `scale` is: a window off every screen keeps that of the last one it was on, which need not
        /// be the main screen's).
        @MainActor func fits(_ window: NSWindow) -> Bool {
            frame.size == window.frame.size && scale == window.backingScaleFactor
        }
    }

    /// The overlay, kept from one morph to the next (a screen-sized window is not free to make); made again for another
    /// screen.
    private static var sharedOverlay: NSWindow?

    fileprivate static func overlay(on screen: NSScreen) -> NSWindow {
        // A test run's overlay covers no screen (its layers are laid out on `screen` all the same).
        let frame = UnderTest.isRunning ? NSRect(origin: UnderTest.away, size: screen.frame.size) : screen.frame
        if let sharedOverlay, sharedOverlay.frame == frame { return sharedOverlay }
        sharedOverlay?.orderOut(nil)
        let overlay = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        overlay.animationBehavior = .none
        sharedOverlay = overlay
        return overlay
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
        private let screen: NSScreen
        private let host: NSView
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

        fileprivate init(window: NSWindow, image: CGImage?, imageIsKey: Bool, screen: NSScreen, bar: BarMorph?,
                         radius: CGFloat) {
            self.screen = screen
            self.bar = bar
            self.image = image
            self.imageIsKey = imageIsKey
            windowFrame = window.frame
            windowRadius = radius
            let scale = screen.backingScaleFactor
            overlay = AppTransition.overlay(on: screen)
            // Above the window, and above the bar (floating) which fades in or out beneath.
            overlay.level = NSWindow.Level(rawValue: max(window.level.rawValue, NSWindow.Level.floating.rawValue) + 1)
            host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

        /// A newer picture of the window (it was built, or its content changed since): the same frame. `crossFade`: the
        /// picture shown is another (none, or another place's), so the new one fades in over it rather than popping in.
        func refresh(_ window: NSWindow, crossFade: Bool = false) {
            guard let image = AppTransition.snapshot(of: window) else { return }
            self.image = image
            imageIsKey = AppTransition.isKey(window)
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

        private func containers(set pose: Pose) {
            // The handoff's cut-out (see `letGo`) is no part of any pose: the whole shadow shows again.
            shadow.mask = nil
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
                        shadow: Pose.shadow(drawn: s.shadowOpacity, container: c.opacity),
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

        /// On screen: shown, or on its way to hidden (a close under way).
        private var showing: Bool {
            overlay.isVisible && (container.opacity > 0 || !(container.animationKeys() ?? []).isEmpty)
        }

        /// Grows from where the overlay is now (or the bar's cell, when it was not showing) to the window. `done` runs once
        /// it is there (not if another animation takes over first).
        func open(reduced: Bool, done: @escaping () -> Void) {
            let wasShowing = showing
            show()
            // Not showing: the start is set here, and taken as it is (its layers are not on screen yet, so they have no
            // presentation to read it from).
            guard !reduced, let cell = cellPose else {
                let hidden = Pose(rect: windowFrame, radius: windowRadius, window: 1, bar: 0, shadow: 1, container: 0)
                if !wasShowing { apply(hidden) }
                fade(to: 1, from: wasShowing ? nil : hidden, done: done)
                return
            }
            if !wasShowing { apply(cell) }
            // The handoff starts two refreshes before the spring settles: the real window is composited by then, and the
            // overlay over it stays until it has.
            play(to: windowPose, from: wasShowing ? nil : cell, spring: .opening, opacities: .opening, lead: 2 * frameDuration,
                 done: done)
        }

        /// One refresh of the overlay's screen.
        private var frameDuration: TimeInterval { 1 / Double(max(screen.maximumFramesPerSecond, 60)) }

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
            play(to: end, spring: .closing, opacities: .closing, lead: 0, done: done)
        }

        /// A cross-fade of the overlay alone, at the window's frame, from `start` (else from where it is now).
        private func fade(to opacity: Float, from start: Pose? = nil, done: @escaping () -> Void) {
            var from = start ?? pose
            from.rect = windowFrame
            var end = windowPose
            end.container = opacity
            token += 1
            let mine = token
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
            // Called within the turn's own transaction: on screen now, before whatever else the turn does.
            CATransaction.flush()
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

        /// From `start` (else from where the layers are now). `lead`: how long before the spring settles `done` runs.
        private func play(to end: Pose, from start: Pose? = nil, spring: Spring, opacities: Opacities, lead: TimeInterval,
                          done: @escaping () -> Void) {
            let from = start ?? pose
            token += 1
            let mine = token
            startPose = from
            completion = done
            let fromRect = local(from.rect)
            let toRect = local(end.rect)
            // Every animation starts at this one time: fades timed against the spring stay where they belong on it.
            let start = CACurrentMediaTime()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            removeMotion()
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
                s.beginTime = layer.convertTime(start, from: nil)
                s.fillMode = .backwards
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
                o.beginTime = layer.convertTime(start, from: nil) + length * window.0
                o.fillMode = .backwards
                o.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(o, forKey: key)
            }
            fadeLayer(barLayer, "opacity", from.bar, end.bar, opacities.bar)
            fadeLayer(windowLayer, "opacity", from.window, end.window, opacities.window)
            fadeLayer(shadow, "shadowOpacity", from.shadow * from.container, end.shadow * end.container, opacities.shadow)
            fadeLayer(container, "opacity", from.container, end.container, opacities.container)
            CATransaction.commit()
            // Called within the turn's own transaction: on screen now, before whatever else the turn does.
            CATransaction.flush()
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
        /// overlay's shadow gives way to the window's own, then the overlay goes.
        private func letGo(_ mine: Int, finished: @escaping () -> Void) {
            handedOver = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.opacity = 0
            // A layer's shadow is drawn under its shape too: only what lies outside the window may show now.
            let mask = CAShapeLayer()
            mask.frame = shadow.bounds
            let around = CGMutablePath()
            around.addRect(shadow.bounds.insetBy(dx: -200, dy: -200))
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
                    guard let self, self.token == mine else { return }
                    self.end()
                    finished()
                }
            }
        }

        func end() {
            guard !ended else { return }
            ended = true
            completion = nil
            token += 1
            // The overlay is shared: a newer morph may have it already.
            guard overlay.contentView === host else { return }
            overlay.orderOut(nil)
            overlay.contentView = nil
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
