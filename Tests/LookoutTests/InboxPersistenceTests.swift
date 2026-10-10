import Foundation
import Testing
@testable import Lookout

/// What the inbox keeps between launches, and how a click on its notifications finds a thing.
@MainActor
@Suite(.serialized) struct InboxPersistence {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lookout-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func baselinesAndResolvedReposAreKeptAndMarksAreOnlyMarks() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let category = InboxFixture.category()
        let resolved = Date(timeIntervalSince1970: 1_800_000_000)

        let first = Store()
        first.stateFile = file
        first.categories = [category]
        first.categoryBaselines = [category.id: Set(category.rules.map(\.id))]
        first.ownedRepos = ["me/own"]
        first.contributedRepos = ["o/c"]
        first.reposResolvedAt = resolved
        first.things = ["pr:a/one#1": InboxFixture.pr(1)]
        first.marks = ["pr:a/one#1": EntryMarks(seen: ["greptile:3"])]
        first.save()
        first.flushSave()

        let second = Store()
        second.stateFile = file
        second.load()
        #expect(second.categoryBaselines == [category.id: Set(category.rules.map(\.id))])
        #expect(second.ownedRepos == ["me/own"] && second.contributedRepos == ["o/c"])
        #expect(second.reposResolvedAt == resolved)
        #expect(second.marks.keys.sorted() == ["pr:a/one#1"])
        // The editor's preview has the repos a rule names without waiting for a refresh.
        #expect(second.inboxContext.contributedRepos == ["o/c"])
    }

    @Test func aDoneOrACategoryEditIsKeptByQuittingBeforeAnyPoll() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let category = InboxFixture.category()

        let first = Store()
        first.stateFile = file
        first.load()
        // No poll and no `save()`: only the edits themselves, then quitting.
        first.categories = [category]
        first.marks = ["pr:a/one#1": EntryMarks(seen: ["greptile:3"])]
        first.flushSave()

        let second = Store()
        second.stateFile = file
        second.load()
        #expect(second.categories.map(\.id) == [category.id])
        #expect(second.marks.keys.sorted() == ["pr:a/one#1"])
    }

    @Test func aWriteThatFailedIsNotCountedAsSavedAndQuittingTriesAgain() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Its folder isn't there yet: writing fails.
        let file = folder.appendingPathComponent("gone", isDirectory: true).appendingPathComponent("state.json")

        let first = Store()
        first.stateFile = file
        first.marks = ["pr:a/one#1": EntryMarks(seen: ["greptile:3"])]
        first.flushSave()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // The folder is back: the change still pending is written, though nothing changed since.
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        first.flushSave()

        let second = Store()
        second.stateFile = file
        second.load()
        #expect(second.marks.keys.sorted() == ["pr:a/one#1"])
    }

    @Test func aFileFromBeforeTheCategoriesLoadsWhatItCanAndLosesTheRest() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        try Data(#"""
        {"repos": [{"fullName": "a/one", "events": ["prComment"], "cursors": {}, "addedAt": "2026-01-01T00:00:00Z", "allComments": true}],
         "items": [{"id": "x", "repo": "a/one", "kind": "prComment", "number": 1, "title": "t", "snippet": "", "author": "u",
                    "authorIsApp": false, "url": "https://github.com/a/one", "createdAt": "2026-01-01T00:00:00Z", "state": "unread"}],
         "ci": {"a/one": {"state": "failure", "branch": "main", "failing": ["build"], "checkedAt": "2026-01-01T00:00:00Z"}},
         "settings": {"botHandles": ["vercel"], "treatAppsAsBots": true, "pollInterval": 30, "notifications": false,
                      "reviewRequests": true, "didInitialReviewSync": true}}
        """#.utf8).write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.settings.pollInterval == 30 && !store.settings.notifications)
        #expect(store.things.isEmpty && store.marks.isEmpty && store.groups.isEmpty)
        // The default categories stand.
        #expect(store.categories.map(\.name) == ["My repos"])
    }

    @Test func theRulesAboutYouMatchAtLaunchBeforeGitHubSaysWhoYouAre() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let mine = InboxCategory(name: "My repos", symbol: "folder", color: .blue,
                                 rules: [Rule(scope: Scope(kinds: [.pr, .issue], in: Pick(include: [.owned])))])
        let first = Store()
        first.stateFile = file
        first.categories = [mine]
        first.things = ["pr:me/old#1": InboxFixture.pr(1, repo: "me/old")]
        first.me = GHUser(login: "me", avatarUrl: nil, type: nil)
        first.save()
        first.flushSave()

        let second = Store()
        second.stateFile = file
        second.load()
        #expect(second.me == nil)
        #expect(second.entries(in: mine.id).map(\.id) == ["pr:me/old#1"])
    }

    @Test func aPartThatNoLongerDecodesIsLostAlone() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        try Data(#"{"settings": {"pollInterval": 45, "notifications": true}, "categories": [{"name": 5}], "groups": []}"#.utf8).write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.settings.pollInterval == 45)
        #expect(store.categories.map(\.name) == ["My repos"])
    }

    // MARK: Notification clicks

    @Test func aClickOnAThingsBannerOpensItsCategoryWithItSelected() {
        let category = InboxFixture.category()
        let store = InboxFixture.store([InboxFixture.pr(7)], category: category)
        var opened: [(UUID?, String?)] = []
        store.onOpenInbox = { opened.append(($0, $1)) }
        store.openNotification(id: "inbox:pr:a/one#7", url: "https://github.com/a/one/pull/7")
        #expect(opened.count == 1 && opened[0].0 == category.id && opened[0].1 == "pr:a/one#7")
    }

    @Test func aSummaryOpensTheInboxAndAGoneThingDoesNot() {
        let store = InboxFixture.store([InboxFixture.pr(7)])
        var opened = 0
        store.onOpenInbox = { category, thing in opened += 1; #expect(category == nil && thing == nil) }
        store.openNotification(id: Notifier.summaryPrefix + "x", url: nil)
        #expect(opened == 1)
        // A thing no rule holds any more is not in the inbox: the inbox does not open on it.
        store.openNotification(id: "inbox:pr:a/one#99", url: nil)
        #expect(opened == 1)
    }
}
