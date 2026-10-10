import Foundation
import Testing
@testable import Lookout

/// A session going in circles: its last turns end alike, Jev is asked in the triage's call, the card is stuck and said once.
@MainActor
@Suite(.serialized) struct RouterCirclesTests {
    private func line(_ obj: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    private func user(_ text: String) -> String { line(["type": "user", "message": ["content": text]]) }
    private func said(_ text: String) -> String { line(["type": "assistant", "message": ["content": [["type": "text", "text": text]]]]) }
    private func tool() -> String { line(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "x", "name": "Bash"]]]]) }
    private func result() -> String { line(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "x"]]]]) }

    @Test func eachTurnsFinalMessageIsWhatFollowsItsLastStep() {
        let tail = [user("fix it"), said("Looking."), tool(), result(), said("Tried A; the build still fails."),
                    user("try again"), tool(), result(), said("Tried B; the build still fails."),
                    user("again"), said("Thinking"), tool(), result(), said("Tried C;"), said("still failing.")]
            .joined(separator: "\n")
        #expect(Claude.turnEnds(tail: Data(tail.utf8)) == ["Tried A; the build still fails.", "Tried B; the build still fails.",
                                                             "Tried C;\n\nstill failing."])
    }

    @Test func onlyTurnsThatLookAlikeAreWorthAsking() {
        let fail = "The linker still fails with undefined symbol _foo after rebuilding the framework target."
        let again = ["The linker fails with undefined symbol _foo after rebuilding the framework.",
                     "Rebuilt the framework target; the linker still fails: undefined symbol _foo."]
        #expect(RouterCircles.looksAlike(fail, earlier: again))
        #expect(!RouterCircles.looksAlike(fail, earlier: [again[0]]))
        #expect(!RouterCircles.looksAlike(fail, earlier: ["Wrote the docs page for the settings.", "Added a test for the parser."]))
    }

    // MARK: The store

    final class Asked { var questions: [[String]] = []; var states: [[String: String]] = [] }

    private func store(earlier: [String], circles: Double) -> (Store, Asked) {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.routerTriager.rescanned = true
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "Linker", folder: "/code/app", completedTurns: 4,
                                               lastActivity: Date(), cliID: "cli-a")]
        s.routerTriager.reader = { _ in "The linker still fails with undefined symbol _foo after rebuilding the framework target." }
        s.routerTriager.earlier = { _ in earlier }
        let asked = Asked()
        s.routerTriager.asker = { questions, state in
            asked.questions.append(questions.keys.sorted())
            asked.states.append(state)
            var a: [String: JevClient.Answer] = ["urgency": .score(2, confidence: 0.8), "unverified": .noul(0.1)]
            if questions["circles"] != nil { a["circles"] = .noul(circles) }
            return a
        }
        return (s, asked)
    }

    private let alike = ["The linker fails with undefined symbol _foo after rebuilding the framework.",
                         "Rebuilt the framework target; the linker still fails: undefined symbol _foo."]

    private func card(_ turns: Int, minutes: Double = 0) -> RouterCard {
        RouterCard(id: "a#t\(turns)", sessionID: "a", kind: .done, title: "Linker", folder: "/code/app", text: "Still failing",
                   createdAt: Date().addingTimeInterval(minutes * 60))
    }

    @Test func aSessionGoingInCirclesIsStuckAndSaidSo() async {
        let (s, asked) = store(earlier: alike, circles: 0.85)
        s.router.cards = [card(4)]
        var announced: [String] = []
        s.onNewRouterCards = { announced += $0.map(\.id) }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(asked.questions.count == 1 && asked.questions[0].contains("circles"))
        #expect(asked.states[0].keys.contains { $0.hasPrefix("final messages of the session's earlier turns") })
        let c = s.router.cards[0]
        #expect(c.triage?.circles == true && c.kind == .stuck && c.kind.rank == RouterCard.Kind.stuck.rank)
        #expect(announced == ["a#t4"])
    }

    @Test func notSureEnoughOrNotAlikeLeavesTheCardDone() async {
        let (s, _) = store(earlier: alike, circles: 0.7)
        s.router.cards = [card(4)]
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[0].triage?.circles == false && s.router.cards[0].kind == .done)

        let (t, asked) = store(earlier: ["Wrote the docs page.", "Added a parser test."], circles: 0.99)
        t.router.cards = [card(4)]
        t.triageTurns()
        await t.routerTriager.idle()
        #expect(!asked.questions[0].contains("circles") && t.router.cards[0].kind == .done)
    }

    @Test func aStreakIsAnnouncedOnce() async {
        let (s, _) = store(earlier: alike, circles: 0.9)
        var before = card(3, minutes: -5)
        before.triage = RouterTriage(state: .done)
        before.triage?.circles = true
        before.kind = .stuck
        before.addressedAt = Date().addingTimeInterval(-60)
        before.addressedBy = .superseded
        s.router.cards = [before, card(4)]
        var announced: [String] = []
        s.onNewRouterCards = { announced += $0.map(\.id) }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[1].kind == .stuck && announced.isEmpty)
    }
}
