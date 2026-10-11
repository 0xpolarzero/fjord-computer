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

    /// Lookout's own destinations, each worded by who the message is for: worded as "a question about what is going on",
    /// `question` caught questions you ask a session about its own work, p > 0.95, on 1 real message in 10.
    static let intentCriteria: [(name: String, criteria: String)] = [
        ("change_lookout", "Change how Lookout itself behaves: its settings, notifications, inbox categories, rules or groups. Not asking a session to build or change code"),
        ("question", "A question to Lookout, the assistant that watches the board, about the board: which sessions are working, done or waiting on the user, or what a session named in the third person is doing. Not a question for a session about its own work or what it said"),
        ("compound", "Requests meant for two or more different places in one message: Lookout itself and a session, or two different sessions. Not one long message with several points for one session"),
        ("unclear", "none of these: small talk, a fragment, or nothing says where it goes"),
    ]

    static let routeQuestion: [String: Any] = [
        "question": "Where does the user's `message` go?",
        "focus": "Decide about `message` alone; `earlier messages` only say what it refers to. A message addressed to a session (\"tell the CI one to…\", \"lcu: …\") goes to that existing session. A question about a session or about what is going on (\"is the CI one done?\") is `question`, not a message to the session. Start a new session only when the message asks for one or no existing session does that work.",
    ]

    static let answersInstructions = "Is `message` the user's answer to `card`: a reply to what it asks?"

    /// Checks that decide an intent before the route does: the route alone sent "turn off jev labels" to the session
    /// building that feature, and "commit it and add a category" to the session as a whole.
    /// `gate_compound2` keeps one long message with several points for one session from reading as several things;
    /// `gate_you` (it speaks to one agent as "you") vetoes Lookout's intents.
    static let gates: [String: JevClient.Question] = [
        "gate_setting": .structuredNoul(instructions: ["question": "Does `message` ask to change how Lookout behaves for the user (a setting turned on or off, its notifications, an inbox category, a rule or a group), rather than for code to be written or for a session to do something?"]),
        "gate_compound": .structuredNoul(instructions: ["question": "Does `message` ask for two or more different things, meant for different places (sessions or Lookout itself)?"]),
        "gate_question": .structuredNoul(instructions: ["question": "Is `message` a question to the user's assistant about what is going on (a session's progress, what is waiting), rather than a message for a session to read?"]),
        "gate_compound2": .structuredNoul(instructions: ["question": "Does `message` ask for things meant for two or more different places: Lookout itself and a session, or two different sessions it names? A message with several points or steps for one session is no."]),
        "gate_you": .structuredNoul(instructions: ["question": "Does `message` speak to one agent as \"you\" about its own work (\"did you…\", \"your end\", \"what are you waiting for\", \"you said…\"), or reply to something it just said?"]),
    ]

    static let nextInstructions = "Is `message` the user's next message in `conversation`: what the user says back to it?"
    /// How many of the latest sessions get the next-message check.
    static let nextLatest = 3

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
        let last = cards.last { $0.kind == .done || $0.kind == .finish || $0.kind == .stuck || $0.kind == .waiting }
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
        case .done, .finish, .stuck, .waiting: return nil
        }
        var text = hinted(card.text, 300)
        let options = store.pendingForm(for: card)?.questions.flatMap { $0.options.map(\.label) } ?? []
        if !options.isEmpty { text += " Options: " + options.map { hinted($0, 60) }.joined(separator: " / ") }
        return "\(what): \(text)"
    }

    /// What the board says about the offered sessions, beside what Jev reads: where a real message goes is most often the
    /// session that just finished (60% of 550 of yours; evals/router/real).
    struct Facts {
        /// The sessions not running, latest to finish first.
        var latest: [String] = []
        var running: Set<String> = []
        var idleMinutes: [String: Double] = [:]
        /// The session your last message went to.
        var lastTold: String?
        /// Each session's target (its card's when it has one).
        var targetOf: [String: String] = [:]
        var message = ""
        /// The sessions whose last message asks you something or proposes a next step.
        var leavesItToYou: Set<String> = []
    }

    func facts(_ store: Store, destinations: [Destination], message: String, now: Date = Date()) -> Facts {
        var f = Facts(message: message)
        var sessions: [ClaudeSession] = []
        for d in destinations {
            guard let id = d.sessionID, f.targetOf[id] == nil else { continue }
            f.targetOf[id] = d.target
            if let s = store.claudeSessions[id] { sessions.append(s) }
        }
        // A session stopped on what it asks you (its turn still open) waits on you: not working.
        let waits = Set(store.routerShownOpenCards.filter { Self.waitsOnYou.contains($0.kind) }.map(\.sessionID))
        f.running = Set(sessions.filter { $0.running && !waits.contains($0.id) }.map(\.id))
        f.latest = sessions.filter { !f.running.contains($0.id) }.sorted { $0.lastActivity > $1.lastActivity }.map(\.id)
        for s in sessions { f.idleMinutes[s.id] = max(0, now.timeIntervalSince(s.lastActivity) / 60) }
        f.lastTold = store.lastTold().filter { f.targetOf[$0.key] != nil }.max { $0.value.at < $1.value.at }?.key
        let cards = store.routerShownOpenCards
        for s in sessions {
            let mine = cards.filter { $0.sessionID == s.id }
            let last = mine.max { $0.createdAt < $1.createdAt }?.text ?? ""
            if RouterLexical.leavesItToYou(last, waiting: mine.contains { Self.waitsOnYou.contains($0.kind) }) {
                f.leavesItToYou.insert(s.id)
            }
        }
        return f
    }

    /// What BM25 reads per offered session: its title, and its turns from its transcript, else from the board (what you
    /// told it, its cards, its summary and working line). Taken on the main actor; the transcripts are read off it.
    struct LexicalSource {
        var title: String
        var cliID: String?
        var working: Bool
        var board: [RouterLexical.Turn]
    }

    func lexicalSources(_ store: Store, facts: Facts) -> [String: LexicalSource] {
        let told = store.toldAll()
        let cards = store.routerShownOpenCards
        var out: [String: LexicalSource] = [:]
        for id in facts.targetOf.keys {
            guard let s = store.claudeSessions[id] else { continue }
            let board = RouterLexical.boardTurns(
                told: told[id] ?? [], cards: cards.filter { $0.sessionID == id }.map(\.text),
                earlier: [s.summary?.detail ?? "", store.claudeActivity[id]?.text ?? ""])
            out[id] = LexicalSource(title: s.title, cliID: s.cliID, working: facts.running.contains(id), board: board)
        }
        return out
    }

    /// Every field's BM25 scores, transcripts read with `reader` (nil: the board alone).
    nonisolated static func lexical(_ message: String, sources: [String: LexicalSource],
                                    reader: Claude.ActivityReader?) -> [String: [String: Double]] {
        var sessions: [String: (title: String, turns: [RouterLexical.Turn])] = [:]
        for (id, source) in sources {
            var turns: [RouterLexical.Turn] = []
            if let reader, let cli = source.cliID, let url = reader.transcript(cli) {
                turns = RouterLexical.turns(tail: Claude.tail(of: url, bytes: 256 * 1024), working: source.working)
            }
            sessions[id] = (source.title, turns.isEmpty ? source.board : turns)
        }
        return RouterLexical.all(message, sessions: sessions)
    }

    /// The latest sessions' conversations, for the next-message check: what you last told each and what it last said.
    func conversations(_ store: Store, facts: Facts) -> [(session: String, conversation: [[String: String]])] {
        let told = store.lastTold()
        let cards = store.routerShownOpenCards
        return facts.latest.prefix(Self.nextLatest).compactMap { id in
            var conversation: [[String: String]] = []
            if let last = told[id] { conversation.append(["user": Self.hinted(last.text, 300)]) }
            let said = cards.filter { $0.sessionID == id }.max { $0.createdAt < $1.createdAt }?.text
                ?? store.claudeSessions[id]?.summary?.detail ?? store.claudeActivity[id]?.text ?? ""
            if !said.isEmpty { conversation.append(["session": Self.hinted(said, 400)]) }
            return conversation.isEmpty ? nil : (id, conversation)
        }
    }

    /// The questions of one routing call, and which target each route option, each card's check and each session's
    /// next-message check stands for.
    static func routingQuestions(_ destinations: [Destination], waiting: [Waiting],
                                 conversations: [(session: String, conversation: [[String: String]])] = [])
        -> (questions: [String: JevClient.Question], route: [String: String], answers: [String: Waiting], next: [String: String]) {
        var questions = gates
        var criteria: [String: Any] = [:], route: [String: String] = [:], answers: [String: Waiting] = [:], next: [String: String] = [:]
        for d in destinations {
            criteria[d.name] = d.criteria
            route[d.name] = d.target
        }
        questions["route"] = .structuredChoice(destinations.map(\.name), criteria: criteria, instructions: routeQuestion)
        for (i, w) in waiting.enumerated() {
            questions["answers\(i)"] = .structuredNoul(instructions: ["question": answersInstructions, "card": w.card])
            answers["answers\(i)"] = w
        }
        for (i, c) in conversations.enumerated() {
            questions["next\(i)"] = .structuredNoul(instructions: ["question": nextInstructions, "conversation": c.conversation])
            next["next\(i)"] = c.session
        }
        return (questions, route, answers, next)
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
    /// The tight compound gate's bar beside it, and the second-person gate's veto of Lookout's intents.
    static let compound2Sure = 0.5
    static let youVeto = 0.5
    /// A latest session's next-message yes that stands out (this sure, ahead of the others by `nextLead`) sends there
    /// when the route agrees, reads the message as unclear, or is under `nextAgree` sure of anything.
    static let nextSure = 0.5
    static let nextLead = 0.3
    static let nextAgree = 0.4

    /// Jev's answers made a ranking, and whether its first is sure enough to act on:
    /// 1. one latest session's next-message yes standing out, the route not sure of anything else: that session;
    /// 2. a gate sure enough: its intent (not when the message speaks to one agent as "you");
    /// 3. one card's check standing out: that card, unless the route is sure of another session (then you pick);
    /// 4. the route's pick, against the bar of what it is; one of Lookout's intents never when it speaks to an agent.
    static func verdict(route: [String: Double], answers: [(target: String, session: String, p: Double)],
                        gates: [String: Double], next: [(target: String, p: Double)] = [],
                        sessionOf: (String) -> String?) -> (ranked: [RouterDispatcher.Scored], sure: Bool) {
        var ranked = route.map { RouterDispatcher.Scored(target: $0.key, p: $0.value) }
            .sorted { $0.p != $1.p ? $0.p > $1.p : $0.target < $1.target }
        func first(_ target: String, _ p: Double) {
            ranked.removeAll { $0.target == target }
            ranked.insert(.init(target: target, p: p), at: 0)
        }
        let nexts = next.sorted { $0.p > $1.p }
        if let best = nexts.first, best.p >= nextSure, best.p - (nexts.dropFirst().first?.p ?? 0) >= nextLead,
           let top = ranked.first, top.target == best.target || top.target == "unclear" || top.p < nextAgree {
            first(best.target, best.p)
            return (ranked, true)
        }
        let vetoed = (gates["gate_you"] ?? 0) >= youVeto
        if !vetoed, let p = gates["gate_compound"], p >= gateSure, (gates["gate_compound2"] ?? 1) >= compound2Sure {
            first("compound", p)
            return (ranked, true)
        }
        if !vetoed, let p = gates["gate_setting"], p >= gateSure { first("change_lookout", p); return (ranked, true) }
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
        let intent = RouterRun.Intent(rawValue: top.target) != nil
        if intent && vetoed { return (ranked, false) }
        let bar = top.target.hasPrefix("new:") ? newSure : intent ? intentSure : sessionSure
        return (ranked, top.p >= bar)
    }
}

