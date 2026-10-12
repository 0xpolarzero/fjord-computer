import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FjordComputer

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
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
            let (hosting, window) = mount(store, model, width: width)
            defer { window.contentView = nil; window.orderOut(nil) }
            /// The page's scrolls, down the page: not the composer's field, nor one inside a card (an open form's).
            func pages() -> [NSRect] {
                hosting.layoutSubtreeIfNeeded()
                return scrolls(hosting).filter { !($0.documentView is MentionTextView) }
                    .map { $0.convert($0.bounds, to: nil) }.filter { $0.height > 600 }
            }
            await waitUntil { !pages().isEmpty }
            await waitUntilSteady(turns: 8) { pages().map { [Int($0.minX), Int($0.width), Int($0.height)] } }
            let shown = pages().sorted { $0.minX < $1.minX }
            // Now and History, nothing else scrolling down the page.
            #expect(shown.count == 2, "Now and History: \(shown)")
            guard shown.count == 2 else { continue }
            if width == 1100 {
                #expect(shown[0].maxX <= shown[1].minX + 1, "side by side: \(shown)")
            } else {
                // One over the other, each the page's width: the history kept under Now, hidden, where it was.
                #expect(shown.allSatisfy { $0.width > width - 80 }, "each the page's width: \(shown)")
                model.show(.history)
                await waitUntilSteady(turns: 8) { pages().map { [Int($0.minX), Int($0.width), Int($0.height)] } }
                #expect(pages().count == 1, "History alone: \(pages())")
            }
        }
    }

    /// On macOS 26 Now and History run under the Router's top bar and under the floating composer: their scrolls reach the
    /// page's top and bottom, so what scrolls shows through the bars' glass and the composer's (glass-plan §5.3, §5.4).
    @Test func nowAndHistoryRunUnderTheTopBarAndTheComposer() async {
        guard #available(macOS 26, *) else { return }
        let model = RouterModel()
        let store = demo(copies: 6)
        for zone in RouterZone.allCases { model.setFolded(zone, false) }
        let (hosting, window) = mount(store, model, width: 1100, height: 900)
        defer { window.contentView = nil; window.orderOut(nil) }
        func pages() -> [NSRect] {
            hosting.layoutSubtreeIfNeeded()
            return scrolls(hosting).filter { !($0.documentView is MentionTextView) }
                .map { $0.convert($0.bounds, to: nil) }.filter { $0.height > 600 }
        }
        await waitUntil { pages().count == 2 }
        await waitUntilSteady(turns: 8) { pages().map { [Int($0.minY), Int($0.maxY)] } }
        for page in pages() {
            #expect(page.minY <= 1, "under the composer: \(page)")
            #expect(page.maxY >= 899, "under the top bar: \(page)")
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

/// The history's room over its first line: the top fade's height before macOS 26, a short gap under the bars on 26.
@MainActor
@Suite struct RouterHistoryTopTests {
    @Test func theHistoryStartsCloseUnderItsBarsOnGlass() {
        if #available(macOS 26, *) {
            #expect(RouterPageView.historyTop < CDS.Transcript.fade)
            #expect(RouterPageView.historyTop > 0)
        } else {
            #expect(RouterPageView.historyTop == CDS.Transcript.fade)
        }
    }
}
