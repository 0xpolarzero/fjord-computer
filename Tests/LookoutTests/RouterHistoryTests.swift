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

    @Test func linesShownEarlierStayWhenTheOldestGoPastWhatIsKept() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let all = (0..<300).map { i in
            RouterPage.Entry.decision(RouterDecision(at: start.addingTimeInterval(Double(i) * 60), trigger: .you("message \(i)")))
        }
        // At the bottom: the newest page.
        #expect(HistoryWindow.drawn(all, from: nil, page: 100).first?.id == all[200].id)
        // Show earlier drew from line 50 on.
        let boundary = HistoryWindow.Boundary(all[50])
        #expect(HistoryWindow.drawn(all, from: boundary, page: 100).startIndex == 50)
        // Retention drops the first 60 lines, the boundary with them: what followed it holds the top, not the newest 100.
        let kept = Array(all.dropFirst(60))
        let drawn = HistoryWindow.drawn(kept, from: boundary, page: 100)
        #expect(drawn.first?.id == all[60].id && drawn.count == 240)
        // Retention drops only the boundary: the line after it.
        let without = all.filter { $0.id != all[50].id }
        #expect(HistoryWindow.drawn(without, from: boundary, page: 100).first?.id == all[51].id)
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

    @Test func aLongNeedsYouLeavesTheHistoryItsFloor() async {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        // Every open card six times over: far more than the page holds.
        let open = store.router.cards.filter(\.isOpen)
        store.router.cards += (1...5).flatMap { n in open.map { var c = $0; c.id += "#copy\(n)"; return c } }
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
        /// The history is the topmost scroll; Needs you the one holding the most of the others (an open form and the
        /// composer scroll too).
        func frames() -> (history: NSRect, needs: NSRect, needsContent: CGFloat)? {
            hosting.layoutSubtreeIfNeeded()
            let all = scrolls(hosting).filter { $0.frame.height > 0 }.map { ($0.convert($0.bounds, to: nil), $0.documentView?.frame.height ?? 0) }
            guard let top = all.max(by: { $0.0.maxY < $1.0.maxY }),
                  let low = all.filter({ $0.0 != top.0 }).max(by: { $0.1 < $1.1 }) else { return nil }
            return (top.0, low.0, low.1)
        }
        await waitUntil { frames() != nil }
        await waitUntilSteady(turns: 8) { frames().map { [Int($0.history.height), Int($0.needs.height)] } ?? [] }
        guard let f = frames() else { Issue.record("no scrolls"); return }
        #expect(f.history.height >= 140, "the history keeps a few lines: \(f.history)")
        #expect(f.needsContent > f.needs.height + 100, "Needs you scrolls inside: \(f.needs.height) of \(f.needsContent)")
        #expect(f.needs.height >= 120, "\(f.needs)")
    }
}