// MARK: - Jev's answers and the board, fused

/// Jev reads the message well and the board's recency poorly (minutes and order are his weak spots), and his sureness
/// was 97% right on written cases but 63% on real ones. A small model weighs his answers with what the board says, fitted
/// on real moments and written cases (evals/router/explore/fuse2.py): P(destination) = softmax of `weights` · features;
/// the fused pick's chance of being right is a logistic on the moment (`sureness`).
@MainActor
enum RouteFusion {
    static let weights: [String: Double] = [
        "lp": 0.84,                                   // Jev's route probability (log, floored at 0.001)
        "fin0": 0.55, "fin1": 1.16, "fin2": 0.29,     // 1st / 2nd / 3rd most recently finished session
        "run": -1.26,                                 // still running
        "reply": 0.64,                                // "is it the answer to this session's card?" yes
        "told0": 0.72,                                // the session your last message went to
        "fin0u": 1.03, "idle5u": 2.44,                // latest / finished ≤ 5 min ago, times Jev's `unclear` p
        "nxt": 0.87,                                  // "is it your next message in this conversation?" yes
        "f_said": 1.11, "f_old": 1.36,                // the message's words in the session's last answer, older turns
        "f_you": -0.84,                               // …in what you last told it: a message repeating it starts anew
        "f_title": -0.57,                             // …in its title (it already weighs in Jev's reading)
        "new": 0.66,
        "question": -0.57, "compound": 1.03, "change_lookout": 0.63,
        "g_q": 1.26, "g_c": 2.11, "g_s": 2.26, "c2": 0.18,   // an intent's own gate
        "you": -1.46,                                 // "does it speak to one agent as you?" yes, against intents
        "ilong": -1.51,                               // an intent for a message over 80 characters
    ]
    static let sureness: [String: Double] = [
        "bias": 0.88, "lPtop": 1.28, "lgap": -0.3, "ljev": -0.21, "agree": 0.44, "u": -1.44, "lenlog": -0.35,
        "recent2": -0.4, "top_fin0": -0.02, "top_intent": 0.46, "top_new": 0.82, "top_reply": 0.31,
    ]
    /// The rules' send stands when the fused P gives it at least this and the fused pick is the same at `rulesSure`;
    /// else the fused pick is sent at `sure`. On real moments the rules made 24 of 25 wrong sends; the fused pick at 0.9
    /// was right 78 times in 79.
    static let agrees = 0.5
    static let rulesSure = 0.6
    static let sure = 0.9
    /// The fused pick alone sends no message shorter than this, and never to one of Lookout's intents…
    static let fusedWords = 3
    /// …except a short reply ("go", "yes do it") to a session whose last message asks or proposes, at this sureness.
    static let shortSure = 0.95

