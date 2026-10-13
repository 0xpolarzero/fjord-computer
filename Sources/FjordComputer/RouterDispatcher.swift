import Foundation
import Observation

// Workflow B of docs/design/spec/router.md: what you type. Each message is a run of its own (several can be in flight),
// with no transcript: deterministic rules first (a reply armed on a card, a typed @project), then Jev with context,
// then a Haiku run only for what needs judgment or tools (changing Fjord Computer, a question about its state). Every
// run is one entry of the decision log, and the line on the page shows how far it is. When Jev isn't sure, nothing is
// sent: an ask-back card puts the question to you, and your pick is logged (as a correction when it isn't what Jev
// suggested).

/// What a message of yours comes with besides its text: the card you're replying to (its session is the target), the
/// projects you tagged (routing is narrowed to them, and a new session starts there), and what you made of Jev's pick while
/// you typed: the target you fixed by clicking it, or the one you waved off.
struct RouterContext: Equatable {
    /// A card id.
    var replyTo: String?
    /// Folder paths.
    var projects: [String]
    /// A dispatcher target (`session:<id>`, `new:<folder>`, an intent) you pinned.
    var target: String?
    /// A target you dismissed: the message never goes there without asking you.
    var notTo: String?
    /// Jev's pick you clicked (the pinned target, or `answer:<card>` for the reply), and what he made of the draft: the send
    /// logs it as confirmed, and goes with what was shown without asking him again.
    var predicted: String?
    var jev: RouterDispatcher.Classification?
    /// The target of Jev's pick shown over the composer for these very words as they are sent: only then does a send go
    /// with it as your confirmation (what was read while you typed but not shown, or shown for other words, is not).
    var shown: String?
    /// Where the @project and @session pills are in the message (character offsets of each "@name"): only these are ever
    /// taken out of your words as tags, never words that happen to match a project or a session's title.
    var pills: [Range<Int>]
    /// Every pill of the message, what it points to and where (`RouterPointer`; `tag` sets this, `pills` and `projects`
    /// together): a session tagged is where it goes, a notification or a category goes with it as a fenced block
    /// (`RouterPointers.context`).
    var mentions: [RouterMention] = []
    /// A category's "Then" sends it for a thing (`ActionMessage`): unattended, it goes only to a session (one there or a new
    /// one, never the Router's own runs: an incoming PR must never change settings), and when where isn't clear it waits for
    /// your pick, with no fallback.
    var action: RouterActionSource?
    /// Sent from the Router page's composer: its run shows as a pill over the composer, flying to where it went
    /// (`RouterFlights`), and an ask about it unfolds there rather than in Needs you.
    var flies = false

    init(replyTo: String? = nil, projects: [String] = [], target: String? = nil, notTo: String? = nil,
         predicted: String? = nil, jev: RouterDispatcher.Classification? = nil, shown: String? = nil, pills: [Range<Int>] = []) {
        self.replyTo = replyTo
        self.projects = projects
        self.target = target
        self.notTo = notTo
        self.predicted = predicted
        self.jev = jev
        self.shown = shown
        self.pills = pills
    }
}

// MARK: - The ask-back card

/// "Where should this go?": a message waiting for you to say where. Nothing is sent until you pick.
struct RouterAskBack: Identifiable, Equatable {
    /// "Choose folder…": a new session in a folder you pick (`RouterDispatcher.pick(_:folder:)`), where no clone of a
    /// notification's repo is known.
    static let chooseFolder = "choose_folder"

    /// A target you can pick: `answer:<card>`, `session:<id>`, `new:<folder>`, `change_fjord`, `question` or `chooseFolder`.
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
    /// Why it asks, when it isn't Jev's doubt ("No clone of owner/repo").
    var note: String? = nil
}

// MARK: - Dispatcher

@Observable @MainActor final class RouterDispatcher {
    /// A target and how likely Jev finds it.
    struct Scored: Equatable {
        var target: String
        var p: Double
    }

    /// Jev's answers to a routing call: the targets, and the questions asked with them in the same call.
    struct Ranking: Equatable {
        var scored: [Scored]
        /// Whether the first is sure enough to act on (`RouterTools.verdict`); nil: by the verdict of the scores alone.
        var sure: Bool? = nil
        /// The ask card's targets in order (`RouterTools.askCard`); nil: the ranking's own order.
        var card: [String]? = nil
        /// What it was decided on, for the routing trace (`RouterTrace`).
        var trace: RouterTrace.Inputs? = nil
    }

    /// What Jev (or the words alone) made of a message.
    struct Classification: Equatable {
        /// Best first.
        var ranked: [Scored]
        /// Confident enough to act (`RouterTools.verdict`).
        var sure: Bool
        /// Jev answered (else the words alone were matched against titles).
        var assisted: Bool
        /// Shown over the composer for these words as they were sent (`RouterContext.shown`): you went with it.
        var live = false
        /// The ask card's targets in order, if they differ from the ranking's (`RouterTools.askCard`).
        var card: [String]? = nil
        /// What it was decided on, for the routing trace (`RouterTrace`).
        var trace: RouterTrace.Inputs? = nil

        var top: Scored? { ranked.first }

        init(ranked: [Scored], sure: Bool, assisted: Bool) {
            self.ranked = ranked
            self.sure = sure
            self.assisted = assisted
        }

        /// Jev's answer, best first: in the verdict's order, sure by it; else the scores alone, through the same verdict.
        @MainActor init(_ ranking: Ranking) {
            if let sure = ranking.sure {
                self.init(ranked: ranking.scored, sure: sure, assisted: true)
                card = ranking.card
                trace = ranking.trace
                return
            }
            let route = Dictionary(ranking.scored.map { ($0.target, $0.p) }, uniquingKeysWith: +)
            let verdict = RouterTools.verdict(route: route, answers: [], gates: [:]) { $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil }
            self.init(ranked: verdict.ranked, sure: verdict.sure, assisted: true)
        }
    }

    /// Where a message goes without asking Jev, or that it needs him.
    enum Plan: Equatable {
        case reply(session: String, card: String?)
        case start(folder: String)
        /// A session forked ("fork <session>…", `SessionFork.request`).
        case fork(SessionFork.Request)
        /// A target you pinned.
        case route(String)
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

    /// Everything a run does outside Fjord Computer's own state, so a test stands in for each. The defaults are the
    /// real ones.
    struct Effects {
        /// Jev's probabilities over the targets, with the other questions of the same call, or why not.
        var rank: @MainActor (RouterTools, _ message: String, _ projects: [String]) async throws -> Ranking
        /// The message for a session with its addressing taken out (`Addressing`), and its signature.
        var prepare: @MainActor (RouterTools, _ session: String) async throws -> Delivery
        /// A new session in a project (folder) with the prepared first message. Throws `SessionStart.Held` when the Claude
        /// app has the session but doesn't run it yet.
        var start: @MainActor (RouterTools, _ folder: String, _ title: String, _ settings: SessionSettings?) async throws -> Delivery
        /// The signed send, through the gate: the plugin's ack when it went through the inbox.
        var send: @MainActor (RouterTools, Delivery) async throws -> String?
        /// A form answered for a card: what was answered.
        var answer: @MainActor (RouterTools, _ card: String, _ answers: [String: String]) async throws -> String
        /// A Haiku run for an intent, given the context it starts from.
        var run: @MainActor (RouterTools, RouterRun.Intent, _ input: String) async throws -> RouterRun.Answer
        /// Whether the plugin of the session (by Claude Code's id) takes back a delivery (`abort-v1`).
        var abortable: @MainActor (_ cli: String) async -> Bool = { _ in false }
        /// Takes a delivery back through the session's inbox: how far it had gone, as its plugin answered.
        var cancel: @MainActor (RouterDecision.Delivered) async throws -> RouterDecision.Cancelled = { _ in
            throw RouterTools.Failure("The Router isn't ready")
        }
        /// A held start's first message, prepared once the app runs its session (bounded: `SessionStart.heldWait`).
        var finish: @MainActor (RouterTools, SessionStart.Held) async throws -> Delivery = { _, _ in
            throw RouterTools.Failure("The Router isn't ready")
        }
        /// A session forked, with the prepared first message (none: `text` is empty). Throws `SessionStart.Held` as `start` does.
        var fork: @MainActor (RouterTools, SessionFork.Request) async throws -> Delivery = { _, _ in
            throw RouterTools.Failure("The Router isn't ready")
        }
    }

