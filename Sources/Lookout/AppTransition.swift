import AppKit

// The morph between the bar and the app window: the window grows out of the bar when it opens, and shrinks back into it
// when it closes. A borderless overlay carries snapshots of the two (the real window waits, invisible, at its frame), and
// goes away when the animation is over. Reduce Motion gets a plain short cross-fade, and a test run no animation at all.

/// Where the bar is, for the morph to start from or end at.
struct BarMorph {
    /// On screen (AppKit coordinates).
    var frame: NSRect
    /// The bar as it looks, when it can be shown (it is on screen).
    var snapshot: NSImage?
    var radius: CGFloat = 18
}

@MainActor
enum AppTransition {
    static let duration: TimeInterval = 0.38
    static let reducedDuration: TimeInterval = 0.15
    static let windowRadius: CGFloat = 14
    /// An ease-out with a little settle, as close to a spring as a window frame animation gets.
    static let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)

    /// Off under a test: the window opens and closes at once.
    static var enabled = !UnderTest.isRunning
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A running transition: `end` takes the overlay away at once.
    @MainActor
    final class Run {
        fileprivate let overlay: NSWindow
        init(overlay: NSWindow) { self.overlay = overlay }
        func end() { overlay.orderOut(nil) }
    }

    /// The window's pixels as they are now (title bar included).
    static func snapshot(of window: NSWindow) -> NSImage? {
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0 else { return nil }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The window (already ordered in at its target frame, at alpha 0) grows out of the bar. `done` runs once it is time to
    /// show the real window.
    static func open(_ window: NSWindow, from bar: BarMorph, done: @escaping () -> Void) -> Run? {
        let target = window.frame
        guard let shot = snapshot(of: window) else { done(); return nil }
        return animate(from: bar.frame, to: target, fromImage: bar.snapshot, toImage: shot,
                       fromRadius: bar.radius, toRadius: windowRadius, showing: .to, done: done)
    }

    /// The window (hidden by the caller) shrinks into the bar. `image` is its snapshot, taken before it was hidden.
    static func close(_ window: NSWindow, image: NSImage, into bar: BarMorph, done: @escaping () -> Void) -> Run? {
        animate(from: window.frame, to: bar.frame, fromImage: image, toImage: nil, fromRadius: windowRadius,
                toRadius: bar.radius, showing: .from, done: done)
    }

    /// A short cross-fade of the window itself: Reduce Motion.
    static func fade(_ window: NSWindow, in appearing: Bool, done: @escaping () -> Void) {
        window.alphaValue = appearing ? 0 : 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reducedDuration
            window.animator().alphaValue = appearing ? 1 : 0
        }, completionHandler: done)
    }

    private enum Side { case from, to }

    private static func animate(from start: NSRect, to end: NSRect, fromImage: NSImage?, toImage: NSImage?,
                                fromRadius: CGFloat, toRadius: CGFloat, showing: Side, done: @escaping () -> Void) -> Run? {
        let overlay = NSWindow(contentRect: start, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let content = NSView(frame: NSRect(origin: .zero, size: start.size))
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        content.layer?.cornerRadius = fromRadius
        content.layer?.backgroundColor = showing == .to ? NSColor(CDS.Surface.s1).cgColor : nil
        func imageView(_ image: NSImage?, alpha: CGFloat) -> NSImageView? {
            guard let image else { return nil }
            let view = NSImageView(frame: content.bounds)
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            view.alphaValue = alpha
            content.addSubview(view)
            return view
        }
        // Opening: the bar's picture gives way to the window's. Closing: the window's picture alone, fading as it lands.
        let fromView = imageView(fromImage, alpha: 1)
        let toView = imageView(toImage, alpha: showing == .to ? 0 : 1)
        overlay.contentView = content
        overlay.orderFrontRegardless()

        let run = Run(overlay: overlay)
        let radius = CABasicAnimation(keyPath: "cornerRadius")
        radius.fromValue = fromRadius
        radius.toValue = toRadius
        radius.duration = duration
        radius.timingFunction = curve
        content.layer?.cornerRadius = toRadius
        content.layer?.add(radius, forKey: "cornerRadius")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = curve
            context.allowsImplicitAnimation = true
            overlay.animator().setFrame(end, display: true)
            if showing == .to {
                fromView?.animator().alphaValue = 0
                toView?.animator().alphaValue = 1
            } else {
                fromView?.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            MainActor.assumeIsolated {
                done()
                run.end()
            }
        })
        return run
    }
}