    struct Signals {
        var route: [String: Double]
        /// Per session: its card's answer check, its next-message check.
        var reply: [String: Double] = [:]
        var next: [String: Double] = [:]
        var gates: [String: Double] = [:]
        /// BM25 per field (RouterLexical.fields): field → session → score.
        var lexical: [String: [String: Double]] = [:]
    }

    static func features(_ s: Signals, facts f: RouterTools.Facts, sessionOf: (String) -> String?) -> [String: [String: Double]] {
        let u = s.route["unclear"] ?? 0
        var out: [String: [String: Double]] = [:]
        for (target, p) in s.route where target != "unclear" {
            var x: [String: Double] = ["lp": log(max(p, 0.001))]
            if let id = sessionOf(target) {
                let rank = f.latest.firstIndex(of: id)
                if let rank, rank <= 2 { x["fin\(rank)"] = 1 }
                if f.running.contains(id) { x["run"] = 1 }
                let idle5 = !f.running.contains(id) && (f.idleMinutes[id] ?? .infinity) <= 5
                x["reply"] = s.reply[id] ?? 0
                if f.lastTold == id { x["told0"] = 1 }
                x["fin0u"] = (rank == 0 ? 1 : 0) * u
                x["idle5u"] = (idle5 ? 1 : 0) * u
                x["nxt"] = s.next[id] ?? 0
                for (field, byID) in s.lexical { x[field] = byID[id] ?? 0 }
                x["session"] = 1
            } else if target.hasPrefix("new:") {
                x["new"] = 1
            } else if RouterRun.Intent(rawValue: target) != nil {
                x[target] = 1
                x["ilong"] = f.message.count > 80 ? 1 : 0
                x["you"] = s.gates["gate_you"] ?? 0
                if target == "compound" {
                    x["g_c"] = s.gates["gate_compound"] ?? 0
                    x["c2"] = s.gates["gate_compound2"] ?? 0
                }
                if target == "change_lookout" { x["g_s"] = s.gates["gate_setting"] ?? 0 }
                if target == "question" { x["g_q"] = s.gates["gate_question"] ?? 0 }
            }
            out[target] = x
        }
        return out
    }