    /// Asks waiting for a pick, oldest first.
    private(set) var askBacks: [RouterAskBack] = []
    /// The runs of messages sent from the composer (`RouterContext.flies`), oldest first: the composer's pills.
    private(set) var flying: [UUID] = []
    /// How far each run under way is, by its entry in the log ("classifying", "sending"…).
    private(set) var progress: [UUID: String] = [:]
    /// A run of yours is under way: the composer shows Stop. An action's message being placed, or waiting its turn, is the
    /// inbox's, in the background (`actionRuns`): you send meanwhile, and Stop leaves it be.
    var isBusy: Bool { progress.keys.contains { !actionRuns.contains($0) } }
    /// What an action's message waiting its turn says on its line.
    static let waitingTurn = "waiting its turn"
    /// The entries of actions' messages under way or waiting their turn (`submit`, `launch`), until they end.
    @ObservationIgnored private var actionRuns: Set<UUID> = []
    /// Sends being taken back, by their entry in the log.
    private(set) var cancelling: Set<UUID> = []
    /// Starts whose session the Claude app has but doesn't run yet, by their entry: what their first message waits for. Not
    /// a run under way (you may send meanwhile); Stop ends them too.
    private(set) var held: [UUID: String] = [:]
    @ObservationIgnored private var heldTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var heldTools: [UUID: RouterTools] = [:]
    /// Held starts you chose not to send (`dropHeld`): their line says so.
    @ObservationIgnored private var dropped: Set<UUID> = []

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
    /// Jev's questions (tests answer for him); else `RouterTools.chooser` for the routing alone, else TypeSafe with your key.
    @ObservationIgnored var asker: JevAsker?
    /// Jev's routing of drafts asked while you typed, by their words and projects, for a while: sending one asks nothing again.
    @ObservationIgnored private var liveCache: [String: (at: Date, found: Classification, board: String)] = [:]
    static let liveFor: TimeInterval = 120
    /// Those still being asked, by the same key: a send of the same words waits for the answer instead of asking again.
    @ObservationIgnored private var livePending: [String: (id: UUID, task: Task<Classification?, Never>)] = [:]
    /// Moves on each correction or dismissal (`forgetLive`): an answer asked for before it is neither kept nor used.
    @ObservationIgnored private var liveGeneration = 0

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

    /// A composer pill is done with (landed, failed or dismissed): its run is no longer one of `flying`.
    func forgetFlying(_ id: UUID) { flying.removeAll { $0 == id } }

    /// The demo's ask and run under way gone (`RouterFlightDemo` plays its own).
    func clearPreview() {
        askBacks = []
        progress = [:]
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
        // An action's message: only while Triage and the Router are both on.
        if context.action != nil, !store.toolsLinked { return nil }
        // Sent as written (`RouterModel.sendable`): code keeps the indentation of its first line. Trimmed only to see it isn't empty.
        let text = RouterModel.sendable(text)
        guard !text.isEmpty else { return nil }
        var seen = Set<String>()
        let projects = context.projects.filter { seen.insert($0).inserted }
        var context = context
        context.projects = projects
        // A pill is an "@name" where it was said; anything else given as one isn't.
        let chars = Array(text)
        context.pills = context.pills.filter { $0.lowerBound >= 0 && $0.upperBound <= chars.count && !$0.isEmpty && chars[$0.lowerBound] == "@" }
        context.mentions = Self.mentions(context.mentions, in: text)
        var entry = RouterDecision(trigger: .you(text), decision: .init(intent: "message"),
                                   links: .init(cards: context.replyTo.map { [$0] } ?? []))
        entry.mentions = context.mentions.isEmpty ? nil : context.mentions
        entry.fromAction = context.action?.origin
        entry.actionStart = context.action.map { .init(title: $0.title, model: $0.model, effort: $0.effort) }
        let id = store.logDecision(entry)
        if context.flies, context.action == nil { flying.append(id) }
        let job = Job(id: id, text: text, context: context,
                      tools: makeTools(id, text, pills: context.pills, mentions: context.mentions, action: context.action != nil))
        // Actions' messages one at a time, in order (`nextAction`); yours at once.
        if context.action != nil {
            actionRuns.insert(id)
            actionQueue.append(job)
            progress[id] = Self.waitingTurn
            nextAction()
        } else {
            launch(job, stage: "starting") { [self] job in try await execute(job) }
        }
        return id
    }

    /// Actions' messages waiting their turn, oldest first, and the one being placed. A backlog (a refresh brings up to
    /// `InboxActions.perSync`) is placed one by one: the next starts once the one before is sent, has started a session,
    /// failed or waits on your pick, so it may go to the session that one started rather than start another beside it.
    @ObservationIgnored private var actionQueue: [Job] = []
    @ObservationIgnored private var actionPlacing: UUID?

    private func nextAction() {
        guard actionPlacing == nil else { return }
        while !actionQueue.isEmpty {
            let job = actionQueue.removeFirst()
            guard store?.toolsLinked == true else { drop(job, Self.unlinkedWords); continue }
            actionPlacing = job.id
            launch(job, stage: "starting") { [self] job in try await execute(job) }
            return
        }
    }

    /// An action's message that never ran (Stop, Triage or the Router switched off while it waited its turn): why, as its
    /// entry's last line.
    private func drop(_ job: Job, _ reason: String) {
        job.tools.endTurn()
        actionRuns.remove(job.id)
        progress[job.id] = nil
        store?.updateDecision(job.id) {
            $0.add(.failed(reason))
            $0.outcome = .done
        }
        follow(job.id)
        onFinish?(job.id)
    }

    /// You picked where an ask-back goes. Sends as an armed reply or a start would; the entry says it was a correction when
    /// the pick isn't what Jev suggested.
    @discardableResult
    func pick(_ id: UUID, target: String) -> Bool {
        guard let store, store.routerOn, let ask = askBacks.first(where: { $0.id == id }) else { return false }
        // "Choose folder…" picks with the folder you chose (`pick(_:folder:)`).
        guard target != RouterAskBack.chooseFolder else { return false }
        // An action's message goes only to a session, and only while Triage and the Router are both on.
        if ask.context.action != nil, RouterRun.Intent(rawValue: target) != nil || !store.toolsLinked { return false }
        // Offered when it was asked: a card the page has hidden since (or one addressed, a session archived) isn't sent to.
        guard eligible(target, store: store) else { return false }
        answer(ask, target: target, store: store)
        return true
    }

    /// "Choose folder…" on an ask: a new session in the folder you chose, with the message, whether Fjord Computer knew the
    /// folder or not.
    @discardableResult
    func pick(_ id: UUID, folder: String) -> Bool {
        guard let store, store.routerOn, !folder.isEmpty, let ask = askBacks.first(where: { $0.id == id }),
              ask.options.contains(where: { $0.target == RouterAskBack.chooseFolder }) else { return false }
        if ask.context.action != nil, !store.toolsLinked { return false }
        answer(ask, target: "new:\(folder)", store: store, folder: folder)
        return true
    }

    /// Sends an ask's message where you picked, logged as your pick (or your correction of Jev's suggestion).
    private func answer(_ ask: RouterAskBack, target: String, store: Store, folder: String? = nil) {
        let id = ask.id
        askBacks.removeAll { $0.id == id }
        let chosen = describe(target, store: store)
        let corrected = target != ask.suggestion
        traceLog.append(RouterTrace(kind: corrected ? .corrected : .picked, id: id, target: target,
                                    index: ask.options.firstIndex { $0.target == target }, from: ask.suggestion))
        // What Jev read while you typed no longer holds against your correction.
        if corrected { forgetLive() }
        store.updateDecision(id) {
            $0.decision.target = chosen
            $0.decision.targetID = target
            if corrected {
                $0.outcome = .corrected(from: ask.suggestion.map { describe($0, store: store) } ?? "no clear target", to: chosen)
                $0.decision.fromID = ask.suggestion
            }
        }
        // A pick that is Jev's own suggestion confirms it: an example for the next ones.
        if !corrected { store.updateDecision(id) { $0.decision.confirmed = true } }
        let tools = makeTools(id, ask.message, pills: ask.context.pills, mentions: ask.context.mentions,
                              action: ask.context.action != nil)
        tools.chosenFolder = folder
        launch(Job(id: id, text: ask.message, context: ask.context, tools: tools), stage: "starting") { [self] job in
            try await route(job, to: target)
        }
        follow(id)
    }

    /// You dismissed an ask-back: nothing is sent.
    /// `reason`: why it goes when you didn't dismiss it (Stop, a switch turned off): an action's entry says it as its last
    /// line, so its run fails with why.
    func dismiss(_ id: UUID, reason: String? = nil) {
        guard let store, let i = askBacks.firstIndex(where: { $0.id == id }) else { return }
        let ask = askBacks.remove(at: i)
        forgetLive()
        store.updateDecision(id) {
            if let reason, ask.context.action != nil {
                $0.add(.failed(reason))
            } else {
                $0.reply = $0.delivered == nil ? "Dismissed: nothing was sent." : "Dismissed: sent nowhere else."
            }
            $0.outcome = .done
        }
        follow(id)
    }

    /// Triage switched off: an action's message no longer goes anywhere. Its asks go, saying why, and those waiting their
    /// turn with them; one under way is stopped at its next step (`linked`).
    func unlinked() {
        for ask in askBacks where ask.context.action != nil { dismiss(ask.id, reason: Self.unlinkedWords) }
        let queued = actionQueue
        actionQueue = []
        for job in queued { drop(job, Self.unlinkedWords) }
    }

    /// An action's message moved on: its run says so (`Store.followActionRun`).
    private func follow(_ id: UUID) { store?.followActionRun(id, dispatcher: self) }

    /// Stops every run under way (nothing more is sent by them) and drops the asks waiting for you. A held start's first
    /// message isn't a run: its own line's "Don't send" drops it (`dropHeld`).
    /// `reason`: what an action's entry says of it (its run fails with why). `actions`: the inbox's actions' messages too,
    /// their runs and their asks (the Router switched off); Stop is for yours, and leaves those be (they weren't sent by
    /// you, and go on in the background).
    func stopAll(reason: String = "Stopped; nothing was sent", actions: Bool = false) {
        let stopped = { [actionRuns] (id: UUID) in actions || !actionRuns.contains(id) }
        for (id, task) in tasks where stopped(id) { task.cancel() }
        // Their turns end now, not once each run sees it was stopped: a send on its way is refused at its last gate.
        for (id, tools) in runTools where stopped(id) { tools.endTurn() }
        for ask in askBacks where actions || ask.context.action == nil { dismiss(ask.id, reason: reason) }
    }

