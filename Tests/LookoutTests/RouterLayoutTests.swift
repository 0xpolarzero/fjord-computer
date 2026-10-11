import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// The Router page's sizes as they are laid out: Now and History each one scroll, nothing scrolling inside them, and the
/// composer as tall as its lines.
@MainActor
@Suite(.hostsWindows) struct RouterLayoutTests {
    /// The Router's page in an offscreen window, `width` × `height`.
    private func mount(_ store: Store, _ model: RouterModel, width: CGFloat = 1100, height: CGFloat = 900) -> (NSHostingView<some View>, NSWindow) {
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: model, checksClaudeCode: false)
            .frame(width: width, height: height))
        let window = AwayWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless,
                                backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        return (hosting, window)
    }

    private func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }

    private func demo(copies: Int = 1) -> Store {
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        let open = store.router.cards.filter(\.isOpen)
        store.router.cards += (1..<copies).flatMap { n in open.map { var c = $0; c.id += "#copy\(n)"; return c } }
        return store
    }

    /// A wide page: Now and History side by side, each one scroll down the page with nothing scrolling inside it, whatever
    /// Now holds; a narrow one: one of them at a time, the switch going between them.
    @Test func nowAndHistoryAreEachOneScrollSideBySideOrOneAtATime() async {
        for width in [1100, 900] as [CGFloat] {
            let model = RouterModel()
            let store = demo(copies: 6)
            for zone in RouterZone.allCases { store.setRouterZone(zone, folded: false) }
            let (hosting, window) = mount(store, model, width: width)
            defer { window.contentView = nil; window.orderOut(nil) }
            /// The page's scrolls: not the composer's field, nor one inside another (an open form's, inside a card).
            func pages() -> [NSRect] {
                hosting.layoutSubtreeIfNeeded()
                let all = scrolls(hosting).filter { $0.frame.height > 0 && !($0.documentView is MentionTextView) }
                    .map { $0.convert($0.bounds, to: nil) }
                return all.filter { frame in !all.contains { $0 != frame && $0.contains(frame) } }
            }
            await waitUntil { !pages().isEmpty }
            await waitUntilSteady(turns: 8) { pages().map { [Int($0.minX), Int($0.width), Int($0.height)] } }
            let shown = pages().sorted { $0.minX < $1.minX }
            if width == 1100 {
                #expect(shown.count == 2, "Now and History: \(shown)")
                if shown.count == 2 {
                    #expect(shown[0].maxX <= shown[1].minX + 1, "side by side: \(shown)")
                    #expect(shown.allSatisfy { $0.height > 600 }, "each down the page: \(shown)")
                }
            } else {
                #expect(shown.count == 1 && (shown.first?.height ?? 0) > 600, "Now alone, down the page: \(shown)")
                model.pane = .history
                await waitUntilSteady(turns: 8) { pages().map { [Int($0.minX), Int($0.width), Int($0.height)] } }
                #expect(pages().count == 1, "History alone: \(pages())")
            }
        }
    }

    /// The composer grows a line at a time with what is typed and is back to one line once it is cleared.
    @Test func theComposerGrowsWithItsLinesAndShrinksBack() async throws {
        let model = RouterModel()
        let (hosting, window) = mount(demo(), model)
        defer { window.contentView = nil; window.orderOut(nil) }
        func field() -> NSScrollView? {
            hosting.layoutSubtreeIfNeeded()
            return scrolls(hosting).first { $0.documentView is MentionTextView }
        }
        await waitUntil { (field()?.frame.height ?? 0) > 0 }
        let one = try #require(field()).frame.height
        #expect(one == 20, "one line: \(one)")
        model.draft = "one\ntwo\nthree"
        await waitUntil { (field()?.frame.height ?? 0) > one }
        await waitUntilSteady(turns: 6) { Int(field()?.frame.height ?? 0) }
        #expect(field()?.frame.height == 60, "three lines: \(field()?.frame.height ?? 0)")
        model.draft = ""
        await waitUntil { field()?.frame.height == one }
        #expect(field()?.frame.height == one)
    }

    /// The working mark is drawn again each time its bright dot moves (every 0.35 s), on the moment it moves, rather than 15
    /// times a second.
    @Test func theWorkingMarkStepsWhenItsDotMoves() {
        let now = Date()
        let steps = Array(WorkingMark.schedule(from: now).entries(from: now, mode: .normal).prefix(7))
        #expect(steps.count == 7)
        #expect(abs(steps[0].timeIntervalSince(now)) < WorkingMark.step)
        let first = steps[0].timeIntervalSinceReferenceDate / WorkingMark.step
        #expect(abs(first - first.rounded()) < 0.001, "on a step's moment")
        for (a, b) in zip(steps, steps.dropFirst()) {
            #expect(abs(b.timeIntervalSince(a) - WorkingMark.step) < 0.0001)
            // Each step moves the dot, and it stays put until the next.
            #expect(WorkingMark.lit(at: b) == (WorkingMark.lit(at: a) + 1) % 3)
            #expect(WorkingMark.lit(at: b.addingTimeInterval(-0.01)) == WorkingMark.lit(at: a))
        }
    }
}
