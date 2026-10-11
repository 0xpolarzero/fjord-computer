import Foundation

// How the Router asks Jev where a message goes, and when his answer is acted on. Measured on 360 boards like yours
// (evals/router/README.md): one option per destination, named by the session and described by what it is doing and what
// you last told it; the message alone as the state; in the same call, whether the message answers each waiting card,
// whether it changes Lookout, whether it asks for several things.

extension RouterTools {
    /// Somewhere a message can go, as Jev reads it.
    struct Destination {
        /// What acting on it does: `answer:<card>` (a session with an open card: replying addresses it), `session:<id>`,
        /// `new:<folder>`, or an intent.
        var target: String
        /// The option's name: the session's title (with its project when titles repeat), "new session in <project>", an
        /// intent's name.
        var name: String
        /// The option's description: what kind of destination it is, its project, what it is doing now, what you last told it.
        var criteria: Any
        var sessionID: String?
    }

    /// A card waiting on you, asked about on its own: does the message answer it?
    struct Waiting {
        var target: String
        var sessionID: String
        var card: [String: Any]
    }

    static let intentCriteria: [(name: String, criteria: String)] = [
        ("change_lookout", "The user wants to change Lookout itself: its inbox categories, groups or settings"),
        ("question", "A question about what is going on now (cards, working sessions, the inbox, settings), not for any session"),
        ("compound", "Several different things in one message, such as changing Lookout and telling a session something"),
        ("unclear", "none of these: small talk, a fragment, or nothing says where it goes"),
    ]

    static let routeQuestion: [String: Any] = [
        "question": "Where does the user's `message` go?",
        "focus": "Decide about `message` alone; `earlier messages` only say what it refers to. A message addressed to a session (\"tell the CI one to…\", \"lcu: …\") goes to that existing session. A question about a session or about what is going on (\"is the CI one done?\") is `question`, not a message to the session. Start a new session only when the message asks for one or no existing session does that work.",
    ]

    static let answersInstructions = "Is `message` the user's answer to `card`: a reply to what it asks?"

    /// Checks that decide an intent before the route does: the route alone sent "turn off jev labels" to the session
    /// building that feature, and "commit it and add a category" to the session as a whole.
    static let gates: [String: JevClient.Question] = [
        "gate_setting": .structuredNoul(instructions: ["question": "Does `message` ask to change how Lookout behaves for the user (a setting turned on or off, its notifications, an inbox category, a rule or a group), rather than for code to be written or for a session to do something?"]),
        "gate_compound": .structuredNoul(instructions: ["question": "Does `message` ask for two or more different things, meant for different places (sessions or Lookout itself)?"]),
    ]

    private static let waitsOnYou: Set<RouterCard.Kind> = [.question, .plan, .asks, .approval]

