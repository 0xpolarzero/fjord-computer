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

    @Test func aSessionsRowRedrawsForThatSessionAloneAndIsAsMadeAfresh() {
        let store = Store()
        Demo.populate(store, .router)
        let id = store.claudeSessions.keys.sorted()[0]
        let other = store.claudeSessions.keys.first { $0 != id }!
        _ = store.sessionRow(id)
        var notified = false
        withObservationTracking { _ = store.sessionRow(id) } onChange: { notified = true }
        store.claudeActivity[other] = ClaudeActivity(text: "Reading a file", since: Date())
        store.claudeSessions[other]?.title = "Another title"
        store.claudeTasks[other] = []
        #expect(!notified)
        #expect(store.sessionRow(id) == store.row(store.claudeSessions[id]!))
        // Its own session renamed, its project renamed, its letters set: made again, as a row made now is.
        store.claudeSessions[id]?.title = "Renamed session"
        #expect(notified)
        #expect(store.sessionRow(id)?.session.title == "Renamed session")
        let folder = store.claudeSessions[id]!.folderKey
        store.folderNames[folder] = "qqwwee"
        store.setProjectColor(folder, 3)
        #expect(store.sessionRow(id) == store.row(store.claudeSessions[id]!))
        #expect(store.sessionRow("no such session") == nil)
    }

    @Test func anotherSessionsEntryOrProjectColourLeavesARowAloneAndAGoneSessionsRowGoes() {
        let store = Store()
        Demo.populate(store, .router)
        let id = store.claudeSessions.keys.sorted()[0]
        let folder = store.claudeSessions[id]!.folderKey
        let other = store.claudeSessions.values.first { s in s.id != id && s.folderKey != folder && store.agents.entries.contains { $0.id == s.id } }!
        _ = store.sessionRow(id)
        _ = store.sessionRow(other.id)
        var notified = false
        withObservationTracking { _ = store.sessionRow(id) } onChange: { notified = true }
        let i = store.agents.entries.firstIndex { $0.id == other.id }!
        store.agents.entries[i].label = "ZZ"
        store.setProjectColor(other.folderKey, 5)
        #expect(!notified)
        #expect(store.sessionRow(other.id)?.label == "ZZ")
        #expect(store.sessionRow(other.id) == store.row(store.claudeSessions[other.id]!))
        // Gone, and no card names it: its row is let go of.
        store.router.cards.removeAll { $0.sessionID == other.id }
        store.claudeSessions[other.id] = nil
        #expect(store.sessionRowBoxes[other.id] == nil)
        #expect(store.sessionRow(id) == store.row(store.claudeSessions[id]!))
    }

    @Test func aCardsExcerptIsParsedOncePerText() {
        let text = "Should I **push** to `main`?"
        #expect(CardView.inline(text) == RouterText.inline(text))
        #expect(CardView.inline(text) == RouterText.inline(text))
    }
}
