import Foundation
import Observation

// Workflow B of docs/design/spec/router.md: what you type. Each message is a run of its own (several can be in flight), with
// no transcript: deterministic rules first (a reply armed on a card, a typed @project), then Jev with context, then a Haiku run
// only for what needs judgment or tools (changing Lookout, a question about its state). Every run is one entry of the decision
// log, and the line on the page shows how far it is. When Jev isn't sure, nothing is sent: an ask-back card puts the question
// to you, and your pick is logged (as a correction when it isn't what Jev suggested).

/// What a message of yours comes with besides its text: the card you're replying to (its session is the target) and the
/// projects you tagged (routing is narrowed to them, and a new session starts there).
struct RouterContext: Equatable {
    /// A card id.
    var replyTo: String?
    /// Folder paths.
    var projects: [String]

    init(replyTo: String? = nil, projects: [String] = []) {
        self.replyTo = replyTo
        self.projects = projects
    }
}

// MARK: - The ask-back card

/// "Where should this go?": a message waiting for you to say where. Nothing is sent until you pick.
struct RouterAskBack: Identifiable, Equatable {
    /// A target you can pick: `answer:<card>`, `session:<id>`, `new:<folder>`, `change_lookout` or `question`.
    struct Option: Identifiable, Equatable, Hashable {
        var target: String
        var title: String
        var detail: String
        var id: String { target }
    }

    /// The entry of the run in the decision log.
    var id: UUID
    var message: String
    var context: RouterContext
    /// The top targets, best first.
    var options: [Option]
    /// Jev's top target (what a different pick corrects).
    var suggestion: String?
    var at: Date
}

// MARK: - Dispatcher

@Observable @MainActor final class RouterDispatcher {
    /// A target and how likely Jev finds it.
    struct Scored: Equatable {
        var target: String
        var p: Double
    }

    /// What Jev (or the words alone) made of a message.
    struct Classification: Equatable {
        /// Best first.
        var ranked: [Scored]
        /// Confident enough to act: the same thresholds as `route` (p ≥ 0.75 and a lead of 0.3).
        var sure: Bool
        /// Jev answered (else the words alone were matched against titles).
        var assisted: Bool

        var top: Scored? { ranked.first }
    }

    /// Where a message goes without asking Jev, or that it needs him.
    enum Plan: Equatable {
        case reply(session: String, card: String?)
        case start(folder: String)
        case classify
    }

    /// A message ready to go, as the session will get it.
    struct Delivery: Equatable {
        var to: String
        /// What is sent (signed for the session's plugin).
        var text: String
        /// Your words as the session reads them, and as you wrote them.
        var body: String
        var original: String
        var rephrased: Bool
        var session: String?
        var newSessionIn: String?
        /// For a new session: the model and effort asked for, and whether the text carries them (the session's plugin takes them).
        var settings: SessionSettings? = nil
        var settingsSigned = false
    }

    /// Everything a run does outside Lookout's own state, so a test stands in for each. The defaults are the real ones.
    struct Effects {
        /// Jev's probabilities over the targets (`RouterDispatcher.Scored`), or why not.
        var rank: @MainActor (RouterTools, _ message: String, _ projects: [String], _ history: String) async throws -> [Scored]
        /// Haiku's minimal edit of the message for a session, and its signature.
        var prepare: @MainActor (RouterTools, _ session: String) async throws -> Delivery
        /// A new session in a project (folder) with the prepared first message.
        var start: @MainActor (RouterTools, _ folder: String, _ title: String, _ settings: SessionSettings?) async throws -> Delivery
        /// The signed send, through the gate: the plugin's ack when it went through the inbox.
        var send: @MainActor (RouterTools, Delivery) async throws -> String?
        /// A form answered for a card: what was answered.
        var answer: @MainActor (RouterTools, _ card: String, _ answers: [String: String]) async throws -> String
        /// A Haiku run for an intent, given the context it starts from.
        var run: @MainActor (RouterTools, RouterRun.Intent, _ input: String) async throws -> RouterRun.Answer
    }

