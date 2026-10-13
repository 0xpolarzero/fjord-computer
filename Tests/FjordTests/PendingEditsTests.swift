import Foundation
import SwiftUI
import Testing
@testable import Fjord

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

@MainActor
struct PromptBindingTests {
    /// The field's write, held from its appearing, compares what it holds with the prompt as stored now: saved as B, then A
    /// typed again, a quit writes A rather than finding it equal to the A the row was drawn with.
    @Test func aPromptIsReadAsItIsStoredWhenAsked() {
        let a = ActionPrompt(text: "A"), b = ActionPrompt(text: "B")
        var stored = CategoryAction(kind: .askRouter(prompt: a))
        let action = Binding(get: { stored }, set: { stored = $0 })
        let prompt = ActionsEditor.prompt(of: action, else: a)
        prompt.wrappedValue = b
        #expect(prompt.wrappedValue == b, "the binding made when the row showed A reads B now")
        // What the held write does: what the field holds (A again), against what is stored (B): written.
        let typed = a
        if typed != prompt.wrappedValue { prompt.wrappedValue = typed }
        #expect(ActionsEditor.prompt(of: action, else: b).wrappedValue == a)
        // Already stored: nothing written.
        var writes = 0
        let counted = Binding(get: { stored }, set: { stored = $0; writes += 1 })
        let again = ActionsEditor.prompt(of: counted, else: b)
        if typed != again.wrappedValue { again.wrappedValue = typed }
        #expect(writes == 0)
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
