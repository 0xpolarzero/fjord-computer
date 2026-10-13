import Foundation
import Testing
@testable import FjordComputer

/// The send-flight (`RouterFlights`): a message sent from the composer is a pill over it while the Router works, flies to
/// the place it went once it went (a session that wasn't working coming into Working for it), unfolds into the ask in place
/// when the Router isn't sure, and stays with why when it fails.
@MainActor
@Suite(.serialized) struct RouterFlightTests {
    @MainActor final class Fakes {
        var ranked: [RouterDispatcher.Scored] = []
        var failSend: String?
        /// Prepares held until the test lets them go.
        var held: CheckedContinuation<Void, Never>?
        var hold = false
        var finished: [UUID] = []

        func install(_ d: RouterDispatcher) {
            d.onFinish = { [self] in finished.append($0) }
            d.effects = RouterDispatcher.Effects(
                rank: { [self] _, _, _ in RouterDispatcher.Ranking(scored: ranked) },
                prepare: { [self] _, session in
                    if hold { await withCheckedContinuation { held = $0 } }
                    return RouterDispatcher.Delivery(to: "peer-\(session)", text: "body", body: "body", original: "body",
                                                     rephrased: false, session: session, newSessionIn: nil)
                },
                start: { _, _, _, _ in throw RouterTools.Failure("no starts here") },
                send: { [self] _, _ in
                    if let failSend { throw RouterTools.Failure(failSend) }
                    return nil
                },
                answer: { _, _, _ in "" },
                run: { _, _, _ in RouterRun.Answer(reply: "", done: "") })
        }
    }

    private func setup() -> (Store, RouterFlights, Fakes) {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = [
            "local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date(), running: true),
            "local_b": ClaudeSession(id: "local_b", title: "Update the docs", folder: "/code/docs",
                                     lastActivity: Date().addingTimeInterval(-60), running: false),
        ]
        s.agents.entries = [AgentEntry(id: "local_a"), AgentEntry(id: "local_b")]
        let fakes = Fakes()
        fakes.install(s.routerDispatcher)
        let flights = RouterFlights()
        // Now's view, and the docs session's row and the Working chip in it.
        flights.frames = ["now": CGRect(x: 0, y: 0, width: 800, height: 600), "nowTop": CGRect(x: 0, y: 0, width: 800, height: 40),
                          "composer": CGRect(x: 40, y: 560, width: 700, height: 44),
                          "session:local_b": CGRect(x: 20, y: 200, width: 700, height: 40),
                          "chip:working": CGRect(x: 100, y: 10, width: 80, height: 20)]
        return (s, flights, fakes)
    }

    private func send(_ text: String, _ s: Store) -> UUID? {
        var context = RouterContext()
        context.flies = true
        return s.routerDispatcher.submit(text, context: context)
    }

    @Test func aComposerMessageIsAPillUntilItWentThenFliesIntoItsSessionsRow() async {
        let (s, flights, f) = setup()
        f.ranked = [.init(target: "session:local_b", p: 0.9), .init(target: "unclear", p: 0.1)]
        f.hold = true
        let id = send("add a changelog entry to the docs", s)
        flights.sync(store: s)
        #expect(flights.pills.map(\.id) == [id].compactMap { $0 })
        await waitUntil { f.held != nil }
        flights.sync(store: s)
        #expect(flights.status(id!, store: s) == "→ Update the docs", "once Jev chose, the pill names where it goes")
        #expect(flights.flights.isEmpty, "nothing flies before it went")
        f.held?.resume()
        await waitUntil { f.finished.contains(id!) }
        flights.sync(store: s)
        await waitUntil { !flights.flights.isEmpty }
        #expect(flights.pills.isEmpty, "the flying copy takes the pill's place")
        #expect(flights.flights.first?.target == "session:local_b")
        #expect(s.claudeSessions["local_b"]?.running == true, "the finished session comes into Working to land on")
        flights.land(id!, store: s)
        #expect(flights.landed["session:local_b"] != nil && flights.flights.isEmpty)
        #expect(s.routerDispatcher.flying.isEmpty)
    }