    /// Asks waiting for a pick, oldest first.
    private(set) var askBacks: [RouterAskBack] = []
    /// How far each run under way is, by its entry in the log ("classifying", "sending"…).
    private(set) var progress: [UUID: String] = [:]
    var isBusy: Bool { !progress.isEmpty }

    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored var effects: Effects
    /// Claude Code's binary, as `RouterStatus` found it.
    @ObservationIgnored var claudePath: () -> String? = { nil }
    /// Set up each run's tools before it starts (tests).
    @ObservationIgnored var configure: ((RouterTools) -> Void)?
    /// A run is over (tests wait on it).
    @ObservationIgnored var onFinish: ((UUID) -> Void)?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var runTools: [UUID: RouterTools] = [:]

    init(store: Store) {
        self.store = store
        effects = Effects.unavailable
        effects = Effects.live(self)
    }

    private struct Job {
        var id: UUID
        var text: String
        var context: RouterContext
        var tools: RouterTools
    }

    /// A demo or a shot: an ask waiting for you and runs shown under way, with nothing behind them.
    func preview(ask: RouterAskBack, progress runs: [UUID: String] = [:]) {
        askBacks = [ask]
        progress = runs
    }

    // MARK: Entry points

    /// Your message. A run of its own: other runs go on meanwhile. Returns its entry in the decision log.
    @discardableResult
    func submit(_ text: String, context: RouterContext = RouterContext()) -> UUID? {
        guard let store, store.routerOn else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Typing the name of a target answers an ask-back; nothing else is made of it.
        if context.replyTo == nil, let ask = typedPick(text) {
            pick(ask.ask, target: ask.target)
            return ask.ask
        }
        var seen = Set<String>()
        let projects = context.projects.filter { seen.insert($0).inserted }
        let context = RouterContext(replyTo: context.replyTo, projects: projects)
        let id = store.logDecision(RouterDecision(trigger: .you(text), decision: .init(intent: "message"),
                                                  links: .init(cards: context.replyTo.map { [$0] } ?? [])))
        launch(Job(id: id, text: text, context: context, tools: makeTools(id, text)), stage: "starting") { [self] job in
            try await execute(job)
        }
        return id
    }

    /// You picked where an ask-back goes. Sends as an armed reply or a start would; the entry says it was a correction when
    /// the pick isn't what Jev suggested.
    func pick(_ id: UUID, target: String) {
        guard let store, store.routerOn, let i = askBacks.firstIndex(where: { $0.id == id }) else { return }
        let ask = askBacks.remove(at: i)
        let chosen = describe(target, store: store)
        let corrected = target != ask.suggestion
        store.updateDecision(id) {
            $0.decision.target = chosen
            if corrected { $0.outcome = .corrected(from: ask.suggestion.map { describe($0, store: store) } ?? "no clear target", to: chosen) }
        }
        launch(Job(id: id, text: ask.message, context: ask.context, tools: makeTools(id, ask.message)), stage: "starting") { [self] job in
            try await route(job, to: target)
        }
    }

    /// You dismissed an ask-back: nothing is sent.
    func dismiss(_ id: UUID) {
        guard let store, let i = askBacks.firstIndex(where: { $0.id == id }) else { return }
        askBacks.remove(at: i)
        store.updateDecision(id) {
            $0.reply = "Dismissed: nothing was sent."
            $0.outcome = .done
        }
    }

    /// Stops every run under way (nothing more is sent by them) and drops the asks waiting for you.
    func stopAll() {
        for task in tasks.values { task.cancel() }
        for tools in runTools.values { tools.cancelRuns() }
        for ask in askBacks { dismiss(ask.id) }
    }

    // MARK: Runs

    private func makeTools(_ id: UUID, _ text: String) -> RouterTools {
        let tools = RouterTools(store: store!)
        tools.claudePath = { [weak self] in self?.claudePath() }
        tools.decision = id
        tools.beginTurn(text)
        configure?(tools)
        return tools
    }

