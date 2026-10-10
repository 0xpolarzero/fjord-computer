import Foundation
import Testing
@testable import Lookout

/// The decision log: what each writer records, how a revert settles it, what is kept, the context it renders and the history
/// built on it.
@MainActor
@Suite(.serialized) struct RouterDecisions {
    private func store() -> Store {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = [
            "local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date(), running: true),
        ]
        return s
    }

    // MARK: Writers

    @Test func aChangeJoinsItsRunOrStandsAlone() async throws {
        let s = store()
        let alone = LookoutChange(title: "Changed snooze", patch: .setting(key: "k", before: .on(false), after: .on(true)))
        s.logChange(alone)
        #expect(s.router.decisions.count == 1 && s.router.decisions[0].trigger == .system)
        #expect(s.router.decisions[0].done == [.changed(alone.id)] && s.router.decisions[0].links.changes == [alone.id])

        let run = s.logDecision(RouterDecision(trigger: .you("snooze")))
        let joined = LookoutChange(title: "Changed other", patch: .setting(key: "k", before: .on(false), after: .on(true)))
        s.logChange(joined, into: run)
        #expect(s.router.decisions.count == 2)
        #expect(s.router.decisions[1].done == [.changed(joined.id)])
    }

    @Test func revertingAChangeSettlesItsDecision() async throws {
        let s = store()
        s.categories = [InboxStore.ci]
        let t = RouterTools(store: s)
        t.beginTurn("make one")
        let out = await t.call("create_category", ["category": ["name": "Mine", "symbol": "eye", "color": "amber", "rules": [[String: Any]]()]])
        #expect(out?.isError == false)
        let change = try #require(s.router.changes.last)
        #expect(s.router.decisions.count == 1 && s.router.decisions[0].links.changes == [change.id])
        #expect(s.router.decisions[0].outcome == .done)
        s.revertLookoutChange(change.id)
        #expect(s.router.decisions[0].outcome == .reverted)
        #expect(s.router.decisions[0].summary == "reverted")
    }

    @Test func answersFromThePageAreLogged() {
        let s = store()
        s.router.cards = [RouterCard(id: "local_a#w1", sessionID: "local_a", kind: .question, title: "Fix the login bug",
                                     folder: nil, text: "Which?", createdAt: Date())]
        s.logCardAction("Marked handled", card: "local_a#w1")
        let d = s.router.decisions[0]
        #expect(d.trigger == .you("Marked handled") && d.outcome == .done)
        #expect(d.done == [.answered(card: "Fix the login bug")] && d.links.cards == ["local_a#w1"] && d.links.sessions == ["local_a"])
    }

    // MARK: Persistence

    @Test func theLogSurvivesEncodingAndOldStateHasNone() throws {
        var state = RouterState()
        var d = RouterDecision(trigger: .action(category: "C", thing: "t", actionID: "a", runID: "r"),
                               decision: .init(target: "Docs", intent: "reply", label: "x", confidence: 0.8), outcome: .corrected(from: "A", to: "B"))
        d.add(.started(session: "s", project: "p", model: "haiku", effort: nil), session: "s")
        d.add(.asked(["a", "b"]))
        state.log(d)
        let back = try JSONDecoder().decode(RouterState.self, from: JSONEncoder().encode(state))
        #expect(back.decisions == [d])
        let old = try JSONDecoder().decode(RouterState.self, from: Data(#"{"enabled":true,"cards":[],"chat":[]}"#.utf8))
        #expect(old.decisions.isEmpty && old.enabled)
    }

    @Test func theOldestAreDroppedPastTheCap() {
        var state = RouterState()
        for i in 0..<(RouterDecision.maxKept + 5) { state.log(RouterDecision(trigger: .you("m\(i)"))) }
        #expect(state.decisions.count == RouterDecision.maxKept)
        #expect(state.decisions.first?.trigger == .you("m5"))
    }

    // MARK: Context

    @Test func recentDecisionsAreOneLineEachAndCorrectionsAreSaid() {
        let s = store()
        let now = Date()
        var a = RouterDecision(at: now.addingTimeInterval(-300), trigger: .you("tell docs to ship"), decision: .init(target: "Docs"))
        a.add(.sent(to: "Docs", text: "ship", original: nil))
        a.outcome = .done
        var b = RouterDecision(at: now.addingTimeInterval(-30), trigger: .you("fix it"), outcome: .corrected(from: "Docs", to: "Lookout dev"))
        b.add(.sent(to: "Lookout dev", text: "fix it", original: nil))
        var c = RouterDecision(at: now.addingTimeInterval(-10), trigger: .system, outcome: .reverted)
        c.add(.changed(UUID()))
        for d in [a, b, c] { s.logDecision(d) }
        let lines = s.recentDecisions(10, now: now).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "5m ago · you: “tell docs to ship” → target Docs → sent to Docs: ship")
        #expect(lines[1].hasSuffix("(you corrected this: not Docs, but Lookout dev)") && lines[1].hasPrefix("just now"))
        #expect(lines[2].contains("you reverted this"))
        #expect(s.recentDecisions(2, now: now).split(separator: "\n").count == 2)
        #expect(Store().recentDecisions().isEmpty)
    }

    // MARK: History

    @Test func theHistoryInterleavesDecisionsAndAddressedCardsByTime() {
        let now = Date()
        var card = RouterCard(id: "s#t1", sessionID: "s", kind: .done, title: "T", folder: nil, text: "x", createdAt: now.addingTimeInterval(-500))
        card.addressedAt = now.addingTimeInterval(-100)
        card.addressedBy = .you
        let open = RouterCard(id: "s#t2", sessionID: "s", kind: .question, title: "Q", folder: nil, text: "x", createdAt: now)
        let late = RouterDecision(at: now.addingTimeInterval(-10), trigger: .you("late"))
        let early = RouterDecision(at: now.addingTimeInterval(-300), trigger: .you("early"))
        let page = RouterPage.make(cards: [open, card], working: [], decisions: [late, early])
        #expect(page.history.map(\.id) == [early.id.uuidString, "s#t1", late.id.uuidString])
        #expect(page.needs.map(\.id) == ["s#t2"])
    }

    @Test func theStoresPageShowsTheLog() {
        let s = store()
        let d = s.logDecision(RouterDecision(trigger: .you("hi")))
        let ids = s.routerPage.history.map(\.id)
        #expect(ids == [d.uuidString])
    }
}
