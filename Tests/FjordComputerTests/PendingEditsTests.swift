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
    @Test func aQuitWritesWhatEachFieldOnScreenHoldsNowAndNothingOfAFieldGone() {
        var typed = "", stored = ""
        let field = UUID(), gone = UUID()
        // Held from the field's appearing: its write is of what it holds when called.
        PendingEdits.hold(field) { if stored != typed { stored = typed } }
        PendingEdits.hold(gone) { Issue.record("a field gone writes nothing") }
        PendingEdits.release(gone)
        // A keystroke, in the field before any change of it is seen: a quit right then still writes it.
        typed = "ship"
        PendingEdits.flushAll()
        #expect(stored == "ship")
        typed = "ship it"
        PendingEdits.flushAll()
        #expect(stored == "ship it", "held for the field's lifetime, not once")
        PendingEdits.release(field)
    }
}

@MainActor
struct PendingEditsUndoTests {
    @Test func undoWritesATypedNameStillWaitingThenTakesItBack() {
        let store = InboxFixture.store([InboxFixture.pr(1)])
        let history = CategoryHistory(store: store)
        let before = store.categories[0].name
        let field = UUID()
        var typed: String? = "Typed"
        PendingEdits.hold(field) {
            if let name = typed { typed = nil; store.categories[0].name = name }
        }
        defer { PendingEdits.release(field) }
        history.undo(store)
        #expect(store.categories[0].name == before, "undo took the typed name back, nothing landed over it")
        #expect(history.canRedo)
        history.redo(store)
        #expect(store.categories[0].name == "Typed")
    }
}

struct TypedNameTests {
    @Test func aTypedNameStandsOnlyOverTheNameItWasTypedOver() {
        #expect(CategoryEditor.nameToWrite(typed: "Reviews!", over: "Reviews", stored: "Reviews") == "Reviews!")
        // Renamed by the Router while it was typed: the rename stands.
        #expect(CategoryEditor.nameToWrite(typed: "Reviews!", over: "Reviews", stored: "Code reviews") == nil)
        #expect(CategoryEditor.nameToWrite(typed: "Same", over: "Same", stored: "Same") == nil)
    }
}
