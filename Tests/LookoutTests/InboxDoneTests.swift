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

    @Test func anAssignmentWhoseTimeBecomesKnownStaysDoneRatedAndActedOn() {
        // An issue assigned to you, rated before GitHub said when (`assigned`), and Done.
        var issue = Thing(id: "issue:a/one#2", kind: .issue, repo: "a/one", number: 2, title: "t",
                          url: URL(string: "https://github.com/a/one/issues/2")!, author: alice,
                          createdAt: Date().addingTimeInterval(-1000), updatedAt: Date())
        issue.assignees = ["me"]
        issue.signals = ThingSignals(importance: ImportanceSignal(level: .high, stamp: "assigned"), viewer: "me")
        let rated = InboxCategory(name: "Rated", symbol: "flag", color: .red,
                                  rules: [Rule(scope: Scope(kinds: [.issue]), conditions: [.importance(.high)], createdAt: .distantPast)])
        let s = InboxFixture.store([issue], category: rated)
        #expect(s.entries.map { $0.facts.map(\.key) } == [["importance:high:assigned"]])
        s.markDone(s.entries[0])
        let action = UUID()
        s.actionLedger.set(ActionRun(category: rated.id, thing: issue.id, action: action, trigger: "importance:high:assigned",
                                     state: .done, at: Date()))
        // GitHub now says when, before it was last seen: the same assignment, still Done, its rating and its action's
        // record carried over.
        let at = Date(timeIntervalSince1970: issue.updatedAt.timeIntervalSince1970.rounded(.down) - 100)
        issue.assignedAt = ["me": at]
        s.things[issue.id] = issue
        let stamp = "assigned:\(Int(at.timeIntervalSince1970))"
        let key = "importance:high:" + stamp
        #expect(s.entries.map(\.isDone) == [true])
        #expect(s.entries.first?.facts.map(\.key) == [key])
        #expect(s.things[issue.id]?.signals?.importance?.stamp == stamp)
        #expect(s.marks[issue.id]?.acked == [key])
        #expect(s.actionLedger.run(rated.id, issue.id, action, key)?.state == .done)
        #expect(s.actionLedger.run(rated.id, issue.id, action, "importance:high:assigned") == nil)
    }

    /// An issue assigned to you, rated (`assigned`, before GitHub said when), Done and acted on, in "Rated" (rated high).
    private func ratedAssignment() -> (Store, Thing, category: UUID, action: UUID) {
        var issue = Thing(id: "issue:a/one#2", kind: .issue, repo: "a/one", number: 2, title: "t",
                          url: URL(string: "https://github.com/a/one/issues/2")!, author: alice,
                          createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_001_000))
        issue.assignees = ["me"]
        issue.signals = ThingSignals(importance: ImportanceSignal(level: .high, stamp: "assigned"), viewer: "me")
        let rated = InboxCategory(name: "Rated", symbol: "flag", color: .red,
                                  rules: [Rule(scope: Scope(kinds: [.issue]), conditions: [.importance(.high)], createdAt: .distantPast)])
        let s = InboxFixture.store([issue], category: rated)
        s.markDone(s.entries[0])
        let action = UUID()
        s.actionLedger.set(ActionRun(category: rated.id, thing: issue.id, action: action, trigger: "importance:high:assigned",
                                     state: .done, at: Date()))
        return (s, issue, rated.id, action)
    }

    @Test func anAssignmentMadeSinceItWasLastSeenIsNewNotTheOldOneDone() {
        var (s, issue, category, action) = ratedAssignment()
        // Taken off and assigned again while the app was closed: GitHub's time is after the thing was last seen.
        issue.assignedAt = ["me": Date(timeIntervalSince1970: 1_700_002_000)]
        issue.updatedAt = Date(timeIntervalSince1970: 1_700_002_000)
        s.things[issue.id] = issue
        let key = "importance:high:assigned:1700002000"
        #expect(s.things[issue.id]?.signals?.importance == nil)
        #expect(s.marks[issue.id]?.acked.contains(key) == false)
        #expect(s.actionLedger.run(category, issue.id, action, key) == nil)
        // Its time seen since, nothing old is carried to it later.
        s.things[issue.id] = issue
        #expect(s.marks[issue.id]?.acked.contains(key) == false)
    }

    @Test func aCachedAssignmentIsCarriedOnceTheLoadIsCompleteNotDuringIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lookout-done-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        var issue = Thing(id: "issue:a/one#2", kind: .issue, repo: "a/one", number: 2, title: "t",
                          url: URL(string: "https://github.com/a/one/issues/2")!, author: alice,
                          createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_001_000))
        issue.assignees = ["me"]
        issue.assignedAt = ["me": Date(timeIntervalSince1970: 1_700_000_500)]
        issue.signals = ThingSignals(importance: ImportanceSignal(level: .high, stamp: "assigned"), viewer: "me")
        // Saved with its time already known but its rating and Done still under `assigned` (not yet carried).
        let legacy = "importance:high:assigned"
        let first = Store()
        first.stateFile = file
        first.things = [issue.id: issue]
        first.marks = [issue.id: EntryMarks(seen: [legacy], acked: [legacy], doneAt: Date(),
                                            doneFacts: [Fact(key: legacy, label: "High")])]
        first.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        first.save()
        first.flushSave()

        // Opened offline: carried once everything is read, the login and Done included.
        let second = Store()
        second.stateFile = file
        second.load()
        let key = "importance:high:assigned:1700000500"
        #expect(second.things[issue.id]?.signals?.importance?.stamp == "assigned:1700000500")
        #expect(second.marks[issue.id]?.acked == [key])
        #expect(second.marks[issue.id]?.doneFacts?.map(\.key) == [key])
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

    @Test func aDoneThingSaysWhatIsTrueNow() {
        var pr = InboxFixture.pr(3)
        pr.threads = ["t1", "t2"].map {
            ThingThread(id: $0, isResolved: false, startedBy: alice, lastReplyBy: alice, lastReplyID: $0 + "r", lastReplyAt: Date(), snippet: "")
        }
        let threads = InboxCategory(name: "Threads", symbol: "bubble", color: .blue,
                                    rules: [Rule(scope: Scope(kinds: [.pr]), conditions: [.unresolvedThreads(startedBy: nil, lastReplyBy: nil)],
                                                 createdAt: .distantPast)])
        let s = InboxFixture.store([pr], category: threads)
        s.markDone(s.entries[0])
        pr.threads[1].isResolved = true
        s.things[pr.id] = pr
        // Still Done for the thread left, which it says as it is now.
        #expect(s.doneEntries.map { $0.facts.map(\.label) } == [["1 unresolved"]])
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

    @Test func aStateGoneSinceDoneIsNewWhenItComesBack() {
        var thing = InboxFixture.pr(2)
        thing.hasConflicts = true
        thing.checks = .failing
        let broken = InboxCategory(name: "Broken", symbol: "xmark", color: .red,
                                   rules: [Rule(scope: Scope(kinds: [.pr]), match: .any, conditions: [.hasConflicts, .checks([.failing])],
                                                createdAt: .distantPast)])
        let s = InboxFixture.store([thing], category: broken)
        var posted: [String] = []
        s.notifier.onPost = { posted.append($0.content.body) }
        s.announceInbox()
        s.markDone(s.entries[0])
        // The conflicts are resolved, the checks still fail: still Done, without the conflicts.
        thing.hasConflicts = false
        s.things[thing.id] = thing
        s.announceInbox()
        #expect(s.doneEntries.first?.facts.map(\.key) == ["checks:failing"])
        #expect(s.marks[thing.id]?.acked.contains("conflicts") == false)
        // They come back: that is new.
        thing.hasConflicts = true
        s.things[thing.id] = thing
        s.announceInbox()
        #expect(s.entries(in: broken.id).map(\.id) == [thing.id])
        #expect(posted == ["has conflicts"])
    }

    @Test func doneMarksSavedBeforeRoutingWasKeptReadAsBefore() throws {
        let old = #"{"seen":["a"],"acked":["a"],"notified":[],"doneAt":0}"#
        let marks = try JSONDecoder().decode(EntryMarks.self, from: Data(old.utf8))
        #expect(marks.doneIn == nil && marks.doneFacts == nil && marks.acked == ["a"])
    }
}
