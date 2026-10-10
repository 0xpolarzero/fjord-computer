import Foundation
import Testing
@testable import Lookout

/// The Store's memoized inbox: what time alone changes, and what the bar reads on every redraw.
@MainActor
@Suite struct InboxMemoTests {
    private func stale(days: Int) -> InboxCategory {
        InboxCategory(name: "Stale", symbol: "clock", color: .blue,
                      rules: [Rule(scope: Scope(kinds: [.pr]), conditions: [.noActivity(days: days)], createdAt: .distantPast)])
    }

    @Test func theNextNoActivityThresholdIsWhenTimeAloneChangesWhatMatches() {
        let now = Date()
        let soon = InboxFixture.pr(1, updated: now.addingTimeInterval(-7 * 86_400 + 60))
        let later = InboxFixture.pr(2, updated: now.addingTimeInterval(-86_400))
        let past = InboxFixture.pr(3, updated: now.addingTimeInterval(-30 * 86_400))
        #expect(InboxEngine.nextChange(things: [soon, later, past], categories: [stale(days: 7)], after: now)
            == now.addingTimeInterval(60))
        #expect(InboxEngine.nextChange(things: [past], categories: [stale(days: 7)], after: now) == nil)
        #expect(InboxEngine.nextChange(things: [soon], categories: [InboxFixture.category()], after: now) == nil)
    }

    @Test func anUnchangedThingCrossingTheThresholdComesInWithoutARefresh() async throws {
        let thing = InboxFixture.pr(1, updated: Date().addingTimeInterval(-86_400 + 0.5))
        let store = InboxFixture.store([thing], category: stale(days: 1))
        #expect(store.entries.isEmpty)
        try await Task.sleep(for: .seconds(1))
        #expect(store.entries.map(\.id) == [thing.id])
    }
}
