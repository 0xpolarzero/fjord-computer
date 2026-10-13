import Foundation
import Testing
@testable import Fjord

/// Where a card stands by whose move is next (RouterTiers.swift): Jev's two questions, the tier each card takes, the zones
/// and counts, and the history's unread lines.
@MainActor
@Suite(.serialized) struct RouterTiersTests {
    private func state(_ pick: String, _ p: Double) -> JevClient.Answer {
        .choice(.init(choice: pick, confidence: p, probabilities: [pick: p, pick == "asks" ? "done" : "asks": 1 - p]))
    }

    private func answers(state pick: String = "done", _ p: Double = 0.9, step: Double?, notable: Double?) -> [String: JevClient.Answer] {
        var a = ["state": state(pick, p)]
        if let step { a["userStep"] = .noul(step) }
        if let notable { a["notable"] = .noul(notable) }
        return a
    }

    private func triage(_ state: RouterTriage.State?, next: RouterTriage.Next? = nil, trivial: Bool = false,
                        unverified: Bool = false) -> RouterTriage {
        var t = RouterTriage(state: state, unverified: unverified)
        t.next = next
        t.trivial = trivial
        return t
    }

    private func card(_ kind: RouterCard.Kind, _ triage: RouterTriage? = nil, session: String = "s1") -> RouterCard {
        var c = RouterCard(id: "\(session)#t1", sessionID: session, kind: kind, title: "T", folder: nil, text: "Did it.",
                           createdAt: Date(timeIntervalSince1970: 1_000))
        c.triage = triage
        return c
    }

    // MARK: Jev's answers

    @Test func aSureStepIsYoursWhateverElseItSays() {
        let t = triage(.done)
        #expect(RouterTriage.next(answers(step: 0.8, notable: 0.9), t) == .you)
        #expect(RouterTriage.next(answers(state: "progress", step: 0.6, notable: 0.1), triage(.progress)) == .you)
    }

    @Test func theHistoryTakesOnlyASurelyDoneTurnWithNothingInIt() {
        #expect(RouterTriage.next(answers(step: 0.1, notable: 0.1), triage(.done)) == .nothing)
        // Not sure enough it is done, a step or a note not unlikely enough, partway, or a claim it didn't check: a note.
        #expect(RouterTriage.next(answers(state: "done", 0.6, step: 0.1, notable: 0.1), triage(.done)) == .note)
        #expect(RouterTriage.next(answers(step: 0.3, notable: 0.1), triage(.done)) == .note)
        #expect(RouterTriage.next(answers(step: 0.1, notable: 0.3), triage(.done)) == .note)
        #expect(RouterTriage.next(answers(state: "progress", step: 0.1, notable: 0.1), triage(.progress)) == .note)
        #expect(RouterTriage.next(answers(step: 0.1, notable: 0.1), triage(.done, unverified: true)) == .note)
        #expect(RouterTriage.next(answers(step: 0.1, notable: nil), triage(.done)) == .note)
        #expect(RouterTriage.next(answers(step: nil, notable: nil), triage(.done)) == nil)
    }

    @Test func aStepLeftMakesFinishUpEvenOnATrivialTurnButNeverCalmsABlockedOne() {
        #expect(RouterTriage.kind(blocked: false, triage: triage(.done, next: .you)) == .finish)
        #expect(RouterTriage.kind(blocked: false, triage: triage(.done, next: .you, trivial: true)) == .finish)
        #expect(RouterTriage.kind(blocked: false, triage: triage(.progress, next: .you)) == .finish)
        #expect(RouterTriage.kind(blocked: true, triage: triage(.done, next: .you)) == .stuck)
        #expect(RouterTriage.kind(blocked: false, triage: triage(.asks, next: .you)) == .asks)
        #expect(RouterTriage.kind(blocked: false, triage: triage(.done, next: .note)) == .done)
    }

    @Test func theQuestionsReadAsTheirOwnBlocker() {
        let q = RouterTriage.questions(options: [])
        guard case .choice(_, let hints, _) = q["state"] else { Issue.record("no state question"); return }
        #expect(hints["waiting"]?.contains("someone other than the user") == true)
        #expect(hints["asks"]?.contains("review, test or action") == true)
        guard case .noul = RouterTriage.nextExtra.questions["userStep"], case .noul = RouterTriage.nextExtra.questions["notable"] else {
            Issue.record("the two questions"); return
        }
    }

