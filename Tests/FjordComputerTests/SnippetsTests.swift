import Foundation
import Testing
@testable import FjordComputer

/// Snippets: kept between launches, made, edited, deleted and moved on their page (with its undo), and found by @'s search.
@MainActor
@Suite(.serialized) struct SnippetsTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-snippets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// One that never reaches the saved state.
    private func store() -> Store {
        let store = Store()
        store.persists = false
        return store
    }

    private let review = Snippet(name: "Review", text: "Review this PR for correctness bugs.\nSkip style nits.")
    private let rebase = Snippet(name: "Rebase", text: "Rebase on main and fix what breaks.")
    private let flaky = Snippet(name: "Flaky test", text: "Find out why this test fails now and then; don't just retry it.")

    // MARK: Persistence

    @Test func snippetsAreKeptInOrderBetweenLaunches() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")

        let first = Store()
        first.stateFile = file
        first.load()
        first.snippets = [review, rebase]
        first.addSnippet(name: "Flaky test", text: flaky.text)
        first.flushSave()

        let second = Store()
        second.stateFile = file
        second.load()
        #expect(second.snippets.map(\.name) == ["Review", "Rebase", "Flaky test"])
        #expect(second.snippets.prefix(2).map(\.id) == [review.id, rebase.id])
        #expect(second.snippets[0].text == review.text)
    }

    @Test func aFileFromBeforeSnippetsLoadsWithNoneAndOneThatNoLongerDecodesIsLostAlone() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        try Data(#"{"settings": {"pollInterval": 60, "notifications": true}}"#.utf8).write(to: file)
        let old = Store()
        old.stateFile = file
        old.load()
        #expect(old.snippets.isEmpty)

        let enc = JSONEncoder()
        let good = String(decoding: try enc.encode(review), as: UTF8.self)
        try Data(#"{"settings": {"pollInterval": 60, "notifications": true}, "snippets": [{"name": 5}, \#(good)]}"#.utf8).write(to: file)
        let store = Store()
        store.stateFile = file
        store.load()
        #expect(store.snippets == [review])
    }

    // MARK: Editing

    @Test func addingEditingMovingAndDeleting() {
        let store = self.store()
        let made = store.addSnippet()
        #expect(store.snippets == [made] && made.name == "New snippet" && made.text.isEmpty)
        store.updateSnippet(made.id) { $0.name = "Ship it"; $0.text = "Merge when green." }
        #expect(store.snippets[0].name == "Ship it" && store.snippets[0].text == "Merge when green.")
        // A snippet gone since is left alone.
        store.updateSnippet(UUID()) { $0.name = "nope" }
        #expect(store.snippets.count == 1)

        store.snippets += [review, rebase]
        #expect(store.moveSnippet(rebase.id, by: -1))
        #expect(store.snippets.map(\.name) == ["Ship it", "Rebase", "Review"])
        #expect(!store.canMoveSnippet(made.id, by: -1) && !store.moveSnippet(review.id, by: 1))
        // Dragged down onto a row: after it; up: before it.
        store.moveSnippet(made.id, onto: review.id)
        #expect(store.snippets.map(\.name) == ["Rebase", "Review", "Ship it"])
        store.moveSnippet(made.id, onto: rebase.id)
        #expect(store.snippets.map(\.name) == ["Ship it", "Rebase", "Review"])

        store.deleteSnippet(rebase.id)
        #expect(store.snippets.map(\.name) == ["Ship it", "Review"])
    }

    @Test func thePageTakesBackADeleteAndTypingIsOneStepUntilItPauses() {
        let store = self.store()
        store.snippets = [review, rebase]
        let history = SnippetHistory(store: store)
        let field = NSObject()
        let t = Date()
        for (i, name) in ["R", "Re", "Rev"].enumerated() {
            store.updateSnippet(review.id) { $0.name = name }
            history.observe(store, field: ObjectIdentifier(field), now: t.addingTimeInterval(Double(i) * 0.4))
        }
        store.deleteSnippet(rebase.id)
        history.observe(store, now: t.addingTimeInterval(1))
        #expect(history.undos.count == 2)

        #expect(history.undo(store) && store.snippets.map(\.name) == ["Rev", "Rebase"])
        #expect(history.undo(store) && store.snippets == [review, rebase])
        #expect(!history.undo(store))
        #expect(history.redo(store) && store.snippets.map(\.name) == ["Rev", "Rebase"])
        // A new edit clears what could be redone.
        store.addSnippet()
        history.observe(store)
        #expect(!history.canRedo)
    }

    // MARK: Search

    @Test func searchFindsByNameOrTextNameFirst() {
        let all = [review, rebase, flaky]
        #expect(Snippet.search("", in: all) == all)
        #expect(Snippet.search("  ", in: all) == all)
        // The name starting with it first, then a name holding it, then the text.
        let main = Snippet(name: "Main branch", text: "Work on main.")
        #expect(Snippet.search("main", in: [rebase, flaky, main]) == [main, rebase])
        let preMerge = Snippet(name: "Pre-merge", text: "")
        #expect(Snippet.search("re", in: [flaky, preMerge, rebase]) == [rebase, preMerge, flaky])
        // Within a tier, their own order.
        #expect(Snippet.search("re", in: all) == [review, rebase, flaky])
        // Every word, in the name or the text; case and accents aside.
        #expect(Snippet.search("REVIEW nits", in: all) == [review])
        #expect(Snippet.search("review rebase", in: all).isEmpty)
        #expect(Snippet.search("fix", in: [Snippet(name: "Fix", text: ""), Snippet(name: "Préfixé", text: "")]).map(\.name) == ["Fix", "Préfixé"])
        #expect(Snippet.search("prefixe", in: [Snippet(name: "Préfixé", text: "")]).count == 1)
        let store = self.store()
        store.snippets = all
        #expect(store.snippets(matching: "rebase") == [rebase])
    }

    @Test func aSnippetShowsItsNameOrUntitledAndItsFirstLine() {
        #expect(Snippet(name: "  ", text: "").title == "Untitled snippet")
        #expect(Snippet(name: " Review ", text: "").title == "Review")
        #expect(Snippet(name: "x", text: "\n\n  First line \nsecond").preview == "First line")
        #expect(Snippet(name: "x", text: " \n ").preview == nil)
    }
}
