import Foundation
import Testing
@testable import Fjord

/// A message you write in a session in Claude clears its open turn cards at once; Jev reads it for the questions it left.
@MainActor
@Suite struct RouterRepliesTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(turns: Int, message: TimeInterval = -120) -> ClaudeSession {
        ClaudeSession(id: "local_a", title: "Session A", folder: "/code/app", completedTurns: turns,
                      lastActivity: now.addingTimeInterval(-60), lastFocused: now.addingTimeInterval(-3600),
                      lastUserMessage: now.addingTimeInterval(message), summary: .init(blocked: false, detail: "Done it"),
                      cliID: "cli-local_a")
    }

    /// The Router on, with a finished turn's card open that asks two questions; Jev finds the message responds to each
    /// with the probability `responds` gives for it (nil: no Jev).
    private func store(_ dir: TempDir, responds: ((String) -> Double)?) async -> Store {
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Fjord Computer.app/Contents/MacOS/Fjord"
        s.interceptOpen = { _ in }
        s.claudeIsFrontmost = { false }
        s.claudeLink = .ok
        s.agents.enabled = true
        s.agents.enabledAt = now.addingTimeInterval(-3600)
        s.routerTriager.rescanned = true
        s.routerTriager.reader = { _ in nil }
        s.routerTriager.replyReader = { _, _ in "ship it" }
        s.routerTriager.replyRereads = [.milliseconds(1), .milliseconds(1)]
        if let responds {
            s.routerTriager.asker = { questions, state in
                let asked = state.values.first { $0.contains("q1:") } ?? ""
                guard !asked.isEmpty else { return [:] }
                return questions.keys.reduce(into: [:]) { out, key in
                    let line = asked.split(separator: "\n").first { $0.contains("\(key): ") }.map(String.init) ?? ""
                    out[key] = .noul(responds(line))
                }
            }
        }
        s.ingest([session(turns: 1)], appUnread: [], claudeFrontmost: false, now: now)
        s.setRouterEnabled(true, now: now)
        await s.routerHookWork?.value
        s.ingest([session(turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        if let i = s.router.cards.firstIndex(where: { $0.id == "local_a#t2" }) {
            s.router.cards[i].asks = [RouterAsk(question: "Ship it?"), RouterAsk(question: "Tag it?")]
        }
        return s
    }

    private func reply(_ s: Store) async {
        s.ingest([session(turns: 2, message: 30)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(31))
        await s.routerTriager.replyJudging["local_a"]?.value
    }

    @Test func aReplyClearsTheCardAtOnceAndKeepsTheQuestionsItLeft() async {
        let dir = TempDir()
        let s = await store(dir) { $0.contains("Tag it?") ? 0.02 : 0.97 }
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
        s.ingest([session(turns: 2, message: 30)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(31))
        // Cleared as the feed sees it, before anything is read.
        #expect(s.openRouterCards.isEmpty && s.router.cards[0].addressedBy == .reply)
        await s.routerTriager.replyJudging["local_a"]?.value
        #expect(s.router.cards[0].addressedNote == "ship it" && s.router.cards[0].skipped == ["Tag it?"])
        #expect(s.router.replies.isEmpty)
    }

    @Test func withoutJevAReplyClearsTheCardAndKeepsNothing() async {
        let dir = TempDir()
        let s = await store(dir, responds: nil)
        await reply(s)
        #expect(s.router.cards[0].addressedBy == .reply && s.router.cards[0].skipped == nil && s.router.replies.isEmpty)
    }

    @Test func aTranscriptWithoutTheMessageYetIsReadAgain() async {
        let dir = TempDir()
        let s = await store(dir) { $0.contains("Tag it?") ? 0.02 : 0.97 }
        var reads = 0
        s.routerTriager.replyReader = { _, _ in reads += 1; return reads < 3 ? nil : "ship it" }
        await reply(s)
        #expect(reads == 3 && s.router.cards[0].skipped == ["Tag it?"])
        // Never there: given up after the last read, the card cleared all the same.
        let t = await store(TempDir()) { $0.contains("Tag it?") ? 0.02 : 0.97 }
        reads = 0
        t.routerTriager.replyReader = { _, _ in reads += 1; return nil }
        await reply(t)
        #expect(reads == 3 && t.router.cards[0].addressedBy == .reply && t.router.cards[0].skipped == nil && t.router.replies.isEmpty)
    }

    @Test func theReplyIsWhatYouWroteSinceTheSessionLastSpoke() {
        func line(_ type: String, _ content: Any, at seconds: Int, meta: Bool = false) -> String {
            let obj: [String: Any] = ["type": type, "timestamp": "2033-05-18T03:3\(seconds / 10):\(seconds % 10)0.000Z",
                                      "isMeta": meta, "message": ["role": type, "content": content]]
            return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
        }
        let tail = [
            line("user", "Fix the build", at: 1),
            line("assistant", [["type": "text", "text": "Fixed. Push it?"]], at: 2),
            line("user", "yes", at: 3),
            line("user", [["type": "text", "text": "and tag it"]], at: 4),
            line("user", "<command-name>/clear</command-name>", at: 5),
            line("user", [["type": "tool_result", "content": "ok"]], at: 6),
            line("assistant", [["type": "tool_use", "name": "Bash", "input": [:]]], at: 7),
        ].joined(separator: "\n")
        #expect(Claude.userMessages(tail: Data(tail.utf8), after: 0) == "yes\n\nand tag it")
        // Nothing newer than the time asked for: none.
        #expect(Claude.userMessages(tail: Data(tail.utf8), after: RouterFeed.Stamp.ms(Date(timeIntervalSince1970: 2_000_000_000))) == nil)
    }
}
