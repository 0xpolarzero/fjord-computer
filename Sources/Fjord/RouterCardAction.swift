import Foundation

// What the Router proposes on its own page, and what Apply, Revert and the history card do with it. Archiving or reopening
// a card, muting or unmuting a project and stopping a session's turn reach out of the message that asked for them (the
// model picks the card, project or session from what sessions wrote), so none is done by the Router: each is recorded as a
// change that waits for your Apply (`FjordChange.pending`), saying exactly what will happen, with Discard beside it.
// Archive, reopen and mute are taken back by Revert; a stop is not (the turn is over once it is stopped).

/// One action on the Router page, as a proposed change records it.
enum CardAction: Codable, Hashable {
    /// `card`: the card's id. `project`: how the lists name its project.
    case archive(card: String, title: String, project: String)
    case reopen(card: String, title: String, project: String)
    /// `project`: the canonical Router project key (`Store.routerProjectGroupKey`), which `mutedFolders` holds.
    case mute(project: String, name: String, muted: Bool)
    /// `decision`, `nonce`: the delivery that started the session's running turn when it was proposed.
    case stop(session: String, title: String, decision: UUID, nonce: String)

    var isMute: Bool { if case .mute = self { true } else { false } }
    var isRevertible: Bool { if case .stop = self { false } else { true } }

    var symbol: String {
        switch self {
        case .archive: "archivebox"
        case .reopen: "arrow.uturn.backward"
        case .mute(_, _, let muted): muted ? "bell.slash" : "bell"
        case .stop: "stop.circle"
        }
    }

    /// The change's one line.
    var title: String {
        switch self {
        case .archive(_, let title, let project): "Archive “\(title)” (\(project))"
        case .reopen(_, let title, let project): "Reopen “\(title)” (\(project))"
        case .mute(_, let name, let muted): "\(muted ? "Mute" : "Unmute") project \(name)"
        case .stop(_, let title, _, _): "Stop the turn of “\(title)”"
        }
    }

    var before: String {
        switch self {
        case .archive(_, let title, _): "“\(title)”: open on the Router page"
        case .reopen(_, let title, _): "“\(title)”: archived"
        case .mute(_, let name, let muted): "\(name): \(muted ? "not muted" : "muted")"
        case .stop(_, let title, _, _): "“\(title)”: working on a turn"
        }
    }

    var after: String {
        switch self {
        case .archive(_, let title, _): "“\(title)”: archived, in the history"
        case .reopen(_, let title, _): "“\(title)”: open on the Router page again"
        case .mute(_, let name, let muted): "\(name): \(muted ? "muted" : "not muted")"
        case .stop(_, let title, _, _): "“\(title)”: the turn is stopped (what it already did stays done)"
        }
    }

    /// Why it waits, as its card says.
    var waitingReason: String {
        switch self {
        case .stop: "The Router proposes stopping this turn; it can't be undone once you apply it"
        default: "The Router proposes this; nothing changes until you apply it"
        }
    }
}

extension Store {
    // MARK: Resolving what a proposal names

    /// The Router's projects as the canvas and the Brief hold them: the canonical key (`routerProjectGroupKey`, which a
    /// guest session's project has instead of its host mirror folder) and the name the lists show. A name keeps its path
    /// above it (`customer-a/app`), which is how a qualified name is told from a bare one.
    func routerProjects() -> [(key: String, name: String)] {
        var keys = Set(claudeSessions.values.map { routerProjectGroupKey(sessionID: $0.id, folder: $0.folderKey) })
        keys.formUnion(agents.mutedFolders)
        keys.remove("")
        return keys.map { (key: $0, name: routerProjectGroupName($0)) }.sorted { ($0.name.lowercased(), $0.key) < ($1.name.lowercased(), $1.key) }
    }

    // MARK: The running turn

    /// The delivery of the session's current turn: the one Fjord sent whose own turn is running now, not one that is queued
    /// behind it. A delivery that found the session working (`busy`) takes its turn after that one finishes, so its turn is
    /// the session's `completedTurns` only then. Why not, as a refusal.
    func runningDelivery(session id: String, now: Date = Date()) -> Result<(entry: RouterDecision, delivery: RouterDecision.Delivered), RouterTools.Failure> {
        guard let session = claudeSessions[id], !session.isArchived, session.running else {
            return .failure(.init("The session isn't working now, so there is nothing to stop"))
        }
        let sent = router.decisions.filter { $0.delivered?.session == id }
        let current = sent.filter { entry in
            guard let d = entry.delivered, d.cancelled == nil, now.timeIntervalSince(d.at) < RouterDecision.Delivered.window else { return false }
            return session.completedTurns == d.turns + (d.busy ? 1 : 0)
        }
        if current.contains(where: { $0.delivered?.abortable == false })
            || (current.isEmpty && sent.contains(where: { $0.delivered?.abortable == false })) {
            return .failure(.init("Fjord's plugin in the session can't stop a turn"))
        }
        guard let entry = current.first, let delivery = entry.delivered else {
            return .failure(.init("Fjord can only stop a turn that a message sent through Fjord started, in the last few minutes, and none of its messages to the session is running now"))
        }
        guard current.count == 1 else {
            return .failure(.init("More than one message sent through Fjord could be the running turn; nothing was stopped"))
        }
        return .success((entry, delivery))
    }

