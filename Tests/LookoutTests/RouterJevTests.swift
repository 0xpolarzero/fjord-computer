import Foundation
import Testing
@testable import Lookout

/// Jev's pick while you type: asked once typing pauses, shown when he is sure, fixed with a click, waved off with Esc, and its
/// card marked on the page.
@MainActor
@Suite(.serialized) struct RouterLiveTargetTests {
    private func setup() -> (Store, RouterModel, () -> Int) {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = [
            "local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date(), running: false),
            "local_b": ClaudeSession(id: "local_b", title: "Update the docs", folder: "/code/docs", lastActivity: Date(), running: false),
        ]
        s.router.cards = [RouterCard(id: "local_a#w1", sessionID: "local_a", kind: .question, title: "Fix the login bug",
                                     folder: "/code/lookout", text: "Which database?", createdAt: Date())]
        var calls = 0
        s.routerDispatcher.asker = { questions, state in
            calls += 1
            guard case .choice(let keys, let hints, _) = questions["route"] else { return [:] }
            // Sure of the card whose hint names the login bug, when the message mentions a database.
            let card = keys.first { hints[$0]?.contains("Which database?") == true } ?? keys[0]
            let sure = state["user message"]?.contains("database") == true
            var p = Dictionary(uniqueKeysWithValues: keys.map { ($0, sure ? 0.02 / Double(keys.count) : 1 / Double(keys.count)) })
            if sure { p[card] = 0.98 }
            return ["route": .choice(.init(choice: card, confidence: 0.9, probabilities: p))]
        }
        let model = RouterModel()
        model.live.delay = .zero
        return (s, model, { calls })
    }

    private func type(_ text: String, _ model: RouterModel, _ store: Store) {
        model.draft = text
        model.predictTarget(store: store)
    }

    @Test func aSurePickIsShownAndASoftOneOrAShortDraftIsNot() async {
        let (s, model, calls) = setup()
        type("use sqlite", model, s)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(calls() == 0 && model.live.prediction == nil, "too short to ask")
        type("I don't know yet, maybe later", model, s)
        await waitUntil(within: 2) { calls() == 1 }
        #expect(model.live.prediction == nil, "not sure: nothing shown")
        type("use sqlite for the database", model, s)
        await waitUntil(within: 2) { model.live.prediction != nil }
        #expect(model.live.prediction?.target == "answer:local_a#w1" && model.live.prediction?.title == "Fix the login bug")
        #expect(model.live.prediction?.mark == "local_a#w1")
        model.markPrediction(from: nil, to: model.live.prediction?.mark)
        #expect(model.highlighted == "local_a#w1")
        model.markPrediction(from: "local_a#w1", to: nil)
        #expect(model.highlighted == nil)
    }

    @Test func nothingIsAskedWhileAReplyFixesTheTarget() async {
        let (s, model, calls) = setup()
        model.replyTo = "local_a#w1"
        type("use sqlite for the database", model, s)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(calls() == 0 && model.live.prediction == nil)
    }

    @Test func clickingACardsPickMakesItTheReplyAndEscWavesItOff() async {
        let (s, model, _) = setup()
        type("use sqlite for the database", model, s)
        await waitUntil(within: 2) { model.live.prediction != nil }
        model.pinPrediction(store: s)
        #expect(model.replyTo == "local_a#w1" && model.live.prediction == nil)

        model.replyTo = nil
        type("use sqlite for the database please", model, s)
        await waitUntil(within: 2) { model.live.prediction != nil }
        model.dismissPrediction()
        #expect(model.live.prediction == nil)
        #expect(model.context(s).notTo == "answer:local_a#w1", "the send won't go there unasked")
        type("use sqlite for the database, thanks", model, s)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.live.prediction == nil, "a waved-off target stays away for this draft")
    }

    @Test func aSessionsPickIsPinnedAndSentWithTheMessage() async {
        let (s, model, _) = setup()
        model.live.preview(.init(target: "session:local_b", title: "Update the docs", detail: "session “Update the docs” in docs",
                                 text: "x", mark: nil))
        model.pinPrediction(store: s)
        #expect(model.live.pinned == "session:local_b" && model.live.pinnedTitle == "Update the docs")
        #expect(model.context(s).target == "session:local_b")
        #expect(model.removeLastChip() && model.live.pinned == nil, "Backspace at the start takes the pin off")
    }
}
