import Foundation
import Observation
import SwiftUI
import Testing
@testable import FjordComputer

/// What an open card in Needs you redraws for: its own card, not every session's activity.
@MainActor @Suite struct RouterCardRedrawTests {
    @Test func aNeedsYouCardDoesNotRedrawForOtherSessions() {
        let store = Store()
        Demo.populate(store, .router)
        let card = store.routerPage.needs.first!
        let view = CardView(store: store, model: RouterModel(), card: card, expanded: false,
                            form: store.pendingForm(for: card), project: store.routerProject(card))
        var notified = false
        withObservationTracking { _ = view.body } onChange: { notified = true }
        // Another session works on: its activity changes, and the sessions as read again.
        let other = store.claudeSessions.keys.first { $0 != card.sessionID }!
        store.claudeActivity[other] = ClaudeActivity(text: "Reading a file", since: Date())
        store.claudeSessions[other] = store.claudeSessions[other]
        #expect(!notified)
    }

    @Test func aCardsExcerptIsParsedOncePerText() {
        let text = "Should I **push** to `main`?"
        #expect(CardView.inline(text) == RouterText.inline(text))
        #expect(CardView.inline(text) == RouterText.inline(text))
    }
}