    // MARK: Runs

    /// `action`: an action's message, whose every send is refused once Triage or the Router is off (`linked`).
    private func makeTools(_ id: UUID, _ text: String, pills: [Range<Int>], mentions: [RouterMention] = [],
                           action: Bool = false) -> RouterTools {
        let tools = RouterTools(store: store!)
        tools.claudePath = { [weak self] in self?.claudePath() }
        tools.decision = id
        tools.beginTurn(text, pills: pills)
        tools.tagged = RouterPointers.context(mentions, store: store!)
        if action { tools.deliveryCheck = { [weak store = self.store] in store?.toolsLinked == true ? nil : Self.unlinkedWords } }
        configure?(tools)
        return tools
    }

    /// A session started for an action's message, known before the Claude app's next read catches up: the next action's
    /// message (`nextAction`) may go to it rather than start another beside it.
    private func know(_ session: String, for job: Job, in folder: String) {
        guard let store, let action = job.context.action, store.claudeSessions[session] == nil else { return }
        store.claudeSessions[session] = ClaudeSession(id: session, title: action.title, folder: folder, lastActivity: Date(),
                                                      running: true)
    }

    /// An action's message its session couldn't take: asked where it goes instead, among its repo's world without that
    /// session (nor the one it was taken back from, when it was sent elsewhere), why said on the card.
    private func couldntReach(_ job: Job, session: String, _ error: Error) {
        guard let store else { return }
        let world = Self.repoWorld(job.context, store: store)
        let notTo = job.context.notTo
        let away = notTo.flatMap { Self.session(of: $0, store: store) }
        let others = (world?.targets ?? []).filter {
            let s = Self.session(of: $0, store: store)
            return s != session && $0 != notTo && (away == nil || s != away)
        }
        let title = store.claudeSessions[session].map { "“\(RouterDecision.clip($0.title, 40))”" } ?? "Its session"
        let why = error.localizedDescription.split(separator: "\n").first.map(String.init) ?? "it can't take a message now"
        askBack(job, Classification(ranked: others.map { Scored(target: $0, p: 0) }, sure: false, assisted: false),
                note: "\(title) couldn't take it: \(RouterDecision.clip(why, 120))", chooseFolder: others.isEmpty)
    }

    /// Why an action's message no longer goes: Triage or the Router switched off since it was sent to the Router.
    static let unlinkedWords = "Triage or the Router is off; nothing was sent"

    /// An action's message goes on only while Triage and the Router are both on, checked again before each step that
    /// reaches a session (after every wait: a start, a session the app runs later); the send's own gate checks once more
    /// (`deliveryCheck`). Anything else goes on.
    private func linked(_ context: RouterContext) throws {
        guard context.action != nil, store?.toolsLinked != true else { return }
        throw RouterTools.Failure(Self.unlinkedWords)
    }

    /// The pills of `text` that are where they say: each an "@name" inside it, none overlapping another.
    static func mentions(_ mentions: [RouterMention], in text: String) -> [RouterMention] {
        let chars = Array(text)
        var end = 0
        return mentions.sorted { $0.range.lowerBound < $1.range.lowerBound }.filter { m in
            guard m.range.lowerBound >= end, m.range.upperBound <= chars.count, !m.range.isEmpty,
                  chars[m.range.lowerBound] == "@" else { return false }
            end = m.range.upperBound
            return true
        }
    }

    private func launch(_ job: Job, stage first: String, _ body: @escaping (Job) async throws -> Void) {
        if job.context.action != nil { actionRuns.insert(job.id) }
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
        actionRuns.remove(job.id)
        progress[job.id] = nil
        tasks[job.id] = nil
        runTools[job.id] = nil
        // Waiting for your pick is not over; anything else not settled is done.
        if !askBacks.contains(where: { $0.id == job.id }), held[job.id] == nil {
            store?.updateDecision(job.id) { if $0.outcome == .pending { $0.outcome = .done } }
        }
        follow(job.id)
        onFinish?(job.id)
        // Placed: the next action's message goes.
        if actionPlacing == job.id {
            actionPlacing = nil
            nextAction()
        }
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
        case .reply(let session, let card):
            trace(job, path: "reply", action: "send", target: card.map { "answer:\($0)" } ?? "session:\(session)")
            // The reply to a card Jev picked while you typed: you went with his pick.
            if let card, job.context.predicted == "answer:\(card)" { confirm(job, "answer:\(card)") } else { chosen(job) }
            try await reply(job, session: session, card: card)
        case .start(let folder):
            trace(job, path: "start", action: "start", target: "new:\(folder)")
            chosen(job)
            try await start(job, folder: folder)
        case .fork(let request):
            trace(job, path: "fork", action: "fork", target: "session:\(request.session)")
            try await fork(job, request)
        case .route(let target):
            // A target you pinned, or the session you tagged.
            trace(job, path: job.context.target == target ? "pinned" : "tagged", action: "send", target: target)
            confirm(job, target)
            try await route(job, to: target)
        case .classify: try await classifyAndAct(job)
        }
    }

    /// Where routed messages are traced (`RouterTrace`); a test gives its own.
    @ObservationIgnored var traceLog = RouterTraceLog.shared

    /// A routing decided: what it was decided on and what it does, as a trace line.
    private func trace(_ job: Job, path: String, action: String, target: String?, inputs: RouterTrace.Inputs? = nil,
                       kind: RouterTrace.Kind = .decided) {
        let text = job.text
        let pills = job.context.pills.compactMap { range -> String? in
            let chars = Array(text)
            guard range.lowerBound >= 0, range.upperBound <= chars.count else { return nil }
            return String(chars[range])
        }
        // What a send to it does: a new session starts one, an intent is the Router's own run.
        let does = action != "send" ? action
            : target?.hasPrefix("new:") == true ? "start"
            : target.flatMap { RouterRun.Intent(rawValue: $0) } != nil ? "intent" : "send"
        traceLog.append(RouterTrace(kind: kind, id: job.id, message: RouterTools.redacted(text),
                                    pills: pills.isEmpty ? nil : pills, pinned: job.context.target, shown: job.context.shown,
                                    notTo: job.context.notTo, replyTo: job.context.replyTo, path: path, action: does,
                                    target: target, inputs: inputs))
    }

    /// Where it goes is yours (the card you replied to, the project you tagged to start in).
    private func chosen(_ job: Job) {
        store?.updateDecision(job.id) { $0.decision.confirmed = true }
    }

    /// A target you fixed yourself: an example for the next ones.
    private func confirm(_ job: Job, _ target: String) {
        guard let store else { return }
        store.updateDecision(job.id) {
            $0.decision.target = describe(target, store: store)
            $0.decision.targetID = target
            $0.decision.label = Self.label(target)
            $0.decision.confirmed = true
        }
    }

    /// Where a message goes without asking Jev. A reply armed on a card fixes the session, and so does a target you pinned. A
    /// single typed `@project` fixes a new session there when the message asks for one, or when the project has nothing else
    /// to be for (no open card, no session). Anything else is for Jev.
    static func plan(text: String, context: RouterContext, store: Store) -> Plan {
        // An action's message is never the Router's own, nor a fork: it is sent or starts a session.
        let unattended = context.action != nil
        // Wholly for the Router ("@router what needs me?"): asked of it, whatever reply is armed or target pinned (a session
        // would get nothing of it). An aside in a message for a session goes with that message, taken out.
        if !unattended, forRouter(text, pills: context.pills) { return .classify }
        // "fork <session>…": of the session named, else of the one pinned ("fork this session"). Never while a card's reply
        // is armed: words for it are its answer ("branch" to "Should I create a branch or commit to main?").
        if !unattended, context.replyTo == nil,
           let fork = SessionFork.request(RouterTools.pastLeadingTags(text, pills: context.pills),
                                          pinned: context.target.flatMap { $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil },
                                          store: store) {
            return .fork(fork)
        }
        if let id = context.replyTo, let card = store.router.cards.first(where: { $0.id == id }) {
            return .reply(session: card.sessionID, card: id)
        }
        if let target = context.target { return .route(target) }
        // A session you tagged is where it goes, while it is there; several tagged, Jev picks among them (`classifyAndAct`).
        let tagged = context.sessions.filter { store.claudeSessions[$0].map { !$0.isArchived } == true }
        if tagged.count == 1 { return .route("session:\(tagged[0])") }
        if context.projects.count == 1, let folder = context.projects.first {
            if wantsNewSession(text, pills: context.pills) { return .start(folder: folder) }
            let other = store.openRouterCards.contains { ($0.folder ?? "") == folder }
                || store.claudeSessions.values.contains { !$0.isArchived && $0.folderKey == folder }
            if !other { return .start(folder: folder) }
        }
        return .classify
    }

    /// Everything in the message is for the Router (`@router`, its asides): nothing of it would go on to a session.
    static func forRouter(_ text: String, pills: [Range<Int>]) -> Bool {
        guard RouterTools.hasRouterAside(text) else { return false }
        do { _ = try Addressing.edit(text, pills: pills) } catch { return error is Addressing.NothingLeft }
        return false
    }

