import Foundation
import Testing
@testable import FjordComputer

/// The inbox is worked out once per change (`InboxStore.Memo`): each category's open entries, how many are unread and Done
/// are read on every redraw, and whatever changes what they are (things, marks, categories, rules, who you are) works them
/// out again.
@MainActor
@Suite struct InboxMemo {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pr(_ n: Int, minutesAgo: Double, greptile: Int? = 3, repo: String = "a/one") -> Thing {
        InboxFixture.pr(n, repo: repo, greptile: greptile, updated: now.addingTimeInterval(-60 * minutesAgo))
    }

    private func store(_ things: [Thing]) -> Store { InboxFixture.store(things) }
    private func mine(_ s: Store) -> UUID { s.categories[0].id }
    private func numbers(_ entries: [InboxEntry]) -> [Int] { entries.compactMap(\.thing.number) }
    private func entry(_ s: Store, _ n: Int) -> InboxEntry { s.entries.first { $0.thing.number == n }! }

    /// What the memo holds, against the inbox worked out from scratch.
    private func expectFresh(_ s: Store, sourceLocation: SourceLocation = #_sourceLocation) {
        let fresh = InboxEngine.evaluate(things: Array(s.things.values), categories: s.categories, marks: s.marks,
                                         context: s.inboxContext)
        #expect(Set(s.entries) == Set(fresh), sourceLocation: sourceLocation)
        for category in s.categories {
            let open = fresh.filter { $0.categoryID == category.id && !$0.isDone }.sorted { $0.thing.updatedAt > $1.thing.updatedAt }
            #expect(s.entries(in: category.id) == open, sourceLocation: sourceLocation)
            #expect(s.count(category.id) == open.count, sourceLocation: sourceLocation)
            #expect(s.unreadCount(category.id) == open.filter(\.isUnread).count, sourceLocation: sourceLocation)
        }
        let done = fresh.filter(\.isDone)
            .sorted { (s.marks[$0.id]?.doneAt ?? .distantPast) > (s.marks[$1.id]?.doneAt ?? .distantPast) }
        #expect(s.doneEntries == done, sourceLocation: sourceLocation)
    }

