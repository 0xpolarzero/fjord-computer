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

    @Test func theListsAndCountsAreGroupedOnceWithTheEntries() {
        let now = Date()
        let store = InboxFixture.store([InboxFixture.pr(1, updated: now.addingTimeInterval(-60)), InboxFixture.pr(2, updated: now),
                                        InboxFixture.pr(3, updated: now.addingTimeInterval(-120))])
        let id = store.categories[0].id
        store.markSeen(store.entries.first { $0.id == "pr:a/one#2" }!)
        store.markDone(store.entries.first { $0.id == "pr:a/one#3" }!)
        #expect(store.entries(in: id).map(\.id) == ["pr:a/one#2", "pr:a/one#1"])
        #expect(store.count(id) == 2 && store.unreadCount(id) == 1 && store.doneEntries.map(\.id) == ["pr:a/one#3"])
        // Read from the memo, as grouped when it was evaluated, until the inbox changes.
        #expect(store.inboxMemo.open[id]?.count == 2 && store.inboxMemo.unread[id] == 1 && store.inboxMemo.done.count == 1)
        store.markSeen(store.entries(in: id)[1])
        #expect(store.unreadCount(id) == 0 && store.count(UUID()) == 0)
    }
}