    /// "start a new session…", "new chat about…", "open a session to…": said as the message's own request, at its start or
    /// after its @projects. A session mentioned anywhere else ("don't start a new session; fix it in this one", "fix it in
    /// a new session") is for Jev.
    static func wantsNewSession(_ text: String, pills: [Range<Int>] = []) -> Bool {
        let t = RouterTools.pastLeadingTags(text, pills: pills)
        return t.range(of: SessionStart.startPhrase, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A short title for a new session from its task (`SessionStart.task`), without the @project: its first sentence when
    /// that is short ("Router test, please ignore and do nothing"), else its first few words, never ending on a little word
    /// ("to", "the") and marked as cut ("add a dark mode badge…").
    static func title(for text: String) -> String {
        // The first line with words of its own (a line of @project tags alone is skipped).
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("@") } }
        var words = lines.first { !$0.isEmpty } ?? []
        if let end = words.firstIndex(where: { ".!?".contains($0.last ?? " ") && !abbreviations.contains($0.lowercased()) }) {
            words = Array(words[...end])
        }
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,:;-–—"))
        var cut = false
        if words.count > titleWords {
            words = Array(words.prefix(titleCut))
            while words.count > 1, let last = words.last, littleWords.contains(last.lowercased().trimmingCharacters(in: trim)) {
                words.removeLast()
            }
            cut = true
        }
        let title = SessionStart.cleanTitle(words.joined(separator: " ")).trimmingCharacters(in: trim)
        return title.isEmpty ? "New session" : cut ? title + "…" : title
    }

