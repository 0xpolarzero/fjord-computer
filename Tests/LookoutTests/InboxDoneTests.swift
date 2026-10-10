import Foundation
import Testing
@testable import Lookout

/// Done holds a thing in the category it was Done in: the activity cutoff Done moves doesn't route it anywhere else.
@MainActor
@Suite struct InboxDoneTests {
    private let alice = Person(login: "alice")

    /// "Comments" (new comments, since Done) above "My PRs" (every open PR of `a/one`), holding one PR alice commented on.
    private func store() -> (Store, comments: UUID, all: UUID) {
        var thing = InboxFixture.pr(1)
        thing.comments = [ThingComment(id: "c1", author: alice, at: Date().addingTimeInterval(-60), snippet: "hi")]
        let comments = InboxCategory(name: "Comments", symbol: "text.bubble", color: .blue,
                                     rules: [Rule(scope: Scope(kinds: [.pr]), conditions: [.newComment(by: Pick())],
                                                  createdAt: .distantPast)])
        let all = InboxCategory(name: "My PRs", symbol: "folder", color: .blue,
                                rules: [Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo("a/one")])), createdAt: .distantPast)])
        let s = InboxFixture.store([thing], category: comments)
        s.categories.append(all)
        return (s, comments.id, all.id)
    }

    @Test func aThingDoneStaysDoneInItsCategoryNotOpenInALaterOne() {
        let (s, comments, all) = store()
        let entry = s.entries(in: comments)[0]
        s.finish(entry)
        // Done moved what counts as new past alice's comment, but nothing new came: it stays Done where it was.
        #expect(s.entries(in: all).isEmpty && s.entries(in: comments).isEmpty)
        #expect(s.doneEntries.map(\.categoryID) == [comments] && s.doneEntries[0].facts.map(\.key) == ["comment:c1"])
        // A refresh keeps what it was Done with, so Undo still puts it back.
        s.announceInbox()
        #expect(s.marks["pr:a/one#1"]?.acked == ["comment:c1"])
        #expect(s.undoLast() && s.entries(in: comments).map(\.id) == ["pr:a/one#1"])
    }

    @Test func somethingNewAfterDoneOpensItAgainAndARuleThatNoLongerTakesItLetsItGo() {
        let (s, comments, all) = store()
        s.markDone(s.entries(in: comments)[0])
        var thing = s.things["pr:a/one#1"]!
        thing.comments.append(ThingComment(id: "c2", author: alice, at: Date().addingTimeInterval(5), snippet: "again"))
        s.things[thing.id] = thing
        #expect(s.entries(in: comments).first?.facts.map(\.key) == ["comment:c2"])
        s.markDone(s.entries(in: comments)[0])
        #expect(s.doneEntries.first?.categoryID == comments)
        // The category now only wants bob's comments: it was never bob's, so it goes where it belongs now.
        s.categories[0].rules[0].conditions = [.newComment(by: Pick(include: [.user("bob")]))]
        #expect(s.entries(in: all).map(\.id) == ["pr:a/one#1"])
    }

    @Test func doneMarksSavedBeforeRoutingWasKeptReadAsBefore() throws {
        let old = #"{"seen":["a"],"acked":["a"],"notified":[],"doneAt":0}"#
        let marks = try JSONDecoder().decode(EntryMarks.self, from: Data(old.utf8))
        #expect(marks.doneIn == nil && marks.doneFacts == nil && marks.acked == ["a"])
    }
}
