import Foundation

// The Router's decision log (docs/design/spec/router.md): one entry per run: what set it off, what was decided, what was
// done, and how it ended. It is the Router's history on the page, and its last entries are context for later runs.

struct RouterDecision: Codable, Identifiable, Equatable {
    enum Trigger: Codable, Equatable {
        /// Your message, or something you did on a card (what it was, in words).
        case you(String)
        /// An inbox action ("Ask the Router"): its category and thing (names), the action, and its run (the message's id).
        case action(category: String, thing: String, actionID: String, runID: String?)
        /// A session did something the Router acted on.
        case session(sessionID: String, event: String)
        /// Lookout itself (a change with no message behind it).
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
        /// Who picked a new session's model and effort when you named none ("Jev").
        var settingsBy: String?
        init(target: String? = nil, intent: String? = nil, label: String? = nil, confidence: Double? = nil) {
            self.target = target
            self.intent = intent
            self.label = label
            self.confidence = confidence
        }
    }

    enum Done: Codable, Equatable {
        /// A message sent to a session, with what you wrote when it was rephrased.
        case sent(to: String, text: String, original: String?)
        case started(session: String?, project: String, model: String?, effort: String?)
        case changed(UUID)
        /// A card answered or marked handled (its id).
        case answered(card: String)
        /// The Router asked you which of these.
        case asked([String])
        /// A card your message resolved, by Jev's judgement (its title, and what you wrote).
        case resolved(card: String, message: String)
        case failed(String)
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
        if case .changed(let id) = item, !links.changes.contains(id) { links.changes.append(id) }
        if let session, !links.sessions.contains(session) { links.sessions.append(session) }
        if let card, !links.cards.contains(card) { links.cards.append(card) }
    }

    // MARK: Words

    /// What set it off, in a line.
    var triggerText: String {
        switch trigger {
        case .you(let text): text
        case .action(let category, let thing, _, _): "From \(category) · \(thing)"
        case .session(_, let event): event
        case .system: "Lookout"
        }
    }

    /// What was done, one phrase per item.
    var doneLines: [String] {
        done.map { item in
            switch item {
            case .sent(let to, let text, _): "sent to \(to): \(Self.clip(text, 80))"
            case .started(_, let project, let model, let effort): "started a session in \(project)" + settingsWords(model, effort)
            case .changed(let id): "changed Lookout (\(id.uuidString.prefix(8)))"
            case .answered(let card): "answered \(card)"
            case .asked(let options): "asked which: " + options.joined(separator: " / ")
            case .resolved(let card, let message): "addressed \(card) by your message: \(Self.clip(message, 80))"
            case .failed(let reason): "failed: \(reason)"
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
        guard let first = done.first else { return note.map { Self.clip($0, 80) } ?? (outcome == .pending ? "working" : "replied") }
        let more = done.count > 1 ? " +\(done.count - 1)" : ""
        switch first {
        case .sent(let to, _, _): return "sent to \(to)" + more
        case .started(_, let project, let model, let effort): return "started in \(project)" + settingsWords(model, effort) + more
        case .changed: return "changed Lookout" + more
        case .answered: return "answered" + more
        case .asked: return "asked you" + more
        case .resolved: return "addressed a card" + more
        case .failed: return "failed" + more
        }
    }

    var symbol: String {
        if outcome == .reverted { return "arrow.uturn.backward" }
        if case .action = trigger { return "bolt" }
        switch done.first {
        case .sent: return "paperplane"
        case .started: return "plus.square"
        case .changed: return "slider.horizontal.3"
        case .answered: return "checkmark"
        case .asked: return "questionmark.bubble"
        case .resolved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case nil: return "text.bubble"
        }
    }

    /// " (haiku, low · picked by Jev)", " (opus, high)", or nothing.
    private func settingsWords(_ model: String?, _ effort: String?) -> String {
        let set = [model, effort].compactMap { $0 }
        guard !set.isEmpty else { return "" }
        return " (" + set.joined(separator: ", ") + (decision.settingsBy.map { " · picked by \($0)" } ?? "") + ")"
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
        case .you(let text): who = "you: “\(Self.clip(text, 100))”"
        case .action(let category, let thing, _, _): who = "action \(category) · \(thing)"
        case .session(_, let event): who = "session: \(Self.clip(event, 100))"
        case .system: who = "lookout"
        }
        var parts = [who]
        if let target = decision.target { parts.append("target \(target)") }
        if let intent = decision.intent ?? decision.label { parts.append(intent) }
        let did = doneLines
        if !did.isEmpty { parts.append(did.joined(separator: "; ")) }
        var line = "\(when) · " + parts.joined(separator: " → ")
        switch outcome {
        case .reverted: line += " (you reverted this)"
        case .corrected(let from, let to): line += " (you corrected this: not \(from), but \(to))"
        case .pending, .done: break
        }
        return line
    }
}

// MARK: - Store

extension RouterState {
    /// Adds an entry, newest last; the oldest go past the cap, but never one linking a change still waiting for your Apply
    /// or Discard (its only place on the page).
    mutating func log(_ decision: RouterDecision) {
        decisions.append(decision)
        guard decisions.count > RouterDecision.maxKept else { return }
        let waiting = Set(changes.filter(\.isPending).map(\.id))
        var over = decisions.count - RouterDecision.maxKept
        decisions = decisions.filter { entry in
            guard over > 0, !entry.links.changes.contains(where: waiting.contains) else { return true }
            over -= 1
            return false
        }
    }
}

extension Store {
    /// Records a decision and returns its id.
    @discardableResult
    func logDecision(_ decision: RouterDecision) -> UUID {
        var state = router
        state.log(decision)
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

    /// How you routed messages before, for Jev, oldest first, one short line each: your corrections (an ask answered with
    /// something else than his suggestion), then a few targets you went with (his pick shown while you typed, his suggestion
    /// on an ask, a target you pinned). At most `limit` lines, the newest; at most a third of them confirmations. The same
    /// words count once, by their newest example: an entry that is neither (a run under way, an ask waiting) hides nothing.
    /// `excluding`: the entry of the run asking. `keys`: a target's option key by its description, said instead of it.
    func routingExamples(limit: Int = 8, now: Date = Date(), excluding: UUID? = nil, keys: [String: String] = [:]) -> String {
        func named(_ target: String) -> String { keys[target] ?? RouterDecision.clip(target, 60) }
        var corrections: [(Date, String)] = [], confirmed: [(Date, String)] = []
        var seen = Set<String>()
        for entry in router.decisions.reversed() where corrections.count + confirmed.count < limit && entry.id != excluding {
            guard case .you(let text) = entry.trigger else { continue }
            let said = "“\(RouterDecision.clip(text, 60))”"
            if case .corrected(let from, let to) = entry.outcome {
                guard seen.insert(text.lowercased()).inserted else { continue }
                corrections.append((entry.at, "\(said) → \(named(to)), not \(named(from))"))
            } else if entry.decision.confirmed == true, let target = entry.decision.target {
                guard seen.insert(text.lowercased()).inserted, confirmed.count < max(1, limit / 3) else { continue }
                confirmed.append((entry.at, "\(said) → \(named(target))"))
            }
        }
        return (corrections + confirmed).sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n")
    }

    /// A change made in Lookout: part of the run under way, else an entry of its own.
    func logChange(_ change: LookoutChange, into run: UUID? = nil) {
        if let id = run, router.decisions.contains(where: { $0.id == id }) {
            updateDecision(id) { $0.add(.changed(change.id)) }
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
        if all { updateDecision(router.decisions[i].id) { $0.outcome = .reverted } }
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
