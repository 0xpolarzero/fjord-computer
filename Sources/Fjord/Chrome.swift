import AppKit
import Observation
import SwiftUI

/// How the navigation layer draws (docs/design/fjord/glass-plan.md §5.1): the bar, its panels, the sidebar and the
/// floating controls are glass on macOS 26 unless Reduce Transparency or Increase Contrast is on, and opaque otherwise;
/// content is always opaque. `FJORD_GLASS=0|1` pins it for A/B runs and shots (`1` still draws opaque where glass can't).
/// One instance, `shared`, sits in the environment of each root (`HubRoot`, `AppRootView`, the playground) and AppKit
/// reads it directly; only chrome views read it, so a change redraws only chrome. A change never animates.
@MainActor @Observable
final class Chrome {
    enum Mode { case glass, opaque }

    /// The app's: follows the system's accessibility settings, or the `FJORD_GLASS` pin.
    static let shared = Chrome.live()

    /// How the navigation layer draws now.
    private(set) var mode: Mode

    private let glassAvailable: Bool
    private let pin: Bool?
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// `FJORD_GLASS=1` pins glass (where it can draw), `0` pins opaque; anything else follows the system.
    static let pinned: Bool? = switch ProcessInfo.processInfo.environment["FJORD_GLASS"] {
    case "1": true
    case "0": false
    default: nil
    }

    /// Whether this system draws glass at all: macOS 26 or later.
    static var glassAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// The mode for these inputs: glass only where the system draws it, then the pin if there is one, else glass unless
    /// Reduce Transparency or Increase Contrast is on.
    nonisolated static func mode(glassAvailable: Bool, reduceTransparency: Bool, increaseContrast: Bool, pin: Bool?) -> Mode {
        guard glassAvailable else { return .opaque }
        if let pin { return pin ? .glass : .opaque }
        return reduceTransparency || increaseContrast ? .opaque : .glass
    }

    /// A chrome decided once from these inputs, observing nothing (tests); `update` moves it as a notification would.
    init(glassAvailable: Bool, reduceTransparency: Bool = false, increaseContrast: Bool = false, pin: Bool? = nil) {
        self.glassAvailable = glassAvailable
        self.pin = pin
        mode = Self.mode(glassAvailable: glassAvailable, reduceTransparency: reduceTransparency,
                         increaseContrast: increaseContrast, pin: pin)
    }

    /// A chrome fixed on one mode, whatever the Mac's settings (tests and shots).
    convenience init(mode: Mode) {
        self.init(glassAvailable: mode == .glass, pin: mode == .glass)
    }

    /// Decides again from the accessibility settings; a change applies without animation, so the switch never leaves a
    /// frame half glass.
    func update(reduceTransparency: Bool, increaseContrast: Bool) {
        let next = Self.mode(glassAvailable: glassAvailable, reduceTransparency: reduceTransparency,
                             increaseContrast: increaseContrast, pin: pin)
        guard next != mode else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { mode = next }
    }

    /// The system's: read now, and again each time the display's accessibility options change. Nothing is observed when
    /// glass can't draw or the mode is pinned, since no setting can change it then.
    private static func live() -> Chrome {
        let workspace = NSWorkspace.shared
        let chrome = Chrome(glassAvailable: glassAvailable,
                            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                            pin: pinned)
        guard chrome.glassAvailable, chrome.pin == nil else { return chrome }
        chrome.observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak chrome] _ in
            MainActor.assumeIsolated {
                let workspace = NSWorkspace.shared
                chrome?.update(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                               increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
            }
        }
        return chrome
    }
}
