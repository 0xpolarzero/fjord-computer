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
            case .started(_, let project, let model, let effort):
                "started a session in \(project)" + ([model, effort].compactMap { $0 }.isEmpty ? "" : " (\([model, effort].compactMap { $0 }.joined(separator: ", ")))")
            case .changed(let id): "changed Lookout (\(id.uuidString.prefix(8)))"
            case .answered(let card): "answered \(card)"
            case .asked(let options): "asked which: " + options.joined(separator: " / ")
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
        case .started(_, let project, _, _): return "started in \(project)" + more
        case .changed: return "changed Lookout" + more
        case .answered: return "answered" + more
        case .asked: return "asked you" + more
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
        case .failed: return "exclamationmark.triangle"
        case nil: return "text.bubble"
        }
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
    /// Adds an entry, newest last; the oldest go past the cap.
    mutating func log(_ decision: RouterDecision) {
        decisions.append(decision)
        if decisions.count > RouterDecision.maxKept { decisions.removeFirst(decisions.count - RouterDecision.maxKept) }
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

    /// A change made in Lookout: part of the run under way, else an entry of its own.
    func logChange(_ change: LookoutChange, into run: UUID? = nil) {
        if let id = run ?? activeDecision, router.decisions.contains(where: { $0.id == id }) {
            updateDecision(id) { $0.add(.changed(change.id)) }
        } else {
            logDecision(RouterDecision(at: change.date, trigger: .system, decision: RouterDecision.Decided(intent: change.title),
                                       done: [.changed(change.id)], outcome: .done, links: .init(changes: [change.id])))
        }
    }

    /// After a revert: an entry whose changes are all taken back is reverted.
    func noteReverted(_ change: UUID) {
        guard let i = router.decisions.firstIndex(where: { $0.links.changes.contains(change) }) else { return }
        let all = router.decisions[i].links.changes.allSatisfy { id in
            router.chat.contains { $0.change?.id == id && $0.change?.isReverted == true }
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
