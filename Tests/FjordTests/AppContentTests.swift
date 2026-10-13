import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite struct AppContentTests {
    @Test func unreadCountsFollowTheRowsAndKeepDoneAndWhitespaceSearchBehavior() throws {
        let store = InboxFixture.store([InboxFixture.pr(1, title: "Needle"), InboxFixture.pr(2, title: "Other"),
                                       InboxFixture.pr(3, repo: "b/two", title: "Needle"), InboxFixture.pr(4, title: "Finished")])
        store.categories[0].rules[0].scope.in = Pick(include: [.repo("a/one")])
        store.categories.append(InboxFixture.category())
        let id = store.categories[0].id
        store.markDone(try #require(store.entries.first { $0.thing.number == 4 }))
        store.markUnread(try #require(store.doneEntries.first))
        let search = InboxSearch()
        let category = InboxListView(store: store, tab: .category(id), search: search)
        let done = InboxListView(store: store, tab: .done, search: search)
        for (query, categoryUnread, doneUnread) in [("", 2, 0), ("   ", 2, 0), ("\t", 0, 0),
                                                   ("\u{00a0}", 0, 0), ("Needle", 2, 2), ("Finished", 1, 1)] {
            search.query = query
            let categoryRows = store.inboxRows(.category(id), search: query)
            let doneRows = store.inboxRows(.done, search: query)
            #expect(category.unread(categoryRows) == categoryUnread)
            #expect(done.unread(doneRows) == doneUnread)
        }
    }
}
