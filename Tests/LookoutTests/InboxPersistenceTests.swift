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

    @Test func theSavedRulesSayTheirFirstKindForBuildsFromBeforeKinds() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let store = Store()
        store.stateFile = file
        store.categories = [InboxCategory(name: "Both", symbol: "tray", color: .blue, rules: [Rule(scope: Scope(kinds: [.issue, .pr]))])]
        store.flushSave()
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let scope = ((saved["categories"] as? [[String: Any]])?.first?["rules"] as? [[String: Any]])?.first?["scope"] as? [String: Any]
        #expect(scope?["kind"] as? String == "pr" && scope?["kinds"] as? [String] == ["pr", "issue"])
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

    /// The first inbox's file (fed5f6c): categories with no `actions` or `section`, rules with one `kind`, things with no
    /// `behindBase`, `headSha` or `reviewRequests`, and no sections.
    static let firstInboxFile = #"""
    {"settings": {"pollInterval": 60, "notifications": true},
     "categories": [{"id": "0E7C1A52-6A3B-4C59-9E0D-1F2A3B4C5D6E", "name": "Reviews", "symbol": "eye", "color": "violet",
                     "rules": [{"id": "5B0F3D9E-2C7A-4E1B-8F6D-7A8B9C0D1E2F", "scope": {"kind": "pr", "toRoles": ["reviewRequested"]},
                                "match": "any", "conditions": [], "createdAt": "2026-10-10T09:00:00Z"}],
                     "notifies": false, "hidden": false, "isCI": false}],
     "groups": [{"id": "9D8C7B6A-5F4E-4D3C-8B2A-1F0E9D8C7B6A", "name": "Friends", "kind": "people", "members": ["octo"]}],
     "things": {"pr:a/one#1": {"id": "pr:a/one#1", "kind": "pr", "repo": "a/one", "number": 1, "title": "Fix the build",
                               "url": "https://github.com/a/one/pull/1", "status": "open", "labels": [], "assignees": [],
                               "requestedReviewers": ["me"], "mentioned": [], "createdAt": "2026-10-09T09:00:00Z",
                               "updatedAt": "2026-10-10T09:00:00Z", "comments": [], "reviews": [], "threads": [], "commits": [],
                               "hasConflicts": false, "failingJobs": []}},
     "marks": {"pr:a/one#1": {"seen": ["k"], "acked": ["k"], "notified": ["k"], "doneAt": "2026-10-10T10:00:00Z"}},
     "categoryBaselines": ["0E7C1A52-6A3B-4C59-9E0D-1F2A3B4C5D6E", ["5B0F3D9E-2C7A-4E1B-8F6D-7A8B9C0D1E2F"]],
     "ownedRepos": ["me/own"], "contributedRepos": [], "reposResolvedAt": "2026-10-10T08:00:00Z"}
    """#

    @Test func theFirstInboxsFileKeepsItsCategoriesThingsAndMarks() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        try Data(Self.firstInboxFile.utf8).write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.categories.map(\.name) == ["Reviews"])
        #expect(store.categories.first?.actions.isEmpty == true && store.categories.first?.notifies == false)
        #expect(store.categories.first?.rules.first?.scope.kinds == [.pr])
        #expect(store.groups.map(\.members) == [["octo"]])
        #expect(store.things["pr:a/one#1"]?.behindBase == false && store.things["pr:a/one#1"]?.reviewRequests == [])
        #expect(store.marks["pr:a/one#1"]?.acked == ["k"])
        #expect(store.categorySections == [.github])
        #expect(store.categoryBaselines.count == 1)
        // Nothing was lost: nothing is kept aside.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["state.json"])
    }

    @Test func aFileReadOnlyInPartIsKeptAsideBeforeItIsWrittenOver() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let original = Data(#"{"settings": {"pollInterval": 45, "notifications": true}, "categories": [{"name": 5}]}"#.utf8)
        try original.write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        store.marks = ["pr:a/one#1": EntryMarks(seen: ["k"])]
        store.flushSave()
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("state.json.bak-") }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try Data(contentsOf: folder.appendingPathComponent($0)) } == original)

        // A file that isn't read at all is kept aside too.
        let other = try self.folder()
        defer { try? FileManager.default.removeItem(at: other) }
        try Data("not json".utf8).write(to: other.appendingPathComponent("state.json"))
        let second = Store()
        second.stateFile = other.appendingPathComponent("state.json")
        second.load()
        #expect(try FileManager.default.contentsOfDirectory(atPath: other.path).contains { $0.hasPrefix("state.json.bak-") })
    }

    @Test func oneElementThatNoLongerDecodesIsLostAloneNotItsWholeList() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let good = InboxFixture.category()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try enc.encode(value), as: UTF8.self) }
        let summary = RouterSummary(at: Date(timeIntervalSince1970: 1_800_000_000), text: "all good")
        try Data("""
        {"settings": {"pollInterval": 60, "notifications": true},
         "categories": [\(try json(good)), {"name": 5}],
         "groups": [{"name": "broken"}, \(try json(InboxGroup(name: "Friends", kind: .people, members: ["octo"])))],
         "things": {"pr:a/one#1": \(try json(InboxFixture.pr(1))), "pr:a/one#2": {"id": 2}},
         "marks": {"pr:a/one#1": {"seen": ["k"]}, "pr:a/one#2": {"seen": 5}},
         "router": {"overviews": [\(try json(summary)), {"at": 5}], "decisions": [{"at": 5}], "changes": [{"nope": true}]}}
        """.utf8).write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.categories.map(\.id) == [good.id])
        #expect(store.groups.map(\.name) == ["Friends"])
        #expect(store.things.keys.sorted() == ["pr:a/one#1"] && store.marks.keys.sorted() == ["pr:a/one#1"])
        #expect(store.router.summaries == [summary])
        // What was lost is kept aside, in the file as it was.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix("state.json.bak-") })
    }

    @Test func aLossInTheRouterAloneKeepsTheFileAside() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let decision = RouterDecision(at: Date(timeIntervalSince1970: 1_800_000_000), trigger: .you("hi"), outcome: .done)
        let original = Data("""
        {"settings": {"pollInterval": 60, "notifications": true},
         "router": {"enabled": true, "decisions": [\(String(decoding: try enc.encode(decision), as: UTF8.self)), {"at": 5}],
                    "waits": {"s1": 12, "s2": "late"}}}
        """.utf8)
        try original.write(to: file)
        let state = try { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return try d.decode(PersistedState.self, from: original) }()
        #expect(state.dropped == ["router: 1 of decisions", "router: 1 of waits"])
        #expect(state.router?.dropped == [])
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.router.enabled && store.router.decisions == [decision] && store.router.waits == ["s1": 12])
        store.marks = ["pr:a/one#1": EntryMarks(seen: ["k"])]
        store.flushSave()
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("state.json.bak-") }
        #expect(try backups.map { try Data(contentsOf: folder.appendingPathComponent($0)) } == [original])
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
