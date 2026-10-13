import AppKit
import SwiftUI
import Testing
@testable import FjordComputer

/// The motion tokens (glass-plan §5.7): each one's curve, and its Reduce Motion fallback.
@Suite struct MotionTests {
    @Test func eachTokenHasItsCurve() {
        #expect(Motion.instant.curve(reduce: false) == Motion.Curve.none)
        #expect(Motion.release.curve(reduce: false) == .easeOut(0.12))
        #expect(Motion.fade.curve(reduce: false) == .easeOut(0.14))
        #expect(Motion.spatial.curve(reduce: false) == .spring(duration: 0.3, bounce: 0))
        #expect(Motion.glass.curve(reduce: false) == .spring(duration: 0.35, bounce: 0.12))
        #expect(Motion.scroll.curve(reduce: false) == .spring(duration: 0.3, bounce: 0))
        #expect(Motion.follow.curve(reduce: false) == .spring(duration: 0.18, bounce: 0))
    }

    @Test func reduceMotionFallsBackPerToken() {
        #expect(Motion.instant.curve(reduce: true) == Motion.Curve.none)
        #expect(Motion.release.curve(reduce: true) == Motion.Curve.none)
        #expect(Motion.fade.curve(reduce: true) == .easeOut(0.14))
        #expect(Motion.spatial.curve(reduce: true) == .easeOut(0.12))
        #expect(Motion.glass.curve(reduce: true) == .easeOut(0.12))
        // A scroll has nothing to fade: it jumps.
        #expect(Motion.scroll.curve(reduce: true) == Motion.Curve.none)
        #expect(Motion.follow.curve(reduce: true) == Motion.Curve.none)
        // No spring is left under Reduce Motion.
        for token in [Motion.instant, .release, .fade, .spatial, .glass, .scroll, .follow] {
            if case .spring = token.curve(reduce: true) { Issue.record("\(token) springs under Reduce Motion") }
        }
    }

    @Test func noneIsNoAnimation() {
        #expect(Motion.instant.resolved(reduce: false) == nil)
        #expect(Motion.release.resolved(reduce: true) == nil)
        #expect(Motion.release.resolved(reduce: false) != nil)
        #expect(Motion.fade.resolved(reduce: true) != nil)
    }

    /// Hover-on is instant, hover-off eases (and with Reduce Motion, neither animates).
    @Test func hoverComesInAtOnceAndEasesOut() {
        #expect(Motion.hover(on: true) == .instant)
        #expect(Motion.hover(on: false) == .release)
        #expect(Motion.hover(on: true).resolved(reduce: false) == nil)
        #expect(Motion.hover(on: false).resolved(reduce: false) != nil)
        #expect(Motion.hover(on: false).resolved(reduce: true) == nil)
    }
}

@MainActor
struct WindowArrivalTests {
    @Test func anArrivalLastsUntilEveryOneBegunHasEnded() {
        let arrival = WindowArrival(inTests: true)
        let a = arrival.begin(), b = arrival.begin()
        #expect(arrival.active)
        arrival.end(a)
        #expect(arrival.active, "b's arrival is still under way")
        arrival.end(a)
        #expect(arrival.active, "a token ends once")
        arrival.end(b)
        #expect(!arrival.active)
    }

    @Test func theAppWindowsArrivalsDoNothingInATestRun() {
        let token = WindowArrival.appWindow.begin()
        #expect(!WindowArrival.appWindow.active)
        WindowArrival.appWindow.end(token)
    }

    @Test func anArrivalLastsUntilItsContentIsLaidOutAndATurnMore() async {
        let arrival = WindowArrival(inTests: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(UnderTest.away)
        let content = NSHostingView(rootView: Text("Arrived"))
        arrival.arrive(laying: content)
        window.contentView = content
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        #expect(arrival.active, "on while the window takes its content")
        // The turn it is laid out in: still on (what that update scheduled for later lands in the next).
        await Task.yield()
        #expect(arrival.active || !content.needsLayout)
        await waitUntil { !arrival.active }
        #expect(!arrival.active && !content.needsLayout)
    }
}
