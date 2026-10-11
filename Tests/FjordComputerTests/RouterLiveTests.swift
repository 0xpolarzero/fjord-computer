import Foundation
import Testing
@testable import FjordComputer

/// The live line and the turn summary, composed from what the transcript holds: no model.
@MainActor
@Suite struct RouterLiveCompose {
    private func jsonl(_ lines: [[String: Any]]) -> Data {
        Data(lines.map { String(decoding: (try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])) ?? Data(), as: UTF8.self) }
            .joined(separator: "\n").utf8)
    }

    private func assistant(_ parts: [[String: Any]]) -> [String: Any] {
        ["type": "assistant", "timestamp": "2026-10-10T10:00:00.000Z", "message": ["content": parts]]
    }

    private let userMessage: [String: Any] = ["type": "user", "message": ["content": "Fix the flaky test"]]
    private func toolResult() -> [String: Any] { ["type": "user", "message": ["content": [["type": "tool_result", "content": "ok"]]]] }
    private func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
    private func tool(_ name: String, _ input: [String: Any]) -> [String: Any] { ["type": "tool_use", "name": name, "id": "t", "input": input] }
    private func todos(_ done: Int, _ total: Int, active: String) -> [String: Any] {
        let items: [[String: Any]] = (0..<total).map { i in
            ["content": "Item \(i)", "activeForm": i == done ? active : "Doing \(i)", "status": i < done ? "completed" : i == done ? "in_progress" : "pending"]
        }
        return tool("TodoWrite", ["todos": items])
    }

    @Test func theReaderFindsTheTaskListAndTheNarration() {
        let tail = jsonl([
            userMessage,
            assistant([todos(3, 7, active: "Running the test suite")]), toolResult(),
            assistant([text("Let me run the suite now. It takes a while."), tool("Bash", ["description": "Run the tests", "command": "swift test"])]),
            toolResult(),
        ])
        let a = Claude.activity(tail: tail)
        #expect(a?.todo == ClaudeActivity.Todo(done: 3, total: 7, active: "Running the test suite"))
        #expect(a?.narration == "Let me run the suite now. It takes a while.")
        #expect(RouterLive.line(activity: a) == "3/7 · Running the test suite")
    }

    @Test func narrationOfAnEarlierTurnIsNotThisTurns() {
        let tail = jsonl([
            assistant([text("All done with the last thing.")]), userMessage,
            assistant([tool("Read", ["file_path": "/a/b.swift"])]),
        ])
        let a = Claude.activity(tail: tail)
        #expect(a?.narration == nil && a?.text == "Reading b.swift")
        #expect(RouterLive.line(activity: a) == "Reading b.swift")
    }

    @Test func withoutATaskListTheNarrationThenTheStepLabelsTheLine() {
        let narrated = ClaudeActivity(text: "Reading a.swift", since: Date(), narration: "I'll check the parser first. Then the lexer.")
        #expect(RouterLive.line(activity: narrated) == "I'll check the parser first.")
        let bare = ClaudeActivity(text: "Review the sandbox changes", since: Date())
        #expect(RouterLive.line(activity: bare) == "Review the sandbox changes")
        let thinking = ClaudeActivity(text: "Thinking", since: Date(), todo: .init(done: 1, total: 4, active: nil))
        #expect(RouterLive.line(activity: thinking) == "1/4")
        #expect(RouterLive.line(activity: ClaudeActivity(text: "Thinking", since: Date())) == nil)
    }

    @Test func theTooltipHasTheGoalTheStepAndTheSubagents() {
        let tasks = [ClaudeTask(id: "a", kind: .agent, title: "Review the sandbox changes", since: Date(),
                                activity: ClaudeActivity(text: "Reading sandbox.rs", since: Date()))]
        let tip = RouterLive.tooltip(title: "Fix CI", activity: ClaudeActivity(text: "Running swift test", since: Date()), tasks: tasks)
        #expect(tip.contains("Goal: Fix CI") && tip.contains("Now: Running swift test"))
        #expect(tip.contains("1 subagent:") && tip.contains("• Review the sandbox changes (Reading sandbox.rs)"))
    }

    @Test func theAppsSummaryComesFirstElseTheFinalMessage() {
        func session(running: Bool, summary: String?) -> ClaudeSession {
            ClaudeSession(id: "s", title: "T", folder: "/c/a", completedTurns: 2, lastActivity: Date(),
                          summary: summary.map { .init(blocked: false, detail: $0) }, running: running)
        }
        let final = ClaudeActivity(text: "Writing", since: Date(), narration: "Fixed the test and pushed. CI is green. Anything else?")
        #expect(RouterLive.turnSummary(session: session(running: false, summary: "App says."), activity: final) == "App says.")
        #expect(RouterLive.turnSummary(session: session(running: false, summary: nil), activity: final) == "Fixed the test and pushed. CI is green.")
        #expect(RouterLive.turnSummary(session: session(running: true, summary: nil), activity: final) == nil)
    }

    @Test func theDoneCardTakesTheFinalMessageWhenTheAppWroteNoSummary() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let dir = TempDir()
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Fjord Computer.app/Contents/MacOS/FjordComputer"
        s.interceptOpen = { _ in }
        s.claudeIsFrontmost = { false }
        s.claudeLink = .ok
        s.agents.enabled = true
        s.agents.enabledAt = now.addingTimeInterval(-3600)
        func session(_ turns: Int, running: Bool) -> ClaudeSession {
            ClaudeSession(id: "local_a", title: "A", folder: "/code/app", completedTurns: turns, lastActivity: now,
                          lastFocused: now.addingTimeInterval(-3600), lastUserMessage: now.addingTimeInterval(-60), running: running, cliID: "cli-a")
        }
        s.ingest([session(1, running: true)], appUnread: [], claudeFrontmost: false, now: now)
        s.setRouterEnabled(true, now: now)
        await s.routerHookWork?.value
        s.ingest([session(1, running: true)], appUnread: [], claudeFrontmost: false, now: now)
        s.feedRouter(now: now)
        s.ingest([session(2, running: false)], appUnread: [], claudeFrontmost: false, now: now.addingTimeInterval(1))
        s.claudeActivity = ["local_a": ClaudeActivity(text: "Writing", since: now, narration: "Added the badge. Tests pass.")]
        s.feedRouter(now: now.addingTimeInterval(2))
        #expect(s.router.cards.first?.text == "Added the badge. Tests pass.")
        #expect(s.turnSummary("local_a") == "Added the badge. Tests pass.")
    }
}