    private func launch(_ job: Job, stage first: String, _ body: @escaping (Job) async throws -> Void) {
        progress[job.id] = first
        runTools[job.id] = job.tools
        tasks[job.id] = Task { [weak self] in
            do {
                try await body(job)
            } catch is CancellationError {
                self?.fail(job, "Stopped")
            } catch {
                self?.fail(job, error.localizedDescription)
            }
            self?.end(job)
        }
    }

    private func end(_ job: Job) {
        job.tools.endTurn()
        progress[job.id] = nil
        tasks[job.id] = nil
        runTools[job.id] = nil
        // Waiting for your pick is not over; anything else not settled is done.
        if !askBacks.contains(where: { $0.id == job.id }) {
            store?.updateDecision(job.id) { if $0.outcome == .pending { $0.outcome = .done } }
        }
        onFinish?(job.id)
    }

    private func fail(_ job: Job, _ reason: String) {
        let first = reason.split(separator: "\n").first.map(String.init) ?? "failed"
        store?.updateDecision(job.id) { $0.add(.failed(RouterDecision.clip(first, 120))) }
    }

    private func stage(_ job: Job, _ text: String) { progress[job.id] = text }

    private func note(_ job: Job, _ item: RouterDecision.Done, session: String? = nil, card: String? = nil) {
        store?.updateDecision(job.id) { $0.add(item, session: session, card: card) }
    }

    // MARK: Workflow B

    /// 1. The rules; 2. Jev; 3. a Haiku run.
    private func execute(_ job: Job) async throws {
        guard let store else { return }
        switch Self.plan(text: job.text, context: job.context, store: store) {
        case .reply(let session, let card): try await reply(job, session: session, card: card)
        case .start(let folder): try await start(job, folder: folder)
        case .classify: try await classifyAndAct(job)
        }
    }

    /// Where a message goes without asking Jev. A reply armed on a card fixes the session. A single typed `@project` fixes a
    /// new session there when the message asks for one, or when the project has nothing else to be for (no open card, no
    /// session). Anything else is for Jev.
    static func plan(text: String, context: RouterContext, store: Store) -> Plan {
        if let id = context.replyTo, let card = store.router.cards.first(where: { $0.id == id }) {
            return .reply(session: card.sessionID, card: id)
        }
        if context.projects.count == 1, let folder = context.projects.first {
            if wantsNewSession(text) { return .start(folder: folder) }
            let other = store.openRouterCards.contains { ($0.folder ?? "") == folder }
                || store.claudeSessions.values.contains { !$0.isArchived && $0.folderKey == folder }
            if !other { return .start(folder: folder) }
        }
        return .classify
    }

    /// "start a new session…", "new chat about…", "open a session to…".
    static func wantsNewSession(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.range(of: #"\bnew\s+(session|chat|conversation)\b"#, options: .regularExpression) != nil { return true }
        return t.range(of: #"\b(start|open|create|launch|spin\s+up|kick\s+off|begin)\b[^.\n]{0,24}\b(session|chat|conversation)\b"#,
                       options: .regularExpression) != nil
    }

    /// A short title for a new session from its task (`SessionStart.task`): the first few words, without the @project.
    static func title(for text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("@") }.prefix(6)
        let title = SessionStart.cleanTitle(words.joined(separator: " "))
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,:;-–—")))
        return title.isEmpty ? "New session" : title
    }

    /// The answer a question card's form takes from a message that is exactly an option (or several, for a multiple choice):
    /// anything else is text for the session. Only a single question; a plan is never answered this way.
    static func formAnswers(_ form: PendingForm, message: String) -> [String: String]? {
        guard !form.isPlan, form.questions.count == 1, let q = form.questions.first else { return nil }
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let said = message.trimmingCharacters(in: trim)
        func option(_ text: String) -> String? {
            let t = text.trimmingCharacters(in: trim).lowercased()
            return q.options.first { $0.label.trimmingCharacters(in: trim).lowercased() == t }?.label
        }
        if let one = option(said) { return [q.question: one] }
        guard q.multiSelect else { return nil }
        let parts = said.replacingOccurrences(of: " and ", with: ",").split(separator: ",").map(String.init)
        let labels = parts.compactMap(option)
        guard parts.count > 1, labels.count == parts.count else { return nil }
        return [q.question: FormBridge.joined(labels)]
    }

