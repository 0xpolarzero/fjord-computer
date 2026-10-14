import Foundation
import Testing
@testable import Fjord

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
            ["type": "user", "uuid": "m1", "parentUuid": "s1", "cwd": "/code/app", "timestamp": "1970-01-01T00:16:40.000Z",
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
        #expect(SessionFork.title(of: "Fork of Fork of Fix it") == "Fork of Fix it")
    }

    @Test func onlyYourOwnMessagesAreRead() throws {
        let messages = SessionFork.messages(in: Self.transcript())
        #expect(messages.map(\.uuid) == ["m1", "m2"])
        #expect(messages[0] == SessionFork.Message(uuid: "m1", parent: "s1", text: "reply with exactly the word one", cwd: "/code/app",
                                                   at: Date(timeIntervalSince1970: 1_000)))
        #expect(messages[1].text == "reply with\nexactly the word two" && messages[1].parent == "a2")
        #expect(SessionFork.messages(in: Data("not json\n{}\n".utf8)).isEmpty)
        // Found by its Claude Code id under any project.
        let dir = TempDir()
        let project = dir.path("projects/-code-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Self.transcript().write(to: project.appendingPathComponent("c-1.jsonl"))
        #expect(SessionFork.transcript("c-1", root: dir.path("projects"))?.lastPathComponent == "c-1.jsonl")
        #expect(SessionFork.transcript("c-2", root: dir.path("projects")) == nil)
        // Read a piece at a time, whatever the pieces: the same messages.
        let url = project.appendingPathComponent("c-1.jsonl")
        for chunk in [7, 100, 1 << 20] { #expect(SessionFork.messages(at: url, chunk: chunk) == messages, "\(chunk)") }
        #expect(SessionFork.messages(at: project.appendingPathComponent("none.jsonl")) == nil)
    }

    @Test func aForkIsCutBeforeTheMessageItLeavesOut() throws {
        let messages = SessionFork.messages(in: Self.transcript())
        // Whole: all of it, where it last ran.
        #expect(try SessionFork.cut(.whole, messages: messages) == (nil, "/code/app/.claude/worktrees/w", false))
        // Before your last message: up to the entry before it, in the folder it was sent in.
        #expect(try SessionFork.cut(.beforeLast, messages: messages) == ("a2", "/code/app/.claude/worktrees/w", false))
        // Before a message by its words, however its spaces fell (the history keeps what was sent).
        #expect(try SessionFork.cut(.before("reply with exactly the word one", after: nil), messages: messages) == ("s1", "/code/app", false))
        #expect(try SessionFork.cut(.before("reply with exactly  the word two", after: nil), messages: messages).at == "a2")
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.before("never sent", after: nil), messages: messages) }
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.beforeLast, messages: []) }
        // Before a conversation's first message: nothing to keep.
        let first = [SessionFork.Message(uuid: "m", parent: nil, text: "hi", cwd: "/code/app")]
        #expect(try SessionFork.cut(.beforeLast, messages: first) == (nil, "/code/app", true))
    }

    @Test func theSameWordsSentTwiceAreToldApartByWhenTheyWereSent() throws {
        func at(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }
        let messages = [SessionFork.Message(uuid: "y1", parent: "p1", text: "yes", cwd: nil, at: at(100)),
                        SessionFork.Message(uuid: "x", parent: "y1", text: "go on", cwd: nil, at: at(200)),
                        SessionFork.Message(uuid: "y2", parent: "p2", text: "yes", cwd: nil, at: at(300))]
        // The first sent at or after the run that sent it (a few seconds' slack for clocks).
        #expect(try SessionFork.cut(.before("yes", after: at(90)), messages: messages).at == "p1")
        #expect(try SessionFork.cut(.before("yes", after: at(250)), messages: messages).at == "p2")
        #expect(try SessionFork.cut(.before("yes", after: at(302)), messages: messages).at == "p2")
        // Without a date, or past the last of them, which one can't be told: refused, nothing forked.
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.before("yes", after: nil), messages: messages) }
        #expect(throws: SessionFork.Failure.self) { try SessionFork.cut(.before("yes", after: at(400)), messages: messages) }
        #expect(try SessionFork.cut(.before("go on", after: nil), messages: messages).at == "y1")
    }

    @Test func aForkIsAskedForInWords() {
        #expect(SessionFork.words("fork Fix the login bug") == .init(name: "Fix the login bug", thisSession: false, beforeLast: false, message: ""))
        #expect(SessionFork.words("Fork it from before my last message: try SQLite instead")
                == .init(name: nil, thisSession: false, beforeLast: true, message: "try SQLite instead"))
        #expect(SessionFork.words("branch off the docs session without my last message")
                == .init(name: "docs", thisSession: false, beforeLast: true, message: ""))
        for this in ["fork this session", "fork the session", "please fork that session: retry"] {
            #expect(SessionFork.words(this)?.thisSession == true && SessionFork.words(this)?.name == nil, "\(this)")
        }
        for bare in ["fork", "fork it", "branch", "please fork this one", "branch: main", "fork: try again"] {
            #expect(SessionFork.words(bare).map { $0.name == nil && !$0.thisSession && !$0.beforeLast } == true, "\(bare)")
        }
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
        #expect(SessionFork.request("fork this session", pinned: "local_b", store: s)?.session == "local_b")
        #expect(SessionFork.request("fork it from before my last message", pinned: "local_b", store: s)?.point == .beforeLast)
        // A bare word or a pronoun, pinned or not, is never a fork.
        for bare in ["fork", "fork it", "branch", "branch off", "please fork that", "branch: main"] {
            #expect(SessionFork.request(bare, pinned: "local_b", store: s) == nil, "\(bare)")
        }
        // Words naming no session are a task, not a fork; nothing pinned and none named isn't one either.
        #expect(SessionFork.request("fork the tests into their own module", pinned: "local_a", store: s) == nil)
        #expect(SessionFork.request("fork it", pinned: nil, store: s) == nil)
    }

    @Test func anEditedMessageIsResentToAForkFromBeforeIt() async throws {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = ["local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date())]
        var forked: [SessionFork.Request] = [], sent: [String] = [], done: [UUID] = []
        let no = RouterTools.Failure("not here")
        s.routerDispatcher.onFinish = { done.append($0) }
        s.routerDispatcher.effects = RouterDispatcher.Effects(
            rank: { _, _, _ in throw no }, prepare: { _, _ in throw no }, start: { _, _, _, _ in throw no },
            send: { _, delivery in sent.append(delivery.body); return nil },
            answer: { _, _, _, _ in throw no }, run: { _, _, _ in throw no },
            fork: { _, request in
                forked.append(request)
                return RouterDispatcher.Delivery(to: "Fork of Fix the login bug", text: "⟦signed⟧\n" + request.message,
                                                 body: request.message, original: request.message, rephrased: false,
                                                 session: "local_fork", newSessionIn: "lookout")
            })
        // A sent message's line: what it sent, to which session.
        var line = RouterDecision(trigger: .you("use postgres"))
        line.add(.sent(to: "Fix the login bug", text: "use postgres", original: nil), session: "local_a")
        let sent0 = try #require(line.sentMessage)
        #expect(sent0.session == "local_a" && sent0.text == "use postgres" && sent0.at == line.at)
        #expect(RouterDecision(trigger: .system, done: [.sent(to: "x", text: "y", original: nil)]).sentMessage == nil)
        // A run that sent to two sessions: which message went where isn't kept, so neither is offered.
        var two = line
        two.add(.sent(to: "Update the docs", text: "and the docs", original: nil), session: "local_b")
        #expect(two.sentMessage == nil)

        // Edit and resend: the message in the composer, then sent to a fork from before it, never to the session itself.
        let model = RouterModel()
        model.reply(to: "some-card", store: s)
        model.edit(session: sent0.session, message: sent0.text, sentAt: sent0.at)
        #expect(model.draft == "use postgres" && model.replyTo == nil
                && model.editing == .init(session: "local_a", original: "use postgres", sentAt: line.at))
        model.draft = "use sqlite"
        model.send(store: s)
        #expect(model.draft.isEmpty && model.editing == nil && model.pane == .history)
        await waitUntil { done.count == 1 }
        #expect(forked == [.init(session: "local_a", point: .before("use postgres", after: line.at), message: "use sqlite")])
        #expect(sent == ["use sqlite"])
        let entry = try #require(s.router.decisions.first { $0.id == done.first })
        #expect(entry.triggerText == "Edited and resent to a fork of “Fix the login bug”: use sqlite")
        #expect(entry.doneLines == ["started a session in lookout (fork of “Fix the login bug”, before that message)",
                                    "sent to Fork of Fix the login bug: use sqlite"])
        // A card's reply armed ends the edit: the draft answers the card instead.
        model.edit(session: "local_a", message: "use postgres")
        model.reply(to: "some-card", store: s)
        #expect(model.editing == nil && model.replyTo == "some-card")
        model.replyTo = nil
        // Taking the edit off (backspace at the start) leaves the draft as a message of its own.
        model.edit(session: "local_a", message: "use postgres")
        #expect(model.removeLastChip() && model.editing == nil && model.draft == "use postgres")
    }

    /// A notification tagged in an edited message (prefilled by its "Open in Router" during the edit): the fork gets the
    /// thing's block after your words, fenced, as a session a message is delivered to does; your words stay yours alone.
    @Test func anEditedMessageTaggingANotificationTakesItsBlockToTheFork() async throws {
        let pr = InboxFixture.pr(12, repo: "octo/app", title: "Fix it")
        let s = InboxFixture.store([pr])
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = ["local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date())]
        var forked: [(message: String, tagged: String?)] = [], done: [UUID] = []
        let no = RouterTools.Failure("not here")
        s.routerDispatcher.onFinish = { done.append($0) }
        s.routerDispatcher.effects = RouterDispatcher.Effects(
            rank: { _, _, _ in throw no }, prepare: { _, _ in throw no }, start: { _, _, _, _ in throw no },
            send: { _, _ in nil }, answer: { _, _, _, _ in throw no }, run: { _, _, _ in throw no },
            fork: { tools, request in
                forked.append((request.message, tools.tagged))
                return RouterDispatcher.Delivery(to: "Fork of Fix the login bug", text: request.message, body: request.message,
                                                 original: request.message, rephrased: false, session: "local_fork",
                                                 newSessionIn: "lookout")
            })
        let model = RouterModel()
        model.edit(session: "local_a", message: "use postgres")
        model.prefill([.notification(pr.id)], text: "is fixed by this")
        #expect(model.editing != nil)
        model.send(store: s)
        await waitUntil { done.count == 1 }
        let fork = try #require(forked.first)
        #expect(fork.message == "use postgres @octo/app#12 is fixed by this")
        let tagged = try #require(fork.tagged)
        #expect(tagged.contains("@octo/app#12: a pull request in the Triage inbox."))
        #expect(tagged.contains(UntrustedFence.github.open) && !fork.message.contains(UntrustedFence.github.open))
    }

    @Test func aHeldStartCutShortByAQuitSaysItsMessageWasntSent() {
        var state = RouterState()
        state.decisions = [
            RouterDecision(trigger: .you("start a session in lookout: fix it"),
                           done: [.started(session: "local_late", project: "lookout", model: nil, effort: nil)]),
            RouterDecision(trigger: .you("what needs me?")),
        ]
        state.settleInterrupted()
        #expect(state.decisions.map(\.doneLines.last) == ["failed: its first message wasn't sent: Fjord quit while it waited for the session to run",
                                                         "failed: interrupted"])
        #expect(state.decisions.allSatisfy { $0.outcome == .done })
    }
}
