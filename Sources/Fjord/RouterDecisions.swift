import Foundation

// The Router's decision log (docs/design/spec/router.md): one entry per run: what set it off, what was decided, what was
// done, and how it ended. It is the Router's history on the page, and its last entries are context for later runs.

struct RouterDecision: Codable, Identifiable, Equatable {
    enum Trigger: Codable, Equatable {
        /// Your message, or something you did on a card (what it was, in words).
        case you(String)
        /// An inbox action that started a session itself, as it did before its message went through the Router: its category
        /// and thing (names), the action, and its run. Only in entries from before; an action's message now is `.you`, with
        /// `fromAction`.
        case action(category: String, thing: String, actionID: String, runID: String?)
        /// A session did something the Router acted on.
        case session(sessionID: String, event: String)
        /// Fjord itself (a change with no message behind it).
        case system
    }

    /// What was decided: the target, the intent or label, and how sure when it was classified.
    struct Decided: Codable, Equatable {
        var target: String?
        var intent: String?
        var label: String?
        var confidence: Double?
        /// You went with the target: Jev's pick shown while you typed (sent as it was, or clicked), his suggestion picked on
        /// an ask, or a target you pinned. An example for the next routings, as corrections are.
        var confirmed: Bool?
        /// The target itself (`session:<id>`, `answer:<card>`, `new:<folder>`, an intent), and on a correction the one Jev
        /// suggested: what examples name it by, as titles can be shared or change. Nil in entries from before.
        var targetID: String?
        var fromID: String?
        init(target: String? = nil, intent: String? = nil, label: String? = nil, confidence: Double? = nil) {
            self.target = target
            self.intent = intent
            self.label = label
            self.confidence = confidence
        }
    }

    enum Done: Codable, Equatable {
        /// Your words went to a session (or started one): what `lastTold` reads.
        var sendsWords: Bool {
            switch self {
            case .sent, .started, .interrupted: true
            default: false
            }
        }

        /// A message sent to a session, with what you wrote when it was rephrased.
        case sent(to: String, text: String, original: String?)
        case started(session: String?, project: String, model: String?, effort: String?)
        /// A prefilled guest session handed off to Claude Desktop, without a local peer or first delivery.
        case preparedGuest(project: String, location: String, pendingStart: String)
        case changed(UUID)
        /// A card answered or marked handled (its id).
        case answered(card: String)
        /// The Router asked you which of these.
        case asked([String])
        /// A card your message resolved, by Jev's judgement (its title, and what you wrote).
        case resolved(card: String, message: String)
        case failed(String)
        /// A message sent here taken back (`RouterDispatcher.cancel`): how far it had gone.
        case cancelled(Cancelled)
        /// A card archived at once on the words (`RouterActionChecks`), its change (with Revert) and the card's title.
        case archived(title: String, change: UUID)
        /// A session's running turn stopped on the words: the session's title and project, and when the turn began.
        case stopped(title: String, project: String, since: Date?)
        /// A running turn stopped and the words sent as the session's next message (`stopped`: one was running).
        case interrupted(title: String, text: String, stopped: Bool)
    }

    /// How a cancel went, as the session's plugin answered it.
    enum Cancelled: String, Codable, Equatable {
        /// Claude hadn't started on it: it never will.
        case beforeStart = "before-start"
        /// Claude was working on it: the turn was stopped.
        case aborted
        /// Its turn was already over.
        case tooLate = "too-late"
        /// Claude read it together with words you typed in that session yourself: not stopped, so neither are they.
        case together
        /// The session's plugin was reloaded since it took it: it can't tell.
        case unknown

        /// The plugin's ack ("ok aborted"); nil for anything else.
        init?(ack: String) {
            guard ack.hasPrefix("ok "), let how = Self(rawValue: String(ack.dropFirst(3))) else { return nil }
            self = how
        }

        /// Whether the message was stopped.
        var stopped: Bool { self == .beforeStart || self == .aborted }

