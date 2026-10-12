import AppKit
import Testing
@testable import FjordComputer

/// Shapes inside the window are concentric with its corners: an inset shape's radius is the window's less the inset, never
/// under the floor, so a full-screen window (no radius) and the fallback both leave rounded corners inside.
@MainActor
@Suite struct WindowCornerTests {
    @Test func anInsetShapeSharesTheCornersCentre() {
        #expect(Theme.Radius.concentric(26, inset: 8) == 18)
        #expect(Theme.Radius.concentric(AppTransition.fallbackRadius, inset: 8) == 8)
    }

    @Test func noRadiusStillLeavesTheFloor() {
        #expect(Theme.Radius.concentric(0, inset: 8) == Theme.Radius.sm)
        #expect(Theme.Radius.concentric(10, inset: 8) == Theme.Radius.sm)
        #expect(Theme.Radius.concentric(0, inset: 8, minimum: 4) == 4)
    }

    @Test func aFullScreenWindowHasNoRadius() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled, .fullScreen], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(AppTransition.cornerRadius(of: window) == 0)
    }

    @Test func aWindowsRadiusIsNeverZeroOutsideFullScreen() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(AppTransition.cornerRadius(of: window) > 0)
    }
}
