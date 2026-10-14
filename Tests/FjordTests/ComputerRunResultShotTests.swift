import CoreGraphics
import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite(.serialized) struct ComputerRunResultShotTests {
    @Test func minimumHeightLongSummaryShotExercisesResultCardScrolling() throws {
        let shot = try #require(AppWindowShots.catalog.first { $0.name == "triage-computer-run-result-long-min" })
        #expect(shot.size == CGSize(width: AppWindowController.minSize.width,
                                    height: AppWindowController.minSize.height))

        let store = Store()
        Demo.populate(store, .router)
        shot.prepare?(store)
        let id = UUID(uuidString: "80000000-0000-4000-8000-000000000001")!
        let summary = try #require(store.actionLedger.computerRuns[id]?.summary)
        #expect(summary.count >= 1_000)
    }
}
