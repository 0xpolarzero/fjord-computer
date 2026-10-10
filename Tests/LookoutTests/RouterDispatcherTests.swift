import Foundation
import Testing
@testable import Lookout

/// Workflow B (what you type): the dispatcher's paths with the model, Jev and the sender stood in for, the ask-back card, the
/// context and arguments of the Haiku runs, and runs that go on independently.
@MainActor
@Suite(.serialized) struct RouterDispatcherTests {
    /// What the stand-ins saw and answer.
    @MainActor final class Fakes {
        var ranked: [RouterDispatcher.Scored] = []
        var rankError: Error?
        var ranks = 0
        var prepared: [String] = []
        var sent: [RouterDispatcher.Delivery] = []
        var started: [(folder: String, title: String)] = []
        var answered: [(card: String, answers: [String: String])] = []
        var runs: [(intent: RouterRun.Intent, input: String)] = []
        var answer = RouterRun.Answer(reply: "Done.", done: "set it")
        var whileRunning: ((RouterTools) async -> Void)?
        var failSend: String?
        /// Held until the test lets it go (to have two runs in flight).
        var hold: [String: CheckedContinuation<Void, Never>] = [:]
        var holdOn: Set<String> = []
        var finished: [UUID] = []
        /// The dispatcher holds its store weakly: the test's stand-ins keep it.
        var store: Store?

        func install(_ d: RouterDispatcher) {
            d.onFinish = { [unowned self] in finished.append($0) }
            d.effects = RouterDispatcher.Effects(
                rank: { [unowned self] _, _, _, _ in
                    ranks += 1
                    if let rankError { throw rankError }
                    return ranked
                },
                prepare: { [unowned self] _, session in
                    prepared.append(session)
                    if holdOn.contains(session) { await withCheckedContinuation { hold[session] = $0 } }
                    return RouterDispatcher.Delivery(to: "peer-\(session)", text: "⟦signed⟧\nbody-\(session)", body: "body-\(session)",
                                                     original: "orig", rephrased: true, session: session, newSessionIn: nil)
                },
                start: { [unowned self] _, folder, title in
                    started.append((folder, title))
                    return RouterDispatcher.Delivery(to: "peer-new", text: "⟦signed⟧\nhello", body: "hello", original: "hello",
                                                     rephrased: false, session: "local_new", newSessionIn: "x")
                },
                send: { [unowned self] _, delivery in
                    if let failSend { throw RouterTools.Failure(failSend) }
                    sent.append(delivery)
                },
                answer: { [unowned self] _, card, answers in
                    answered.append((card, answers))
                    return "answered"
                },
                run: { [unowned self] tools, intent, input in
                    runs.append((intent, input))
                    await whileRunning?(tools)
                    return answer
                })
        }

        func release(_ session: String) {
            hold.removeValue(forKey: session)?.resume()
        }
    }

    private func setup() -> (Store, RouterDispatcher, Fakes) {
        let s = InboxFixture.store([])
        s.categories = InboxStore.defaultCategories
        s.router.enabled = true
        s.agents.enabled = true
        s.claudeSessions = [
            "local_a": ClaudeSession(id: "local_a", title: "Fix the login bug", folder: "/code/lookout", lastActivity: Date(), running: true),
            "local_b": ClaudeSession(id: "local_b", title: "Update the docs", folder: "/code/docs", lastActivity: Date().addingTimeInterval(-60), running: false),
        ]
        s.router.cards = [RouterCard(id: "local_a#w1", sessionID: "local_a", kind: .question, title: "Fix the login bug",
                                     folder: "/code/lookout", text: "Which database?", createdAt: Date())]
        let d = RouterDispatcher(store: s)
        let fakes = Fakes()
        fakes.install(d)
        fakes.store = s
        return (s, d, fakes)
    }

    private func finish(_ d: RouterDispatcher, _ f: Fakes, _ id: UUID?) async {
        await waitUntil { id.map { f.finished.contains($0) } ?? true }
    }

    private func decision(_ s: Store, _ id: UUID?) -> RouterDecision? { s.router.decisions.first { $0.id == id } }

    // MARK: Deterministic

