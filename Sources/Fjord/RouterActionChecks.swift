import Foundation

// What the Router does besides sending: archive a card, stop a running turn, stop it and send the words instead. Measured as
// D3-all (evals/router/explore/actions_d3.py, docs/design/router-research.md): at send time, in a second call to Jev on the same
// state as the route (the redacted message), one yes/no per open card (`dismiss<i>`), one per running session not waiting on
// you (`stop<i>`), then `urgent` and `instead`. No word decides anything: an action comes from a check over its bar, read with
// the route's own answer by `decideAction`, a pure function that mirrors the Python `decide()` (RouterActionsParityTests runs
// both on recorded answers). The checks are asked only when the route is (never for the drafts read while you type; not for
// a reply armed on a card, a pinned or tagged target, the pick shown over the composer, or an inbox action's message).

/// An action on a target, as the decision and the ask card name it.
enum RouterAct: Hashable, Sendable {
    case archive(card: String)
    case stop(session: String)
    /// Stop the running turn and send the words as the next message.
    case interrupt(session: String)
    /// The words to the session (queued if it works).
    case say(session: String)
    /// The words answer a card.
    case answer(card: String)
    case start(folder: String)
    /// Change Fjord itself (settings, Triage, a card's archive proposed by a run).
    case changeFjord
    case askFjord
    case compound
    /// Opens the session in Claude, sending nothing (an ask's option after a stop that couldn't be done).
    case open(session: String)
    /// Anything else the route named (its wire form).
    case other(String)

    /// The form the evals use (`archive:card:<id>`, `say:session:<id>`, `configure`…).
    var wire: String {
        switch self {
        case .archive(let card): "archive:card:\(card)"
        case .stop(let session): "stop:session:\(session)"
        case .interrupt(let session): "interrupt:session:\(session)"
        case .say(let session): "say:session:\(session)"
        case .answer(let card): "answer:card:\(card)"
        case .start(let folder): "start:new:\(folder)"
        case .changeFjord: "configure"
        case .askFjord: "ask_fjord"
        case .compound: "compound"
        case .open(let session): "open:session:\(session)"
        case .other(let wire): wire
        }
    }

    init(wire: String) {
        let parts = wire.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 {
            switch (parts[0], parts[1]) {
            case ("archive", "card"): self = .archive(card: parts[2]); return
            case ("stop", "session"): self = .stop(session: parts[2]); return
            case ("interrupt", "session"): self = .interrupt(session: parts[2]); return
            case ("say", "session"): self = .say(session: parts[2]); return
            case ("answer", "card"): self = .answer(card: parts[2]); return
            case ("start", "new"): self = .start(folder: parts[2]); return
            case ("open", "session"): self = .open(session: parts[2]); return
            default: break
            }
        }
        switch wire {
        case "configure": self = .changeFjord
        case "ask_fjord": self = .askFjord
        case "compound": self = .compound
        default: self = .other(wire)
        }
    }

    /// The dispatcher's target for it (an ask card's option id, `route(_:to:)`): the legacy destination for what sends or
    /// starts or runs, the action's own form for archive, stop and interrupt.
    var target: String {
        switch self {
        case .archive(let card): "archive:card:\(card)"
        case .stop(let session): "stop:session:\(session)"
        case .interrupt(let session): "interrupt:session:\(session)"
        case .say(let session): "session:\(session)"
        case .answer(let card): "answer:\(card)"
        case .start(let folder): "new:\(folder)"
        case .changeFjord: "change_fjord"
        case .askFjord: "question"
        case .compound: "compound"
        case .open(let session): "open:session:\(session)"
        case .other(let wire): wire
        }
    }

    /// The action a dispatcher target stands for (`target`'s inverse).
    init(target: String) {
        if target.hasPrefix("session:") { self = .say(session: String(target.dropFirst(8))) }
        else if target.hasPrefix("answer:") { self = .answer(card: String(target.dropFirst(7))) }
        else if target.hasPrefix("new:") { self = .start(folder: String(target.dropFirst(4))) }
        else if target == "change_fjord" { self = .changeFjord }
        else if target == "question" { self = .askFjord }
        else if target == "compound" { self = .compound }
        else { self = RouterAct(wire: target) }
    }

    var isOpen: Bool { if case .open = self { true } else { false } }