    /// What Jev routes among: the sessions (working, then the 20 most recent others), the cards of sessions not among them,
    /// a new session per project, and the intents. `projects`: folders you tagged; only theirs then.
    func destinations(_ store: Store, projects: Set<String>? = nil, now: Date = Date()) -> [Destination] {
        let cards = store.routerShownOpenCards.filter { projects?.contains($0.folder ?? "") ?? true }
        let told = store.lastTold()
        let (working, recent) = candidates(store, projects: projects)
        let sessions = Array((working + recent).prefix(80))
        var named = Set(Self.intentCriteria.map(\.name))
        func unique(_ base: String) -> String {
            var name = base
            while !named.insert(JevClient.key(for: name)).inserted { name += "'" }
            return name
        }
        let repeated = Dictionary(grouping: sessions) { $0.title.lowercased() }.filter { $0.value.count > 1 }
        var out: [Destination] = []
        for s in sessions {
            let mine = cards.filter { $0.sessionID == s.id }.sorted { $0.createdAt < $1.createdAt }
            let project = store.folderName(s.folderKey)
            var title = Self.hinted(s.title, 80)
            if repeated[s.title.lowercased()] != nil { title += " (\(Self.hinted(project, 40)))" }
            var criteria: [String: Any] = ["kind": "Claude Code session", "project": Self.hinted(project, 80),
                                           "now": Self.status(store, session: s, cards: mine, now: now)]
            if let last = told[s.id] {
                criteria["the user last told it"] = "\(Self.hinted(last.text, 160)) (\(agoPhrase(last.at, now: now)))"
            }
            out.append(Destination(target: mine.last.map { "answer:\($0.id)" } ?? "session:\(s.id)", name: unique(title),
                                   criteria: criteria, sessionID: s.id))
        }
        // A card whose session isn't offered (gone from the list): itself.
        let offered = Set(sessions.map(\.id))
        for card in cards where !offered.contains(card.sessionID) {
            let criteria: [String: Any] = ["kind": "Claude Code session", "project": Self.hinted(store.folderName(card.folder ?? ""), 80),
                                           "now": Self.cardStatus(store, card) ?? "finished: \(Self.hinted(card.text, 300))"]
            out.append(Destination(target: "answer:\(card.id)", name: unique(Self.hinted(card.title, 80)), criteria: criteria,
                                   sessionID: card.sessionID))
        }
        for folder in store.knownFolders.filter({ !$0.isEmpty && (projects?.contains($0) ?? true) }).prefix(60) {
            let name = Self.hinted(store.folderName(folder), 80)
            out.append(Destination(target: "new:\(folder)", name: unique("new session in \(name)"),
                                   criteria: ["kind": "new session", "project": name]))
        }
        for intent in Self.intentCriteria {
            out.append(Destination(target: intent.name, name: intent.name, criteria: intent.criteria))
        }
        return out
    }

    /// The cards waiting on you among `destinations`, each with what it asks.
    func waiting(_ store: Store, among destinations: [Destination]) -> [Waiting] {
        let offered = Set(destinations.map(\.target))
        return store.routerShownOpenCards.filter { Self.waitsOnYou.contains($0.kind) && offered.contains("answer:\($0.id)") }
            .map { card in
                var asks: [String: Any] = ["session": Self.hinted(store.claudeSessions[card.sessionID]?.title ?? card.title, 80),
                                           "asks": Self.hinted(card.text, 400)]
                let options = store.pendingForm(for: card)?.questions.flatMap { $0.options.map { Self.hinted($0.label, 60) } } ?? []
                if !options.isEmpty { asks["options"] = options }
                return Waiting(target: "answer:\(card.id)", sessionID: card.sessionID, card: asks)
            }
    }

    /// What a session is doing now, in a line: what it waits on you for, else working on what, else when it finished
    /// and what it said.
    static func status(_ store: Store, session s: ClaudeSession, cards: [RouterCard], now: Date) -> String {
        if let waiting = cards.last(where: { waitsOnYou.contains($0.kind) }), let line = cardStatus(store, waiting) { return line }
        if s.running {
            let activity = store.claudeActivity[s.id]?.text ?? ""
            return activity.isEmpty ? "working" : "working: \(hinted(activity, 300))"
        }
        let last = cards.last { $0.kind == .done || $0.kind == .stuck || $0.kind == .waiting }
        let said = last?.text ?? s.summary?.detail ?? ""
        let verb = last?.kind == .stuck ? "stuck" : last?.kind == .waiting ? "waiting on something outside it (CI, a deploy…) since" : "finished"
        return "\(verb) \(agoPhrase(s.lastActivity, now: now))" + (said.isEmpty ? "" : ": \(hinted(said, 300))")
    }

    /// A waiting card's line ("asks you a question: SQLite or Postgres? Options: SQLite / Postgres"); nil for others.
    static func cardStatus(_ store: Store, _ card: RouterCard) -> String? {
        let what: String
        switch card.kind {
        case .question: what = "asks you a question"
        case .plan: what = "waits for you to approve its plan"
        case .asks: what = "asks you something"
        case .approval: what = "asks your OK"
        case .done, .stuck, .waiting: return nil
        }
        var text = hinted(card.text, 300)
        let options = store.pendingForm(for: card)?.questions.flatMap { $0.options.map(\.label) } ?? []
        if !options.isEmpty { text += " Options: " + options.map { hinted($0, 60) }.joined(separator: " / ") }
        return "\(what): \(text)"
    }