    @Test func anArmedReplyIsPreparedSentAndNeverClassified() async {
        let (s, d, f) = setup()
        let id = d.submit("use sqlite", context: RouterContext(replyTo: "local_a#w1"))
        #expect(d.progress[id!] != nil, "the line shows the run is under way")
        await finish(d, f, id)
        #expect(f.ranks == 0 && f.prepared == ["local_a"])
        #expect(f.sent.map(\.to) == ["peer-local_a"])
        let entry = decision(s, id)
        #expect(entry?.done == [.sent(to: "peer-local_a", text: "body-local_a", original: "orig")])
        #expect(entry?.outcome == .done && entry?.links.sessions == ["local_a"] && entry?.links.cards == ["local_a#w1"])
        #expect(d.progress.isEmpty)
        // Your message is in the chat as yours, and the session's card is addressed by the Router's message.
        #expect(s.router.chat.last?.role == .you && s.router.chat.last?.replyTo == "local_a#w1")
        #expect(s.router.cards[0].addressedBy == .router)
    }

    @Test func aReplyOnAQuestionCardThatGivesTheAnswerAnswersTheForm() {
        let form = PendingForm(id: "f", cliSessionID: "a", transcriptPath: "", questions: [
            .init(question: "Which database?", header: "DB", multiSelect: false,
                  options: [.init(label: "SQLite", description: ""), .init(label: "Postgres", description: "")]),
        ], createdAt: Date(), pid: 1)
        #expect(RouterDispatcher.formAnswers(form, message: "sqlite.") == ["Which database?": "SQLite"])
        #expect(RouterDispatcher.formAnswers(form, message: "use sqlite, and add an index") == nil, "more than the option: text for the session")
        #expect(RouterDispatcher.formAnswers(form, message: "maybe") == nil)
        var multi = form
        multi.questions[0].multiSelect = true
        #expect(RouterDispatcher.formAnswers(multi, message: "SQLite and Postgres")?["Which database?"] == FormBridge.joined(["SQLite", "Postgres"]))
        var plan = form
        plan.plan = "The plan"
        #expect(RouterDispatcher.formAnswers(plan, message: "SQLite") == nil)
        var two = form
        two.questions.append(two.questions[0])
        #expect(RouterDispatcher.formAnswers(two, message: "SQLite") == nil)
    }

    @Test func aTaggedProjectStartsASessionWhenAskedOrWhenItHasNothingElse() async {
        let (s, d, f) = setup()
        // Asks for one: even though the project has a session.
        let a = d.submit("start a new session to add a badge", context: RouterContext(projects: ["/code/lookout"]))
        await finish(d, f, a)
        #expect(f.started.map(\.folder) == ["/code/lookout"] && f.ranks == 0)
        #expect(f.sent.map(\.to) == ["peer-new"])
        #expect(decision(s, a)?.done == [.started(session: "local_new", project: "lookout", model: nil, effort: nil)])
        // Nothing else to be for: a project with no session or card.
        let b = d.submit("add a changelog", context: RouterContext(projects: ["/code/empty"]))
        await finish(d, f, b)
        #expect(f.started.map(\.folder) == ["/code/lookout", "/code/empty"] && f.ranks == 0)
        #expect(f.started.last?.title == "add a changelog")
        // A project with a session, and no ask for a new one: Jev decides, among that project's targets.
        f.ranked = [.init(target: "session:local_a", p: 0.95), .init(target: "unclear", p: 0.05)]
        let c = d.submit("what is the status", context: RouterContext(projects: ["/code/lookout"]))
        await finish(d, f, c)
        #expect(f.ranks == 1 && f.prepared == ["local_a"])
    }

    @Test func theRulesForAskingForANewSession() {
        for yes in ["start a new session for the api", "new chat about tests", "open a session to look at the build", "Spin up a session"] {
            #expect(RouterDispatcher.wantsNewSession(yes), "\(yes)")
        }
        for no in ["the session is stuck", "fix the news feed", "tell it to open the file"] {
            #expect(!RouterDispatcher.wantsNewSession(no), "\(no)")
        }
        #expect(RouterDispatcher.title(for: "@lookout add a dark mode badge to the settings page please") == "add a dark mode badge to")
    }

    // MARK: Jev

