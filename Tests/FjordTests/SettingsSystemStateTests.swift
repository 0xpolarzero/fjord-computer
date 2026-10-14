import Foundation
import Testing
@testable import Fjord

@MainActor
struct SettingsSystemStateTests {
    /// An answer from the system asked for before you switched the login item is older than your switch: it doesn't turn
    /// the switch back.
    @Test func aLoginItemReadFromBeforeYourSwitchDoesNotUndoIt() async {
        let state = SettingsView.SystemState()  // its own: other suites' Settings pages read the shared one
        let gate = Gate()
        let read = Task { await state.read { await gate.wait(); return .init(launchAtLogin: false, accessibility: true) } }
        await waitUntil { gate.waiting }
        state.remember(launchAtLogin: true)
        gate.open()
        let answer = await read.value
        #expect(answer.launchAtLogin == nil && answer.accessibility)
        #expect(state.known.launchAtLogin, "the page made again opens on your switch, not on the older answer")
        // Asked after the switch: its answer stands.
        let later = await state.read { .init(launchAtLogin: true, accessibility: true) }
        #expect(later.launchAtLogin == true)
    }

    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var waiting: Bool { continuation != nil }
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func open() { continuation?.resume(); continuation = nil }
    }
}