    @Test func aRowOutOfSightIsLandedOnByItsSectionsChip() async {
        let (s, flights, f) = setup()
        // The row is under the composer: not enough of it shows.
        flights.frames["session:local_b"] = CGRect(x: 20, y: 580, width: 700, height: 40)
        f.ranked = [.init(target: "session:local_b", p: 0.9), .init(target: "unclear", p: 0.1)]
        let id = send("add a changelog entry to the docs", s)
        await waitUntil { f.finished.contains(id!) }
        flights.sync(store: s)
        await waitUntil { !flights.flights.isEmpty }
        #expect(flights.flights.first?.target == "chip:working")
    }

    @Test func anAskUnfoldsInPlaceAndIsNotInNeedsYou() async {
        let (s, flights, f) = setup()
        f.ranked = [.init(target: "session:local_b", p: 0.4), .init(target: "session:local_a", p: 0.35), .init(target: "unclear", p: 0.25)]
        let id = send("ship it tomorrow", s)
        await waitUntil { f.finished.contains(id!) }
        flights.sync(store: s)
        #expect(s.routerDispatcher.askBacks.map(\.id) == [id].compactMap { $0 })
        #expect(flights.pills.first?.phase == .pending, "the pill waits as the ask, over the composer")
        #expect(s.routerPage.asks.isEmpty, "Needs you shows only the asks of messages not sent from the composer")
        // A message sent elsewhere (a notification's "Send to the Router") still asks in Needs you.
        let other = s.routerDispatcher.submit("ship it tomorrow too")
        await waitUntil { f.finished.contains(other!) }
        #expect(s.routerPage.asks.map(\.id) == [other].compactMap { $0 })
    }

    @Test func aFailedSendStaysWithWhyAndRetrySendsItAgain() async {
        let (s, flights, f) = setup()
        f.ranked = [.init(target: "session:local_b", p: 0.9), .init(target: "unclear", p: 0.1)]
        f.failSend = "the session's inbox is closed"
        let id = send("add a changelog entry to the docs", s)
        await waitUntil { f.finished.contains(id!) }
        flights.sync(store: s)
        #expect(flights.pills.first?.phase == .failed("the session's inbox is closed", retry: true))
        #expect(!flights.tracking, "a failed pill goes nowhere: nothing is measured while it waits for its Retry")
        f.failSend = nil
        flights.retry(id!, store: s)
        flights.sync(store: s)
        #expect(flights.pills.count == 1 && flights.pills.first?.id != id, "sent again as a new message")
        #expect(flights.tracking, "the new message is on its way")
        #expect(!s.routerDispatcher.flying.contains(id!))
        await waitUntil { f.finished.count == 2 }
    }

    @Test func whereARunLands() {
        func entry(target: String?, done: [RouterDecision.Done], sessions: [String] = [], cards: [String] = []) -> RouterDecision {
            var e = RouterDecision(trigger: .you("x"), decision: .init(intent: "message"))
            e.decision.targetID = target
            e.done = done
            e.links.sessions = sessions
            e.links.cards = cards
            return e
        }
        #expect(RouterFlights.landing(entry(target: "answer:c1", done: [.answered(card: "Which DB?")], cards: ["c1"])) == "card:c1")
        #expect(RouterFlights.landing(entry(target: "new:/code/lcu", done: [.started(session: "local_n", project: "lcu", model: nil, effort: nil)]))
                == "session:local_n")
        #expect(RouterFlights.landing(entry(target: "session:local_b", done: [.sent(to: "p", text: "t", original: nil)], sessions: ["local_b"]))
                == "session:local_b")
        #expect(RouterFlights.landing(entry(target: "question", done: [])) == "history")
        #expect(!RouterFlights.went(entry(target: nil, done: [.asked(["a"])])))
        #expect(RouterFlights.failure(entry(target: nil, done: [.failed("no")])) == "no")
    }
}
