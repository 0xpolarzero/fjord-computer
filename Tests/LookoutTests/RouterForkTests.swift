import Foundation
import Testing
@testable import Lookout

/// Forking a session: the CLI run, your messages read from a transcript, where a fork is cut, and a fork asked for in words.
@MainActor
@Suite struct RouterForkTests {
    /// A transcript as Claude Code 2.1.295 writes one: the rename's lines, two turns of yours with what comes between them.
    static func transcript() -> Data {
        let lines: [[String: Any]] = [
            ["type": "custom-title", "customTitle": "Base"],
            ["type": "user", "uuid": "u0", "parentUuid": NSNull(), "isMeta": true, "cwd": "/code/app",
             "message": ["role": "user", "content": "<local-command-caveat>Caveat: …</local-command-caveat>"]],
            ["type": "user", "uuid": "u1", "parentUuid": "u0", "cwd": "/code/app",
             "message": ["role": "user", "content": "<command-name>/rename</command-name>"]],
            ["type": "system", "uuid": "s1", "parentUuid": "u1", "subtype": "local_command"],
            ["type": "user", "uuid": "m1", "parentUuid": "s1", "cwd": "/code/app",
             "message": ["role": "user", "content": "reply with exactly the word one"]],
            ["type": "attachment", "uuid": "a1", "parentUuid": "m1"],
            ["type": "assistant", "uuid": "r1", "parentUuid": "a1", "message": ["role": "assistant", "content": [["type": "text", "text": "one"]]]],
            ["type": "user", "uuid": "t1", "parentUuid": "r1", "toolUseResult": ["stdout": "x"],
             "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "x", "content": "x"]]]],
            ["type": "user", "uuid": "side", "parentUuid": "r1", "isSidechain": true, "message": ["role": "user", "content": "a subagent's"]],
            ["type": "attachment", "uuid": "a2", "parentUuid": "t1"],
            ["type": "user", "uuid": "m2", "parentUuid": "a2", "cwd": "/code/app/.claude/worktrees/w",
             "message": ["role": "user", "content": [["type": "text", "text": "reply with\nexactly the word two"], ["type": "image"]]]],
            ["type": "assistant", "uuid": "r2", "parentUuid": "m2", "message": ["role": "assistant", "content": [["type": "text", "text": "two"]]]],
        ]
        let text = lines.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n")
        return Data((text + "\n").utf8)
    }

    @Test func theForkIsACLIRunWithNoModelCallFromTheOriginalsConversation() {
        #expect(SessionFork.arguments(cliID: "c-1", uuid: "n-1", title: "Fork of X", at: "e-1")
                == ["-p", "/rename Fork of X", "--resume", "c-1", "--fork-session", "--session-id", "n-1",
                    "--resume-session-at", "e-1", "--output-format", "json", "--setting-sources", ""])
        #expect(SessionFork.arguments(cliID: "c-1", uuid: "n-1", title: "Fork of X", at: nil)
                == ["-p", "/rename Fork of X", "--resume", "c-1", "--fork-session", "--session-id", "n-1",
                    "--output-format", "json", "--setting-sources", ""])
        #expect(SessionFork.title(of: "Fix the login bug") == "Fork of Fix the login bug")
    }

    @Test func onlyYourOwnMessagesAreRead() throws {
        let messages = SessionFork.messages(in: Self.transcript())
        #expect(messages.map(\.uuid) == ["m1", "m2"])
        #expect(messages[0] == SessionFork.Message(uuid: "m1", parent: "s1", text: "reply with exactly the word one", cwd: "/code/app"))
        #expect(messages[1].text == "reply with\nexactly the word two" && messages[1].parent == "a2")
        #expect(SessionFork.messages(in: Data("not json\n{}\n".utf8)).isEmpty)
        // Found by its Claude Code id under any project.
        let dir = TempDir()
        let project = dir.path("projects/-code-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Self.transcript().write(to: project.appendingPathComponent("c-1.jsonl"))
        #expect(SessionFork.transcript("c-1", root: dir.path("projects"))?.lastPathComponent == "c-1.jsonl")
        #expect(SessionFork.transcript("c-2", root: dir.path("projects")) == nil)
    }

    @Test func aForkIsCutBeforeTheMessageItLeavesOut() throws {
        let messages = SessionFork.messages(in: Self.transcript())
        // Whole: all of it, where it last ran.
        #expect(try SessionFork.cut(.whole, messages: messages) == (nil, "/code/app/.claude/worktrees/w", false))
        // Before your last message: up to the entry before it, in the folder it was sent in.
        #expect(try SessionFork.cut(.beforeLast, messages: messages) == ("a2", "/code/app/.claude/worktrees/w", false))
        // Before a message by its words, however its spaces fell (the history keeps what was sent).
        #expect(try SessionFork.cut(.before("reply with exactly the word one"), messages: messages) == ("s1", "/code/app", false))
        #expect(try SessionFork.cut(.before("reply with exactly  the word two"), messages: messages).at == "a2")
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.before("never sent"), messages: messages) }
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.beforeLast, messages: []) }
        // Before a conversation's first message: nothing to keep.
        let first = [SessionFork.Message(uuid: "m", parent: nil, text: "hi", cwd: "/code/app")]
        #expect(try SessionFork.cut(.beforeLast, messages: first) == (nil, "/code/app", true))
    }

    @Test func aForkIsAskedForInWords() {
        #expect(SessionFork.words("fork Fix the login bug") == .init(name: "Fix the login bug", beforeLast: false, message: ""))
        #expect(SessionFork.words("Fork it from before my last message: try SQLite instead")
                == .init(name: nil, beforeLast: true, message: "try SQLite instead"))
        #expect(SessionFork.words("branch off the docs session without my last message")
                == .init(name: "docs", beforeLast: true, message: ""))
        #expect(SessionFork.words("fork: try again") == .init(name: nil, beforeLast: false, message: "try again"))
        #expect(SessionFork.words("please fork this one") == .init(name: nil, beforeLast: false, message: ""))
        #expect(SessionFork.words("forking is fine") == nil && SessionFork.words("the fork in the road") == nil)

        let s = InboxFixture.store([])
        s.claudeSessions = [
            "local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date()),
            "local_b": ClaudeSession(id: "local_b", title: "Update the docs", folder: "/code/docs", lastActivity: Date()),
            "local_c": ClaudeSession(id: "local_c", title: "Old", folder: "/code/docs", isArchived: true, lastActivity: Date()),
        ]
        // By its title, or a project with one session; else the pinned one.
        #expect(SessionFork.request("fork fix the login bug", pinned: nil, store: s)
                == .init(session: "local_a", point: .whole, message: ""))
        #expect(SessionFork.request("branch docs from before my last message: redo it", pinned: nil, store: s)
                == .init(session: "local_b", point: .beforeLast, message: "redo it"))
        #expect(SessionFork.request("fork it", pinned: "local_b", store: s)?.session == "local_b")
        // Words naming no session are a task, not a fork; nothing pinned and none named isn't one either.
        #expect(SessionFork.request("fork the tests into their own module", pinned: "local_a", store: s) == nil)
        #expect(SessionFork.request("fork it", pinned: nil, store: s) == nil)
    }
}
