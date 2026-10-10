import AppKit
import SwiftUI

// macOS 14 has neither scroll phases nor scroll geometry to read: the Router's history asks its scroll view itself. A move of
// what shows, with neither the content nor the view resized, is a scroll (yours, or one asked for); anything else is layout.

/// Placed inside the history's scroll content: says what each change of its scroll view means for the history's pin.
struct HistoryScrollWatch: NSViewRepresentable {
    let pinned: Bool
    let apply: (HistoryPin.Step) -> Void

    func makeNSView(context: Context) -> HistoryScrollWatchView {
        let view = HistoryScrollWatchView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HistoryScrollWatchView, context: Context) {
        let pinned = pinned, apply = apply
        view.changed = { geometry, scrolled in apply(HistoryPin.next(pinned: pinned, scrolling: scrolled, geometry)) }
    }
}

final class HistoryScrollWatchView: NSView {
    var changed: ((HistoryPin.Geometry, Bool) -> Void)?
    private var observer: HistoryScrollObserver?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let scrollView = window == nil ? nil : enclosingScrollView else { observer = nil; return }
        if observer?.scrollView !== scrollView {
            observer = HistoryScrollObserver(scrollView) { [weak self] in self?.changed?($0, $1) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Watches a scroll view's clip view; each change says the geometry and whether it was a scroll.
@MainActor final class HistoryScrollObserver {
    private(set) weak var scrollView: NSScrollView?
    private var token: NSObjectProtocol?
    private var last: (content: CGFloat, size: CGSize)?

    init(_ scrollView: NSScrollView, changed: @escaping (HistoryPin.Geometry, _ scrolled: Bool) -> Void) {
        self.scrollView = scrollView
        last = Self.sizes(scrollView)
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let scrollView = self.scrollView else { return }
                let now = Self.sizes(scrollView)
                let scrolled = self.last.map { $0.content == now.content && $0.size == now.size } ?? false
                self.last = now
                changed(Self.geometry(scrollView), scrolled)
            }
        }
    }

    deinit { token.map(NotificationCenter.default.removeObserver) }

    private static func sizes(_ scrollView: NSScrollView) -> (content: CGFloat, size: CGSize) {
        (scrollView.documentView?.frame.height ?? 0, scrollView.contentView.bounds.size)
    }

    /// The content's height and the bottom of what shows, from the content's top.
    static func geometry(_ scrollView: NSScrollView) -> HistoryPin.Geometry {
        let content = scrollView.documentView?.frame.height ?? 0
        let visible = scrollView.documentVisibleRect
        let flipped = scrollView.documentView?.isFlipped ?? true
        return HistoryPin.Geometry(content: content, visibleBottom: flipped ? visible.maxY : content - visible.minY)
    }
}