    static func probabilities(_ features: [String: [String: Double]]) -> [String: Double] {
        let scores = features.mapValues { x in x.reduce(0) { $0 + (weights[$1.key] ?? 0) * $1.value } }
        guard let top = scores.values.max() else { return [:] }
        let e = scores.mapValues { exp($0 - top) }
        let z = e.values.reduce(0, +)
        return e.mapValues { $0 / z }
    }

    /// The fused pick and its chance of being right.
    static func pick(_ P: [String: Double], features: [String: [String: Double]], signals s: Signals,
                     facts f: RouterTools.Facts) -> (target: String, sure: Double)? {
        let ranked = P.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let (top, p) = ranked.first else { return nil }
        let second = ranked.dropFirst().first?.value ?? 0
        // Jev agrees when nothing else is above the pick in his route (he often gives several the same small p).
        let jevBest = s.route.filter { $0.key != "unclear" }.values.max() ?? 0
        let x = features[top] ?? [:]
        let recent = f.idleMinutes.filter { !f.running.contains($0.key) && $0.value <= 5 }.count
        let moment: [String: Double] = [
            "bias": 1, "lPtop": log(p / max(1 - p, 1e-4)), "lgap": log(max(p - second, 1e-3)),
            "ljev": log(max(s.route[top] ?? 0, 1e-3)), "agree": (s.route[top] ?? 0) >= jevBest ? 1 : 0, "u": s.route["unclear"] ?? 0, "lenlog": log(1 + Double(f.message.count)),
            "recent2": recent >= 2 ? 1 : 0, "top_fin0": x["fin0"] ?? 0,
            "top_intent": RouterRun.Intent(rawValue: top) != nil ? 1 : 0, "top_new": x["new"] ?? 0, "top_reply": x["reply"] ?? 0,
        ]
        let z = moment.reduce(0) { $0 + (sureness[$1.key] ?? 0) * $1.value }
        return (top, 1 / (1 + exp(-z)))
    }

