import Foundation

// The Router's actions on its own page, for words like "I'll do the theme one myself", "reopen the docs card", "mute
// microsandbox" and "stop the CI session": archive and reopen a card, mute a project, stop a running session's turn. None
// of them is done by the tool. Which card, project or session it is comes from what the model picked out of text that
// sessions wrote, so each is only proposed: a change that says exactly what will happen and waits for the user's Apply
// (`CardAction`, `FjordChange.pending`), with Revert after it for all but a stop.

extension RouterTools {
    /// The cards among `cards` that `query` means: its id (or its session's), or all the words in its title.
    private func cardHits(_ query: String, in cards: [RouterCard]) -> [RouterCard] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = q.lowercased().split(whereSeparator: \.isWhitespace)
        return cards.filter { card in
            card.sessionID == q || card.id == q || (!words.isEmpty && words.allSatisfy { card.title.lowercased().contains($0) })
        }
    }

    /// The one card `query` means among `cards`, or why not.
    private func oneCard(_ query: String, in cards: [RouterCard], what: String) -> Result<RouterCard, Failure> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = cardHits(q, in: cards)
        guard let card = hits.first else { return .failure(Failure("“\(q)”: no \(what) by that name")) }
        guard hits.count == 1 || hits.allSatisfy({ $0.sessionID == card.sessionID }) else {
            let choices = hits.prefix(5).map { "“\(Self.short($0.title, 60))”" }.joined(separator: ", ")
            return .failure(Failure("“\(q)”: more than one \(what) matches (\(choices)); ask the user which"))
        }
        return .success(card)
    }

    /// Records `action` as a change waiting for the user's Apply, unless the same one already waits: then nothing is added.
    /// The title of the proposal when it was made (or the one already waiting).
    private func propose(_ store: Store, _ action: CardAction) -> String {
        let patch = FjordChange.Patch.cardAction(action)
        if let waiting = store.router.changes.first(where: { $0.isPending && $0.patch == patch }) { return waiting.title }
        var change = FjordChange(title: action.title, patch: patch)
        change.pending = action.waitingReason
        record(store, change)
        return change.title
    }

    private func proposed(_ titles: [String], refused: [String], what: String) -> String {
        var out: [String: Any] = [
            "changed": "nothing yet",
            "waiting": titles.map { Self.short($0, 160) },
            "note": "Not \(what) yet: each waits for the user's Apply on a card in the history (with Discard beside it); say in your reply that it waits for them.",
        ]
        if !refused.isEmpty { out["refused"] = refused }
        return Self.json(out)
    }

    // MARK: Archive and reopen

    /// Open Router cards proposed for archiving, as the Archive button would do it, once the user applies it.
    func archiveCards(_ store: Store, _ args: [String: Any]) throws -> String {
        let asked = try Self.strings(checked("archive_cards", args), "cards")
        guard !asked.isEmpty else { throw Failure("Name the cards to archive") }
        guard asked.count <= 5 else { throw Failure("At most 5 cards at a time") }
        var titles: [String] = [], refused: [String] = []
        for query in asked {
            switch oneCard(query, in: store.shownRouterCards, what: "open card") {
            case .failure(let why): refused.append(why.message)
            case .success(let card):
                titles.append(propose(store, .archive(card: card.id, title: UntrustedText.clean(card.title, limit: 60), project: UntrustedText.clean(store.routerProject(card).name, limit: 40))))
            }
        }
        if titles.isEmpty { throw Failure("Nothing proposed: " + refused.joined(separator: "; ")) }
        return proposed(titles, refused: refused, what: "archived")
    }

    /// The cards archived lately that Reopen can bring back, newest first.
    func reopenable(_ store: Store, limit: Int = 10) -> [RouterCard] {
        Array(store.router.cards.filter { store.routerCanReopen($0) }
            .sorted { ($0.addressedAt ?? .distantPast) > ($1.addressedAt ?? .distantPast) }.prefix(limit))
    }

    /// A card archived lately, proposed for reopening. Reopening replaces its session's open card (a session has one), so a
    /// card whose session has another open one is refused, with why.
    func reopenCard(_ store: Store, _ args: [String: Any]) throws -> String {
        let query = try Self.string(checked("reopen_card", args), "card")
        switch oneCard(query, in: reopenable(store), what: "recently archived card") {
        case .failure(let why): throw why
        case .success(let card):
            if let open = store.router.cards.first(where: { $0.sessionID == card.sessionID && $0.isOpen }) {
                throw Failure("“\(Self.short(card.title, 60))” can't be reopened: its session has another open card (“\(Self.short(open.title, 60))”), which reopening would replace; nothing was proposed")
            }
            return proposed([propose(store, .reopen(card: card.id, title: UntrustedText.clean(card.title, limit: 60), project: UntrustedText.clean(store.routerProject(card).name, limit: 40)))],
                            refused: [], what: "reopened")
        }
    }

    // MARK: Mute

    /// A project's sessions proposed for muting or unmuting in the Router. The project is the Router's own (a guest session's
    /// project, not its host mirror folder), by the name the lists show, a path above it included.
    func muteProject(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("mute_project", args)
        let query = try Self.string(args, "project").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let muted = args["muted"] as? Bool else { throw Failure("`muted` must be true or false") }
        let projects = store.routerProjects()
        let lower = query.lowercased()
        var hits = projects.filter { $0.name.lowercased() == lower }
        if hits.isEmpty { hits = projects.filter { $0.name.lowercased().contains(lower) } }
        guard let hit = hits.first else {
            throw Failure("No project “\(query)”. Projects: " + projects.map { "“\(Self.short($0.name, 60))”" }.joined(separator: ", "))
        }
        guard hits.count == 1 else {
            throw Failure("“\(query)” fits more than one project (" + hits.map { "“\(Self.short($0.name, 60))”" }.joined(separator: ", ")
                          + "); ask the user which")
        }
        guard store.isFolderMuted(hit.key) != muted else {
            return Self.json(["changed": "nothing", "note": "“\(Self.short(hit.name, 60))” already is \(muted ? "muted" : "unmuted")."])
        }
        return proposed([propose(store, .mute(project: hit.key, name: UntrustedText.clean(hit.name, limit: 80), muted: muted))], refused: [], what: muted ? "muted" : "unmuted")
    }

    // MARK: Stop

    /// A running session's current turn, proposed for stopping. Fjord can take back only a delivery of its own (the plugin's
    /// `abort-v1` names the delivery), so it is the turn that a message sent through Fjord started and that is running now,
    /// not one queued behind it; any other, or a session whose plugin can't, is refused with why. Nothing is sent until the
    /// user applies it, and Apply checks that turn again.
    func stopSession(_ store: Store, _ args: [String: Any]) throws -> String {
        let query = try Self.string(checked("stop_session", args), "session").trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let live = store.claudeSessions.values.filter { !$0.isArchived }
        let hits = live.filter { s in s.id == query || (!words.isEmpty && words.allSatisfy { s.title.lowercased().contains($0) }) }
            .sorted { $0.lastActivity > $1.lastActivity }
        guard let session = hits.first else { throw Failure("“\(query)”: no session by that name") }
        let running = hits.filter(\.running)
        guard hits.count == 1 || running.count == 1 else {
            throw Failure("“\(query)” fits more than one session (" + hits.prefix(5).map { "“\(Self.short($0.title, 60))”" }.joined(separator: ", ")
                          + "); ask the user which")
        }
        let target = hits.count == 1 ? session : running[0]
        switch store.runningDelivery(session: target.id) {
        case .failure(let why):
            throw Failure("“\(Self.short(target.title, 60))”: \(why.message); nothing was proposed")
        case .success(let found):
            let title = propose(store, .stop(session: target.id, title: UntrustedText.clean(target.title, limit: 60), decision: found.entry.id, nonce: found.delivery.nonce))
            return proposed([title], refused: [], what: "stopped")
        }
    }
}
