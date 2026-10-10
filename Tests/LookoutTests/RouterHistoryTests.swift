import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// The Router page's history in a window: where it sits as lines arrive, open and are asked for.
@MainActor
@Suite(.hostsWindows) struct RouterHistoryTests {
    @Test func atTheBottomMeansWithinTheSlackOfIt() {
        #expect(HistoryPin.atBottom(1000, visibleBottom: 1000))
        #expect(HistoryPin.atBottom(1000, visibleBottom: 1000 - HistoryPin.slack))
        #expect(!HistoryPin.atBottom(1000, visibleBottom: 1000 - HistoryPin.slack - 1))
        // Shorter than its view: at the bottom.
        #expect(HistoryPin.atBottom(200, visibleBottom: 600))
    }

    @Test func onlyAScrollTakesTheHistoryOffItsBottom() {
        // A line arrives, one opens, the composer grows: no scroll, and a pinned history short of its bottom goes back there.
        #expect(HistoryPin.next(pinned: true, scrolling: false, .init(content: 1200, visibleBottom: 1000)) == .stick)
        #expect(HistoryPin.next(pinned: true, scrolling: false, .init(content: 1200, visibleBottom: 1185)) == .stick)
        #expect(HistoryPin.next(pinned: true, scrolling: false, .init(content: 1200, visibleBottom: 1200)) == .stay)
        #expect(HistoryPin.next(pinned: true, scrolling: false, .init(content: 200, visibleBottom: 600)) == .stay)
        // Scrolled up, nothing but a scroll moves it.
        #expect(HistoryPin.next(pinned: false, scrolling: false, .init(content: 1200, visibleBottom: 600)) == .stay)
        // A scroll sets it, either way.
        #expect(HistoryPin.next(pinned: true, scrolling: true, .init(content: 1000, visibleBottom: 700)) == .pin(false))
        #expect(HistoryPin.next(pinned: false, scrolling: true, .init(content: 1000, visibleBottom: 990)) == .pin(true))
    }

    /// A store whose history is long (300 runs) and whose Needs you is empty, so the history has the room.
    private func store() -> Store {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        var state = store.router
        let start = Date().addingTimeInterval(-3 * 86400)
        for i in 0..<300 {
            state.decisions.append(RouterDecision(at: start.addingTimeInterval(Double(i) * 60), trigger: .you("message \(i)"),
                                                  decision: .init(intent: "message"), outcome: .done))
        }
        state.cards = state.cards.map { var c = $0; if c.isOpen { c.addressedAt = start; c.addressedBy = .you }; return c }
        store.router = state
        return store
    }

    private struct Geometry: Equatable {
        var top: Int
        var fromBottom: Int
        var height: Int
    }

    @Test func itOpensAtTheBottomFollowsWhileThereAndHoldsWhileScrolledUp() async throws {
        let store = store()
        let model = RouterModel()
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: model, checksClaudeCode: false)
            .frame(width: 1100, height: 900))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: .borderless, backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }

        func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }
        func history() -> NSScrollView? { scrolls(hosting).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) } }
        func geometry() -> Geometry {
            hosting.layoutSubtreeIfNeeded()
            guard let view = history(), let doc = view.documentView else { return Geometry(top: 0, fromBottom: 0, height: 0) }
            let r = view.contentView.bounds
            return Geometry(top: Int(r.minY), fromBottom: Int(doc.frame.height - r.maxY), height: Int(doc.frame.height))
        }
        func settled() async -> Geometry {
            await waitUntilSteady(turns: 8) { geometry() }
            return geometry()
        }
        func line(_ text: String) { store.logDecision(RouterDecision(at: Date(), trigger: .you(text), outcome: .done)) }

        await waitUntil { history() != nil }
        let start = await settled()
        #expect(start.fromBottom <= 1, "opens at the bottom: \(start)")
        // Only the newest lines are drawn: far less than 300 lines' worth.
        #expect(start.height < 100 * 40, "\(start)")

        // At the bottom, a new line keeps it there.
        line("arrives at the bottom")
        let followed = await settled()
        #expect(followed.fromBottom <= 1, "\(followed)")

        // Asked for an old line, it scrolls up to it (drawing the lines down from it); a line arriving then moves nothing.
        let old = store.routerHistory[store.routerHistory.count - 160].id
        model.reveal(old, highlight: false)
        let up = await settled()
        #expect(up.fromBottom > 1000 && up.height > start.height, "\(up)")
        line("arrives while reading")
        let held = await settled()
        #expect(held.top == up.top, "\(up) → \(held)")

        // Back to the bottom (the Router picked), then clicking the newest card's line opens it there.
        model.select(nil, store: store)
        let back = await settled()
        #expect(back.fromBottom <= 1, "\(back)")
        var card = RouterCard(id: "history#newest", sessionID: store.router.cards[0].sessionID, kind: .done, title: "Newest",
                              folder: nil, text: "What was done.", createdAt: Date())
        card.addressedAt = Date()
        card.addressedBy = .you
        store.router.cards.append(card)
        _ = await settled()
        model.tap(card.id, store: store)
        let opened = await settled()
        #expect(model.expanded.contains(card.id) && opened.height > back.height && opened.fromBottom <= 1, "\(back) → \(opened)")
    }

    @Test func aMessageAskedForBeforeThePageShowsIsWhereItOpens() async {
        let store = store()
        let model = RouterModel()
        // An action's chip, clicked before the page is drawn: a message far up the log.
        let message = store.router.decisions[store.router.decisions.count - 200].id
        model.show(message: message)
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: model, checksClaudeCode: false)
            .frame(width: 1100, height: 900))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: .borderless, backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }
        func fromBottom() -> Int {
            hosting.layoutSubtreeIfNeeded()
            guard let view = scrolls(hosting).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
                  let doc = view.documentView else { return -1 }
            return Int(doc.frame.height - view.contentView.bounds.maxY)
        }
        await waitUntil { fromBottom() > 1000 }
        await waitUntilSteady(turns: 8) { fromBottom() }
        #expect(fromBottom() > 1000, "the page opened on the message, far above the bottom")
    }
}