    /// The word the trace and the history's label use.
    var kindWord: String {
        switch self {
        case .archive: "archive"
        case .stop: "stop"
        case .interrupt: "interrupt"
        case .open: "open"
        default: "send"
        }
    }

    /// Archive, stop or interrupt: what the checks name, done by `RouterDispatcher.perform`.
    var isCheckAction: Bool {
        switch self {
        case .archive, .stop, .interrupt: true
        default: false
        }
    }

    /// How a legacy destination is acted on by the live app: a send to a session holding a form (question, plan) answers
    /// it; `cards`: the open cards `(id, session, kind)`. Nil for no target. (`live_action` of actions_d3.py.)
    static func routing(_ target: String?, cards: [(id: String, session: String, kind: RouterCard.Kind)]) -> RouterAct? {
        guard let target, !target.isEmpty else { return nil }
        if target.hasPrefix("session:") {
            let session = String(target.dropFirst(8))
            if let form = cards.first(where: { $0.session == session && ($0.kind == .question || $0.kind == .plan) }) {
                return .answer(card: form.id)
            }
            return .say(session: session)
        }
        return RouterAct(target: target)
    }
}

/// One yes/no of the checks call: a card to archive, or a session to stop.
struct RouterActionCheck: Equatable, Sendable {
    enum Kind: String, Sendable { case dismiss, stop }
    var kind: Kind
    /// The card (dismiss).
    var card: String?
    /// The session the check is about (a card's session for dismiss).
    var session: String
    var p: Double
}

/// What the checks call read: every check, the two global ones, and the sessions that were stoppable when it was asked.
struct RouterActionReading: Equatable, Sendable {
    var checks: [RouterActionCheck] = []
    var urgent = 0.0
    var instead = 0.0
    var stoppable: [String] = []
}

/// What the decision reads: the route's outcome and the checks.
struct RouterActionInfo: Equatable, Sendable {
    /// Today's target: the send's session, else the fused top (`session:<id>` for a session or its card, else the target).
    var target: String?
    /// The fused probability of `target`.
    var targetP = 0.0
    /// Jev's raw top of the route (the target, or `unclear`).
    var rawTop: String?
    var reading = RouterActionReading()
    /// What acting on `target` is.
    var targetAct: RouterAct?
    /// Today's outcome: whether the route asks, what it sends, and the ask card's actions.
    var routeAsks = false
    var routeAct: RouterAct?
    var routeOptions: [RouterAct] = []
}

struct RouterActionDecision: Equatable, Sendable {
    enum Kind: String, Sendable { case act, ask, route }
    var kind: Kind
    var act: RouterAct?
    var options: [RouterAct] = []
    /// Why: `T`, `urgent`, `standing-out`, `elsewhere`, `unsure`, `route-ask`, `route`.
    var why: String
}

enum RouterActionChecks {
    /// The wording of the measured checks (explore/actions_d3.py FINAL; the dismiss and stop texts are explore/actions0.py AO).
    static let dismissQuestion = "Does `message` ask to archive or drop this card, because the user will handle it or doesn't need it?"
    static let stopQuestion = "Does `message` ask to stop or interrupt what this session is doing now?"
    static let urgentQuestion = "Does `message` ask a session to stop or change what it is doing right now, not after it finishes?"
    static let insteadQuestion = "Besides stopping, does `message` say what to do next or instead?"

    /// The bars (frozen on dev: explore/actions_d3.py PARAMS).
    static let dismissBar = 0.85
    static let stopBar = 0.9
    static let urgentBar = 0.85
    static let insteadBar = 0.6
    /// A check that stands out leads every other session's checks by this; the target's own leads the same kind's by `targetLead`.
    static let lead = 0.4
    static let targetLead = 0.2
    /// A check from here to its bar is a doubt: you pick.
    static let askLow = 0.5
    /// The target is unclear under this fused probability.
    static let clearTarget = 0.4
    /// The ask card's room.
    static let askRoom = 4

    // MARK: Candidates and questions

    /// What the checks are asked about, at the time they are asked.
    struct Candidates: Equatable {
        /// Every open card on the board (board order) whose session is known.
        var cards: [RouterCard]
        /// Every session that works and doesn't wait on you (board order).
        var sessions: [ClaudeSession]
    }

