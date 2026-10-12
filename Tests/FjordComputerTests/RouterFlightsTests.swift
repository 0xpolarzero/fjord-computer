import Foundation
import SwiftUI
import Testing
@testable import FjordComputer

/// Your messages on the canvas: which wait over the composer, which leave it as they settle, and where each flies.
@MainActor
@Suite struct RouterFlightsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ id: String, _ session: String, _ folder: String?) -> RouterCard {
        RouterCard(id: id, sessionID: session, kind: .question, title: id, folder: folder, text: "", createdAt: now)
    }

    private func row(_ session: String, _ folder: String?) -> AgentRow {
        AgentRow(session: ClaudeSession(id: session, title: session, folder: folder, lastActivity: now, running: true),
                 entry: AgentEntry(id: session), label: session)
    }

    /// A frame for /code/app with a question of session "a" and session "b" working; /code/web with nothing of "n" yet.
    private var folders: [CanvasFolder] {
        var page = RouterPage()
        page.needs = [card("q", "a", "/code/app")]
        page.working = [row("a", "/code/app"), row("b", "/code/app"), row("other", "/code/web")]
        return RouterCanvasModel.make(page: page, done: [], name: { $0 }, color: { _ in nil })
    }

    private func message(_ text: String, outcome: RouterDecision.Outcome = .pending, sentTo session: String? = nil) -> RouterDecision {
        var d = RouterDecision(at: now, trigger: .you(text), decision: .init(intent: "message"), outcome: outcome)
        if let session { d.add(.sent(to: session, text: text, original: nil), session: session) }
        return d
    }

    private func departures(_ settled: Set<UUID>, _ decisions: [RouterDecision]) -> (departures: [RouterFlights.Departure], settled: Set<UUID>) {
        RouterFlights.departures(settled: settled, now: decisions, folders: folders) { ["n": "/code/web"][$0] }
    }

    @Test func onlyYourMessagesUnderWayWaitAndAQuestionAskedBackStandsForItsOwn() {
        let typed = message("fix the tests")
        let asked = message("ship it")
        var action = message("from a category")
        action.fromAction = SessionOrigin(category: "CI", thing: "build", actionID: "a", runID: "r")
        let cardAction = RouterDecision(at: now, trigger: .you("Answered the form"), decision: .init(intent: "answer"))
        let done = message("earlier", outcome: .done)
        let pending = RouterFlights.pending([typed, asked, action, cardAction, done], asking: [asked.id])
        #expect(pending.map(\.id) == [typed.id])
    }

    @Test func aMessageSentToASessionFliesToItsCardBeforeItsRow() {
        var sent = message("use sqlite", sentTo: "a")
        let settled = RouterFlights.settled([sent])
        #expect(settled.isEmpty)
        sent.outcome = .done
        let out = departures(settled, [sent])
        #expect(out.departures == [.init(id: sent.id, text: "use sqlite", target: .node("q"))])
        #expect(out.settled == [sent.id])
        // Once flown, never again.
        #expect(departures(out.settled, [sent]).departures.isEmpty)
        // A session only working: its row.
        let toB = message("go on", outcome: .done, sentTo: "b")
        #expect(departures([], [toB]).departures.first?.target == .node(RouterModel.workingID("b")))
    }

    @Test func aNewSessionFliesToItsProjectsFrameUntilItsNodeIsThere() {
        var started = message("start one in web", outcome: .done)
        started.add(.started(session: "n", project: "web", model: nil, effort: nil), session: "n")
        #expect(departures([], [started]).departures.first?.target == .folder("/code/web"))
        // A project with no frame: nowhere to go.
        var elsewhere = message("start one", outcome: .done)
        elsewhere.add(.started(session: "x", project: "x", model: nil, effort: nil), session: "x")
        #expect(departures([], [elsewhere]).departures.first?.target == nil)
    }

    @Test func aReplyToTheRouterOnlyOrAFailureFadesAndOneTakenBackOrNotYoursNeverLeaves() {
        var answered = message("what's running?", outcome: .done)
        answered.reply = "Three sessions."
        var failed = message("tell a", outcome: .done)
        failed.add(.failed("no such session"), session: "a")
        let out = departures([], [answered, failed])
        #expect(out.departures.map(\.target) == [nil, nil])

        var cancelled = message("stop that", outcome: .done, sentTo: "a")
        cancelled.delivered = .init(session: "a", cli: "a", nonce: "n", at: now, turns: 0, busy: false, abortable: true, cancelled: .aborted)
        let session = RouterDecision(at: now, trigger: .session(sessionID: "a", event: "asked"), outcome: .done)
        let next = departures([], [cancelled, session])
        #expect(next.departures.isEmpty)
        #expect(next.settled == [cancelled.id])
    }

    @Test func theArcLeavesAndLandsOnItsPointsAndRisesBetween() {
        let from = CGPoint(x: 400, y: 800), to = CGPoint(x: 200, y: 300)
        #expect(ArcFlight.point(0, from: from, to: to) == from)
        #expect(ArcFlight.point(1, from: from, to: to) == to)
        #expect(ArcFlight.point(0.5, from: from, to: to).y < (from.y + to.y) / 2)
    }
}