    /// The questions of one routing call, and which target each route option and each card's check stands for.
    static func routingQuestions(_ destinations: [Destination], waiting: [Waiting])
        -> (questions: [String: JevClient.Question], route: [String: String], answers: [String: Waiting]) {
        var questions = gates
        var criteria: [String: Any] = [:], route: [String: String] = [:], answers: [String: Waiting] = [:]
        for d in destinations {
            criteria[d.name] = d.criteria
            route[d.name] = d.target
        }
        questions["route"] = .structuredChoice(destinations.map(\.name), criteria: criteria, instructions: routeQuestion)
        for (i, w) in waiting.enumerated() {
            questions["answers\(i)"] = .structuredNoul(instructions: ["question": answersInstructions, "card": w.card])
            answers["answers\(i)"] = w
        }
        return (questions, route, answers)
    }

    // MARK: When to act

    /// The bars, by what a wrong pick costs: your words in the wrong session, a new session started for nothing, or one
    /// of Lookout's own runs (answered, or a change you can revert).
    static let sessionSure = 0.7
    static let newSure = 0.6
    static let intentSure = 0.6
    /// A card's check, when it alone stands out (the others at most `answersOthers`).
    static let answersSure = 0.5
    static let answersOthers = 0.4
    /// The route this sure of another session disagrees with the card's check: you pick.
    static let answersConflict = 0.5
    /// A gate that decides its intent first.
    static let gateSure = 0.75

    /// Jev's answers made a ranking, and whether its first is sure enough to act on:
    /// 1. a gate sure enough: its intent;
    /// 2. one card's check standing out: that card, unless the route is sure of another session (then you pick);
    /// 3. the route's pick, against the bar of what it is.
    static func verdict(route: [String: Double], answers: [(target: String, session: String, p: Double)],
                        gates: [String: Double], sessionOf: (String) -> String?) -> (ranked: [RouterDispatcher.Scored], sure: Bool) {
        var ranked = route.map { RouterDispatcher.Scored(target: $0.key, p: $0.value) }
            .sorted { $0.p != $1.p ? $0.p > $1.p : $0.target < $1.target }
        func first(_ target: String, _ p: Double) {
            ranked.removeAll { $0.target == target }
            ranked.insert(.init(target: target, p: p), at: 0)
        }
        if let p = gates["gate_compound"], p >= gateSure { first("compound", p); return (ranked, true) }
        if let p = gates["gate_setting"], p >= gateSure { first("change_lookout", p); return (ranked, true) }
        // A session's cards are one: its surest check stands for it.
        var surest: [String: (target: String, session: String, p: Double)] = [:]
        for a in answers where a.p > (surest[a.session]?.p ?? -1) { surest[a.session] = a }
        let checks = surest.values.sorted { $0.p > $1.p }
        if let top = checks.first, top.p >= answersSure, checks.dropFirst().first.map({ $0.p <= answersOthers }) ?? true {
            if let pick = ranked.first, let other = sessionOf(pick.target), other != top.session, pick.p >= answersConflict {
                return (ranked, false)
            }
            first(top.target, top.p)
            return (ranked, true)
        }
        guard let top = ranked.first, top.target != "unclear" else { return (ranked, false) }
        let bar = top.target.hasPrefix("new:") ? newSure : RouterRun.Intent(rawValue: top.target) != nil ? intentSure : sessionSure
        return (ranked, top.p >= bar)
    }
}

extension Store {
    /// What you last sent each session, and when: from the decision log, your messages that went to one.
    func lastTold() -> [String: (text: String, at: Date)] {
        var out: [String: (text: String, at: Date)] = [:]
        for entry in router.decisions {
            guard case .you(let text) = entry.trigger, let session = entry.links.sessions.last,
                  entry.done.contains(where: { if case .sent = $0 { true } else if case .started = $0 { true } else { false } })
            else { continue }
            out[session] = (text, entry.at)
        }
        return out
    }
}