    @MainActor
    static func candidates(_ store: Store) -> Candidates {
        let live = store.claudeSessions.filter { !$0.value.isArchived }
        let cards = store.routerShownOpenCards.filter { live[$0.sessionID] != nil }
        let waiting = Set(store.routerShownOpenCards.filter { RouterTools.waitsOnYou.contains($0.kind) }.map(\.sessionID))
        let sessions = live.values.filter { s in
            guard !waiting.contains(s.id) else { return false }
            // Running by the feed or by the plugin's own presence; a plugin that says it is idle outranks the feed.
            if let target = store.controlTarget(s.id), target.hasTurnField, target.turn == nil { return false }
            return s.running || store.runningTurn(sessionID: s.id) != nil
        }
            .sorted { ($0.lastActivity, $1.id) > ($1.lastActivity, $0.id) }
        return Candidates(cards: cards, sessions: sessions)
    }

    /// The checks call: its questions, in the order they are asked (`dismiss0…`, `stop0…`, `urgent`, `instead`).
    struct Call {
        var questions: [String: JevClient.Question]
        var order: [String]
        var card: [String: RouterCard]
        var session: [String: ClaudeSession]
    }

    @MainActor
    static func call(_ store: Store, candidates c: Candidates) -> Call {
        var questions: [String: JevClient.Question] = [:], order: [String] = []
        var cards: [String: RouterCard] = [:], sessions: [String: ClaudeSession] = [:]
        for (i, card) in c.cards.enumerated() {
            let key = "dismiss\(i)"
            let title = store.claudeSessions[card.sessionID]?.title ?? card.title
            questions[key] = .structuredNoul(instructions: [
                "question": dismissQuestion,
                "card": ["session": RouterTools.hinted(title, 80), "report": RouterTools.hinted(card.text, 400)],
            ])
            order.append(key)
            cards[key] = card
        }
        for (i, s) in c.sessions.enumerated() {
            let key = "stop\(i)"
            let activity = store.claudeActivity[s.id]?.text ?? ""
            questions[key] = .structuredNoul(instructions: [
                "question": stopQuestion,
                "session": ["title": RouterTools.hinted(s.title, 80), "project": RouterTools.hinted(store.routerSessionProject(s.id).name, 80),
                            "now": "working: " + RouterTools.hinted(activity, 300)],
            ])
            order.append(key)
            sessions[key] = s
        }
        questions["urgent"] = .structuredNoul(instructions: ["question": urgentQuestion])
        questions["instead"] = .structuredNoul(instructions: ["question": insteadQuestion])
        order += ["urgent", "instead"]
        return Call(questions: questions, order: order, card: cards, session: sessions)
    }

    /// The answers of a checks call as a reading. Throws what the asker threw; nil answers count as 0.
    @MainActor
    static func read(_ store: Store, message: String, tagged: String?, ask: JevAsker) async throws -> RouterActionReading {
        let c = candidates(store)
        let call = call(store, candidates: c)
        // The state is the route's own: the redacted message (what it tags goes with it).
        var state = ["message": RouterTools.redacted(message)]
        if let tagged { state["tagged in the message"] = RouterTools.redacted(tagged) }
        let answers = try await JevClient.$questionOrder.withValue(call.order) { try await ask(call.questions, state) }
        var reading = RouterActionReading(stoppable: c.sessions.map(\.id))
        for key in call.order {
            if let card = call.card[key] {
                reading.checks.append(.init(kind: .dismiss, card: card.id, session: card.sessionID, p: answers[key]?.yes ?? 0))
            } else if let s = call.session[key] {
                reading.checks.append(.init(kind: .stop, card: nil, session: s.id, p: answers[key]?.yes ?? 0))
            }
        }
        reading.urgent = answers["urgent"]?.yes ?? 0
        reading.instead = answers["instead"]?.yes ?? 0
        return reading
    }

    // MARK: Decision