    /// Passes your words to a session: the form's answer when you gave one, else the minimal edit, signed, through the gate.
    private func reply(_ job: Job, session: String, card: String?) async throws {
        guard let store else { return }
        if let card, let c = store.router.cards.first(where: { $0.id == card }), let form = store.pendingForm(for: c),
           let answers = Self.formAnswers(form, message: job.text) {
            stage(job, "answering")
            _ = try await effects.answer(job.tools, card, answers)
            note(job, .answered(card: c.title), session: session, card: card)
            return
        }
        stage(job, "preparing")
        let delivery = try await effects.prepare(job.tools, session)
        stage(job, "sending")
        // The cards open now, as they are: one that changes while this goes isn't addressed by it.
        let eligible = Dictionary(store.router.cards.filter(\.isOpen).map { ($0.id, store.cardRevisions[$0.id, default: 0]) },
                                  uniquingKeysWith: { a, _ in a })
        _ = try await effects.send(job.tools, delivery)
        note(job, .sent(to: delivery.to, text: delivery.body, original: delivery.rephrased ? delivery.original : nil),
             session: session, card: card)
        // Which of the session's open cards the message resolves is Jev's call; none are addressed just for being sent to.
        stage(job, "checking its cards")
        await store.judgeCards(session: session, message: job.text, eligible: eligible, chooser: job.tools.chooser, decision: job.id)
    }

    /// Starts a session in a project with your words as its first message.
    private func start(_ job: Job, folder: String) async throws {
        guard let store else { return }
        stage(job, "starting a session")
        // "…with opus, high effort": set in the session by its plugin before the first message.
        let settings = SessionSettings.parse(job.text)
        // The title and the first message come from the task, never from the request to start the session.
        let task = SessionStart.task(from: job.text, projects: [store.folderName(folder), (folder as NSString).lastPathComponent])
        let delivery = try await effects.start(job.tools, folder, Self.title(for: task), settings)
        let project = store.folderName(folder)
        if delivery.text.isEmpty {
            // Nothing to send: the settings travel with the first message, so they can't be applied.
            note(job, .started(session: delivery.session, project: project, model: nil, effort: nil), session: delivery.session)
            if settings != nil {
                store.updateDecision(job.id) { $0.add(.failed("model/effort: no first message to set them with")) }
            }
            return
        }
        stage(job, "sending")
        let ack = try await effects.send(job.tools, delivery)
        if let settings {
            let applied = AppliedSettings.from(ack: ack, requested: settings, supported: delivery.settingsSigned)
            store.updateDecision(job.id) { applied.record(session: delivery.session, project: project, in: &$0) }
        } else {
            note(job, .started(session: delivery.session, project: project, model: nil, effort: nil), session: delivery.session)
        }
    }

    /// Haiku, fresh, for what needs judgment or tools; its reply is what the history shows.
    private func think(_ job: Job, _ intent: RouterRun.Intent) async throws {
        guard let store else { return }
        stage(job, "working")
        let input = store.routerRunContext(message: job.text, projects: job.context.projects, excluding: job.id).text()
        let answer = try await effects.run(job.tools, intent, input)
        let reply = answer.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = answer.done.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateDecision(job.id) {
            $0.reply = reply.isEmpty ? nil : reply
            $0.note = done.isEmpty ? nil : done
        }
    }

    /// Acts on a target: a card or session gets the message, a project a new session, an intent a run.
    private func route(_ job: Job, to target: String) async throws {
        guard let store else { return }
        if target.hasPrefix("answer:") {
            let id = String(target.dropFirst("answer:".count))
            guard let card = store.router.cards.first(where: { $0.id == id }) else { throw RouterTools.Failure("That card is gone") }
            return try await reply(job, session: card.sessionID, card: id)
        }
        if target.hasPrefix("session:") { return try await reply(job, session: String(target.dropFirst("session:".count)), card: nil) }
        if target.hasPrefix("new:") { return try await start(job, folder: String(target.dropFirst("new:".count))) }
        if let intent = RouterRun.Intent(rawValue: target) { return try await think(job, intent) }
        throw RouterTools.Failure("Nowhere to send that")
    }

