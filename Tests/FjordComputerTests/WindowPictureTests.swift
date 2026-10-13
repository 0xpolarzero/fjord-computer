import AppKit
import Testing
@testable import FjordComputer

/// The window's kept picture: the glance that says whether it is still the window, and what may stand in for what.
@MainActor @Suite struct WindowPictureTests {
    private typealias Glance = AppTransition.Glance

    private func glance(_ width: Int, _ height: Int, _ change: [(Int, UInt8)] = []) -> Glance {
        var pixels = [UInt8](repeating: 100, count: width * height * 4)
        for (at, value) in change { pixels[at] = value }
        return Glance(width: width, height: height, pixels: pixels)
    }

    @Test func aGlanceDiffersByTheShareOfPixelsMovedMoreThanTwoLevels() {
        let base = glance(10, 10)
        #expect(base.difference(from: base) == 0 && base.same(as: base))
        // Two levels in a channel is noise; three is a change, counted once per pixel whatever its channels.
        #expect(glance(10, 10, [(0, 102), (5, 98)]).difference(from: base) == 0)
        #expect(glance(10, 10, [(0, 103), (1, 90), (8, 97)]).difference(from: base) == 0.02)
        #expect(!glance(10, 10, [(0, 103)]).same(as: base))
        // Another size, or nothing to compare with, is no match at all.
        #expect(glance(10, 9).difference(from: base) == 1 && !base.same(as: nil) && !base.within(1, of: nil))
    }

    @Test func aGlanceStopsCountingPastItsLimit() {
        let base = glance(10, 10)
        let moved = glance(10, 10, (0..<10).map { ($0 * 4, 200) })
        #expect(moved.difference(from: base) == 0.1)
        // Past 3 of 100 the count stops: the share is only known to be over the limit.
        let stopped = moved.difference(from: base, limit: 0.03)
        #expect(stopped > 0.03 && stopped < 0.1)
        #expect(moved.within(0.1, of: base) && !moved.within(0.05, of: base))
    }
}