    /// `decide()` of explore/actions_d3.py with its frozen PARAMS, line by line.
    static func decideAction(_ info: RouterActionInfo) -> RouterActionDecision {
        let cs = info.reading.checks
        let urgent = info.reading.urgent, instead = info.reading.instead
        let running = Set(info.reading.stoppable)
        let T = info.target
        let tSession = T.flatMap { $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil }

        func bar(_ c: RouterActionCheck) -> Double { c.kind == .dismiss ? dismissBar : stopBar }
        func otherMax(_ c: RouterActionCheck, anyKind: Bool = false) -> Double {
            cs.filter { $0.session != c.session && (anyKind || $0.kind == c.kind) }.map(\.p).max() ?? 0
        }
        func over(_ c: RouterActionCheck) -> Bool { c.p >= bar(c) && (c.kind != .stop || running.contains(c.session)) }
        func act(_ c: RouterActionCheck) -> RouterAct {
            switch c.kind {
            case .dismiss: .archive(card: c.card ?? "")
            case .stop: instead >= insteadBar ? .interrupt(session: c.session) : .stop(session: c.session)
            }
        }
        /// Highest first, a tie in the checks' order (a stable sort).
        func best(_ list: [RouterActionCheck]) -> [RouterActionCheck] {
            list.enumerated().sorted { ($0.element.p, $1.offset) > ($1.element.p, $0.offset) }.map(\.element)
        }

        let unclear = info.rawTop == "unclear" || info.targetP < clearTarget || tSession == nil
        if let tSession {
            let mine = best(cs.filter { $0.session == tSession && over($0) && $0.p - otherMax($0) >= targetLead })
            if let first = mine.first { return .init(kind: .act, act: act(first), why: "T") }
            if running.contains(tSession), urgent >= urgentBar, instead >= insteadBar {
                return .init(kind: .act, act: .interrupt(session: tSession), why: "urgent")
            }
        }
        let stand = best(cs.filter { over($0) && $0.p - otherMax($0, anyKind: true) >= lead })
        if let first = stand.first, unclear { return .init(kind: .act, act: act(first), why: "standing-out") }
        if let first = stand.first, first.session != tSession { return ask(info, [act(first)], "elsewhere") }
        let near = best(cs.filter { $0.p >= askLow && ($0.kind != .stop || running.contains($0.session)) && ($0.session == tSession || unclear) })
        if !near.isEmpty { return ask(info, near.prefix(2).map(act), "unsure") }
        if info.routeAsks {
            let any = best(cs.filter { $0.p >= askLow && ($0.kind != .stop || running.contains($0.session)) })
            return ask(info, any.prefix(2).map(act), "route-ask")
        }
        return .init(kind: .route, act: info.routeAct, why: "route")
    }

    /// The ask card's actions: the unsure ones first, then today's target (when the route doesn't ask) and the route's card; four.
    private static func ask(_ info: RouterActionInfo, _ first: [RouterAct], _ why: String) -> RouterActionDecision {
        let rest = (info.targetAct.flatMap { info.routeAsks ? nil : $0 }.map { [$0] } ?? []) + info.routeOptions
        var out: [RouterAct] = []
        for a in first + rest where !out.contains(a) { out.append(a) }
        return .init(kind: .ask, act: nil, options: Array(out.prefix(askRoom)), why: why)
    }

    // MARK: From the dispatcher's classification

    /// What the decision reads, from the classification the route made (after the dispatcher's own adjustments) and the
    /// checks' reading. `found.sure` and `found.top` are today's outcome.
    @MainActor
    static func info(found: RouterDispatcher.Classification, reading: RouterActionReading, store: Store) -> RouterActionInfo {
        let cards = store.routerShownOpenCards.map { (id: $0.id, session: $0.sessionID, kind: $0.kind) }
        func canon(_ target: String) -> String {
            RouterDispatcher.session(of: target, store: store).map { "session:\($0)" } ?? target
        }
        var info = RouterActionInfo(reading: reading)
        if let top = found.top {
            info.target = canon(top.target)
            info.targetP = top.p
            info.targetAct = RouterAct.routing(info.target, cards: cards)
        }
        info.rawTop = found.trace?.route.max { $0.value < $1.value }?.key
        info.routeAsks = !(found.sure && found.top != nil)
        if !info.routeAsks, let top = found.top { info.routeAct = RouterAct.routing(canon(top.target), cards: cards) }
        var card: [RouterAct] = []
        for target in (found.card ?? []) + found.ranked.map(\.target) where target != "unclear" {
            if let a = RouterAct.routing(canon(target), cards: cards), !card.contains(a) { card.append(a) }
        }
        info.routeOptions = Array(card.prefix(askRoom))
        return info
    }
}

extension RouterTools {
    /// The kinds of card that wait on you.
    static let waitsOnYou: Set<RouterCard.Kind> = [.question, .plan, .asks, .approval]
}
