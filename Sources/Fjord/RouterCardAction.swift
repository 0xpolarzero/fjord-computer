import Foundation

// What the user does on the Router page to a card or a project: archive or reopen a card, mute or unmute a project. Each is
// done at once, as a change recorded as applied (`FjordChange`, `.cardAction`) with Revert on its history card, so the
// history shows it and takes it back. Nothing waits for an Apply.

/// One action on the Router page, as a proposed change records it.
enum CardAction: Codable, Hashable {
    /// `card`: the card's id. `project`: how the lists name its project.
    case archive(card: String, title: String, project: String)
    case reopen(card: String, title: String, project: String)
    /// `project`: the canonical Router project key (`Store.routerProjectGroupKey`), which `mutedFolders` holds.
    case mute(project: String, name: String, muted: Bool)

    var isMute: Bool { if case .mute = self { true } else { false } }

    var symbol: String {
        switch self {
        case .archive: "archivebox"
        case .reopen: "arrow.uturn.backward"
        case .mute(_, _, let muted): muted ? "bell.slash" : "bell"
        }
    }

    /// The change's one line.
    var title: String {
        switch self {
        case .archive(_, let title, let project): "Archive “\(title)” (\(project))"
        case .reopen(_, let title, let project): "Reopen “\(title)” (\(project))"
        case .mute(_, let name, let muted): "\(muted ? "Mute" : "Unmute") project \(name)"
        }
    }

    var before: String {
        switch self {
        case .archive(_, let title, _): "“\(title)”: open on the Router page"
        case .reopen(_, let title, _): "“\(title)”: archived"
        case .mute(_, let name, let muted): "\(name): \(muted ? "not muted" : "muted")"
        }
    }

    var after: String {
        switch self {
        case .archive(_, let title, _): "“\(title)”: archived, in the history"
        case .reopen(_, let title, _): "“\(title)”: open on the Router page again"
        case .mute(_, let name, let muted): "\(name): \(muted ? "muted" : "not muted")"
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

    /// The sessions whose Router project is muted, which the session-side readers (the sessions list, notifications, the
    /// feed) skip. A session belongs to its canonical project key (`routerProjectGroupKey`: a guest session's project is
    /// `guest-project:…`, a local one's is its folder), so two guest projects sharing a host mirror folder are muted apart.
    /// The answer is kept until the muted keys, the guest starts or the sessions' folders change.
    func mutedSessionIDs(_ muted: [String]? = nil, among sessions: [ClaudeSession]? = nil) -> Set<String> {
        let muted = muted ?? agents.mutedFolders
        guard !muted.isEmpty else { return [] }
        let sessions = sessions ?? Array(claudeSessions.values)
        let folders = Dictionary(sessions.map { ($0.id, $0.folderKey) }, uniquingKeysWith: { a, _ in a })
        let starts = router.pendingDesktopStarts
        if let cache = mutedIDsCache, cache.muted == muted, cache.starts == starts, cache.folders == folders { return cache.result }
        // The first matched start of a session names its project, as `routerProjectGroupKey` finds it.
        var guestKeys: [String: String] = [:]
        for start in starts where start.state == .matched {
            guard let id = start.desktopSessionID, guestKeys[id] == nil else { continue }
            guestKeys[id] = "guest-project:\(start.projectID.uuidString):\(start.location.key):\(start.folder)"
        }
        let keys = Set(muted)
        let result = Set(folders.compactMap { id, folder in keys.contains(guestKeys[id] ?? folder) ? id : nil })
        mutedIDsCache = (muted, starts, folders, result)
        return result
    }

    // MARK: Apply and Revert

    /// Performs an archive, reopen or mute.
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
        }
    }

    /// Does `action` now and records it as an applied change with Revert, in the history. Nil (nothing recorded) when it
    /// can't be done any more, or changes nothing (muting a muted project). `run`: the Router's run that did it, whose line
    /// the change joins (as `done` says, else as a change of Fjord) rather than an entry of its own.
    @discardableResult
    func act(_ action: CardAction, now: Date = Date(), into run: UUID? = nil, as done: ((FjordChange) -> RouterDecision.Done)? = nil) -> FjordChange? {
        if case .mute(let project, _, let muted) = action, isFolderMuted(project) == muted { return nil }
        do { try applyCardAction(action) } catch { return nil }
        let change = FjordChange(date: now, title: action.title, patch: .cardAction(action))
        var state = router
        state.changes.append(change)
        RouterFeed.prune(&state)
        router = state
        logChange(change, into: run, as: done?(change))
        return change
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
}
