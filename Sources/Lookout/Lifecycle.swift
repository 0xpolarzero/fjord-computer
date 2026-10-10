import AppKit

/// `--lifecycle`: tooling only (`scripts/idle-cpu.sh`). Says on stdout what the idle gate needs to know to trust a number:
/// the sessions, how many work, whether a window is showing and whether Reduce Motion is on. Said after a few seconds, and
/// again when Reduce Motion is turned on or off, once each, so a measurement taken with the bar standing still shows in the
/// output. Nothing runs without the flag.
@MainActor
enum Lifecycle {
    static let flag = "--lifecycle"

    private static var said = ""
    private static var observer: NSObjectProtocol?

    static func line(_ store: Store) -> String {
        let rows = store.allAgentRows
        // The ones that blink: working and not waiting on you (the sidebar's `BlinkingDot`).
        let working = rows.filter { $0.group == .working }.count
        let showing = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
        return "lifecycle: sessions=\(rows.count) working=\(working) "
            + "showing=\(showing ? 1 : 0) reduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0)\n"
    }

    static func start(_ store: Store) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { say(store) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            say(store)
        }
    }

    private static func say(_ store: Store) {
        let text = line(store)
        if text != said {
            said = text
            FileHandle.standardOutput.write(Data(text.utf8))
        }
    }
}