    @Test func aConfidentPickIsActedOnAndLabelled() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "session:local_b", p: 0.9), .init(target: "session:local_a", p: 0.06), .init(target: "unclear", p: 0.04)]
        let id = d.submit("tell docs to ship")
        await finish(d, f, id)
        #expect(f.prepared == ["local_b"] && f.sent.count == 1)
        let entry = decision(s, id)
        #expect(entry?.decision.label == "reply" && entry?.decision.confidence == 0.9)
        #expect(entry?.decision.target == "session “Update the docs” in docs")
        #expect(d.askBacks.isEmpty && entry?.outcome == .done)
    }

    @Test func aPickWithoutAClearLeadAsksBackAndSendsNothing() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "session:local_a", p: 0.5), .init(target: "session:local_b", p: 0.4), .init(target: "unclear", p: 0.1)]
        let id = d.submit("tell it to ship")
        await finish(d, f, id)
        #expect(f.sent.isEmpty && f.prepared.isEmpty)
        let ask = d.askBacks.first
        #expect(ask?.id == id && ask?.suggestion == "session:local_a")
        #expect(ask?.options.map(\.target) == ["session:local_a", "session:local_b"])
        #expect(decision(s, id)?.outcome == .pending && decision(s, id)?.done == [.asked(["Fix the login bug", "Update the docs"])])
        #expect(d.progress[id!] == nil)
    }

    @Test func withoutJevAMessageNamingASessionStillGoesAndOtherwiseAsks() async {
        let (s, d, f) = setup()
        f.rankError = RouterTools.Failure("no TypeSafe key is set")
        let named = d.submit("tell the Update the docs session to ship")
        await finish(d, f, named)
        #expect(f.prepared == ["local_b"])
        let vague = d.submit("do the thing")
        await finish(d, f, vague)
        #expect(d.askBacks.map(\.id) == [vague!] && f.prepared == ["local_b"])
    }

    @Test func pickingTheSuggestionLogsNoCorrectionAndAnotherPickDoes() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "session:local_a", p: 0.5), .init(target: "session:local_b", p: 0.4), .init(target: "unclear", p: 0.1)]
        let same = d.submit("tell it to ship")
        await finish(d, f, same)
        f.finished = []
        d.pick(same!, target: "session:local_a")
        await finish(d, f, same)
        #expect(f.prepared == ["local_a"] && d.askBacks.isEmpty)
        #expect(decision(s, same)?.outcome == .done)
        #expect(decision(s, same)?.done.contains(.sent(to: "peer-local_a", text: "body-local_a", original: "orig")) == true)

        let other = d.submit("tell it to ship again")
        await finish(d, f, other)
        f.finished = []
        d.pick(other!, target: "session:local_b")
        await finish(d, f, other)
        #expect(f.prepared == ["local_a", "local_b"])
        guard case .corrected(let from, let to)? = decision(s, other)?.outcome else { Issue.record("not a correction"); return }
        #expect(from.contains("Fix the login bug") && to.contains("Update the docs"))
        // The correction is part of the next run's context.
        #expect(s.recentDecisions(10).contains("you corrected this: not session “Fix the login bug”"))
    }

    @Test func typingATargetsNameAnswersTheAsk() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "session:local_a", p: 0.5), .init(target: "session:local_b", p: 0.4), .init(target: "unclear", p: 0.1)]
        let id = d.submit("ship it")
        await finish(d, f, id)
        f.finished = []
        let before = s.router.decisions.count
        let by = d.submit("Update the docs")
        #expect(by == id, "the name is the answer: no new run")
        await finish(d, f, id)
        #expect(f.prepared == ["local_b"] && s.router.decisions.count == before)
        // A name that fits nothing is a message of its own.
        f.ranked = [.init(target: "unclear", p: 1)]
        let other = d.submit("Something unrelated")
        #expect(other != id && other != nil)
        await finish(d, f, other)
    }

    @Test func somethingElseCanPickAProjectToStartIn() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "unclear", p: 1)]
        let id = d.submit("write the changelog")
        await finish(d, f, id)
        f.finished = []
        let picker = d.pickerOptions()
        #expect(picker.sessions.count == 2 && picker.projects.map(\.detail).sorted() == ["docs", "lookout"])
        d.pick(id!, target: "new:/code/docs")
        await finish(d, f, id)
        #expect(f.started.map(\.folder) == ["/code/docs"])
        guard case .corrected? = decision(s, id)?.outcome else { Issue.record("not a correction"); return }
        d.dismiss(UUID())
    }

    @Test func dismissingAnAskSendsNothing() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "unclear", p: 1)]
        let id = d.submit("hmm")
        await finish(d, f, id)
        d.dismiss(id!)
        #expect(d.askBacks.isEmpty && f.sent.isEmpty)
        #expect(decision(s, id)?.outcome == .done && decision(s, id)?.reply == "Dismissed: nothing was sent.")
    }

    // MARK: Haiku runs

    @Test func changingLookoutIsAFreshRunWhoseChangesJoinItsEntry() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "change_lookout", p: 0.92), .init(target: "unclear", p: 0.08)]
        // Another run is "active" in the log: the change must still go to this run's entry.
        let other = s.logDecision(RouterDecision(trigger: .you("other")))
        s.activeDecision = other
        f.whileRunning = { tools in _ = await tools.call("set_setting", ["key": "notifications", "value": false]) }
        let id = d.submit("turn the notifications off")
        await finish(d, f, id)
        #expect(f.runs.map(\.intent) == [.changeLookout])
        #expect(f.runs[0].input.contains("The user's message:\nturn the notifications off"))
        let entry = decision(s, id)
        #expect(entry?.decision.label == "change_lookout" && entry?.reply == "Done." && entry?.note == "set it")
        #expect(entry?.links.changes.count == 1 && decision(s, other)?.links.changes.isEmpty == true)
        #expect(s.router.chat.compactMap(\.change).count == 1, "a card with Revert")
        #expect(entry?.outcome == .done && entry?.summary == "changed Lookout")
        #expect(f.sent.isEmpty && f.prepared.isEmpty)
    }

    @Test func aQuestionRunAnswersWithoutChangingAnything() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "question", p: 0.9), .init(target: "unclear", p: 0.1)]
        f.answer = .init(reply: "One session is working.", done: "answered")
        let id = d.submit("what is going on")
        await finish(d, f, id)
        #expect(f.runs.map(\.intent) == [.question])
        let entry = decision(s, id)
        #expect(entry?.reply == "One session is working." && entry?.summary == "answered" && entry?.done.isEmpty == true)
    }

    @Test func aCompoundMessageIsOneRunWithTheLookoutTools() async {
        let (s, d, f) = setup()
        f.ranked = [.init(target: "compound", p: 0.9), .init(target: "unclear", p: 0.1)]
        let id = d.submit("hide the CI category and tell docs to ship")
        await finish(d, f, id)
        #expect(f.runs.map(\.intent) == [.compound] && f.sent.isEmpty)
    }

    @Test func aFailureIsInTheEntryAndTheChatAndNothingIsLeftPending() async {
        let (s, d, f) = setup()
        f.failSend = "isn't running in the Claude app: open it first"
        let id = d.submit("use sqlite", context: RouterContext(replyTo: "local_a#w1"))
        await finish(d, f, id)
        #expect(decision(s, id)?.done == [.failed("isn't running in the Claude app: open it first")] && decision(s, id)?.outcome == .done)
        #expect(s.router.chat.last?.role == .error)
        #expect(s.router.cards[0].isOpen, "nothing was sent, so the card stays")
    }

    // MARK: Independent runs

    @Test func twoMessagesAreInFlightAtOnceEachWithItsOwnEntry() async {
        let (s, d, f) = setup()
        f.holdOn = ["local_a"]
        let first = d.submit("use sqlite", context: RouterContext(replyTo: "local_a#w1"))
        await waitUntil { f.prepared == ["local_a"] }
        // The first is held in its preparation; the second goes through meanwhile.
        f.ranked = [.init(target: "session:local_b", p: 0.9), .init(target: "unclear", p: 0.1)]
        let second = d.submit("tell docs to ship")
        await finish(d, f, second)
        #expect(f.sent.map(\.to) == ["peer-local_b"])
        #expect(d.progress[first!] != nil && d.progress[second!] == nil && d.isBusy)
        #expect(decision(s, first)?.outcome == .pending && decision(s, second)?.outcome == .done)
        f.release("local_a")
        await finish(d, f, first)
        #expect(f.sent.map(\.to) == ["peer-local_b", "peer-local_a"] && !d.isBusy)
        #expect(decision(s, first)?.done.count == 1 && decision(s, second)?.done.count == 1)
    }

    @Test func nothingRunsWhileTheRouterIsOff() {
        let (s, d, _) = setup()
        s.router.enabled = false
        #expect(d.submit("hello") == nil && s.router.decisions.isEmpty)
    }

    // MARK: Context and arguments

    @Test func theRunContextIsTheStateTheDecisionsAndTheMessage() {
        let context = RouterRunContext(
            cards: [.init(id: "c1", kind: "question", title: "Fix it", project: "lookout", text: "Which database?")],
            working: [.init(title: "Docs", project: "docs", doing: "Editing README.md")],
            decisions: "2m ago · you: “ship” → sent to Docs", projects: ["api"], message: "what is going on")
        let text = context.text()
        #expect(text.contains("- [question] “Fix it” (lookout): Which database? (card c1)"))
        #expect(text.contains("- “Docs” (docs): Editing README.md"))
        #expect(text.contains("The last decisions (oldest first):\n2m ago · you: “ship” → sent to Docs"))
        #expect(text.contains("Projects the user tagged: api"))
        #expect(text.hasSuffix("The user's message:\nwhat is going on"))
        let empty = RouterRunContext(message: "hi").text()
        #expect(empty.contains("Open cards (what needs the user):\n- none") && empty.contains("Sessions working on their own:\n- none"))
    }

    @Test func theContextOfARunLeavesOutItsOwnEntry() {
        let (s, _, _) = setup()
        s.logDecision(RouterDecision(trigger: .you("earlier"), outcome: .done))
        let own = s.logDecision(RouterDecision(trigger: .you("this one")))
        let text = s.routerRunContext(message: "this one", excluding: own).text()
        #expect(text.contains("earlier") && !text.contains("you: “this one”"))
        #expect(text.contains("[question] “Fix the login bug” (lookout)"), "the open card")
    }

    @Test func eachIntentGetsOnlyTheToolsItNeeds() {
        let read = RouterRun.toolNames(.question)
        #expect(read.contains("board") && read.contains("list_categories") && read.contains("list_inbox") && read.contains("get_settings"))
        for change in ["create_category", "update_category", "delete_category", "reorder_categories", "create_group", "update_group",
                       "delete_group", "mark_entries", "set_setting"] {
            #expect(!read.contains(change), "a question can't \(change)")
        }
        let all = RouterRun.toolNames(.changeLookout)
        #expect(all == LookoutTools.names && all.contains("set_setting") && all.contains("list_categories"))
        #expect(RouterRun.toolNames(.compound) == all)
        for intent in RouterRun.Intent.allCases {
            let served = RouterRun.specs(intent).compactMap { $0["name"] as? String }
            #expect(Set(served) == RouterRun.toolNames(intent), "\(intent) serves what it may call")
        }
        // Nothing of the sessions: no way to send, start or answer from a run.
        for intent in RouterRun.Intent.allCases {
            let names = RouterRun.toolNames(intent)
            for forbidden in ["prepare", "start_session", "answer_form", "mark", "open_session", "route"] { #expect(!names.contains(forbidden)) }
        }
    }

    @Test func aRunIsAFreshHaikuWithNoBuiltInToolsAndATypedResult() {
        let args = RouterRun.arguments(.changeLookout, config: "/tmp/mcp.json")
        func value(after flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        #expect(value(after: "--model") == "claude-haiku-5-5" && value(after: "--tools") == "")
        #expect(value(after: "--mcp-config") == "/tmp/mcp.json" && args.contains("--strict-mcp-config"))
        #expect(args.contains("--no-session-persistence") && !args.contains("--resume") && !args.contains("--continue"))
        #expect(value(after: "--output-format") == "json" && value(after: "--setting-sources") == "")
        #expect(value(after: "--allowedTools") == "mcp__lookout")
        let schema = (try? JSONSerialization.jsonObject(with: Data((value(after: "--json-schema") ?? "").utf8))) as? [String: Any]
        #expect((schema?["required"] as? [String])?.sorted() == ["done", "reply"])
        #expect(value(after: "--append-system-prompt") == RouterRun.role(.changeLookout))
        #expect(RouterRun.role(.question).contains("You change nothing"))
        #expect(RouterRun.role(.compound).contains("which part you left"))
    }

    @Test func theTypedResultIsReadFromStructuredOutputOrFromJsonText() throws {
        func output(_ object: [String: Any]) -> OneShot.Output {
            OneShot.Output(stdout: try! JSONSerialization.data(withJSONObject: object), stderr: Data(), status: 0)
        }
        let typed = try RouterRun.parse(output(["is_error": false, "result": "{}", "structured_output": ["reply": "Hidden the CI category.", "done": "hid CI"]]))
        #expect(typed == RouterRun.Answer(reply: "Hidden the CI category.", done: "hid CI"))
        let text = try RouterRun.parse(output(["is_error": false, "result": "{\"reply\":\"ok\",\"done\":\"x\"}"]))
        #expect(text == RouterRun.Answer(reply: "ok", done: "x"))
        let plain = try RouterRun.parse(output(["is_error": false, "result": "All good"]))
        #expect(plain == RouterRun.Answer(reply: "All good", done: ""))
        #expect(throws: (any Error).self) { try RouterRun.parse(output(["is_error": true, "result": "overloaded"])) }
        #expect(throws: (any Error).self) { try RouterRun.parse(OneShot.Output(stdout: Data("nope".utf8), stderr: Data("boom\n".utf8), status: 1)) }
    }

    @Test func theDeliveryProcessIsGatedLikeTheRoutersOwn() {
        let args = RouterSender.arguments()
        #expect(args.contains("--permission-prompt-tool") && args.contains("stdio") && args.contains("manual"))
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "SendMessage")
        #expect(args.firstIndex(of: "--settings").map { args[$0 + 1] }?.contains("\"ask\":[\"SendMessage\"]") == true)
        #expect(args.contains("--no-session-persistence") && !args.contains("--resume"))
        let ask = RouterSender.request(to: "Docs", text: "⟦lookout⟧\nShip it.")
        #expect(ask.contains("---BEGIN---\n⟦lookout⟧\nShip it.\n---END---") && ask.hasPrefix("SendMessage to: Docs"))
    }

    // MARK: The delivery process, against a stand-in for Claude Code

    /// A program that speaks Claude Code's stream the way a SendMessage turn does: it asks for permission, and reports what
    /// the answer allowed.
    private func standIn(_ dir: TempDir) -> String {
        let script = dir.path("claude")
        let body = """
        #!/bin/bash
        read -r first
        echo "$first" > "$(dirname "$0")/stdin.txt"
        echo "$@" > "$(dirname "$0")/args.txt"
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"SendMessage","input":{"to":"Docs","message":"hello"}}]}}'
        echo '{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"SendMessage","input":{"to":"Docs","message":"hello"}}}'
        read -r answer
        echo "$answer" > "$(dirname "$0")/answer.txt"
        if echo "$answer" | grep -q '"behavior":"allow"'; then
          echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"{\\"success\\":true}"}]}}'
        else
          echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"refused"}]}}'
        fi
        echo '{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
        """
        try! Data(body.utf8).write(to: script)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    @Test func theDeliveryGoesThroughTheGateAndOnlyAsPrepared() async throws {
        let dir = TempDir()
        let (s, _, f) = setup()
        let tools = RouterTools(store: s)
        tools.beginTurn("hello")
        tools.prepared["Docs"] = Prepared(text: "hello", original: "hello", rephrased: false)
        try await RouterSender.send(binary: standIn(dir), cwd: dir.url, to: "Docs", text: "hello", tools: tools, timeout: 30)
        #expect(tools.takeApproved("Docs", "hello") != nil, "the gate let exactly the prepared text through")
        let asked = try String(contentsOf: dir.path("stdin.txt"), encoding: .utf8)
        #expect(asked.contains("SendMessage to: Docs") && asked.contains("---BEGIN---"))
        let answer = try String(contentsOf: dir.path("answer.txt"), encoding: .utf8)
        #expect(answer.contains("\"allow\"") && answer.contains("control_response"))
        withExtendedLifetime(f) {}
    }

    @Test func aDeliveryTheGateRefusesIsNotSent() async throws {
        let dir = TempDir()
        let (s, _, f) = setup()
        // Not prepared at all.
        let bare = RouterTools(store: s)
        bare.beginTurn("hello")
        await #expect(throws: (any Error).self) {
            try await RouterSender.send(binary: self.standIn(dir), cwd: dir.url, to: "Docs", text: "hello", tools: bare, timeout: 30)
        }
        // Prepared, but the process asks to send other words.
        let other = RouterTools(store: s)
        other.beginTurn("hello")
        other.prepared["Docs"] = Prepared(text: "something else", original: "x", rephrased: true)
        do {
            try await RouterSender.send(binary: standIn(dir), cwd: dir.url, to: "Docs", text: "something else", tools: other, timeout: 30)
            Issue.record("sent words that weren't the prepared ones")
        } catch {
            #expect(error.localizedDescription.contains("isn't the prepared text"), "\(error.localizedDescription)")
        }
        withExtendedLifetime(f) {}
    }

    @Test func aProcessThatNeverAnswersIsGivenUpOn() async throws {
        let dir = TempDir()
        let (s, _, f) = setup()
        let script = dir.path("claude")
        try Data("#!/bin/bash\nread -r x\nsleep 30\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let tools = RouterTools(store: s)
        tools.beginTurn("hello")
        await #expect(throws: (any Error).self) {
            try await RouterSender.send(binary: script.path, cwd: dir.url, to: "Docs", text: "hello", tools: tools, timeout: 0.5)
        }
        withExtendedLifetime(f) {}
    }
}
