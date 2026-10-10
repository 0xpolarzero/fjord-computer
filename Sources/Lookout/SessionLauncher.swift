import Foundation

// Starting a Claude Code session without a model turn, and the inbox action that uses it (docs/design/spec/router.md, C).
// The steps are the ones `start_session` takes (RouterMCP), minus the model: a CLI session is made in the folder (its one line
// renames it), the Claude app imports it, its process registers as a peer, Lookout's plugin comes up in it, and the first
// message is signed for that plugin and delivered through the same gate as every other send. Phase 4 moves RouterMCP and the
// dispatcher onto this and removes the copy.

// MARK: - Settings an action may carry

enum ActionSettings {
    /// What `claude --model` takes as an alias.
    static let models = ["opus", "sonnet", "haiku"]
    /// What `claude --effort` takes (it also has `xhigh`, which the editor doesn't offer).
    static let efforts = ["low", "medium", "high", "max"]

    /// `value` if it is one of `allowed`; anything else (nothing, a value saved by a newer version) is the default.
    static func clean(_ value: String?, in allowed: [String]) -> String? {
        guard let value, allowed.contains(value) else { return nil }
        return value
    }
}

// MARK: - The launcher

@MainActor
final class SessionLauncher {
    /// Everything it does outside Lookout's own state; tests stand in for each. The defaults are the real ones.
    struct Effects {
        /// Makes the CLI session in `folder`, has the app import it and waits for its process.
        var bootstrap: @MainActor (_ folder: String, _ title: String, _ model: String?, _ effort: String?) async throws -> SessionStart.Started
        /// Waits until Lookout's plugin runs in the session (its Claude Code id).
        var pluginReady: @MainActor (_ cli: String) async throws -> Void
        /// `body` signed for the session's plugin.
        var sign: @MainActor (_ body: String, _ cli: String) async throws -> String
        /// Delivers the signed message to the peer, through the gate.
        var send: @MainActor (_ peer: String, _ prepared: Prepared) async throws -> Void
    }

    private weak var store: Store?
    var effects: Effects
    /// How long the new session's plugin has to say it runs.
    var pluginWait: TimeInterval = SessionStart.wait

    init(store: Store, effects: Effects? = nil) {
        self.store = store
        self.effects = effects ?? Effects.unavailable
        if effects == nil { self.effects = Effects.live(self) }
    }

    /// A new session in `folder` with `firstMessage` as its first message, as Lookout's own words (signed), and the session's
    /// id and peer name. `model` and `effort` are `claude --model` / `--effort` values, nil for your defaults.
    @discardableResult
    func start(folder: String, title: String, firstMessage: String, model: String? = nil,
               effort: String? = nil) async throws -> (sessionID: String, peer: String) {
        guard let store else { throw RouterTools.Failure("Lookout isn't ready") }
        guard store.router.enabled, store.agents.enabled else { throw RouterTools.Failure("The Router is off") }
        guard store.routerPluginStatus == .installed else {
            throw RouterTools.Failure("Lookout's plugin isn't installed in Claude Code, so nothing can be sent (Settings → Router)")
        }
        guard !firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RouterTools.Failure("There is no message to start the session with")
        }
        let title = SessionStart.cleanTitle(title)
        let started = try await effects.bootstrap(folder, title, ActionSettings.clean(model, in: ActionSettings.models),
                                                  ActionSettings.clean(effort, in: ActionSettings.efforts))
        try await effects.pluginReady(started.cliID)
        let signed = try await effects.sign(firstMessage, started.cliID)
        let prepared = Prepared(text: signed, original: firstMessage, rephrased: false, newSessionIn: store.folderName(folder), body: firstMessage)
        try await effects.send(started.peer, prepared)
        return (started.sessionID, started.peer)
    }

    /// The bootstrap's arguments: `SessionStart`'s, with the model and effort of the session. The app starts the process it
    /// imports with your settings, so these reach the session only as far as the app takes them from its transcript.
    static func bootstrapArguments(uuid: String, title: String, model: String?, effort: String?) -> [String] {
        var arguments = SessionStart.bootstrapArguments(uuid: uuid, title: title)
        if let model { arguments += ["--model", model] }
        if let effort { arguments += ["--effort", effort] }
        return arguments
    }
}

