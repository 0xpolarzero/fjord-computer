import Foundation

extension Demo {
    /// On top of Jev's triage demo (`routerTriage`): a session going in circles on a flaky test, one whose turn builds on
    /// another session's work and is ready to continue now that it finished, and, with `away`, what came while you were away.
    static func routerJevAttention(_ store: Store, away: Bool, now: Date = Date()) {
        routerTriage(store, now: now)
        func session(_ id: String, _ title: String, _ folder: String, minutes: Double, turns: Int, detail: String) -> ClaudeSession {
            let at = now.addingTimeInterval(-minutes * 60)
            return ClaudeSession(id: id, title: title, folder: "/Users/me/code/\(folder)", completedTurns: turns, lastActivity: at,
                                 lastFocused: at.addingTimeInterval(-600), lastUserMessage: at.addingTimeInterval(-90),
                                 summary: ClaudeSession.Summary(blocked: false, detail: detail))
        }
        let flaky = session("local_demo-flaky", "Fix the flaky upload test", "microsandbox", minutes: 2, turns: 7,
                            detail: "Retried the upload test with a longer timeout; it still fails on CI.")
        let client = session("local_demo-client", "Typed client for the public API", "microsandbox", minutes: 4, turns: 3,
                             detail: "The client is generated; it uses the new rate-limit headers once they land.")
        for (s, icon) in [(flaky, "arrow.triangle.2.circlepath"), (client, "shippingbox.and.arrow.backward")] {
            store.claudeSessions[s.id] = s
            store.agents.entries.append(AgentEntry(id: s.id, seen: s.activity, focusedAt: s.lastFocused, icon: icon))
        }
        var circles = RouterTriage(state: .progress, urgency: 2, unverified: true, work: .uncommitted)
        circles.circles = true
        var builds = RouterTriage(state: .waiting, urgency: 1, work: .committed, waitingOn: .session,
                                  watch: .init(target: .session(id: "local_demo-api", turns: 3), label: "session “Rate limiter for the public API”"))
        builds.ready = .init(result: "it finished its turn", at: now.addingTimeInterval(-30))
        for (s, triage, minutes) in [(flaky, circles, 2.0), (client, builds, 4.0)] {
            var card = RouterCard(id: "\(s.id)#t\(s.completedTurns)", sessionID: s.id, kind: RouterTriage.kind(blocked: false, triage: triage),
                                  title: s.title, folder: s.folder, text: s.summary?.detail ?? "", createdAt: now.addingTimeInterval(-minutes * 60))
            card.triage = triage
            store.router.cards.append(card)
        }
        guard away else { return }
        let came = ["local_demo-flaky#t7", "local_demo-api#t\(store.claudeSessions["local_demo-api"]?.completedTurns ?? 0)",
                    "local_demo-client#t3", "local_demo-docs#t\(store.claudeSessions["local_demo-docs"]?.completedTurns ?? 0)"]
        store.routerAttention.strip = AwayStrip(since: now.addingTimeInterval(-50 * 60), cards: came, inbox: 3)
    }
}