    /// A first sentence up to this many words is the title whole; a longer one is cut to `titleCut`.
    static let titleWords = 8
    /// Words ending in a full stop that don't end a sentence.
    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "cf.", "approx.", "mr.", "mrs.", "ms.", "dr.", "no."]
    static let titleCut = 6
    private static let littleWords: Set<String> = [
        "a", "an", "the", "to", "and", "or", "but", "of", "for", "in", "on", "at", "by", "with", "from", "into", "that", "this",
        "it", "is", "are", "be", "so", "as", "if", "my", "our", "your", "its",
    ]

    /// The answer a question card's form takes from a message that is exactly an option (or several, for a multiple choice):
    /// anything else is text for the session. Only a single question; a plan is never answered this way.
    static func formAnswers(_ form: PendingForm, message: String) -> [String: String]? {
        guard !form.isPlan, form.questions.count == 1, let q = form.questions.first else { return nil }
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let said = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // The label as said (case aside) wins, its punctuation kept ("C#" vs "C"); only else the words alone ("sqlite."
        // for "SQLite"), and then only when they fit one option: two fitting ("C." for "C#" and "C") is text for the session.
        func option(_ text: String) -> String? {
            let ws = CharacterSet.whitespacesAndNewlines
            let exact = text.trimmingCharacters(in: ws).lowercased()
            let hits = q.options.filter { $0.label.trimmingCharacters(in: ws).lowercased() == exact }
            if hits.count == 1 { return hits[0].label }
            guard hits.isEmpty else { return nil }
            let t = text.trimmingCharacters(in: trim).lowercased()
            let loose = q.options.filter { $0.label.trimmingCharacters(in: trim).lowercased() == t }
            return loose.count == 1 ? loose[0].label : nil
        }
        if let one = option(said) { return [q.question: one] }
        guard q.multiSelect else { return nil }
        let parts = said.replacingOccurrences(of: " and ", with: ",").split(separator: ",").map(String.init)
        let labels = parts.compactMap(option)
        guard parts.count > 1, labels.count == parts.count else { return nil }
        return [q.question: FormBridge.joined(labels)]
    }

    /// Passes your words to a session: the form's answer when you gave one, else your words without their addressing, signed, through the gate.
    private func reply(_ job: Job, session: String, card: String?) async throws {
        guard let store else { return }
        // What the session would get, its addressing taken out ("@lookout SQLite", "SQLite (@router no rush)"), is what
        // answers its form. Sent to the session itself (picked under "Something else…"), the form it is stopped on.
        let said = (try? Addressing.edit(job.text, pills: job.context.pills).text) ?? job.text
        let held = card.map { id in store.router.cards.filter { $0.id == id } }
            ?? store.routerShownOpenCards.filter { $0.sessionID == session && store.pendingForm(for: $0) != nil }
        if held.count == 1, let c = held.first, let form = store.pendingForm(for: c),
           let answers = Self.formAnswers(form, message: said) {
            stage(job, "answering")
            _ = try await effects.answer(job.tools, c.id, answers)
            note(job, .answered(card: c.title), session: session, card: c.id)
            return
        }
        stage(job, "preparing")
        try linked(job.context)
        let delivery: Delivery
        do {
            delivery = try await effects.prepare(job.tools, session)
        } catch where job.context.action != nil && !(error is CancellationError) && !Task.isCancelled {
            // An action's message the session can't take (it doesn't run in the Claude app now): nothing went, so it isn't
            // lost: you pick where it goes instead, that session left out.
            try linked(job.context)
            return couldntReach(job, session: session, error)
        }
        try linked(job.context)
        stage(job, "sending")
        // The cards open now, as they are: one that changes while this goes isn't addressed by it.
        let eligible = Dictionary(store.router.cards.filter(\.isOpen).map { ($0.id, store.cardRevisions[$0.id, default: 0]) },
                                  uniquingKeysWith: { a, _ in a })
        let before = store.claudeSessions[session]
        _ = try await effects.send(job.tools, delivery)
        note(job, .sent(to: delivery.to, text: delivery.body, original: delivery.rephrased ? delivery.original : nil),
             session: session, card: card)
        await delivered(job, delivery, session: session, turns: before?.completedTurns ?? 0, busy: before?.running ?? false)
        // Its turn cards are cleared by it; Jev reads it for the questions it left, and judges a question or plan it waits on.
        stage(job, "checking its cards")
        await store.judgeCards(session: session, message: job.text, eligible: eligible,
                               asker: job.tools.chooser.map(JevClient.asker(choosing:)), decision: job.id)
    }

    /// A send went: what it delivered, for a Cancel (`turns` and `busy`: the session as it was just before).
    private func delivered(_ job: Job, _ delivery: Delivery, session: String?, turns: Int, busy: Bool) async {
        guard let session, let header = RelayInbox.header(of: delivery.text) else { return }
        let at = Date()
        let abortable = await effects.abortable(header.target)
        store?.updateDecision(job.id) {
            $0.delivered = .init(session: session, cli: header.target, nonce: header.nonce, at: at, turns: turns, busy: busy,
                                 abortable: abortable)
        }
    }

    // MARK: Cancel

    /// Takes back what a run sent: if Claude hadn't started on it, it never will; if it was working on it, its turn stops.
    /// Anything it already did stays done, and the message stays in the session's history. The entry says how it went
    /// (and the trace, `elsewhere` when it is to be sent elsewhere); nil when there's nothing to take back, or it failed.
    @discardableResult
    func cancel(_ id: UUID, elsewhere: Bool = false) async -> RouterDecision.Cancelled? {
        guard let store, let entry = store.router.decisions.first(where: { $0.id == id }), let sent = entry.delivered,
              sent.cancelled == nil, sent.abortable, !cancelling.contains(id) else { return nil }
        cancelling.insert(id)
        defer { cancelling.remove(id) }
        do {
            let how = try await effects.cancel(sent)
            store.updateDecision(id) {
                guard $0.delivered?.nonce == sent.nonce else { return }
                $0.delivered?.cancelled = how
                $0.add(.cancelled(how))
            }
            traceLog.append(RouterTrace(kind: .cancelled, id: id, target: entry.decision.targetID ?? "session:\(sent.session)",
                                        how: how.rawValue, after: (Date().timeIntervalSince(sent.at) * 10).rounded() / 10,
                                        elsewhere: elsewhere ? true : nil))
            return how
        } catch {
            let first = error.localizedDescription.split(separator: "\n").first.map(String.init) ?? "failed"
            store.updateDecision(id) { $0.add(.failed("couldn't cancel: " + RouterDecision.clip(first, 100))) }
            return nil
        }
    }

    /// A wrong send: taken back where it went, then asked again with that place left out. The button you pick is a
    /// correction of it, an example for the next routings, as a correction on an ask is. Only once it was stopped there: a
    /// cancel that fails, or comes too late, sends no second copy (the entry says so, and you can send it again yourself).
    func sendElsewhere(_ id: UUID) {
        guard let store, store.routerOn, progress[id] == nil, !askBacks.contains(where: { $0.id == id }),
              let entry = store.router.decisions.first(where: { $0.id == id }), case .you(let text) = entry.trigger,
              let sent = entry.delivered else { return }
        let wrong = entry.decision.targetID ?? "session:\(sent.session)"
        var context = RouterContext(notTo: wrong)
        // What it tagged goes with it again; where it goes is asked anew, not taken from its pills. An action's message is
        // still one: only to a session, a new one called after its thing and on its model and effort, while Triage and the
        // Router are both on.
        context.mentions = entry.mentions ?? []
        context.action = entry.actionSource
        if context.action != nil, !store.toolsLinked { return }
        forgetLive()
        store.updateDecision(id) { $0.outcome = .pending }
        let unattended = context.action != nil
        launch(Job(id: id, text: text, context: context,
                   tools: makeTools(id, text, pills: [], mentions: context.mentions, action: unattended)),
               stage: "cancelling") { [self] job in
            let how = await cancel(id, elsewhere: true)
            guard let how, how.stopped else {
                let why = how.map { "It wasn't stopped there (\($0.words)), so it wasn't sent elsewhere: send it again if it should go somewhere else too." }
                store.updateDecision(id) { $0.reply = why ?? "Couldn't cancel it, so it wasn't sent elsewhere." }
                return
            }
            stage(job, "classifying")
            let world = Self.repoWorld(job.context, store: store)
            let noClone = world?.clones.isEmpty == true
            var found = noClone && unattended ? Classification(ranked: [], sure: false, assisted: false)
                : await classify(job, projects: noClone ? [] : world?.clones ?? [])
            Self.keep(&found, world: world, unattended: unattended, store: store)
            let away = { (target: String) in target != wrong && Self.session(of: target, store: store) != sent.session }
            found.ranked = found.ranked.filter { away($0.target) }
            found.card = found.card?.filter(away)
            // Nothing left for an action's message (the repo's one clone was where it went): a folder of your choosing.
            let none = unattended && found.ranked.isEmpty && (found.card ?? []).isEmpty
            try linked(job.context)
            askBack(job, found, suggestion: wrong, path: "elsewhere", note: noClone ? world?.note : nil, chooseFolder: noClone || none)
        }
    }

    /// Starts a session in a project with your words as its first message.
    private func start(_ job: Job, folder: String) async throws {
        guard let store else { return }
        stage(job, "starting a session")
        // The title and the first message come from the task, never from the request to start the session.
        let task = SessionStart.task(from: job.text, pills: job.context.pills,
                                     projects: [store.folderName(folder), (folder as NSString).lastPathComponent])
        let project = store.folderName(folder)
        // "…with opus, high effort": set in the session by its plugin before the first message; else your defaults. An
        // action's are its own (its words don't set them), and its session is called after its thing.
        let settings = if let action = job.context.action { SessionSettings(model: action.model, effort: action.effort) }
            else { SessionSettings.parse(SessionStart.request(job.text, pills: job.context.pills)) }
        let delivery: Delivery
        try linked(job.context)
        do {
            delivery = try await effects.start(job.tools, folder, job.context.action?.title ?? Self.title(for: task), settings)
        } catch let waiting as SessionStart.Held {
            // Not known as a session yet: the app doesn't run it, so it can't take the next action's message.
            return hold(job, waiting)
        }
        if let session = delivery.session { know(session, for: job, in: folder) }
        // Started for an action: its cards say where it came from.
        if let action = job.context.action, let session = delivery.session { store.noteOrigin(action.origin, for: session) }
        if delivery.text.isEmpty {
            // Nothing to send: the settings travel with the first message, so they can't be applied.
            note(job, .started(session: delivery.session, project: project, model: nil, effort: nil), session: delivery.session)
            if settings != nil {
                store.updateDecision(job.id) { $0.add(.failed("model/effort: no first message to set them with")) }
            }
            return
        }
        if let session = delivery.session { store.noteFjordStarted(session) }
        // Started, its first message not sent while Triage or the Router is off: the session stays, the line says why.
        do { try linked(job.context) } catch {
            note(job, .started(session: delivery.session, project: project, model: nil, effort: nil), session: delivery.session)
            throw error
        }
        stage(job, "sending")
        let ack = try await effects.send(job.tools, delivery)
        await delivered(job, delivery, session: delivery.session, turns: 0, busy: false)
        if let settings {
            let applied = AppliedSettings.from(ack: ack, requested: settings, supported: delivery.settingsSigned)
            store.updateDecision(job.id) { applied.record(session: delivery.session, project: project, in: &$0) }
        } else {
            note(job, .started(session: delivery.session, project: project, model: nil, effort: nil), session: delivery.session)
        }
    }

    // MARK: Forks

    /// Forks `session` (`SessionFork`): from `point`, with `message` as the fork's first message (empty: none). A run of
    /// its own, in the history as `trigger` says. Returns its entry in the log. `mentions`: the pills in the message, whose
    /// blocks go after it, fenced (`RouterTools.tagged`).
    @discardableResult
    func fork(_ request: SessionFork.Request, trigger: String, mentions: [RouterMention] = []) -> UUID? {
        guard let store, store.routerOn else { return nil }
        let id = store.logDecision(RouterDecision(trigger: .you(trigger), decision: .init(intent: "fork")))
        // The turn is the fork's first message: the words the send gate lets through, as yours.
        let words = request.message.isEmpty ? trigger : request.message
        launch(Job(id: id, text: words, context: RouterContext(), tools: makeTools(id, words, pills: [], mentions: mentions)),
               stage: "starting") { [self] job in
            trace(job, path: "fork", action: "fork", target: "session:\(request.session)")
            try await fork(job, request)
        }
        return id
    }

    /// What the history says a fork made: a session in the original's project, forked from it.
    static func forkLabel(_ request: SessionFork.Request, store: Store) -> String {
        let session = store.claudeSessions[request.session]
        let project = session.map { store.folderName($0.folderKey) } ?? "a project"
        let from = session.map { "“\(RouterDecision.clip($0.title, 40))”" } ?? "a session"
        return switch request.point {
        case .whole: "\(project) (fork of \(from))"
        case .beforeLast: "\(project) (fork of \(from), before your last message)"
        case .before: "\(project) (fork of \(from), before that message)"
        }
    }

    private func fork(_ job: Job, _ request: SessionFork.Request) async throws {
        guard let store else { return }
        stage(job, "forking the session")
        let label = Self.forkLabel(request, store: store)
        store.updateDecision(job.id) {
            $0.decision.intent = "fork"
            $0.decision.label = "fork"
            $0.decision.target = describe("session:\(request.session)", store: store)
            $0.decision.targetID = "session:\(request.session)"
        }
        let delivery: Delivery
        do {
            delivery = try await effects.fork(job.tools, request)
        } catch var waiting as SessionStart.Held {
            waiting.project = label
            return hold(job, waiting)
        }
        if let session = delivery.session { store.noteFjordStarted(session) }
        note(job, .started(session: delivery.session, project: label, model: nil, effort: nil), session: delivery.session)
        guard !delivery.text.isEmpty else { return }
        stage(job, "sending")
        _ = try await effects.send(job.tools, delivery)
        note(job, .sent(to: delivery.to, text: delivery.body, original: nil), session: delivery.session)
    }

    /// A start the Claude app has but doesn't run yet: done as a start (the session is there), its first message sent once
    /// the app runs it, in a turn of its own and not as a run under way (the composer is free meanwhile, and Stop leaves
    /// it be: its line's "Don't send" drops it). Waiting too long, the Router switched off or reset, says the message wasn't
    /// sent; the session stays.
    private func hold(_ job: Job, _ waiting: SessionStart.Held) {
        guard let store else { return }
        let id = job.id
        let session = waiting.waiting.sessionID
        store.noteFjordStarted(session)
        if let action = job.context.action { store.noteOrigin(action.origin, for: session) }
        store.updateDecision(id) { $0.add(.started(session: session, project: waiting.project, model: nil, effort: nil), session: session) }
        guard waiting.ready != nil else {
            if waiting.settings != nil { store.updateDecision(id) { $0.add(.failed("model/effort: no first message to set them with")) } }
            return
        }
        held[id] = Self.heldWords
        let tools = makeTools(id, job.text, pills: job.context.pills, mentions: job.context.mentions,
                              action: job.context.action != nil)
        let context = job.context
        heldTools[id] = tools
        heldTasks[id] = Task { [weak self] in
            do {
                guard let self else { return }
                let delivery = try await effects.finish(tools, waiting)
                try Task.checkCancellation()
                // The session ran only now: an action's first message goes only if Triage and the Router are still on.
                try linked(context)
                held[id] = "sending"
                let ack = try await effects.send(tools, delivery)
                store.updateDecision(id) { entry in
                    if let settings = waiting.settings {
                        entry.done.removeAll { if case .started = $0 { true } else { false } }
                        AppliedSettings.from(ack: ack, requested: settings, supported: delivery.settingsSigned)
                            .record(session: session, project: waiting.project, in: &entry)
                    }
                    entry.add(.sent(to: delivery.to, text: delivery.body, original: nil), session: session)
                }
            } catch {
                let dropped = self?.dropped.remove(id) != nil
                let reason = dropped ? "its first message wasn't sent: you chose not to send it"
                    : error is CancellationError ? "its first message wasn't sent"
                    : error.localizedDescription.split(separator: "\n").first.map(String.init) ?? "failed"
                store.updateDecision(id) { $0.add(.failed(RouterDecision.clip(reason, 120))) }
            }
            tools.endTurn()
            self?.held[id] = nil
            self?.heldTasks[id] = nil
            self?.heldTools[id] = nil
            store.updateDecision(id) { if $0.outcome == .pending { $0.outcome = .done } }
            self?.follow(id)
            self?.onFinish?(id)
        }
    }

    /// What a held start's line says while its first message waits.
    static let heldWords = "the first message waits for the Claude app to run it" + SessionStart.NotRunning.reason

    /// "Don't send" on a held start's line: its first message is dropped (the session stays), its turn ended at once so
    /// nothing of it can still go.
    func dropHeld(_ id: UUID) {
        guard let task = heldTasks[id] else { return }
        dropped.insert(id)
        heldTools[id]?.endTurn()
        task.cancel()
    }

    /// Haiku, fresh, for what needs judgment or tools; its reply is what the history shows.
    private func think(_ job: Job, _ intent: RouterRun.Intent) async throws {
        guard let store else { return }
        stage(job, "working")
        let input = store.routerRunContext(message: job.text, projects: job.context.projects, tagged: job.tools.tagged,
                                           excluding: job.id).text()
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
        let unattended = job.context.action != nil
        // A notification tagged with no project or session: the message is for its repo's world, its clones' sessions and a
        // new session in each (`repoWorld`); yours may also be for the Router itself (a question about the PR).
        let world = Self.repoWorld(job.context, store: store)
        // No clone of the repo at all: no guess. An action's message waits for you to choose a folder, with no call to Jev.
        let noClone = world?.clones.isEmpty == true
        if noClone, unattended {
            try linked(job.context)
            return askBack(job, Classification(ranked: [], sure: false, assisted: false), note: world?.note, chooseFolder: true)
        }
        let narrowed = noClone ? job.context.projects : world?.clones ?? job.context.projects
        let inWorld = Self.inWorld(world, unattended: unattended, store: store)
        // The pick shown over the composer for these words is the decision: sent as shown, not asked again.
        var found: Classification
        if let shown = job.context.shown, let carried = job.context.jev, carried.assisted, carried.sure, carried.top?.target == shown {
            found = carried
        } else {
            found = await classify(job, projects: narrowed)
        }
        try Task.checkCancellation()
        // Switched off while Jev was asked: an action's message goes nowhere, not even to a card for you.
        try linked(job.context)
        // Only the pick you saw over the composer, for these words, is one you went with; a pick read while you typed (and
        // kept for the send) that you never saw is Jev's like any other.
        found.live = found.assisted && found.sure && found.top.map { $0.target == job.context.shown } == true
        // Where you waved Jev's pick off isn't gone to without asking you, and his pick for these words is asked again.
        if let notTo = job.context.notTo, found.top?.target == notTo {
            found.sure = false
            liveCache[Self.liveKey(job.text, narrowed)] = nil
        }
        Self.keep(&found, world: world, unattended: unattended, store: store)
        // Where your own words send it ("start a session in lookout …", "tell CI to …"), resolved here and not by Jev, is
        // where it goes: his pick of another doesn't send it elsewhere ("tell CI to update the docs" isn't for Docs). Not
        // where you waved it off, nor when it is gone.
        // The sessions you tagged (more than one: one alone was sent to, `plan`): only they, their cards and the Router's own
        // runs are gone to; when Jev's pick isn't among them, you pick among them. Not for a message wholly for the Router.
        let scope = Self.forRouter(job.text, pills: job.context.pills) ? []
            : Set(job.context.sessions.filter { store.claudeSessions[$0].map { !$0.isArchived } == true })
        let inScope = { (target: String) in
            scope.isEmpty || RouterRun.Intent(rawValue: target) != nil || Self.session(of: target, store: store).map(scope.contains) == true
        }
        if !scope.isEmpty {
            let kept = found.ranked.filter { inScope($0.target) }
            if kept.first?.target != found.top?.target { found.sure = false }
            found.ranked = kept.isEmpty ? scope.sorted().map { Scored(target: "session:\($0)", p: 0) } : kept
            found.card = found.card?.filter(inScope)
        }
        // An action's message with nothing saying where it may go (its notification gone, a session pill of one archived
        // since): never sent on Jev's pick among every session; you pick.
        let unbounded = unattended && world == nil && job.context.projects.isEmpty && scope.isEmpty
        if unbounded { found.sure = false }
        let targets = job.tools.targets(store, projects: narrowed.isEmpty ? nil : Set(narrowed))
        let named = unbounded || (!unattended && Self.forRouter(job.text, pills: job.context.pills))
            ? nil : RouterTools.destination(job.text, targets, store: store, pills: job.context.pills)
        if let named, named != found.top?.target, named != job.context.notTo, inScope(named), inWorld(named),
           eligible(named, store: store) {
            trace(job, path: "named", action: "send", target: named, inputs: found.trace)
            confirm(job, named)
            return try await route(job, to: named)
        }
        // Wholly for the Router: one of its own runs, never a session or a project; you pick when Jev's pick isn't one.
        if !unattended, Self.forRouter(job.text, pills: job.context.pills) {
            let intents = found.ranked.filter { RouterRun.Intent(rawValue: $0.target) != nil }
            if intents.first?.target != found.top?.target { found.sure = false }
            found.ranked = intents.isEmpty ? [Scored(target: "question", p: 0), Scored(target: "change_fjord", p: 0)] : intents
        }
        store.updateDecision(job.id) {
            $0.decision.label = found.top.map { Self.label($0.target) }
            $0.decision.confidence = found.top?.p
            $0.decision.target = found.top.map { describe($0.target, store: store) }
            $0.decision.targetID = found.top?.target
            // Sent with Jev's pick shown over the composer: you went with it.
            if found.live, found.sure { $0.decision.confirmed = true }
        }
        // A session stopped on a permission gets words not addressed to it only with your click: it is the ask's first
        // button. Its card could be what made it the pick ("May I delete the production data?" for a "yes"). An ask of its
        // own ("SQLite or Postgres?") takes an answer on the evidence above, as any session does.
        if found.sure, !found.live, let top = found.top, let session = Self.session(of: top.target, store: store),
           Self.asksYou(session, store: store), !Self.addressed(job.text, to: session, store: store) {
            found.sure = false
        }
        // Hidden, addressed or gone while Jev was asked: you pick among what is there now.
        if found.sure, let top = found.top, !eligible(top.target, store: store) { found.sure = false }
        if found.sure, let top = found.top {
            // Where your own words send it: yours, as a pin is, so a follow-up may go there.
            if named == top.target { chosen(job) }
            trace(job, path: found.live ? "live" : found.assisted ? "jev" : "words", action: "send", target: top.target,
                  inputs: found.trace)
            return try await route(job, to: top.target)
        }
        askBack(job, found, note: noClone ? world?.note : nil, chooseFolder: noClone)
    }

    /// Jev's routing of a draft while you type: the same call a send makes, kept by its words and projects for
    /// `liveFor` so that sending them asks nothing again. Nil when he can't be asked.
    func predict(_ text: String, projects: [String], mentions: [RouterMention] = []) async -> Classification? {
        guard let store, store.jevAllows(.drafts) else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A notification tagged with no project or session: its repo's world, as the send narrows it (`classifyAndAct`).
        var tagged = RouterContext(projects: projects)
        tagged.mentions = mentions
        let narrowed = Self.repoWorld(tagged, store: store).flatMap { $0.clones.isEmpty ? nil : $0.clones } ?? projects
        let key = Self.liveKey(text, narrowed)
        if let hit = live(key) { return hit }
        if let pending = livePending[key] { return await pending.task.value }
        let tools = RouterTools(store: store)
        // What the draft tags is read as the send would have it.
        tools.tagged = RouterPointers.context(mentions, store: store)
        configure?(tools)
        // Its own task: a draft that changes, or is sent, doesn't stop it, so the send can take its answer.
        let id = UUID()
        let generation = liveGeneration
        let board = Self.boardRevision(store)
        let pending = Task { [weak self] () -> Classification? in
            guard let self else { return nil }
            defer { if self.livePending[key]?.id == id { self.livePending[key] = nil } }
            // Switched off meanwhile ("Let Jev read what you type"): nothing more goes, and what came is dropped.
            guard self.store?.jevAllows(.drafts) == true, let ranking = try? await self.effects.rank(tools, text, narrowed),
                  self.store?.jevAllows(.drafts) == true else { return nil }
            // Read before a correction or a dismissal: routed as it was then, so it goes.
            guard self.liveGeneration == generation else { return nil }
            let found = Classification(ranking)
            self.liveCache = self.liveCache.filter { Date().timeIntervalSince($0.value.at) < Self.liveFor }
            self.liveCache[key] = (Date(), found, board)
            return found
        }
        livePending[key] = (id, pending)
        return await pending.value
    }

    static func liveKey(_ text: String, _ projects: [String]) -> String {
        ([text.trimmingCharacters(in: .whitespacesAndNewlines)] + projects).joined(separator: "\u{1}")
    }

    /// What a pick read while you typed depends on beyond its words: the cards shown, the sessions working, the latest
    /// to finish, where your last message went. Evals decide every message on the board it was sent on, so a pick read
    /// on an earlier board is read again (one call) rather than sent.
    static func boardRevision(_ store: Store) -> String {
        let sessions = store.claudeSessions.values.filter { !$0.isArchived }
        let running = sessions.filter(\.running).map(\.id).sorted()
        let latest = sessions.filter { !$0.running }.sorted { ($0.lastActivity, $0.id) > ($1.lastActivity, $1.id) }.prefix(3).map(\.id)
        let told = store.lastTold().max { $0.value.at < $1.value.at }?.key ?? ""
        return [store.routerShownOpenCards.map(\.id).sorted(), running, Array(latest), [told]]
            .map { $0.joined(separator: ",") }.joined(separator: "|")
    }

    /// A pick kept from while you typed, while it is fresh, read on this board, and its target is still there to go to.
    private func live(_ key: String) -> Classification? {
        guard let hit = liveCache[key], Date().timeIntervalSince(hit.at) < Self.liveFor else { return nil }
        guard let store, hit.board == Self.boardRevision(store), hit.found.top.map({ eligible($0.target, store: store) }) ?? true else {
            liveCache[key] = nil
            return nil
        }
        return hit.found
    }

    /// Your corrections and dismissals change how messages are routed: picks made before them are asked again.
    func forgetLive() {
        liveCache = [:]
        livePending = [:]
        liveGeneration &+= 1
    }

    /// Whether a target can still be sent to: an open card, a session not archived, a known project, or an intent.
    func eligible(_ target: String, store: Store) -> Bool {
        if target.hasPrefix("answer:") { return store.routerShownOpenCards.contains { $0.id == String(target.dropFirst(7)) } }
        if target.hasPrefix("session:") { return store.claudeSessions[String(target.dropFirst(8))].map { !$0.isArchived } ?? false }
        // A project Fjord Computer knows: a session's folder, or a repo in your code folders (a clone with no session yet).
        if target.hasPrefix("new:") { return store.isProjectFolder(String(target.dropFirst(4))) }
        return true
    }

    /// Jev's questions: the stand-in, else the routing chooser of a run's tools, else TypeSafe with your key; through the
    /// gate (`JevGate`).
    private func jev(_ tools: RouterTools?) -> JevAsker? {
        store?.jevAsker(.routing, base: asker ?? tools?.chooser.map(JevClient.asker(choosing:)))
    }

    /// The label a target stands for: reply (a card or session), start (a project), change_fjord, question, compound.
    static func label(_ target: String) -> String {
        if target.hasPrefix("answer:") || target.hasPrefix("session:") { return "reply" }
        if target.hasPrefix("new:") { return "start" }
        return target
    }

    /// Jev's pick among the targets and the intents; the words alone when he can't be asked.
    private func classify(_ job: Job, projects: [String]) async -> Classification {
        guard let store else { return Classification(ranked: [], sure: false, assisted: false) }
        let key = Self.liveKey(job.text, projects)
        // What was read while you typed is yours: an action's message is asked of Jev on its own.
        if job.context.action == nil {
            if let hit = live(key) { return hit }
            // Still being asked while you typed: its answer, not a second call.
            if let pending = livePending[key], let found = await pending.task.value {
                if found.top.map({ eligible($0.target, store: store) }) ?? true { return found }
            }
        }
        do {
            return Classification(try await effects.rank(job.tools, job.text, projects))
        } catch {
            let targets = job.tools.targets(store, projects: projects.isEmpty ? nil : Set(projects))
            let (ranked, named) = RouterTools.unassisted(job.text, targets, store: store, pills: job.context.pills)
            if let named { return Classification(ranked: [Scored(target: named, p: 1)], sure: true, assisted: false) }
            let total = Double(max(1, ranked.reduce(0) { $0 + $1.score }))
            return Classification(ranked: ranked.map { Scored(target: $0.target, p: Double($0.score) / total) }, sure: false, assisted: false)
        }
    }

    // MARK: Ask back

    /// `suggestion`: what a pick corrects, when it isn't Jev's top (a wrong send asked again); `path` for the trace likewise.
    /// `note`: why it asks, when it isn't Jev's doubt; `chooseFolder`: "Choose folder…" is offered last.
    private func askBack(_ job: Job, _ found: Classification, suggestion: String? = nil, path: String? = nil, note: String? = nil,
                         chooseFolder: Bool = false) {
        guard let store else { return }
        var options: [RouterAskBack.Option] = []
        var seen = Set<String>()
        // Four: on real moments the fourth holds the answer 3–10% more often (evals/router/explore/selective.py).
        let room = chooseFolder ? 3 : 4
        for target in (found.card ?? []) + found.ranked.map(\.target) where target != "unclear" && options.count < room {
            guard let option = option(target, store: store, tools: job.tools), seen.insert(option.id).inserted else { continue }
            options.append(option)
        }
        if chooseFolder, let choose = option(RouterAskBack.chooseFolder, store: store) { options.append(choose) }
        let ask = RouterAskBack(id: job.id, message: job.text, context: job.context, options: options,
                                suggestion: suggestion ?? found.top?.target, at: Date(), note: note)
        var inputs = found.trace
        inputs?.card = options.map(\.target)
        trace(job, path: path ?? (found.assisted ? "jev" : "words"), action: "ask", target: found.top?.target, inputs: inputs,
              kind: path == "elsewhere" ? .reasked : .decided)
        askBacks.append(ask)
        store.updateDecision(job.id) {
            $0.add(.asked(options.map(\.title)))
            if $0.decision.label == nil { $0.decision.label = "unclear" }
        }
        progress[job.id] = nil
        follow(job.id)
    }

    /// A target as a button.
    func option(_ target: String, store: Store, tools: RouterTools? = nil) -> RouterAskBack.Option? {
        if target.hasPrefix("answer:") {
            guard let card = store.router.cards.first(where: { $0.id == String(target.dropFirst(7)) }),
                  RouterPage.shows(card, tasks: store.routerTasks) else { return nil }
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
        case RouterAskBack.chooseFolder: return .init(target: target, title: "Choose folder…", detail: "a new session there")
        case "change_fjord", "compound": return .init(target: target, title: "Change Fjord Computer", detail: "Categories, groups, settings")
        case "question": return .init(target: target, title: "Answer from what Fjord Computer knows", detail: "A question about now")
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
}

// MARK: - The real effects

extension RouterDispatcher.Effects {
    /// Nothing is available: before the dispatcher has set up its own.
    static var unavailable: Self {
        let no = RouterTools.Failure("The Router isn't ready")
        return Self(rank: { _, _, _ in throw no }, prepare: { _, _ in throw no }, start: { _, _, _, _ in throw no },
                    send: { _, _ in throw no }, answer: { _, _, _ in throw no }, run: { _, _, _ in throw no })
    }

    @MainActor
    static func live(_ dispatcher: RouterDispatcher) -> Self {
        func store(_ d: RouterDispatcher) throws -> Store {
            guard let store = d.storeForEffects else { throw RouterTools.Failure("Fjord Computer isn't ready") }
            return store
        }
        func object(_ json: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        }
        /// A started session's first message as `startSession` prepared it.
        func started(_ answer: [String: Any], _ tools: RouterTools, project: String, settings: SessionSettings?) throws -> RouterDispatcher.Delivery {
            // No task left in the words: the session is started with no first message.
            if let peer = answer["peer"] as? String, (answer["text"] as? String)?.isEmpty == true, tools.prepared[peer] == nil {
                return .init(to: peer, text: "", body: "", original: "", rephrased: false, session: answer["session"] as? String,
                             newSessionIn: project, settings: settings, settingsSigned: false)
            }
            guard let peer = answer["peer"] as? String, let ready = tools.prepared[peer] else { throw RouterTools.Failure("Not prepared") }
            return .init(to: peer, text: ready.text, body: ready.body ?? ready.text, original: ready.original,
                         rephrased: ready.rephrased, session: answer["session"] as? String, newSessionIn: ready.newSessionIn,
                         settings: settings, settingsSigned: ready.text.hasPrefix("⟦fjord v2 "))
        }
        return Self(
            rank: { [weak dispatcher] tools, message, projects in
                guard let dispatcher, let store = dispatcher.storeForEffects else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                guard let ask = dispatcher.jevForEffects(tools) else { throw RouterTools.Failure("no TypeSafe key is set") }
                // One option per destination, described in its own criteria; the message alone as the state; the board's
                // recency weighed with Jev's answers (RouterRoute).
                let destinations = tools.destinations(store, projects: projects.isEmpty ? nil : Set(projects))
                let facts = tools.facts(store, destinations: destinations, message: message)
                let call = RouterTools.routingQuestions(destinations, waiting: tools.waiting(store, among: destinations),
                                                        conversations: tools.conversations(store, facts: facts))
                // The words' evidence, from the sessions' transcripts, read while Jev answers.
                let sources = tools.lexicalSources(store, facts: facts)
                let reader: Claude.ActivityReader? = UnderTest.isRunning ? nil : store.activityReader
                let lexical = Task.detached(priority: .userInitiated) { RouterTools.lexical(message, sources: sources, reader: reader) }
                // Keys you paste go to the session, never to Jev. What the message tags (a notification, a category) goes
                // with it, fenced.
                var state = ["message": RouterTools.redacted(message)]
                if let tagged = tools.tagged { state["tagged in the message"] = RouterTools.redacted(tagged) }
                let answers = try await ask(call.questions, state)
                guard let pick = answers["route"]?.choice else { throw RouterTools.Failure("Jev didn't pick a target") }
                var signals = RouteFusion.Signals(route: [:])
                for (name, p) in pick.probabilities {
                    if let target = call.route[name] { signals.route[target, default: 0] += p }
                }
                let checks = call.answers.compactMap { id, w in answers[id]?.yes.map { (target: w.target, session: w.sessionID, p: $0) } }
                for c in checks { signals.reply[c.session] = max(signals.reply[c.session] ?? 0, c.p) }
                for (id, session) in call.next { signals.next[session] = answers[id]?.yes }
                signals.gates = RouterTools.gates.keys.reduce(into: [String: Double]()) { $0[$1] = answers[$1]?.yes }
                signals.lexical = await lexical.value
                let verdict = RouteFusion.decide(signals, facts: facts, answers: checks) {
                    RouterDispatcher.session(of: $0, store: store)
                }
                let card = RouterTools.askCard(ranked: verdict.ranked.map(\.target), recent: RouterTools.recent(facts))
                var trace = RouterTrace.Inputs(signals: signals, facts: facts, destinations: destinations,
                                               ranked: verdict.ranked, sure: verdict.sure, card: card) {
                    RouterDispatcher.session(of: $0, store: store)
                }
                trace.request = (try? JevClient.requestData(call.questions, about: state)).flatMap { String(data: $0, encoding: .utf8) }
                return RouterDispatcher.Ranking(scored: verdict.ranked, sure: verdict.sure, card: card, trace: trace)
            },
            prepare: { [weak dispatcher] tools, session in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.prepare(store, session: session, ticket: tools.ticket()))
                guard let to = answer["to"] as? String, let ready = tools.prepared[to] else { throw RouterTools.Failure("Not prepared") }
                return .init(to: to, text: ready.text, body: ready.body ?? ready.text, original: ready.original,
                             rephrased: ready.rephrased, session: session, newSessionIn: nil)
            },
            start: { [weak dispatcher] tools, folder, title, settings in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.startSession(store, project: folder, title: title, ticket: tools.ticket(), settings: settings))
                return try started(answer, tools, project: store.folderName(folder), settings: settings)
            },
            send: { [weak dispatcher] tools, delivery in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                guard let binary = dispatcher.claudePath(), let home = store.routerFiles?.routerHome else {
                    throw RouterTools.Failure("Claude Code wasn't found, so nothing can be sent")
                }
                await PrivateFile.makeFolder(home)
                return try await RouterSender.send(binary: binary, cwd: home, to: delivery.to, text: delivery.text, tools: tools,
                                                   inbox: await store.relayInbox(forSigned: delivery.text))
            },
            answer: { [weak dispatcher] tools, card, answers in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                return try await tools.answerForm(try store(dispatcher), ["card": card, "answers": answers], ticket: tools.ticket())
            },
            run: { [weak dispatcher] tools, intent, input in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                guard let binary = dispatcher.claudePath() else { throw RouterTools.Failure("Claude Code wasn't found") }
                return try await RouterRun.run(intent, input: input, tools: tools, store: store, binary: binary)
            },
            abortable: { [weak dispatcher] cli in
                guard let store = dispatcher?.storeForEffects else { return false }
                return await store.supportsAbort(cli)
            },
            cancel: { [weak dispatcher] sent in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                return try await store(dispatcher).cancelDelivery(sent)
            },
            finish: { [weak dispatcher] tools, held in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.finishStart(store, held, ticket: tools.ticket()))
                return try started(answer, tools, project: held.project, settings: held.settings)
            },
            fork: { [weak dispatcher] tools, request in
                guard let dispatcher else { throw RouterTools.Failure("Fjord Computer isn't ready") }
                let store = try store(dispatcher)
                let answer = object(try await tools.forkSession(store, request, ticket: tools.ticket()))
                let project = store.claudeSessions[request.session].map { store.folderName($0.folderKey) } ?? ""
                return try started(answer, tools, project: project, settings: nil)
            })
    }
}

