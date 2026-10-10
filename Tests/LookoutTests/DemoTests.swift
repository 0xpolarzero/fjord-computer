import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite struct DemoScenarios {
    /// A demo's made-up inbox never takes the place of the user's saved one.
    @Test func everyScenarioFillsAStoreThatSavesNothing() {
        for scenario in Demo.Scenario.allCases {
            let store = Store()
            Demo.populate(store, scenario)
            #expect(!store.persists, "\(scenario)")
        }
    }
}