    /// The decision: the rules' send (`RouterTools.verdict`) when the fused P agrees with it and the fused pick is the
    /// same, sure enough; else the fused pick when it is sure, a message of a few words (or a short reply to a session
    /// waiting on one), and not one of Lookout's intents; else you pick, among the fused top ones.
    static func decide(_ s: Signals, facts f: RouterTools.Facts, answers: [(target: String, session: String, p: Double)],
                       sessionOf: (String) -> String?) -> (ranked: [RouterDispatcher.Scored], sure: Bool) {
        let next = s.next.compactMap { id, p in f.targetOf[id].map { (target: $0, p: p) } }
        let rules = RouterTools.verdict(route: s.route, answers: answers, gates: s.gates, next: next, sessionOf: sessionOf)
        let x = features(s, facts: f, sessionOf: sessionOf)
        let P = probabilities(x)
        let fused = P.map { RouterDispatcher.Scored(target: $0.key, p: $0.value) }
            .sorted { $0.p != $1.p ? $0.p > $1.p : $0.target < $1.target }
        let picked = pick(P, features: x, signals: s, facts: f)
        // A card's check names its card; the fused P names the session's own target.
        if rules.sure, let d = rules.ranked.first?.target {
            let own = sessionOf(d).flatMap { f.targetOf[$0] } ?? d
            if (P[own] ?? 0) >= agrees, let picked, picked.target == own, picked.sure >= rulesSure { return (rules.ranked, true) }
        }
        if let (top, sure) = picked, RouterRun.Intent(rawValue: top) == nil {
            let words = f.message.split(whereSeparator: \.isWhitespace).count
            if words >= fusedWords && sure >= Self.sure { return (fused, true) }
            if words < fusedWords, sure >= shortSure, let id = sessionOf(top), f.leavesItToYou.contains(id) { return (fused, true) }
        }
        return (fused.isEmpty ? rules.ranked : fused, false)
    }
}

extension Store {
    /// Everything you sent each session, oldest first.
    func toldAll() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for entry in router.decisions {
            guard case .you(let text) = entry.trigger, let session = entry.links.sessions.last,
                  entry.done.contains(where: { if case .sent = $0 { true } else if case .started = $0 { true } else { false } })
            else { continue }
            out[session, default: []].append(text)
        }
        return out
    }

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
