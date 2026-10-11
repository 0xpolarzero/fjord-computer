import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// The Router page's sizes as they are laid out: the zones as tall as what they hold up to their room, and the composer as
/// tall as its lines.
@MainActor
@Suite(.hostsWindows) struct RouterLayoutTests {
    /// The Router's page in an offscreen window, 1100 × `height`.
    private func mount(_ store: Store, _ model: RouterModel, height: CGFloat = 900) -> (NSHostingView<some View>, NSWindow) {
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: model, checksClaudeCode: false)
            .frame(width: 1100, height: height))
        let window = AwayWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: height), styleMask: .borderless,
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

    /// Each zone's scroll as tall as what it holds when that fits, and the history the rest of the page above them; past
    /// their room, Needs you scrolls inside and the history keeps its floor.
    @Test func theZonesAreAsTallAsTheirCardsUpToTheirRoom() async {
        for copies in [1, 6] {
            // A tall page for one of each card, so that they all fit.
            let (hosting, window) = mount(demo(copies: copies), RouterModel(), height: copies == 1 ? 2000 : 900)
            defer { window.contentView = nil; window.orderOut(nil) }
            /// The history (the topmost scroll), and the zones' scrolls under it with their content's height (not the composer's
            /// field, which scrolls too, nor an open form's, inside a card).
            func frames() -> (history: NSRect, zones: [(frame: NSRect, content: CGFloat)])? {
                hosting.layoutSubtreeIfNeeded()
                let all = scrolls(hosting).filter { $0.frame.height > 0 && !($0.documentView is MentionTextView) }
                    .map { ($0.convert($0.bounds, to: nil), $0.documentView?.frame.height ?? 0) }
                guard let top = all.max(by: { $0.0.maxY < $1.0.maxY }) else { return nil }
                let zones = all.filter { zone in zone.0 != top.0 && !all.contains { $0.0 != zone.0 && $0.0.contains(zone.0) } }
                return zones.count >= 2 ? (top.0, zones.map { (frame: $0.0, content: $0.1) }) : nil
            }
            await waitUntil { frames() != nil }
            await waitUntilSteady(turns: 8) { frames().map { [Int($0.history.height)] + $0.zones.map { Int($0.frame.height) } } ?? [] }
            guard let f = frames() else { Issue.record("no zones"); continue }
            let needs = f.zones.min { $0.frame.minY < $1.frame.minY }!
            if copies == 1 {
                for zone in f.zones {
                    #expect(abs(zone.frame.height - zone.content) <= 1,
                            "as tall as what it holds: \(zone.frame) for \(zone.content) among \(f.zones) under \(f.history)")
                }
            } else {
                #expect(needs.content > needs.frame.height + 100, "Needs you scrolls inside: \(needs.frame.height) of \(needs.content)")
                #expect(f.history.height >= 140, "the history keeps its floor: \(f.history.height)")
            }
            // Nothing between the history and the zones but the line and the zones' headers: the history takes the rest.
            let zonesTop = f.zones.map(\.frame.maxY).max()!
            #expect(f.history.minY > zonesTop, "the history over the zones")
            #expect(f.history.minY - zonesTop < 120, "the history down to the zones: \(f.history.minY - zonesTop)")
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