    // MARK: Jev

    private func classifyAndAct(_ job: Job) async throws {
        guard let store else { return }
        stage(job, "classifying")
        let narrowed = job.context.projects
        let history = store.recentDecisions(10, excluding: job.id)
        let found = await classify(job, projects: narrowed, history: history)
        try Task.checkCancellation()
        store.updateDecision(job.id) {
            $0.decision.label = found.top.map { Self.label($0.target) }
            $0.decision.confidence = found.top?.p
            $0.decision.target = found.top.map { describe($0.target, store: store) }
        }
        if found.sure, let top = found.top { return try await route(job, to: top.target) }
        askBack(job, found)
    }

    /// The label a target stands for: reply (a card or session), start (a project), change_lookout, question, compound.
    static func label(_ target: String) -> String {
        if target.hasPrefix("answer:") || target.hasPrefix("session:") { return "reply" }
        if target.hasPrefix("new:") { return "start" }
        return target
    }

    /// Jev's pick among the targets and the intents; the words alone when he can't be asked.
    private func classify(_ job: Job, projects: [String], history: String) async -> Classification {
        guard let store else { return Classification(ranked: [], sure: false, assisted: false) }
        do {
            let ranked = try await effects.rank(job.tools, job.text, projects, history)
                .sorted { $0.p != $1.p ? $0.p > $1.p : $0.target < $1.target }
            let sure = RouterTools.decision(ranked.map { (target: $0.target, p: $0.p) }) == "send"
            return Classification(ranked: ranked, sure: sure, assisted: true)
        } catch {
            let targets = job.tools.targets(store, projects: projects.isEmpty ? nil : Set(projects))
            let (ranked, named) = RouterTools.unassisted(job.text, targets)
            if let named { return Classification(ranked: [Scored(target: named, p: 1)], sure: true, assisted: false) }
            let total = Double(max(1, ranked.reduce(0) { $0 + $1.score }))
            return Classification(ranked: ranked.map { Scored(target: $0.target, p: Double($0.score) / total) }, sure: false, assisted: false)
        }
    }

    // MARK: Ask back

    private func askBack(_ job: Job, _ found: Classification) {
        guard let store else { return }
        var options: [RouterAskBack.Option] = []
        var seen = Set<String>()
        for scored in found.ranked where scored.target != "unclear" && options.count < 3 {
            guard let option = option(scored.target, store: store, tools: job.tools), seen.insert(option.id).inserted else { continue }
            options.append(option)
        }
        let ask = RouterAskBack(id: job.id, message: job.text, context: job.context, options: options,
                                suggestion: found.top?.target, at: Date())
        askBacks.append(ask)
        store.updateDecision(job.id) {
            $0.add(.asked(options.map(\.title)))
            if $0.decision.label == nil { $0.decision.label = "unclear" }
        }
        progress[job.id] = nil
    }

    /// A target as a button.
    func option(_ target: String, store: Store, tools: RouterTools? = nil) -> RouterAskBack.Option? {
        if target.hasPrefix("answer:") {
            guard let card = store.router.cards.first(where: { $0.id == String(target.dropFirst(7)) }) else { return nil }
            return .init(target: target, title: card.title, detail: "\(card.kind.label) · \(store.folderName(card.folder ?? ""))")
        }
        if target.hasPrefix("session:") {
            guard let s = store.claudeSessions[String(target.dropFirst(8))] else { return nil }
            return .init(target: target, title: s.title, detail: store.folderName(s.folderKey))
        }
        if target.hasPrefix("new:") {
            let folder = String(target.dropFirst(4))
            return .init(target: target, title: "New session", detail: store.folderName(folder))
        }
        switch target {
        case "change_lookout", "compound": return .init(target: target, title: "Change Lookout", detail: "Categories, groups, settings")
        case "question": return .init(target: target, title: "Answer from what Lookout knows", detail: "A question about now")
        default: return nil
        }
    }

