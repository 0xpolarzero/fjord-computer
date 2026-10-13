import Foundation
import Testing
@testable import FjordComputer

/// Edits typed into a category's fields that reach the store after a pause: they never land on another action, and nothing
/// typed is lost to a quit.
@MainActor
struct PendingEditsTests {
    @Test func aPromptWrittenAfterItsActionWasRemovedLandsNowhere() {
        let a = CategoryAction(kind: .comment("a")), b = CategoryAction(kind: .comment("b"))
        var items = [a, b]
        // A removed: its field's late write (as it goes) finds no action with its id.
        items.removeAll { $0.id == a.id }
        var late = a
        late.kind = .comment("typed into a")
        ActionsEditor.replace(late, in: &items)
        #expect(items == [b], "b keeps its own text")
        // B removed too: a late write past the end is dropped, not a crash.
        items.removeAll()
        ActionsEditor.replace(late, in: &items)
        #expect(items.isEmpty)
        // Still there: written in its place.
        items = [a, b]
        ActionsEditor.replace(late, in: &items)
        #expect(items.first?.kind == .comment("typed into a") && items.last == b)
    }
}

@MainActor
struct PendingEditsFlushTests {
    @Test func aQuitWritesWhatWaitsForItsPauseOnceAndForgetsWhatWasWritten() {
        var written: [String] = []
        let a = UUID(), b = UUID()
        PendingEdits.hold(a) { written.append("a") }
        PendingEdits.hold(b) { written.append("b") }
        // Written already, by its pause: nothing left to write for it.
        PendingEdits.release(b)
        PendingEdits.flushAll()
        #expect(written == ["a"])
        PendingEdits.flushAll()
        #expect(written == ["a"], "each write once")
    }
}

@MainActor
struct PendingEditsUndoTests {
    @Test func undoWritesATypedNameStillWaitingThenTakesItBack() {
        let store = InboxFixture.store([InboxFixture.pr(1)])
        let history = CategoryHistory(store: store)
        let before = store.categories[0].name
        let field = UUID()
        PendingEdits.hold(field) {
            PendingEdits.release(field)
            store.categories[0].name = "Typed"
        }
        history.undo(store)
        #expect(store.categories[0].name == before, "undo took the typed name back, nothing landed over it")
        #expect(history.canRedo)
        history.redo(store)
        #expect(store.categories[0].name == "Typed")
    }
}