    // MARK: Tiers

    @Test func eachCardTakesTheTierOfWhoseMoveItIs() {
        #expect(card(.question).tier == .needsYou)
        #expect(card(.finish, triage(.done, next: .you)).tier == .needsYou)
        #expect(card(.stuck).tier == .needsYou)
        // Untriaged, unsure, or a claim it didn't check: worth a look, never quieter.
        #expect(card(.done).tier == .note)
        #expect(card(.done, triage(.done)).tier == .note)
        #expect(card(.done, triage(.done, next: .note)).tier == .note)
        #expect(card(.done, triage(.done, next: .nothing, unverified: true)).tier == .note)
        #expect(card(.done, triage(.done, next: .nothing)).tier == .done)
        // Trivial settles a done turn, never one partway.
        #expect(card(.done, triage(.done, trivial: true)).tier == .done)
        #expect(card(.done, triage(.progress, trivial: true)).tier == .note)
    }

    @Test func aWaitOverIsYoursUntilItIsTold() {
        var t = triage(.waiting)
        #expect(card(.waiting, t).tier == .waiting)
        t.ready = .init(result: "passing", at: Date())
        #expect(card(.waiting, t).tier == .needsYou)
        t.told = Date()
        #expect(card(.waiting, t).tier == .waiting)
    }

    // MARK: The page

    @Test func theZonesSplitByTier() {
        var ready = card(.waiting, { var t = triage(.waiting); t.ready = .init(result: "passing", at: Date()); return t }(), session: "w2")
        ready.id = "w2#t1"
        let cards = [card(.question, session: "q"), card(.finish, triage(.done, next: .you), session: "f"),
                     card(.done, triage(.done, next: .note), session: "n"), card(.waiting, triage(.waiting), session: "w1"), ready]
        let page = RouterPage.make(cards: cards, working: [])
        #expect(page.needs.map(\.sessionID) == ["q", "f"])
        #expect(page.notes.map(\.sessionID) == ["n"])
        #expect(page.waiting.map(\.sessionID) == ["w1"])
        #expect(page.ready.map(\.sessionID) == ["w2"])
        // A note picked opens there, and no card of Needs you with it.
        #expect(page.openNeed(preferred: cards[2].id) == nil)
        #expect(page.openNeed(preferred: nil) == cards[0].id)
    }

    @Test func aTurnWithNothingForYouGoesToTheHistoryUnreadUntilSeen() {
        let store = Store()
        store.persists = false
        var c = card(.done, triage(.done, next: .nothing))
        #expect(c.settles)
        c.addressedAt = Date()
        c.addressedBy = .settled
        c.unread = true
        store.router.cards = [c, card(.done, triage(.done, next: .note), session: "s2")]
        #expect(store.routerUnread.map(\.id) == [c.id])
        #expect(store.routerCounts.notes == 1 && store.routerCounts.needsYou == 0)
        store.acknowledgeRouterCard(c.id)
        #expect(store.routerUnread.isEmpty)
        store.router.cards[0].unread = true
        store.acknowledgeAllRouterCards()
        #expect(store.routerUnread.isEmpty)
        // Opened again, it is open and read.
        store.router.cards[0].unread = true
        var state = store.router
        RouterFeed.reopen(&state, c.id, now: Date())
        #expect(state.cards[0].isOpen && state.cards[0].unread == nil)
    }

    @Test func theNewFieldsSurviveTheFile() throws {
        var c = card(.finish, triage(.done, next: .you))
        c.brief = "Merge PR #88."
        c.unread = true
        let back = try JSONDecoder().decode(RouterCard.self, from: JSONEncoder().encode(c))
        #expect(back.kind == .finish && back.triage?.next == .you && back.brief == "Merge PR #88." && back.unread == true)
        // An older build reads Finish up as a finished turn.
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any]
        #expect(raw?["kind"] as? String == "done" && raw?["kindDetail"] as? String == "finish")
    }
}