extension SessionLauncher.Effects {
    static let unavailable = SessionLauncher.Effects(
        bootstrap: { _, _, _, _ in throw RouterTools.Failure("Lookout isn't ready") },
        pluginReady: { _ in throw RouterTools.Failure("Lookout isn't ready") },
        sign: { _, _ in throw RouterTools.Failure("Lookout isn't ready") },
        send: { _, _ in throw RouterTools.Failure("Lookout isn't ready") })

    @MainActor
    static func live(_ launcher: SessionLauncher) -> SessionLauncher.Effects {
        SessionLauncher.Effects(
            bootstrap: { [weak launcher] folder, title, model, effort in
                guard let store = launcher?.store else { throw RouterTools.Failure("Lookout isn't ready") }
                guard let binary = store.routerStatus.claudeCode?.path,
                      let peersDir = store.routerFiles?.claudeDir.appendingPathComponent("sessions") else {
                    throw RouterTools.Failure("Claude Code wasn't found, so no session can be started")
                }
                let uuid = UUID().uuidString.lowercased()
                let output = try await OneShot.run(binary, SessionLauncher.bootstrapArguments(uuid: uuid, title: title, model: model, effort: effort),
                                                   cwd: URL(fileURLWithPath: folder), timeout: SessionStart.wait)
                _ = try OneShot.result(output)
                guard let url = SessionStart.importURL(uuid: uuid) else { throw RouterTools.Failure("Couldn't make the link") }
                if let intercept = store.interceptOpen { intercept("New Claude session in \(store.folderName(folder))") } else { Link.open(url) }
                let peer = try await SessionStart.waitForPeer(uuid: uuid, dir: peersDir)
                return SessionStart.Started(sessionID: "local_\(uuid)", peer: peer)
            },
            pluginReady: { [weak launcher] cli in
                guard let launcher, let store = launcher.store, let paths = store.routerFiles else { throw RouterTools.Failure("Lookout isn't ready") }
                @MainActor func up() async -> Bool {
                    let keyID = store.relayKeyCache?.keyID
                    return await OffMain.run { store.sessionsWithPlugin(paths: paths, keyID: keyID).contains(cli) }
                }
                let deadline = Date().addingTimeInterval(launcher.pluginWait)
                repeat {
                    try Task.checkCancellation()
                    if await up() { return }
                    try await Task.sleep(nanoseconds: 250_000_000)
                } while Date() < deadline
                if await up() { return }
                throw RouterTools.Failure("The new session started, but Lookout's plugin didn't come up in it within \(Int(RouterTools.bounded(launcher.pluginWait))) s; nothing was sent")
            },
            sign: { [weak launcher] body, cli in
                guard let store = launcher?.store else { throw RouterTools.Failure("Lookout isn't ready") }
                if let text = store.signRelay(body: body, target: cli) { return text }
                // Not cached yet, or the file changed: read it again, once.
                _ = await store.reloadRelayKey()
                if let text = store.signRelay(body: body, target: cli) { return text }
                throw RouterTools.Failure("Lookout couldn't sign the message (its plugin key is missing); nothing was sent")
            },
            send: { [weak launcher] peer, prepared in
                guard let store = launcher?.store else { throw RouterTools.Failure("Lookout isn't ready") }
                guard let binary = store.routerStatus.claudeCode?.path, let home = store.routerFiles?.routerHome else {
                    throw RouterTools.Failure("Claude Code wasn't found, so nothing can be sent")
                }
                try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                // The same gate as every send: only exactly this text goes to this peer, once.
                let tools = RouterTools(store: store)
                tools.beginTurn(prepared.original)
                tools.prepared[peer] = prepared
                defer { tools.endTurn() }
                try await RouterSender.send(binary: binary, cwd: home, to: peer, text: prepared.text, tools: tools,
                                            inbox: await store.relayInbox(for: peer))
            })
    }
}

