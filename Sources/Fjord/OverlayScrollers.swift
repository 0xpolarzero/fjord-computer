import AppKit
import SwiftUI

/// A page's scroll view keeps overlay scrollers whatever the Mac's "Show scroll bars" setting: legacy scrollers take room
/// from the content when they appear (a mouse plugged in, a list growing past the page), which moves a centred column
/// sideways; overlay ones float over it. Put inside the scroll view's content (`.overlayScrollers()`): it finds its
/// `NSScrollView` and sets it again whenever the system's preferred style changes (AppKit resets it then).
private final class OverlayScrollerView: NSView {
    private var observer: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        guard observer == nil, window != nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            // After AppKit has applied the new style to every scroll view.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply() } }
        }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    private func apply() {
        guard let scroll = enclosingScrollView, scroll.scrollerStyle != .overlay else { return }
        scroll.scrollerStyle = .overlay
    }
}

private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { OverlayScrollerView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

extension View {
    /// The enclosing scroll view's scrollers float over the content, never taking room from it (see `OverlayScrollerView`).
    func overlayScrollers() -> some View { background(OverlayScrollers().frame(width: 0, height: 0)) }
}
