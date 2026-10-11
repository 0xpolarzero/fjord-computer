import Foundation
import Testing
@testable import Lookout

/// A message you write in a session in Claude settles its open turn cards only as Jev judges it does.
@MainActor
@Suite struct RouterRepliesTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(turns: Int, message: TimeInterval = -120) -> ClaudeSession {
        ClaudeSession(id: "local_a", title: "Session A", folder: "/code/app", completedTurns: turns,
                      lastActivity: now.addingTimeInterval(-60), lastFocused: now.addingTimeInterval(-3600),
                      lastUserMessage: now.addingTimeInterval(message), summary: .init(blocked: false, detail: "Done it"),
                      cliID: "cli-local_a")
    }

    /// The Router on, with a finished turn's card open; Jev answers the card's judgement with `verdict` (nil: no Jev).
    private func store(_ dir: TempDir, verdict: String?) async -> Store {
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Lookout.app/Contents/MacOS/Lookout"
        s.interceptOpen = { _ in }
        s.claudeIsFrontmost = { false }
        s.claudeLink = .ok
        s.agents.enabled = true
        s.agents.enabledAt = now.addingTimeInterval(-3600)
        s.routerTriager.rescanned = true
        s.routerTriager.reader = { _ in nil }
        s.routerTriager.replyReader = { _, _ in "ship it" }
        if let verdict {
            s.routerTriager.asker = { questions, _ in
                guard questions["card"] != nil else { return [:] }
                return ["card": .choice(JevClient.Choice(choice: verdict, confidence: 1, probabilities: [verdict: 1]))]
            }
        }
        s.ingest([session(turns: 1)], appUnread: [], claudeFrontmost: false, now: now)
        s.setRouterEnabled(true, now: now)
        await s.routerHookWork?.value
        s.ingest([session(turns: 2)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(1))
        return s
    }

    private func reply(_ s: Store) async {
        s.ingest([session(turns: 2, message: 30)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now.addingTimeInterval(31))
        await s.routerTriager.replyJudging["local_a"]?.value
    }

    @Test func aReplyJevJudgesSettledAddressesTheCard() async {
        let dir = TempDir()
        let s = await store(dir, verdict: "resolved")
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"])
        await reply(s)
        #expect(s.router.cards[0].addressedBy == .reply && s.router.cards[0].addressedNote == "ship it")
        #expect(s.router.replies.isEmpty)
    }

    @Test func aReplyJevDoesntJudgeSettledLeavesTheCardOpen() async {
        let dir = TempDir()
        let s = await store(dir, verdict: "not")
        await reply(s)
        #expect(s.openRouterCards.map(\.id) == ["local_a#t2"] && s.router.replies.isEmpty)
    }

    @Test func withoutJevAReplyAddressesTheCard() async {
        let dir = TempDir()
        let s = await store(dir, verdict: nil)
        await reply(s)
        #expect(s.router.cards[0].addressedBy == .reply && s.router.replies.isEmpty)
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