        var words: String {
            switch self {
            case .beforeStart: "cancelled before Claude started on it"
            case .aborted: "cancelled: Claude stopped working on it; what it already did stays done, and a command it was running finishes unseen"
            case .tooLate: "too late to cancel: Claude had finished with it"
            case .together: "not cancelled: Claude read it together with words you typed there, which a cancel would stop too"
            case .unknown: "couldn't tell whether it was cancelled: Fjord's plugin in the session was reloaded since"
            }
        }
    }

    /// The message a send put in a session, so it can be taken back (`RouterDispatcher.cancel`): the session (Fjord's
    /// id, and Claude Code's, which its inbox goes by), the delivery's nonce, when, how many turns the session had
    /// finished then and whether one was running, whether its plugin takes aborts, and how a cancel went. Nil for
    /// anything else and in entries from before.
    struct Delivered: Codable, Equatable {
        var session: String
        var cli: String
        var nonce: String
        var at: Date
        var turns: Int
        var busy: Bool
        var abortable: Bool
        var cancelled: Cancelled?

        /// How long a Cancel is offered after a send: past it, the turn has nearly always finished.
        static let window: TimeInterval = 10 * 60

        /// Whether a Cancel can still stop it, as Fjord sees the session (`now`, and its turns finished now): not
        /// cancelled yet, its plugin takes aborts, sent within `window`, the session not archived, and its turn not
        /// seen to finish (the one it waited behind, then its own). A session Fjord hasn't read yet (one just started)
        /// is given the window. The plugin has the last word: a turn over meanwhile is told as too late.
        func cancellable(session: ClaudeSession?, now: Date) -> Bool {
            guard cancelled == nil, abortable, now.timeIntervalSince(at) < Self.window else { return false }
            guard let session else { return true }
            return !session.isArchived && session.completedTurns < turns + (busy ? 2 : 1)
        }
    }

    enum Outcome: Codable, Equatable {
        case done
        case reverted
        /// You chose something other than what was suggested.
        case corrected(from: String, to: String)
        case pending
    }

    struct Links: Codable, Equatable {
        var sessions: [String] = []
        var cards: [String] = []
        var changes: [UUID] = []
    }

    var id = UUID()
    var at: Date
    var trigger: Trigger
    var decision = Decided()
    var done: [Done] = []
    var outcome: Outcome = .pending
    var links = Links()
    /// What a typed run said back (shown when the line opens), and the one phrase it gave for what it did.
    var reply: String?
    var note: String?
    /// The last message it sent to a session, for a Cancel.
    var delivered: Delivered?
    /// The pills of your message (`.you`), drawn where their "@name" is; nil for anything else and in entries from before.
    var mentions: [RouterMention]?
    /// A message a category's "Then" sent for a thing (your prompt, `.you`): the category, the thing, the action and its run.
    /// Nil for anything else.
    var fromAction: SessionOrigin?
    /// The same message's session settings: what a session the Router starts for it is called and runs on. Nil for anything
    /// else, and in entries from before (the thing's line is the title then, on your defaults).
    var actionStart: ActionStart?
    /// The decision whose compound message this one is a session part of (`RouterDispatcher.think`): it waited for your pick,
    /// and is yours like any message you sent. Nil for anything else.
    var splitFrom: UUID?
    /// No longer set: parts of a compound message wait for your pick and are then your decisions, linked by `splitFrom`.
    /// Kept so entries from before still decode.
    var generated: Bool?
    /// What a part inherits from the message it was split from, to rank it within the same scope (and again when it is sent
    /// elsewhere): the projects and pointers of the original.
    var inherited: Inherited?

    struct Inherited: Codable, Equatable {
        var projects: [String]
        var mentions: [RouterMention]
    }

    struct ActionStart: Codable, Equatable {
        var title: String
        var model: String?
        var effort: String?
    }

    /// Where an action's message came from and what a session started for it is (`RouterContext.action`), as it was sent:
    /// what sending it elsewhere goes with again.
    var actionSource: RouterActionSource? {
        fromAction.map { origin in
            RouterActionSource(origin: origin, title: actionStart?.title ?? origin.thing, model: actionStart?.model,
                               effort: actionStart?.effort)
        }
    }
    /// Its message was stopped where it was sent (a Cancel that wasn't too late).
    var isCancelled: Bool { delivered?.cancelled?.stopped == true }