    /// A target in words, for the log ("session “Fix build” in lookout").
    func describe(_ target: String, store: Store) -> String {
        guard let option = option(target, store: store) else { return target }
        if target.hasPrefix("answer:") { return "card “\(option.title)” (\(option.detail))" }
        if target.hasPrefix("session:") { return "session “\(option.title)” in \(option.detail)" }
        if target.hasPrefix("new:") { return "new session in \(option.detail)" }
        return option.title.lowercased()
    }

    /// Everything the "Something else…" picker offers: the sessions (latest first) and the projects.
    func pickerOptions() -> (sessions: [RouterAskBack.Option], projects: [RouterAskBack.Option]) {
        guard let store else { return ([], []) }
        let sessions = store.claudeSessions.values.filter { !$0.isArchived }.sorted { $0.lastActivity > $1.lastActivity }.prefix(30)
        return (sessions.compactMap { option("session:\($0.id)", store: store) },
                store.knownFolders.filter { !$0.isEmpty }.prefix(30).compactMap { option("new:\($0)", store: store) })
    }

    /// Typing a target's name in reply to an ask-back: its title or its project's name, as the whole message (a few words).
    /// The newest ask that the name fits once.
    func typedPick(_ text: String) -> (ask: UUID, target: String)? {
        guard let store, !askBacks.isEmpty else { return nil }
        var name = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !name.isEmpty, name.split(separator: " ").count <= 6 else { return nil }
        for prefix in ["to ", "the ", "in "] where name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
        func fits(_ option: RouterAskBack.Option) -> Bool {
            let title = option.title.lowercased(), detail = option.detail.lowercased()
            return name == title || name == "\(title) (\(detail))" || name == "\(title) in \(detail)"
                || (option.target.hasPrefix("new:") && (name == detail || name == "new session in \(detail)"))
        }
        let everything = pickerOptions()
        for ask in askBacks.reversed() {
            let own = ask.options.filter(fits)
            if own.count == 1 { return (ask.id, own[0].target) }
            guard own.isEmpty else { continue }
            let any = (everything.sessions + everything.projects).filter(fits)
            if any.count == 1 { return (ask.id, any[0].target) }
        }
        _ = store
        return nil
    }
}

// MARK: - The real effects

extension RouterDispatcher.Effects {
    /// Nothing is available: before the dispatcher has set up its own.
    static var unavailable: Self {
        let no = RouterTools.Failure("The Router isn't ready")
        return Self(rank: { _, _, _, _ in throw no }, prepare: { _, _ in throw no }, start: { _, _, _, _ in throw no },
                    send: { _, _ in throw no }, answer: { _, _, _ in throw no }, run: { _, _, _ in throw no })
    }