extension RouterDispatcher {
    fileprivate var storeForEffects: Store? { store }
    /// An action's message is read by Jev only as an inbox action may be (`JevUse.actions`): it holds what GitHub wrote.
    fileprivate func jevForEffects(_ tools: RouterTools) -> JevAsker? {
        let action = tools.decision.flatMap { id in store?.router.decisions.last { $0.id == id } }?.fromAction != nil
        return action ? store?.jevAsker(.actions, base: asker ?? tools.chooser.map(JevClient.asker(choosing:))) : jev(tools)
    }

    /// Where a message that tags a notification goes, when it tags no project or session: the repos of the notifications,
    /// their local clones (`Store.localClones`) and the targets there (the sessions working in them, latest first, then a new
    /// session in each clone). Nil for any other message.
    struct RepoWorld: Equatable {
        var repos: [String]
        var clones: [String]
        var targets: [String]
        /// What an ask says when there is no clone: "No clone of owner/repo".
        var note: String { "No clone of " + repos.joined(separator: " or ") }
    }

    static func repoWorld(_ context: RouterContext, store: Store) -> RepoWorld? {
        // Only a pill that still says where: a project, or a session still there (one archived since says nothing).
        let addressed = context.mentions.contains { m in
            switch m.pointer {
            case .project: true
            case .session(let id): store.claudeSessions[id].map { !$0.isArchived } == true
            case .notification, .category, .thisItem: false
            }
        }
        guard context.projects.isEmpty, !addressed else { return nil }
        var repos: [String] = []
        for id in context.notifications {
            guard let repo = store.things[id]?.repo, !repos.contains(where: { $0.lowercased() == repo.lowercased() }) else { continue }
            repos.append(repo)
        }
        guard !repos.isEmpty else { return nil }
        var clones: [String] = []
        for repo in repos { for folder in store.localClones(of: repo) where !clones.contains(folder) { clones.append(folder) } }
        let sessions = store.claudeSessions.values.filter { !$0.isArchived && clones.contains($0.folderKey) }
            .sorted { $0.lastActivity > $1.lastActivity }.map { "session:\($0.id)" }
        return RepoWorld(repos: repos, clones: clones, targets: sessions + clones.map { "new:\($0)" })
    }

