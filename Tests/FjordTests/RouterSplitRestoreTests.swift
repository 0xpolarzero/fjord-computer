import Foundation
import Testing
@testable import Fjord

/// "Split…" puts the compound message back in the composer without any armed state going with it, and without losing a draft.
@MainActor
struct RouterSplitRestoreTests {
    @Test func anEditOrAPinOrAReplyDoesNotSurviveTheSplit() {
        let model = RouterModel()
        model.edit(session: "local_a", message: "an earlier message")
        model.draft = ""
        model.live.pinned = "session:local_a"
        #expect(model.editing != nil)
        model.restore("update the category and tell CI to rerun")
        #expect(model.editing == nil && model.replyTo == nil && model.live.pinned == nil && model.pointers.isEmpty)
        #expect(model.draft == "update the category and tell CI to rerun", "an empty composer holds just the message")
        model.replyTo = "local_a#w1"
        model.restore("again")
        #expect(model.replyTo == nil)
    }

    @Test func anUnsentDraftStaysAndTheMessageFollowsIt() {
        let model = RouterModel()
        model.draft = "something I was typing"
        model.restore("update the category and tell CI to rerun")
        #expect(model.draft == "something I was typing\n\nupdate the category and tell CI to rerun")
    }
}