// MARK: - An inbox action starting a session

/// "Ask the Router" without a model: the repo's local clone (Jev picks among several), a session started there with the action's
/// prompt, tagged with where it came from, and the run logged in the Router's history.
enum ActionSessions {
    /// Jev's pick (options, hints, state, instructions); tests answer for it.
    typealias Chooser = ([String], [String: String], [String: String], String) async throws -> JevClient.Choice

    @MainActor
    static func start(_ request: ActionSessionRequest, store: Store, clones: [String], launcher: SessionLauncher,
                      chooser: Chooser?, now: Date = Date()) async throws -> ActionSessionStarted {
        let entry = RouterDecision(at: now, trigger: .action(category: request.category, thing: request.reference,
                                                              actionID: request.action.uuidString, runID: request.run.uuidString),
                                   decision: .init(intent: "start a session"))
        let id = store.logDecision(entry)
        func fail(_ reason: String) -> ActionFailure {
            store.updateDecision(id) { $0.add(.failed(reason)); $0.outcome = .done }
            return ActionFailure(reason)
        }
        guard store.router.enabled, store.agents.enabled else { throw fail("the Router is off") }
        guard !clones.isEmpty else { throw fail("no local clone of \(request.repo)") }
        let folder = await pick(clones, for: request, store: store, chooser: chooser)
        let project = store.folderName(folder)
        store.updateDecision(id) { $0.decision.target = project }
        do {
            let (session, _) = try await launcher.start(folder: folder, title: request.title, firstMessage: request.message,
                                                        model: request.model, effort: request.effort)
            store.noteOrigin(SessionOrigin(category: request.category, thing: request.title, actionID: request.action.uuidString,
                                           runID: request.run.uuidString), for: session)
            store.updateDecision(id) {
                $0.add(.started(session: session, project: project, model: request.model, effort: request.effort), session: session)
                $0.outcome = .done
            }
            return ActionSessionStarted(sessionID: session, project: project)
        } catch {
            throw fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The only clone; else Jev's pick among them; else the one with the most recent Claude session (else the first, the
    /// shortest path, which is a checkout before its worktrees).
    @MainActor
    static func pick(_ clones: [String], for request: ActionSessionRequest, store: Store, chooser: Chooser?) async -> String {
        guard clones.count > 1 else { return clones[0] }
        let key = store.typesafeKey ?? ""
        let choose = chooser ?? (key.isEmpty ? nil : { options, hints, state, instructions in
            try await JevClient(key: key).choose(options, hints: hints, for: state, instructions: instructions)
        })
        if let choose {
            // Plain keys for Jev (paths have characters it may not take), mapped back after.
            let keys = clones.indices.map { "o\($0)" }
            let hints = Dictionary(uniqueKeysWithValues: zip(keys, clones.map { folder in
                "\(store.folderName(folder)) at \(folder)" + (recent(folder, store: store).map { ", last used \(shortAgo($0))" } ?? "")
            }))
            if let pick = try? await choose(keys, hints, ["item": request.summary, "action": request.category],
                                            "Which local clone of the repository should a Claude Code session work in for this item? Prefer the main checkout unless the item is about a branch that another checkout has."),
               let i = keys.firstIndex(of: pick.choice) {
                return clones[i]
            }
        }
        let dated = clones.compactMap { folder in recent(folder, store: store).map { (folder, $0) } }
        return dated.max { $0.1 < $1.1 }?.0 ?? clones[0]
    }

    /// When a Claude session in `folder` last did anything.
    @MainActor
    private static func recent(_ folder: String, store: Store) -> Date? {
        store.claudeSessions.values.filter { $0.folderKey == folder }.map(\.lastActivity).max()
    }
}

extension Store {
    /// Tags a session with what started it; its cards (open or not yet made) say so.
    func noteOrigin(_ origin: SessionOrigin, for session: String) {
        var state = router
        state.origins[session] = origin
        for i in state.cards.indices where state.cards[i].sessionID == session && state.cards[i].origin == nil {
            state.cards[i].origin = origin
        }
        router = state
    }
}