    /// Whether a target is one the message may go to: in its repo's world (`repoWorld`; anywhere without one), and for an
    /// action's message never the Router's own runs.
    static func inWorld(_ world: RepoWorld?, unattended: Bool, store: Store) -> (String) -> Bool {
        { target in
            if RouterRun.Intent(rawValue: target) != nil { return !unattended }
            guard let world else { return true }
            if target.hasPrefix("new:") { return world.clones.contains(String(target.dropFirst(4))) }
            return folder(of: target, store: store).map(world.clones.contains) ?? false
        }
    }

    /// Jev's ranking kept to what the message may go to (`inWorld`): when his pick isn't among it, you pick. An action's
    /// message is never sent on the words alone either (Jev not asked).
    static func keep(_ found: inout Classification, world: RepoWorld?, unattended: Bool, store: Store) {
        if unattended, !found.assisted { found.sure = false }
        guard world != nil || unattended else { return }
        let allowed = inWorld(world, unattended: unattended, store: store)
        let kept = found.ranked.filter { allowed($0.target) }
        if kept.first?.target != found.top?.target { found.sure = false }
        found.ranked = kept.isEmpty ? (world?.targets ?? []).map { Scored(target: $0, p: 0) } : kept
        found.card = found.card?.filter(allowed)
    }

