import AppKit
import Observation
import SwiftUI
import Testing
@testable import FjordComputer

extension WindowSeams {
    @MainActor @Suite(.hostsWindows) struct CanvasLayoutViewTests {
        @Observable final class Inputs {
            var width: CGFloat = 420
            var height: CGFloat = 34
            var secondGroup = CanvasGroup.needs
            var placed = false
        }
        private final class Measurements {
            var rects: [String: CGRect] = [:]
        }
        private struct Board: View {
            let inputs: Inputs
            let measurements: Measurements
            var body: some View {
                CanvasBoard(places: [.init(origin: .zero, placed: false),
                                     .init(origin: CGPoint(x: 0, y: 80), placed: inputs.placed)]) {
                    CanvasFolderStack(width: inputs.width, groups: [.needs, inputs.secondGroup]) {
                        Color.clear.frame(height: inputs.height)
                        Color.clear.frame(height: 34)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: {
                                measurements.rects["row"] = $0
                            }
                    }
                    Color.clear.frame(width: 420, height: 44)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: {
                            measurements.rects["frame"] = $0
                        }
                }
                .fixedSize()
                .coordinateSpace(.named("board"))
            }
        }

        @Test func openingRegroupingResizingAndPlacingRecomputeTheLayout() async throws {
            _ = NSApplication.shared
            let inputs = Inputs(), measurements = Measurements()
            let host = NSHostingView(rootView: Board(inputs: inputs, measurements: measurements))
            host.frame = NSRect(x: 0, y: 0, width: 1200, height: 1000)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            window.orderFrontRegardless()
            defer { window.contentView = nil; window.close() }
            func layout() { host.needsLayout = true; host.layoutSubtreeIfNeeded() }
            layout()
            await waitUntil(within: 5) { measurements.rects["row"]?.minY == 40 }
            #expect(measurements.rects["row"]?.size == CGSize(width: 420, height: 34))
            #expect(measurements.rects["frame"]?.minY == 122)
            inputs.height = 100
            layout()
            await waitUntil(within: 5) { measurements.rects["row"]?.minY == 106 }
            #expect(measurements.rects["frame"]?.minY == 188)
            inputs.secondGroup = .working
            inputs.width = 600
            layout()
            await waitUntil(within: 5) { measurements.rects["row"]?.minY == 116 }
            #expect(measurements.rects["row"]?.width == 600)
            #expect(measurements.rects["frame"]?.minY == 198)
            inputs.placed = true
            layout()
            await waitUntil(within: 5) { measurements.rects["frame"]?.minY == 80 }
            #expect(measurements.rects["frame"]?.minY == 80)
        }
    }
}
