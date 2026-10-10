import Foundation
import Testing
@testable import Lookout

@Suite struct PollInterval {
    @Test func lowPowerModeDoublesTheIntervalOpenOrNot() {
        #expect(Store.pollInterval(base: 60, hubOpen: false, lowPower: false) == 60)
        #expect(Store.pollInterval(base: 60, hubOpen: true, lowPower: false) == 30)
        #expect(Store.pollInterval(base: 60, hubOpen: false, lowPower: true) == 120)
        #expect(Store.pollInterval(base: 60, hubOpen: true, lowPower: true) == 60)
        // An interval already under 30 s is not stretched by the hub opening.
        #expect(Store.pollInterval(base: 20, hubOpen: true, lowPower: false) == 20)
    }
}
