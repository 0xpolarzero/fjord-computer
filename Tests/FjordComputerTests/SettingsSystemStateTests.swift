import Foundation
import Testing
@testable import FjordComputer

@MainActor
struct SettingsSystemStateTests {
    /// An answer from the system asked for before you switched the login item is older than your switch: it doesn't turn
    /// the switch back.
    @Test func aLoginItemReadFromBeforeYourSwitchDoesNotUndoIt() async {
        typealias State = SettingsView.SystemState
        let gate = Gate()
        let read = Task { await State.read { await gate.wait(); return .init(launchAtLogin: false, accessibility: true) } }
        await waitUntil { gate.waiting }
        State.remember(launchAtLogin: true)
        gate.open()
        let answer = await read.value
        #expect(answer.launchAtLogin == nil && answer.accessibility)
        // Asked after the switch: its answer stands.
        let later = await State.read { .init(launchAtLogin: true, accessibility: true) }
        #expect(later.launchAtLogin == true)
    }

    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var waiting: Bool { continuation != nil }
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func open() { continuation?.resume(); continuation = nil }
    }
}