    /// The folder a target works in: a session's, a card's session's (or the card's own); nil for anything else.
    static func folder(of target: String, store: Store) -> String? {
        if target.hasPrefix("new:") { return String(target.dropFirst(4)) }
        guard let session = session(of: target, store: store) else { return nil }
        if let s = store.claudeSessions[session] { return s.folderKey }
        return store.router.cards.first { $0.sessionID == session }?.folder
    }

    /// The session a target is for: a session, or a card's.
    static func session(of target: String, store: Store) -> String? {
        if target.hasPrefix("session:") { return String(target.dropFirst(8)) }
        if target.hasPrefix("answer:") { return store.router.cards.first { $0.id == String(target.dropFirst(7)) }?.sessionID }
        return nil
    }

    /// The session has an open card asking you for a permission.
    static func asksYou(_ session: String, store: Store) -> Bool {
        store.routerShownOpenCards.contains { $0.sessionID == session && $0.kind == .approval }
    }

    /// The message is addressed to the session by words you typed: "tell X to …" or "X: …" naming it and nothing else
    /// (`RouterTools.addressedSession`: its project, with it the only session), or a short name of its project's ("CI"), on
    /// the same terms: the name is of that one project, and it has that one session. Never its title: a session sets its own.
    static func addressed(_ message: String, to session: String, store: Store) -> Bool {
        guard let s = store.claudeSessions[session] else { return false }
        if RouterTools.addressedSession(message, store: store) == session { return true }
        let said = shortNames(message)
        func named(_ folder: String) -> Bool {
            !folder.isEmpty && !said.isDisjoint(with: shortNames(store.folderName(folder) + " " + (folder as NSString).lastPathComponent))
        }
        guard named(s.folderKey) else { return false }
        let sessions = store.claudeSessions.values.filter { !$0.isArchived }
        let projects = Set((store.knownFolders + sessions.map(\.folderKey)).filter(named))
        return projects == [s.folderKey] && sessions.filter { $0.folderKey == s.folderKey }.map(\.id) == [session]
    }

    /// Two or three letters, said as a name ("CI", "API", "db"): not a common short word.
    static func shortNames(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
            .filter { (2...3).contains($0.count) && !common.contains($0) && !shortCommon.contains($0) })
    }

    private static let shortCommon: Set<String> = [
        "to", "in", "on", "it", "is", "of", "at", "an", "be", "do", "go", "me", "my", "no", "so", "up", "us", "we", "or", "if",
        "as", "by", "he", "hi", "am",
    ]

    private static let common: Set<String> = [
        "the", "and", "for", "with", "this", "that", "these", "those", "from", "into", "onto", "you", "your", "please", "can",
        "could", "would", "should", "will", "what", "when", "where", "which", "who", "why", "how", "about", "then", "than", "them",
        "they", "have", "has", "had", "not", "are", "was", "were", "its", "our", "out", "all", "any", "some", "just", "also",
        "now", "new", "session", "project", "card", "does", "did", "but", "yes", "too", "there", "here", "let", "one", "get",
        "make", "use", "need", "want", "like", "ok", "okay", "thanks",
    ]
}
