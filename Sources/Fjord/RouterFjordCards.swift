import Foundation

// The Router's actions on its own page, for words like "I'll do the theme one myself", "reopen the docs card", "mute
// microsandbox" and "stop the CI session": archive and reopen a card, mute a project, stop a running session's turn. Each
// acts only on what the user's message names (`FjordGate.namesTitle`), whichever card, project or session the model picks,
// so words a session wrote can't have it archive, mute or stop something the user never mentioned.

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

    /// What the message says about `title`, as a refusal: nil when it names it.
    private func unnamed(_ title: String) -> Failure? {
        FjordGate.namesTitle(turnText ?? "", title: title) ? nil : Failure("The user's message doesn't name “\(Self.short(title, 60))”; nothing was done to it")
    }

    // MARK: Archive and reopen

    /// Open Router cards the user named, archived as the Archive button does, with its history line.
    func archiveCards(_ store: Store, _ args: [String: Any]) throws -> String {
        let asked = try Self.strings(checked("archive_cards", args), "cards")
        guard !asked.isEmpty else { throw Failure("Name the cards to archive") }
        guard asked.count <= 5 else { throw Failure("At most 5 cards at a time") }
        var done: [String] = [], refused: [String] = []
        for query in asked {
            switch oneCard(query, in: store.shownRouterCards, what: "open card") {
            case .failure(let why): refused.append(why.message)
            case .success(let card):
                if let why = unnamed(card.title) { refused.append(why.message); continue }
                store.setCardAddressed(card.id, true)
                store.logCardAction("Archived", card: card.id)
                done.append("“\(Self.short(card.title, 60))”")
            }
        }
        if done.isEmpty { throw Failure("Nothing archived: " + refused.joined(separator: "; ")) }
        return "Archived: " + done.joined(separator: ", ") + (refused.isEmpty ? "." : ". Not archived: " + refused.joined(separator: "; "))
    }

    /// The cards archived lately that Reopen can bring back, newest first.
    func reopenable(_ store: Store, limit: Int = 10) -> [RouterCard] {
        Array(store.router.cards.filter { store.routerCanReopen($0) }
            .sorted { ($0.addressedAt ?? .distantPast) > ($1.addressedAt ?? .distantPast) }.prefix(limit))
    }

    /// A card archived lately, open again.
    func reopenCard(_ store: Store, _ args: [String: Any]) throws -> String {
        let query = try Self.string(checked("reopen_card", args), "card")
        switch oneCard(query, in: reopenable(store), what: "recently archived card") {
        case .failure(let why): throw why
        case .success(let card):
            if let why = unnamed(card.title) { throw why }
            store.setCardAddressed(card.id, false)
            return "Reopened “\(Self.short(card.title, 60))”."
        }
    }

    // MARK: Mute

    /// A project's sessions muted or unmuted in the Router, when the message names the project and asks to.
    func muteProject(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("mute_project", args)
        let query = try Self.string(args, "project").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let muted = args["muted"] as? Bool else { throw Failure("`muted` must be true or false") }
        let projects = store.knownFolders.filter { !$0.isEmpty }.map { (folder: $0, name: store.folderName($0)) }
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
        let said = turnText ?? ""
        guard FjordGate.calls(said, hit.name) else { throw Failure("The user's message doesn't name the project “\(Self.short(hit.name, 60))”; nothing was changed") }
        guard FjordGate.asksToMute(said) else { throw Failure("The user's message doesn't ask to mute or unmute; nothing was changed") }
        guard store.isFolderMuted(hit.folder) != muted else {
            return Self.json(["changed": "nothing", "note": "“\(Self.short(hit.name, 60))” already is \(muted ? "muted" : "unmuted")."])
        }
        store.setFolderMuted(hit.folder, muted)
        return "\(muted ? "Muted" : "Unmuted") the project “\(Self.short(hit.name, 60))”."
    }

    // MARK: Stop

    /// A running session's current turn stopped, when the message names the session and asks to stop it. Fjord can take back
    /// only a delivery of its own (the plugin's `abort-v1` names the delivery), so it is the turn that a message sent through
    /// Fjord started; any other turn, or a session whose plugin can't, is refused with why.
    func stopSession(_ store: Store, _ args: [String: Any]) async throws -> String {
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
        let said = turnText ?? ""
        guard FjordGate.namesTitle(said, title: target.title) else { throw Failure("The user's message doesn't name “\(Self.short(target.title, 60))”; nothing was stopped") }
        guard FjordGate.asksToStop(said) else { throw Failure("The user's message doesn't ask to stop or interrupt it; nothing was stopped") }
        guard target.running else { throw Failure("“\(Self.short(target.title, 60))” isn't working now, so there is nothing to stop") }
        let sent = store.router.decisions.filter { $0.delivered?.session == target.id }
        guard let entry = sent.last(where: { store.canCancel($0) }), let delivery = entry.delivered else {
            if sent.contains(where: { $0.delivered?.abortable == false }) {
                throw Failure("Fjord's plugin in “\(Self.short(target.title, 60))” can't stop a turn; nothing was stopped")
            }
            throw Failure("Fjord can only stop a turn that a message sent through Fjord started, in the last few minutes, and none of its messages to “\(Self.short(target.title, 60))” is running; nothing was stopped")
        }
        let how = try await (canceller ?? { try await store.cancelDelivery($0) })(delivery)
        store.updateDecision(entry.id) {
            guard $0.delivered?.nonce == delivery.nonce else { return }
            $0.delivered?.cancelled = how
            $0.add(.cancelled(how))
        }
        return how.stopped ? "Stopped “\(Self.short(target.title, 60))”: \(how.words)." : "Not stopped: \(how.words)."
    }
}
