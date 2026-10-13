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