    init(id: UUID = UUID(), at: Date = Date(), trigger: Trigger, decision: Decided = Decided(), done: [Done] = [],
         outcome: Outcome = .pending, links: Links = Links()) {
        self.id = id
        self.at = at
        self.trigger = trigger
        self.decision = decision
        self.done = done
        self.outcome = outcome
        self.links = links
    }

    static let maxKept = 1000

    /// Adds `done` and the links it implies.
    mutating func add(_ item: Done, session: String? = nil, card: String? = nil) {
        done.append(item)
        switch item {
        case .changed(let id), .archived(_, let id): if !links.changes.contains(id) { links.changes.append(id) }
        default: break
        }
        if let session, !links.sessions.contains(session) { links.sessions.append(session) }
        if let card, !links.cards.contains(card) { links.cards.append(card) }
    }

    // MARK: Words

    /// What set it off, in a line.
    var triggerText: String {
        switch trigger {
        case .you(let text): fromAction.map { "\($0.category) · " + text } ?? text
        case .action(let category, let thing, _, _): "From \(category) · \(thing)"
        case .session(_, let event): event
        case .system: "Fjord"
        }
    }

    /// What was done, one phrase per item.
    var doneLines: [String] { lines(forModel: false) }

    /// `doneLines`, worded for a model (the user, not "you") when `forModel`.
    func lines(forModel: Bool) -> [String] {
        done.map { item in
            switch item {
            case .sent(let to, let text, _): "sent to \(to): \(Self.clip(text, 80))"
            case .started(_, let project, let model, let effort): "started a session in \(project)" + settingsWords(model, effort)
            case .preparedGuest(let project, let location, _): "ready in Claude · \(project) on \(location)"
            case .changed(let id): "changed Fjord (\(id.uuidString.prefix(8)))"
            case .answered(let card): "answered \(card)"
            case .asked(let options): "asked which: " + options.joined(separator: " / ")
            case .resolved(let card, let message): "closed \(card) by \(forModel ? "the user\'s" : "your") message: \(Self.clip(message, 80))"
            case .failed(let reason): "failed: \(reason)"
            case .cancelled(let how): how.words
            case .archived(let title, _): "archived “\(Self.clip(title, 60))”"
            case .stopped(let title, let project, let since):
                "stopped “\(Self.clip(title, 60))” (\(project)" + (since.map { ", since \(Self.clock($0))" } ?? "") + ")"
            case .interrupted(let title, let text, let stopped):
                (stopped ? "interrupted" : "sent to") + " “\(Self.clip(title, 60))”" + (stopped ? " and sent: " : ": ") + Self.clip(text, 80)
            }
        }
    }

    /// The short phrase after the trigger on the history line: what happened, or how it ended.
    var summary: String {
        switch outcome {
        case .reverted: return "reverted"
        case .corrected(_, let to): return "corrected to \(to)"
        default: break
        }
        if isCancelled { return "cancelled" }
        guard let first = done.first else { return note.map { Self.clip($0, 80) } ?? (outcome == .pending ? "working" : "replied") }
        let more = done.count > 1 ? " +\(done.count - 1)" : ""
        switch first {
        case .sent(let to, _, _): return "sent to \(to)" + more
        case .started(_, let project, let model, let effort): return "started in \(project)" + settingsWords(model, effort) + more
        case .preparedGuest(let project, _, _): return "ready in Claude · \(project)" + more
        case .changed: return "changed Fjord" + more
        case .answered: return "answered" + more
        case .asked: return "asked you" + more
        case .resolved: return "addressed a card" + more
        case .failed: return "failed" + more
        case .cancelled: return "cancelled" + more
        case .archived: return "archived" + more
        case .stopped: return "stopped" + more
        case .interrupted(_, _, let stopped): return (stopped ? "interrupted" : "sent") + more
        }
    }

    /// "09:41": when a stopped turn began.
    static func clock(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }

    var symbol: String {
        if outcome == .reverted { return "arrow.uturn.backward" }
        if isCancelled, outcome == .done || outcome == .pending { return "xmark.circle" }
        if case .action = trigger { return "bolt" }
        // An action's message, before anything is done with it.
        if fromAction != nil, done.isEmpty { return "bolt" }
        switch done.first {
        case .sent: return "paperplane"
        case .started: return "plus.square"
        case .preparedGuest: return "desktopcomputer"
        case .changed: return "slider.horizontal.3"
        case .answered: return "checkmark"
        case .asked: return "questionmark.bubble"
        case .resolved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .archived: return "archivebox"
        case .stopped: return "stop.circle"
        case .interrupted: return "paperplane"
        case nil: return "text.bubble"
        }
    }

    /// " (opus, high)", or nothing.
    private func settingsWords(_ model: String?, _ effort: String?) -> String {
        let set = [model, effort].compactMap { $0 }
        guard !set.isEmpty else { return "" }
        return " (" + set.joined(separator: ", ") + ")"
    }

    static func clip(_ text: String, _ n: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > n ? String(line.prefix(n - 1)) + "…" : line
    }

    /// One line for a model's context: "2m ago · you: "…" → sent to X", with a correction named as yours.
    func contextLine(now: Date) -> String {
        let age = shortAgo(at, now: now)
        let when = age == "now" ? "just now" : age.first?.isNumber == true && age.last?.isLetter == true ? "\(age) ago" : age
        let who: String
        switch trigger {
        case .you(let text):
            who = fromAction.map { "action of the category “\(UntrustedText.clean($0.category, limit: 40))”, the user's prompt: “\(Self.clip(text, 100))”" }
                ?? "the user: “\(Self.clip(text, 100))”"
        case .action(let category, let thing, _, _): who = "action of the category “\(UntrustedText.clean(category, limit: 40))” · \(UntrustedText.clean(thing, limit: 80))"
        case .session(_, let event): who = "session: \(Self.clip(event, 100))"
        case .system: who = "Fjord"
        }
        var parts = [who]
        if let target = decision.target { parts.append("target \(target)") }
        if let intent = decision.intent ?? decision.label { parts.append(intent) }
        let did = lines(forModel: true)
        if !did.isEmpty { parts.append(did.joined(separator: "; ")) }
        var line = "\(when) · " + parts.joined(separator: " → ")
        switch outcome {
        case .reverted: line += " (the user reverted this)"
        case .corrected(let from, let to): line += " (the user corrected this: not \(from), but \(to))"
        case .pending, .done: break
        }
        return line
    }
}

// MARK: - Store

extension RouterState {
    /// Adds an entry, newest last; the oldest go past the cap, but never one linking a change still waiting for your Apply
    /// or Discard (its only place on the page), nor an action's message still under way (its run follows it), nor one whose ask-back card is still up (`inUse`).
    mutating func log(_ decision: RouterDecision, inUse: Set<UUID> = []) {
        decisions.append(decision)
        guard decisions.count > RouterDecision.maxKept else { return }
        let waiting = Set(changes.filter(\.isPending).map(\.id))
        var over = decisions.count - RouterDecision.maxKept
        decisions = decisions.filter { entry in
            guard over > 0, !entry.links.changes.contains(where: waiting.contains),
                  entry.fromAction == nil || entry.outcome != .pending, !inUse.contains(entry.id) else { return true }
            over -= 1
            return false
        }
    }
}

extension RouterState {
    /// Runs and asks still under way when the app quit (quitting can't wait for them to settle) can't go on in this launch:
    /// they say they were interrupted, rather than "working…" for ever.
    mutating func settleInterrupted() {
        for i in decisions.indices where decisions[i].outcome == .pending {
            // A start whose first message was held for the session to run: the session is there, the message never went.
            let held = decisions[i].done.contains { if case .started = $0 { true } else { false } }
            let guestPrepared = decisions[i].done.contains { if case .preparedGuest = $0 { true } else { false } }
            if !guestPrepared {
                decisions[i].add(.failed(held ? "its first message wasn't sent: Fjord quit while it waited for the session to run" : "interrupted"))
            }
            decisions[i].outcome = .done
        }
    }