    @Test func aCategorysEntriesAreSortedOnceAndKeptUntilSomethingChanges() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10), pr(3, minutesAgo: 20)])
        #expect(numbers(s.entries(in: mine(s))) == [2, 3, 1])
        let revision = s.inboxRevision
        #expect(s.inboxMemo.revision == revision)
        // Read again: the same memo, nothing worked out.
        _ = s.count(mine(s)); _ = s.unreadCount(mine(s)); _ = s.doneEntries; _ = s.tabNeedingYou
        #expect(s.inboxRevision == revision && s.inboxMemo.revision == revision)
        expectFresh(s)
    }

    @Test func thingsComingGoingAndMovingAreSeen() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10)])
        #expect(s.count(mine(s)) == 2)
        s.things[pr(3, minutesAgo: 5).id] = pr(3, minutesAgo: 5)
        #expect(numbers(s.entries(in: mine(s))) == [3, 2, 1])
        #expect(s.unreadCount(mine(s)) == 3)
        expectFresh(s)
        // 1 is updated: it goes to the top.
        s.things[pr(1, minutesAgo: 0).id] = pr(1, minutesAgo: 0)
        #expect(numbers(s.entries(in: mine(s))) == [1, 3, 2])
        // 2's score is fine now: it leaves the category.
        s.things[pr(2, minutesAgo: 10).id] = pr(2, minutesAgo: 10, greptile: 5)
        #expect(numbers(s.entries(in: mine(s))) == [1, 3])
        s.things[pr(3, minutesAgo: 5).id] = nil
        #expect(numbers(s.entries(in: mine(s))) == [1])
        #expect(s.badge(s.categories[0]) == 1)
        expectFresh(s)
    }

    @Test func seenAndUnreadAgainMoveTheUnreadCount() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10)])
        #expect(s.unreadCount(mine(s)) == 2 && s.badge(s.categories[0]) == 2)
        s.markSeen(entry(s, 1))
        #expect(s.unreadCount(mine(s)) == 1 && s.badge(s.categories[0]) == 1)
        #expect(s.entries(in: mine(s)).first { $0.thing.number == 1 }?.isUnread == false)
        expectFresh(s)
        s.markUnread(entry(s, 1))
        #expect(s.unreadCount(mine(s)) == 2)
        #expect(s.entries(in: mine(s)).first { $0.thing.number == 1 }?.isUnread == true)
        expectFresh(s)
        s.markAllSeen(.category(mine(s)))
        #expect(s.unreadCount(mine(s)) == 0)
        #expect(s.tabNeedingYou == .category(mine(s)))
        expectFresh(s)
    }

    @Test func doneAndRestoreMoveEntriesBetweenTheCategoryAndDone() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10), pr(3, minutesAgo: 20)])
        s.markDone(entry(s, 3))
        s.marks[entry(s, 3).id]?.doneAt = now
        s.markDone(entry(s, 1))
        s.marks[entry(s, 1).id]?.doneAt = now.addingTimeInterval(60)
        // Most recently done first; the category keeps the rest, newest first.
        #expect(numbers(s.doneEntries) == [1, 3])
        #expect(numbers(s.entries(in: mine(s))) == [2])
        #expect(s.unreadCount(mine(s)) == 1)
        #expect(numbers(s.entries(in: .done)) == [1, 3])
        expectFresh(s)
        // Done again later: it is the most recent.
        s.marks[entry(s, 3).id]?.doneAt = now.addingTimeInterval(120)
        #expect(numbers(s.doneEntries) == [3, 1])
        s.restore(entry(s, 1))
        #expect(numbers(s.doneEntries) == [3])
        #expect(numbers(s.entries(in: mine(s))) == [2, 1])
        expectFresh(s)
    }

    @Test func categoriesAndTheirRulesChangeWhatEachHolds() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10), pr(3, minutesAgo: 20, repo: "b/two")])
        let first = mine(s)
        #expect(s.count(first) == 3)
        // A narrower rule: only a/one.
        s.categories[0].rules = [Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo("a/one")])), conditions: [.greptileBelow(5)],
                                      createdAt: .distantPast)]
        #expect(numbers(s.entries(in: first)) == [2, 1])
        expectFresh(s)
        // A category ahead of it takes b/two's and a/one's: a thing is in the first category that matches it.
        let ahead = InboxCategory(name: "Two", symbol: "star", color: .green,
                                  rules: [Rule(scope: Scope(kinds: [.pr]), conditions: [.greptileBelow(5)], createdAt: .distantPast)])
        s.categories.insert(ahead, at: 0)
        #expect(s.count(ahead.id) == 3 && s.count(first) == 0)
        #expect(s.unreadCount(ahead.id) == 3 && s.unreadCount(first) == 0)
        expectFresh(s)
        // Moved after it: the first takes its own back.
        s.moveCategory(ahead.id, by: 1)
        #expect(numbers(s.entries(in: first)) == [2, 1] && numbers(s.entries(in: ahead.id)) == [3])
        expectFresh(s)
        // Deleted: nothing is left under its id.
        s.categories.removeAll { $0.id == ahead.id }
        #expect(s.entries(in: ahead.id).isEmpty && s.count(ahead.id) == 0 && s.unreadCount(ahead.id) == 0)
        expectFresh(s)
    }

    @Test func whoYouAreChangesWhatYourReposHold() {
        let s = InboxFixture.store([pr(1, minutesAgo: 30, repo: "me/x"), pr(2, minutesAgo: 10, repo: "other/y")],
                                   category: InboxStore.myRepos)
        let repos = s.categories[0].id
        #expect(numbers(s.entries(in: repos)) == [1])
        s.me = GHUser(login: "other", avatarUrl: nil, type: "User")
        #expect(numbers(s.entries(in: repos)) == [2])
        expectFresh(s)
    }

    @Test func aSearchReadsTheCategorysNameAsItIsNow() {
        let s = store([pr(1, minutesAgo: 30), pr(2, minutesAgo: 10)])
        #expect(s.inboxRows(.category(mine(s)), search: "mine").count == 2)
        s.categories[0].name = "Reviews"
        #expect(s.inboxRows(.category(mine(s)), search: "mine").isEmpty)
        #expect(numbers(s.inboxRows(.category(mine(s)), search: "reviews")) == [2, 1])
        // A thing renamed is found by its new title.
        var renamed = pr(1, minutesAgo: 30)
        renamed.title = "Fix the parser"
        s.things[renamed.id] = renamed
        #expect(numbers(s.inboxRows(.category(mine(s)), search: "PARSER")) == [1])
        // Done ones come last.
        s.markDone(entry(s, 2))
        #expect(numbers(s.inboxRows(.category(mine(s)), search: "reviews")) == [1, 2])
    }
}

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
        await waitUntil { !store.entries.isEmpty }
        #expect(store.entries.map(\.id) == [thing.id])
    }

    @Test func crossingTheThresholdIsSeenAndAnnouncedWithNothingReadingTheInbox() async throws {
        let thing = InboxFixture.pr(1, updated: Date().addingTimeInterval(-86_400 + 0.5))
        let store = InboxFixture.store([thing], category: stale(days: 1))
        var posted: [String] = []
        store.notifier.onPost = { posted.append($0.identifier) }
        store.announceInbox()
        let revision = store.inboxRevision
        await waitUntil { store.inboxRevision != revision && !posted.isEmpty }
        #expect(store.inboxRevision != revision)
        #expect(posted == ["inbox:\(thing.id)"])
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
