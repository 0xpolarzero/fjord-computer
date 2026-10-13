import AppKit
import QuartzCore
import Testing
@testable import FjordComputer

extension WindowSeams {
    @MainActor @Suite(.hostsWindows) struct WorkingMarkViewTests {
        @Test func dotsAnimateOnTheirLayersAndStopWhenHiddenDetachedOrMotionIsReduced() throws {
            _ = NSApplication.shared
            let view = WorkingMarkView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let dots = try #require(view.layer?.sublayers)
            #expect(dots.count == 3)
            for (i, dot) in dots.enumerated() {
                let animation = try #require(dot.animation(forKey: "step") as? CAKeyframeAnimation)
                #expect(animation.keyPath == "opacity" && animation.calculationMode == .discrete)
                #expect(abs(animation.duration - 3 * WorkingMark.step) < 0.0001)
                #expect((animation.values as? [NSNumber])?[i].doubleValue == 1)
                #expect(animation.keyTimes?.count == (animation.values?.count ?? 0) + 1)
            }
            view.still = true
            #expect(dots.allSatisfy { $0.animationKeys()?.isEmpty != false })
            #expect(dots.map(\.opacity) == [0.55, 1, 0.55])
            view.still = false
            #expect(dots.allSatisfy { $0.animation(forKey: "step") != nil })
            view.isHidden = true
            #expect(dots.allSatisfy { $0.animationKeys()?.isEmpty != false })
            view.isHidden = false
            window.contentView = nil
            #expect(dots.allSatisfy { $0.animationKeys()?.isEmpty != false })
        }
    }
}