    // MARK: Apply and Revert

    /// Performs an archive, reopen or mute as the user applied it. A stop goes through `applyStopChange`.
    func applyCardAction(_ action: CardAction) throws {
        switch action {
        case .archive(let card, let title, _):
            guard router.cards.first(where: { $0.id == card })?.isOpen == true else {
                throw RouterTools.Failure("“\(title)” isn't open any more")
            }
            setCardAddressed(card, true)
        case .reopen(let card, let title, _):
            try reopen(card, title)
        case .mute(let project, _, let muted):
            setFolderMuted(project, muted)
        case .stop:
            throw RouterTools.Failure("A stop is applied through its delivery")
        }
    }

    /// Puts back what an applied archive, reopen or mute did.
    func revertCardAction(_ action: CardAction) throws {
        switch action {
        case .archive(let card, let title, _):
            try reopen(card, title)
        case .reopen(let card, let title, _):
            guard router.cards.first(where: { $0.id == card })?.isOpen == true else { throw RouterTools.Failure("“\(title)” isn't open any more") }
            setCardAddressed(card, true)
        case .mute(let project, _, let muted):
            setFolderMuted(project, !muted)
        case .stop:
            throw RouterTools.Failure("A stop can't be undone")
        }
    }

    /// A card open again, unless that would replace its session's open card (`RouterFeed.reopen` supersedes the others).
    private func reopen(_ card: String, _ title: String) throws {
        guard let found = router.cards.first(where: { $0.id == card }), !found.isOpen, routerCanReopen(found) else {
            throw RouterTools.Failure("“\(title)” can't be reopened any more")
        }
        guard !router.cards.contains(where: { $0.sessionID == found.sessionID && $0.isOpen }) else {
            throw RouterTools.Failure("Its session has another open card now; reopening “\(title)” would replace it")
        }
        setCardAddressed(card, false)
    }

    /// Applies a waiting stop: the turn is checked again (still the running delivery), then the session's plugin is told, with
    /// the same check made once more right before the abort is written. The click is the authority, so nothing else is asked.
    /// A refusal or a failure leaves the change waiting, saying why.
    @discardableResult
    func applyStopChange(_ id: UUID) async -> FjordChange? {
        guard let i = router.changes.firstIndex(where: { $0.id == id }), router.changes[i].isPending,
              case .cardAction(.stop(let session, let title, _, let nonce)) = router.changes[i].patch,
              !stopsApplying.contains(id) else { return nil }
        stopsApplying.insert(id)
        defer { stopsApplying.remove(id) }
        func fail(_ note: String) -> FjordChange? {
            guard let i = router.changes.firstIndex(where: { $0.id == id }) else { return nil }
            router.changes[i].revertNote = note
            return router.changes[i]
        }
        func check() -> (entry: RouterDecision, delivery: RouterDecision.Delivered)? {
            if case .success(let found) = runningDelivery(session: session), found.delivery.nonce == nonce { return found }
            return nil
        }
        guard let found = check() else { return fail("“\(title)” isn't running that turn any more, so there is nothing to stop") }
        let gate: @MainActor @Sendable () -> String? = { [weak self] in
            guard let self else { return "Fjord is closing" }
            guard self.routerOn else { return "The Router is off" }
            return self.router.changes.first(where: { $0.id == id })?.isPending == true && check() != nil
                ? nil : "The turn isn't running any more"
        }
        let how: RouterDecision.Cancelled
        do {
            how = try await (deliveryCanceller ?? { try await self.cancelDelivery($0, gate: $1) })(found.delivery, gate)
        } catch {
            return fail("Couldn't stop it: \(error.localizedDescription)")
        }
        updateDecision(found.entry.id) {
            guard $0.delivered?.nonce == nonce else { return }
            $0.delivered?.cancelled = how
            $0.add(.cancelled(how))
        }
        guard let i = router.changes.firstIndex(where: { $0.id == id }), router.changes[i].isPending else { return nil }
        router.changes[i].pending = nil
        router.changes[i].revertNote = how.stopped ? nil : "Not stopped: \(how.words)"
        return router.changes[i]
    }
}
