import Foundation

// A turn that ended waiting on something Lookout can see (another session's turn, CI on a PR or workflow the inbox tracks)
// closes its own loop: once that is done its row in Working says it's ready to continue, a banner says so, and "Tell it"
// sends the session a short message through the Router's usual send path (signed, through the gate). With "Continue it
// automatically" on (per session, else Settings' default, off) the message goes on its own, logged in the history like any
// run of the Router's.

enum RouterWaits {
    /// What came of the watched thing, once it is done; nil while it isn't (or when Lookout can't tell).
    static func result(_ watch: RouterTriage.Watch, sessions: [String: ClaudeSession], things: [String: Thing]) -> String? {
        switch watch.target {
        case .session(let id, let turns):
            guard let session = sessions[id], !session.isArchived, session.completedTurns > turns, !session.running else { return nil }
            return session.summary?.blocked == true ? "it stopped, blocked" : "it finished its turn"
        case .ci(let id):
            guard let thing = things[id] else { return nil }
            switch thing.checks {
            case .passing: return "passing"
            case .failing:
                let jobs = thing.failingJobs.prefix(3).map { RouterDecision.clip($0, 40) }
                return jobs.isEmpty ? "failing" : "failing (\(jobs.joined(separator: ", ")))"
            case .pending, nil: return nil
            }
        }
    }

    /// What the session is told: "The CI on owner/repo#12 finished: passing." It goes to the session as your own words
    /// (signed), so nothing free-form goes in, not even what Lookout saw (a workflow's or job's name, a title, another
    /// session's): only a repo and number checked to look like GitHub's, and the outcome in fixed words.
    static func message(_ triage: RouterTriage) -> String? {
        guard let ready = triage.ready, let target = triage.watch?.target else { return nil }
        switch target {
        case .ci:
            let outcome = ready.result == "passing" ? "passing" : ready.result.hasPrefix("failing") ? "failing" : "finished"
            let what = triage.watch?.ref.flatMap(safeRef).map { "CI on \($0)" } ?? "CI you were waiting on"
            return "The \(what) finished: \(outcome)."
        case .session:
            let outcome = ready.result == "it stopped, blocked" ? "it stopped, blocked" : "it finished its turn"
            return "The session you were waiting on finished: \(outcome)."
        }
    }

    /// "owner/repo#12" or "owner/repo", when it is only that (GitHub's characters, GitHub's lengths); nil otherwise.
    static func safeRef(_ ref: String) -> String? {
        ref.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}(#[0-9]{1,9})?$"#, options: .regularExpression) != nil
            && !ref.contains("..") ? ref : nil
    }

    /// The CI's repo and number for the message, checked.
    static func ref(_ thing: Thing) -> String? {
        safeRef(thing.kind == .workflow ? thing.repo : "\(thing.repo)\(thing.number.map { "#\($0)" } ?? "")")
    }

    /// "CI on owner/repo#12" for a PR, "CI: Tests on main" for a workflow.
    static func ciLabel(_ thing: Thing) -> String {
        if thing.kind == .workflow { return "CI: \(thing.workflowName ?? thing.title) on \(thing.branch ?? "the default branch")" }
        return "CI on \(thing.repo)\(thing.number.map { "#\($0)" } ?? "")"
    }
}

extension Store {
    /// What a session's turn might be waiting on that Lookout can watch: the other live sessions (working ones first), and
    /// the checks still running on the inbox's PRs and workflows in a repo named like the session's folder. Each under a
    /// plain key for Jev.
    func waitOptions(for session: ClaudeSession) -> [RouterTriage.WaitOption] {
        let others = claudeSessions.values.filter { !$0.isArchived && $0.id != session.id }
            .sorted { a, b in a.running != b.running ? a.running : a.lastActivity > b.lastActivity }
            .prefix(10)
        var options = others.enumerated().map { i, other in
            RouterTriage.WaitOption(key: "s\(i)",
                                    hint: "The Claude session “\(other.title)” in \(other.folderName)" + (other.running ? ", working now" : ""),
                                    watch: .init(target: .session(id: other.id, turns: other.completedTurns),
                                                 label: "session “\(RouterDecision.clip(other.title, 50))”"))
        }
        let name = session.folderName.lowercased()
        let ci = things.values.filter { thing in
            thing.checks == .pending && (thing.kind == .pr || thing.kind == .workflow)
                && thing.repo.split(separator: "/").last.map { $0.lowercased() == name } == true
        }.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)
        options += ci.enumerated().map { i, thing in
            RouterTriage.WaitOption(key: "c\(i)", hint: "\(RouterWaits.ciLabel(thing)): \(thing.title), checks running",
                                    watch: .init(target: .ci(thing: thing.id), label: RouterWaits.ciLabel(thing),
                                                 ref: RouterWaits.ref(thing)))
        }
        return options
    }

