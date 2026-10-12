import AppKit
import SwiftUI
import Testing
@testable import FjordComputer

/// The corner badge's ring is cut out of its cell: through it shows whatever is under the cell, not the cell and not a
/// painted black. On today's opaque bar that is the bar's black, so the look is the one the painted ring gave.
@MainActor
@Suite(.hostsWindows) struct CornerBadgeCutoutTests {
    /// A white 28pt cell with a one-count badge, 16 in from the edges of a square of `background`.
    private struct Cell: View {
        let background: Color
        var body: some View {
            Rectangle().fill(Color.white)
                .frame(width: 28, height: 28)
                .cornerBadge(1, fill: Color.blue, ink: Color.white)
                .padding(16)
                .background(background)
        }
    }

    /// The colour at a point (top-left origin, in points) of the view as drawn, in sRGB.
    private static func pixels(_ background: Color) async throws -> (CGPoint) -> NSColor? {
        _ = NSApplication.shared
        let size = CGSize(width: 60, height: 60)
        let hosting = NSHostingView(rootView: Cell(background: background).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(UnderTest.away)
        window.orderFrontRegardless()
        defer { window.close() }
        // The badge's size is read after its first layout, and the hole follows it.
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
        return { point in
            rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        }
    }

    private static func same(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.redComponent - b.redComponent) < 0.03 && abs(a.greenComponent - b.greenComponent) < 0.03
            && abs(a.blueComponent - b.blueComponent) < 0.03
    }

    // The cell spans 16...44. Its badge (16 × 16) sits 6 past its trailing edge and 5 above its top: a circle centred at
    // (42, 19), radius 8, its ring out to 10. (33, 19) and (42, 28.5) are 9 and 9.5 from the centre: on the ring, and on the
    // cell. (42, 13) is on the badge, above its digit.
    private static let ring = [CGPoint(x: 33, y: 19), CGPoint(x: 42, y: 28.5)]
    private static let bare = CGPoint(x: 4, y: 4)
    private static let cell = CGPoint(x: 22, y: 38)
    private static let badge = CGPoint(x: 42, y: 13)
    private static let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    @Test func onTodaysBarTheRingIsTheBarsBlack() async throws {
        let at = try await Self.pixels(Theme.bg)
        for point in Self.ring { #expect(Self.same(at(point), at(Self.bare)), "\(point)") }
        #expect(Self.same(at(Self.cell), Self.white))
        #expect(!Self.same(at(Self.badge), at(Self.bare)) && !Self.same(at(Self.badge), Self.white))
    }

    @Test func theRingShowsWhateverIsUnderTheCell() async throws {
        let at = try await Self.pixels(Color(red: 1, green: 0, blue: 0))
        // Against the background as drawn, not a constant: SwiftUI's red is converted to the window's colour space on the way.
        let red = try #require(at(Self.bare))
        #expect(red.redComponent > 0.8 && red.greenComponent < 0.4 && red.blueComponent < 0.4)
        for point in Self.ring { #expect(Self.same(at(point), red), "\(point)") }
        #expect(Self.same(at(Self.cell), Self.white))
    }
}
