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
    /// The GitHub repos (`owner/repo`, lowercased) a folder's git remotes name, read once per folder, off the main thread.
    func gitRepos(of folder: String?) async -> Set<String> {
        guard let folder, !folder.isEmpty else { return [] }
        if let known = routerTriager.repos[folder] { return known }
        let repos = await Task.detached(priority: .utility) { Set(LocalClones.remotes(of: folder)) }.value
        routerTriager.repos[folder] = repos
        return repos
    }

    /// What a session's turn might be waiting on that Lookout can watch: the other live sessions (working ones first), and
    /// the checks still running on the inbox's PRs and workflows of the very repo the session's folder is a clone of (its
    /// git remotes, owner and name: another owner's repo of the same name is not it). Each under a plain key for Jev.
    /// What finished after the waiting turn ended (`session.lastActivity`) still counts, though it was over by the time
    /// the options were read: a session whose latest turn ended since is watched from the turn before it (so it is done
    /// already), and CI whose checks changed since is offered done. A session at work is watched for the turn it is on,
    /// done once it stops: its count of finished turns may already include that turn (it is counted before its summary
    /// is written, while it still shows running), so it is watched from the turn before that count, never for a turn more.
    func waitOptions(for session: ClaudeSession) async -> [RouterTriage.WaitOption] {
        let since = session.lastActivity
        let repos = await gitRepos(of: session.folder)
        let others = claudeSessions.values.filter { !$0.isArchived && $0.id != session.id }
            .sorted { a, b in a.running != b.running ? a.running : a.lastActivity > b.lastActivity }
            .prefix(10)
        var options = others.enumerated().map { i, other in
            let finishedSince = !other.running && other.completedTurns > 0 && other.lastActivity > since
            let from = other.completedTurns - (finishedSince || other.running ? 1 : 0)
            return RouterTriage.WaitOption(key: "s\(i)",
                                           hint: "The Claude session “\(other.title)” in \(other.folderName)"
                                               + (other.running ? ", working now" : finishedSince ? ", finished a turn since" : ""),
                                           watch: .init(target: .session(id: other.id, turns: from),
                                                        label: "session “\(RouterDecision.clip(other.title, 50))”"))
        }
        let ci = things.values.filter { thing in
            (thing.checks == .pending || (thing.checks != nil && thing.updatedAt > since))
                && (thing.kind == .pr || thing.kind == .workflow) && repos.contains(thing.repo.lowercased())
        }.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)
        options += ci.enumerated().map { i, thing in
            RouterTriage.WaitOption(key: "c\(i)", hint: "\(RouterWaits.ciLabel(thing)): \(thing.title), "
                                        + (thing.checks == .pending ? "checks running" : "checks finished since"),
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
    /// Once per wait: a send that fails can be tried again. That it is being sent is kept in memory only (quitting midway
    /// leaves it untold, to be told again); that it was told is saved once it was delivered.
    func tellWaiting(_ cardID: String, automatic: Bool = false, now: Date = Date()) {
        guard let i = router.cards.firstIndex(where: { $0.id == cardID }), router.cards[i].isOpen,
              let triage = router.cards[i].triage, triage.told == nil, !routerTriager.telling.contains(cardID),
              let text = RouterWaits.message(triage) else { return }
        let card = router.cards[i]
        routerTriager.telling.insert(cardID)
        var entry = RouterDecision(at: now, trigger: automatic ? .system : .you("Tell it to continue"),
                                   decision: .init(target: card.title, intent: "continue"),
                                   links: .init(sessions: [card.sessionID], cards: [card.id]))
        if automatic { entry.reply = "Sent on its own: “Continue it automatically” is on for this session." }
        let id = logDecision(entry)
        // Bound to this card as it is now: anything that changes it meanwhile (handled, the session going on, auto-continue
        // turned off) stops the send, checked again right before it is delivered.
        let revision = cardRevisions[cardID, default: 0]
        let check: @MainActor () throws -> Void = { [weak self] in
            guard let self, self.waitStillTellable(cardID, revision: revision, automatic: automatic) else {
                throw RouterTools.Failure("Not sent: it no longer waits for this")
            }
        }
        let send: RouterTriager.Sender = if let sender = routerTriager.sender {
            { session, text in try await check(); try await sender(session, text) }
        } else if routerIsPretend {
            { _, _ in try await check() }
        } else {
            Self.sendVerbatim(store: self, check: check)
        }
        Task { [weak self] in
            do {
                try await send(card.sessionID, text)
                guard let self else { return }
                self.routerTriager.telling.remove(card.id)
                self.updateDecision(id) {
                    $0.add(.sent(to: card.title, text: text, original: nil), session: card.sessionID, card: card.id)
                    $0.outcome = .done
                }
                var state = self.router
                if let j = state.cards.firstIndex(where: { $0.id == card.id }) { state.cards[j].triage?.told = Date() }
                RouterFeed.address(&state, card.sessionID, .router, Date()) { $0.id == card.id }
                if state != self.router { self.router = state }
            } catch {
                guard let self else { return }
                self.routerTriager.telling.remove(card.id)
                self.updateDecision(id) {
                    $0.add(.failed(RouterDecision.clip(error.localizedDescription, 120)), session: card.sessionID, card: card.id)
                    $0.outcome = .done
                }
            }
        }
    }

    /// Whether a waiting card can still be told, as it was when the send began (`revision`): open, ready and untold, of
    /// the session's latest turn, which isn't running, and (`automatic`) still to be continued on its own.
    func waitStillTellable(_ cardID: String, revision: Int, automatic: Bool) -> Bool {
        guard router.enabled, cardRevisions[cardID, default: 0] == revision,
              let card = router.cards.first(where: { $0.id == cardID }), card.isOpen, card.kind == .waiting,
              card.triage?.ready != nil, card.triage?.told == nil,
              let session = claudeSessions[card.sessionID], !session.isArchived, !session.running,
              card.id == "\(session.id)#t\(session.completedTurns)" else { return false }
        return !automatic || continuesAutomatically(card.sessionID)
    }

    /// The Router's send path with the words as they are (no rephrasing): prepared and signed for the session's plugin, then
    /// through the gate, which lets only exactly this text go, once. `check` stops it by throwing: run after the preparing,
    /// and again at each of the gate's own (the approval, right before the inbox's write, the fallback's permission), after
    /// every wait, so a wait handled or auto-continue turned off meanwhile sends nothing.
    static func sendVerbatim(store: Store, check: @escaping @MainActor () throws -> Void) -> RouterTriager.Sender {
        { [weak store] session, text in
            guard let store else { throw RouterTools.Failure("Lookout isn't ready") }
            let tools = RouterTools(store: store)
            tools.claudePath = { [weak store] in store?.routerStatus.claudeCode?.path }
            tools.rephrase = { message, _, _ in Prepared(text: message, original: message, rephrased: false) }
            tools.deliveryCheck = {
                do { try check(); return nil } catch { return error.localizedDescription }
            }
            tools.beginTurn(text)
            defer { tools.endTurn() }
            let answer = try await tools.prepare(store, session: session, ticket: tools.ticket())
            guard let to = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])?["to"] as? String,
                  let ready = tools.prepared[to] else { throw RouterTools.Failure("Not prepared") }
            guard let binary = store.routerStatus.claudeCode?.path, let home = store.routerFiles?.routerHome else {
                throw RouterTools.Failure("Claude Code wasn't found, so nothing can be sent")
            }
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try await check()
            try await RouterSender.send(binary: binary, cwd: home, to: to, text: ready.text, tools: tools,
                                        inbox: await store.relayInbox(forSigned: ready.text))
        }
    }
}
