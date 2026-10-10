import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite(.serialized) struct SayingALaunchAtLoginRefusal {
    @Test func aRefusedLaunchAtLoginIsSaidWithTheReasonLeftOnScreen() async {
        struct Refused: LocalizedError { var errorDescription: String? { "Operation not permitted" } }
        await Announced.exclusively {
            var said: [String] = []
            Announce.sink = { said.append($0) }
            #expect(SettingsView.launchFailure(turningOn: true, using: { _ in }) == nil && said.isEmpty)
            #expect(SettingsView.launchFailure(turningOn: true, using: { _ in throw Refused() }) == "Operation not permitted")
            #expect(said.count == 1)
            // Turning it off is a different sentence: not the same words twice.
            #expect(SettingsView.launchFailure(turningOn: false, using: { _ in throw Refused() }) == "Operation not permitted")
            #expect(said.count == 2 && said[0] != said[1])
        }
    }
}