    /// A change waiting for your Apply or Discard, or one an older file kept in its chat, is reached only through an
    /// entry linking it: one whose entry was lost (unreadable) or never made gets an entry of Fjord's own, at its date.
    mutating func linkUnlinkedChanges(legacy: Set<UUID>) {
        let linked = Set(decisions.flatMap(\.links.changes))
        for change in changes where !linked.contains(change.id) && (change.isPending || legacy.contains(change.id)) {
            var entry = RouterDecision(at: change.date, trigger: .system, outcome: change.isReverted ? .reverted : .done)
            entry.add(.changed(change.id))
            decisions.insert(entry, at: decisions.firstIndex { $0.at > change.date } ?? decisions.endIndex)
        }
    }
}

extension Store {
    /// Records a decision and returns its id.
    @discardableResult
    func logDecision(_ decision: RouterDecision) -> UUID {
        var state = router
        state.log(decision, inUse: decisionsInUse())
        router = state
        return decision.id
    }

    /// Changes an entry in place (nothing if it has been pruned).
    func updateDecision(_ id: UUID, _ change: (inout RouterDecision) -> Void) {
        guard let i = router.decisions.firstIndex(where: { $0.id == id }) else { return }
        var decision = router.decisions[i]
        change(&decision)
        if decision != router.decisions[i] { router.decisions[i] = decision }
    }

    /// The last `count` decisions, oldest first, one line each: context for a model (or Jev).
    /// `excluding`: the entry of the run asking (it is the newest, and not yet history).
    func recentDecisions(_ count: Int = 10, now: Date = Date(), excluding: UUID? = nil) -> String {
        router.decisions.filter { $0.id != excluding }.suffix(count).map { $0.contextLine(now: now) }.joined(separator: "\n")
    }

    /// A change made in Fjord: part of the run under way, else an entry of its own.
    func logChange(_ change: FjordChange, into run: UUID? = nil, as done: RouterDecision.Done? = nil) {
        if let id = run, router.decisions.contains(where: { $0.id == id }) {
            updateDecision(id) { $0.add(done ?? .changed(change.id)) }
        } else {
            logDecision(RouterDecision(at: change.date, trigger: .system, decision: RouterDecision.Decided(intent: change.title),
                                       done: [.changed(change.id)], outcome: .done, links: .init(changes: [change.id])))
        }
    }

    /// A change that no longer exists (it cancelled out with a later one of its run): its entry forgets it, and goes
    /// when it was only that.
    func dropChange(_ change: UUID) {
        guard let i = router.decisions.firstIndex(where: { $0.links.changes.contains(change) }) else { return }
        var entry = router.decisions[i]
        entry.done.removeAll { $0 == .changed(change) }
        entry.links.changes.removeAll { $0 == change }
        if entry.done.isEmpty, entry.links.changes.isEmpty, entry.trigger == .system { router.decisions.remove(at: i) } else { router.decisions[i] = entry }
    }

    /// A change's record was merged with a later one: an entry made only for it says the new title.
    func retitleChange(_ change: UUID, from old: String, to new: String) {
        guard let i = router.decisions.firstIndex(where: { $0.links.changes == [change] && $0.trigger == .system }),
              router.decisions[i].decision.intent == old else { return }
        router.decisions[i].decision.intent = new
    }

    /// After a revert: an entry whose changes are all taken back is reverted.
    func noteReverted(_ change: UUID) {
        guard let i = router.decisions.firstIndex(where: { $0.links.changes.contains(change) }) else { return }
        let all = router.decisions[i].links.changes.allSatisfy { id in
            router.changes.contains { $0.id == id && $0.isReverted }
        }
        if all {
            updateDecision(router.decisions[i].id) { $0.outcome = .reverted }
            routerRunReverted(router.decisions[i].id)
        }
    }

    /// Something you did on a card from the page (answered its form, approved its plan, marked it handled).
    func logCardAction(_ text: String, card: String, done: RouterDecision.Done? = nil, now: Date = Date()) {
        let session = router.cards.first { $0.id == card }?.sessionID
        var entry = RouterDecision(at: now, trigger: .you(text), decision: .init(target: router.cards.first { $0.id == card }?.title,
                                                                                  intent: "answer"), outcome: .done)
        entry.add(done ?? .answered(card: router.cards.first { $0.id == card }?.title ?? card), session: session, card: card)
        logDecision(entry)
    }
}