    /// Whether a session is told on its own when its wait is over: its own choice, else Settings'.
    func continuesAutomatically(_ sessionID: String) -> Bool {
        router.autoContinueSessions[sessionID] ?? router.autoContinue
    }

    func setContinuesAutomatically(_ sessionID: String, _ on: Bool) {
        var state = router
        state.autoContinueSessions[sessionID] = on == state.autoContinue ? nil : on
        if state != router { router = state }
    }

    func setAutoContinueDefault(_ on: Bool) {
        guard router.autoContinue != on else { return }
        router.autoContinue = on
    }

    /// The waiting cards whose watched thing is done: ready to continue, with a banner, or told at once when the session
    /// continues automatically.
    func resolveWaits(now: Date = Date()) {
        guard router.enabled, router.cards.contains(where: { $0.isOpen && $0.kind == .waiting && $0.triage?.watch != nil }) else { return }
        var state = router
        var ready: [RouterCard] = []
        for i in state.cards.indices {
            let card = state.cards[i]
            guard card.isOpen, card.kind == .waiting, let watch = card.triage?.watch, card.triage?.ready == nil,
                  let result = RouterWaits.result(watch, sessions: claudeSessions, things: things) else { continue }
            state.cards[i].triage?.ready = .init(result: result, at: now)
            ready.append(state.cards[i])
        }
        guard !ready.isEmpty else { return }
        router = state
        for card in ready {
            if continuesAutomatically(card.sessionID) {
                tellWaiting(card.id, automatic: true, now: now)
            } else {
                routerTriager.onReady?(card)
            }
        }
    }

    /// Sends a waiting session the message that what it waited on is done, and logs it (`automatic`: as Lookout's own run).
    /// Once per wait: a send that fails can be tried again.
    func tellWaiting(_ cardID: String, automatic: Bool = false, now: Date = Date()) {
        guard let i = router.cards.firstIndex(where: { $0.id == cardID }), router.cards[i].isOpen,
              let triage = router.cards[i].triage, triage.told == nil, let text = RouterWaits.message(triage) else { return }
        let card = router.cards[i]
        router.cards[i].triage?.told = now
        var entry = RouterDecision(at: now, trigger: automatic ? .system : .you("Tell it to continue"),
                                   decision: .init(target: card.title, intent: "continue"),
                                   links: .init(sessions: [card.sessionID], cards: [card.id]))
        if automatic { entry.reply = "Sent on its own: “Continue it automatically” is on for this session." }
        let id = logDecision(entry)
        let send = routerTriager.sender ?? (routerIsPretend ? { _, _ in } : Self.sendVerbatim(store: self))
        Task { [weak self] in
            do {
                try await send(card.sessionID, text)
                guard let self else { return }
                self.updateDecision(id) {
                    $0.add(.sent(to: card.title, text: text, original: nil), session: card.sessionID, card: card.id)
                    $0.outcome = .done
                }
                var state = self.router
                RouterFeed.address(&state, card.sessionID, .router, Date()) { $0.id == card.id }
                if state != self.router { self.router = state }
            } catch {
                guard let self else { return }
                self.updateDecision(id) {
                    $0.add(.failed(RouterDecision.clip(error.localizedDescription, 120)), session: card.sessionID, card: card.id)
                    $0.outcome = .done
                }
                if let j = self.router.cards.firstIndex(where: { $0.id == card.id }) { self.router.cards[j].triage?.told = nil }
            }
        }
    }

    /// The Router's send path with the words as they are (no rephrasing): prepared and signed for the session's plugin, then
    /// through the gate, which lets only exactly this text go, once.
    static func sendVerbatim(store: Store) -> RouterTriager.Sender {
        { [weak store] session, text in
            guard let store else { throw RouterTools.Failure("Lookout isn't ready") }
            let tools = RouterTools(store: store)
            tools.claudePath = { [weak store] in store?.routerStatus.claudeCode?.path }
            tools.rephrase = { message, _, _ in Prepared(text: message, original: message, rephrased: false) }
            tools.beginTurn(text)
            defer { tools.endTurn() }
            let answer = try await tools.prepare(store, session: session, ticket: tools.ticket())
            guard let to = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])?["to"] as? String,
                  let ready = tools.prepared[to] else { throw RouterTools.Failure("Not prepared") }
            guard let binary = store.routerStatus.claudeCode?.path, let home = store.routerFiles?.routerHome else {
                throw RouterTools.Failure("Claude Code wasn't found, so nothing can be sent")
            }
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try await RouterSender.send(binary: binary, cwd: home, to: to, text: ready.text, tools: tools,
                                        inbox: await store.relayInbox(forSigned: ready.text))
        }
    }
}
