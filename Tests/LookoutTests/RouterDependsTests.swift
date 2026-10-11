import Foundation
import Testing
@testable import Lookout

/// A turn that builds on another session's work waits on it: ready to continue once that session finishes its turn.
@MainActor
@Suite(.serialized) struct RouterDependsTests {
    @Test func aMessageNamesAnotherSessionByItsTitleOrItsProject() {
        let message = "The API side is ready; once the schema migration lands I'll wire the endpoints."
        #expect(RouterDepends.names(message, title: "Schema migration", project: "db", ownProject: "app"))
        #expect(!RouterDepends.names(message, title: "Docs site redesign", project: "docs", ownProject: "app"))
        #expect(RouterDepends.names("Waiting for the billing work to land.", title: "Billing", project: "x", ownProject: "app"))
        #expect(RouterDepends.names("I need what microsandbox ships next.", title: "Bump", project: "microsandbox", ownProject: "app"))
        // Its own project names nothing.
        #expect(!RouterDepends.names("Done in app.", title: "Bump", project: "app", ownProject: "app"))
    }

    final class Asked { var keys: [[String]] = [] }

    private func store(message: String, pick: String, p: Double, state: String = "done") -> (Store, Asked) {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.routerTriager.rescanned = true
        s.claudeSessions = [
            "a": ClaudeSession(id: "a", title: "Public API", folder: "/code/app", completedTurns: 2, lastActivity: Date(), cliID: "cli-a"),
            "b": ClaudeSession(id: "b", title: "Schema migration", folder: "/code/db", completedTurns: 7, lastActivity: Date(), running: true),
        ]
        s.router.cards = [RouterCard(id: "a#t2", sessionID: "a", kind: .done, title: "Public API", folder: "/code/app",
                                     text: "API ready", createdAt: Date())]
        s.routerTriager.reader = { _ in message }
        s.routerTriager.earlier = { _ in [] }
        let asked = Asked()
        s.routerTriager.asker = { questions, _ in
            asked.keys.append(questions.keys.sorted())
            var a: [String: JevClient.Answer] = [
                "state": .choice(.init(choice: state, confidence: 0.9, probabilities: [state: 0.9, "progress": 0.1])),
                "urgency": .score(1, confidence: 0.8),
            ]
            if questions["buildsOn"] != nil {
                a["buildsOn"] = .choice(.init(choice: pick, confidence: p, probabilities: [pick: p, "none": 1 - p]))
            }
            return a
        }
        return (s, asked)
    }

    @Test func aTurnBuildingOnAnotherSessionWaitsForItAndIsReadyOnceItFinishes() async {
        let (s, asked) = store(message: "The API side is ready; once the schema migration lands I'll wire the endpoints.", pick: "s0", p: 0.9)
        var ready: [String] = []
        s.routerTriager.onReady = { ready.append($0.id) }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(asked.keys.count == 1 && asked.keys[0].contains("buildsOn"))
        let c = s.router.cards[0]
        #expect(c.kind == .waiting && c.triage?.waitingOn == .session)
        #expect(c.triage?.watch?.target == .session(id: "b", turns: 6))
        // The migration finishes its turn: the API session can continue.
        s.claudeSessions["b"]?.completedTurns = 8
        s.claudeSessions["b"]?.running = false
        s.resolveWaits()
        #expect(s.router.cards[0].triage?.ready != nil && ready == ["a#t2"])
    }

    @Test func jevsAnswerIsReadThroughTheOptionsHeWasShown() async {
        // Two sessions at work, both named; the newer one is s0 when the options are read. While the earlier turns are read,
        // the other one moves ahead: Jev's s0 is still the session he was shown under s0.
        let (s, _) = store(message: "Once the schema migration and the schema indexes land I'll wire the endpoints.", pick: "s0", p: 0.9)
        s.claudeSessions["b"]?.lastActivity = Date()
        s.claudeSessions["c"] = ClaudeSession(id: "c", title: "Schema indexes", folder: "/code/idx", completedTurns: 3,
                                              lastActivity: Date().addingTimeInterval(-60), running: true)
        s.routerTriager.earlier = { _ in
            s.claudeSessions["c"]?.lastActivity = Date().addingTimeInterval(60)
            return []
        }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[0].triage?.watch?.target == .session(id: "b", turns: 6))
    }

    @Test func aSessionWhoseTurnWasCountedBeforeItsSummaryIsWaitedOnForThatTurn() async {
        // The migration's turn ended (8 counted) but it still shows running, its summary not written yet, as the link forms.
        let (s, _) = store(message: "The API side is ready; once the schema migration lands I'll wire the endpoints.", pick: "s0", p: 0.9)
        s.claudeSessions["b"]?.completedTurns = 8
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[0].kind == .waiting && s.router.cards[0].triage?.ready == nil)
        // Its summary comes, it stops: the API session is ready, though no other turn was counted.
        s.claudeSessions["b"]?.running = false
        s.claudeSessions["b"]?.summary = .init(blocked: false, detail: "Migrated")
        s.resolveWaits()
        #expect(s.router.cards[0].triage?.ready?.result == "it finished its turn")
    }

    @Test func unsureOrAskingOrNamingNoOneLeavesTheTurnAsItWas() async {
        let (s, _) = store(message: "Once the schema migration lands I'll wire the endpoints.", pick: "s0", p: 0.7)
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[0].kind == .done && s.router.cards[0].triage?.watch == nil)

        let (t, _) = store(message: "Once the schema migration lands, should I wire the endpoints?", pick: "s0", p: 0.95, state: "asks")
        t.triageTurns()
        await t.routerTriager.idle()
        #expect(t.router.cards[0].kind == .asks && t.router.cards[0].triage?.watch == nil)

        let (u, asked) = store(message: "Wired the endpoints; all tests pass.", pick: "s0", p: 0.95)
        u.triageTurns()
        await u.routerTriager.idle()
        #expect(!asked.keys[0].contains("buildsOn") && u.router.cards[0].kind == .done)
    }
}