    @MainActor
    static func live(_ dispatcher: RouterDispatcher) -> Self {
        func store(_ d: RouterDispatcher) throws -> Store {
            guard let store = d.storeForEffects else { throw RouterTools.Failure("Lookout isn't ready") }
            return store
        }
        func object(_ json: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        }
        return Self(
            rank: { [weak dispatcher] tools, message, projects, history in
                guard let dispatcher, let store = dispatcher.storeForEffects else { throw RouterTools.Failure("Lookout isn't ready") }
                let key = store.typesafeKey ?? ""
                let choose = tools.chooser ?? (key.isEmpty ? nil : { options, hints, state, instructions in
                    try await JevClient(key: key).choose(options, hints: hints, for: state, instructions: instructions)
                })
                guard let choose else { throw RouterTools.Failure("no TypeSafe key is set") }
                var targets = tools.targets(store, projects: projects.isEmpty ? nil : Set(projects))
                let unclear = targets.removeLast()
                targets += [
                    .init(target: "change_lookout", hint: "The user wants to change Lookout itself: its inbox categories, groups or settings", title: "", project: ""),
                    .init(target: "question", hint: "A question about what is going on now (cards, working sessions, the inbox, settings), not for any session", title: "", project: ""),
                    .init(target: "compound", hint: "Several different things in one message, such as changing Lookout and telling a session something", title: "", project: ""),
                    unclear,
                ]
                // Plain keys for Jev (card ids and paths have characters it may not take), mapped back after.
                let keys = targets.indices.map { "o\($0)" }
                let hints = Dictionary(uniqueKeysWithValues: zip(keys, targets.map(\.hint)))
                var state = ["user message": message]
                if !history.isEmpty { state["the last decisions (corrections are the user's own)"] = history }
                let pick = try await choose(keys, hints, state,
                    "Which of the user's Claude Code sessions, open cards or projects is this message for? Or is it a request to change Lookout itself, a question about the current state, or several things at once? Follow what the user corrected before. Pick unclear unless the message makes it clear.")
                return pick.probabilities.compactMap { key, p -> RouterDispatcher.Scored? in
                    keys.firstIndex(of: key).map { RouterDispatcher.Scored(target: targets[$0].target, p: p) }
                }
            },
            prepare: { [weak dispatcher] tools, session in
                guard let dispatcher else { throw RouterTools.Failure("Lookout isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.prepare(store, session: session, ticket: tools.ticket()))
                guard let to = answer["to"] as? String, let ready = tools.prepared[to] else { throw RouterTools.Failure("Not prepared") }
                return .init(to: to, text: ready.text, body: ready.body ?? ready.text, original: ready.original,
                             rephrased: ready.rephrased, session: session, newSessionIn: nil)
            },
            start: { [weak dispatcher] tools, folder, title, settings in
                guard let dispatcher else { throw RouterTools.Failure("Lookout isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.startSession(store, project: folder, title: title, ticket: tools.ticket(), settings: settings))
                // No task left in the words: the session is started with no first message.
                if let peer = answer["peer"] as? String, (answer["text"] as? String)?.isEmpty == true, tools.prepared[peer] == nil {
                    return .init(to: peer, text: "", body: "", original: "", rephrased: false, session: answer["session"] as? String,
                                 newSessionIn: store.folderName(folder), settings: settings, settingsSigned: false)
                }
                guard let peer = answer["peer"] as? String, let ready = tools.prepared[peer] else { throw RouterTools.Failure("Not prepared") }
                return .init(to: peer, text: ready.text, body: ready.body ?? ready.text, original: ready.original,
                             rephrased: ready.rephrased, session: answer["session"] as? String, newSessionIn: ready.newSessionIn,
                             settings: settings, settingsSigned: ready.text.hasPrefix("⟦lookout v2 "))
            },
            send: { [weak dispatcher] tools, delivery in
                guard let dispatcher else { throw RouterTools.Failure("Lookout isn't ready") }
                let store = try store(dispatcher)
                guard let binary = dispatcher.claudePath(), let home = store.routerFiles?.routerHome else {
                    throw RouterTools.Failure("Claude Code wasn't found, so nothing can be sent")
                }
                try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                return try await RouterSender.send(binary: binary, cwd: home, to: delivery.to, text: delivery.text, tools: tools,
                                                   inbox: await store.relayInbox(for: delivery.to))
            },
            answer: { [weak dispatcher] tools, card, answers in
                guard let dispatcher else { throw RouterTools.Failure("Lookout isn't ready") }
                return try await tools.answerForm(try store(dispatcher), ["card": card, "answers": answers], ticket: tools.ticket())
            },
            run: { [weak dispatcher] tools, intent, input in
                guard let dispatcher else { throw RouterTools.Failure("Lookout isn't ready") }
                let store = try store(dispatcher)
                guard let binary = dispatcher.claudePath() else { throw RouterTools.Failure("Claude Code wasn't found") }
                return try await RouterRun.run(intent, input: input, tools: tools, store: store, binary: binary)
            })
    }
}

extension RouterDispatcher {
    fileprivate var storeForEffects: Store? { store }
}
