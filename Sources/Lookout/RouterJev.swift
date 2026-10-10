import Foundation

// What the Router asks Jev besides where a sent message goes: the same question while you type (the composer shows his
// pick), and how big a new session's task is (its model and effort). Every call goes through a `JevAsker`, so tests answer
// for it.

/// Typed questions about a state, all in one call (`JevClient.ask`).
typealias JevAsker = @MainActor ([String: JevClient.Question], [String: String]) async throws -> [String: JevClient.Answer]

extension JevClient {
    /// TypeSafe with your key; nil without one.
    @MainActor
    static func asker(_ store: Store) -> JevAsker? {
        guard let key = store.typesafeKey, !key.isEmpty else { return nil }
        return { questions, state in try await JevClient(key: key).ask(questions, about: state) }
    }

    /// An older one-choice stand-in (`RouterTools.chooser`, `ActionSessions.Chooser`) as an asker: it answers the choices,
    /// one call each, and leaves every other question unanswered.
    static func asker(choosing choose: @escaping ([String], [String: String], [String: String], String) async throws -> Choice) -> JevAsker {
        { questions, state in
            var out: [String: Answer] = [:]
            for (id, question) in questions {
                guard case .choice(let options, let hints, let instructions) = question else { continue }
                out[id] = .choice(try await choose(options, hints, state, instructions))
            }
            return out
        }
    }
}

// MARK: - A new session's model and effort

/// How big a task is, on Jev's five levels, and the model and effort each level gets: one table.
enum SessionScope {
    static let table: [(level: String, model: String, effort: String)] = [
        ("trivial", "haiku", "low"),
        ("small", "sonnet", "low"),
        ("medium", "sonnet", "medium"),
        ("large", "opus", "high"),
        ("deep", "opus", "max"),
    ]

    static let question = JevClient.Question.score(levels: table.map(\.level), instructions: """
        How big and hard is the task a new Claude Code session is given? trivial: a quick lookup or a one-line change; \
        small: a focused change in a file or two; medium: a feature or a fix across a few files; large: a multi-part \
        feature, a refactor or a tricky bug; deep: architecture, research or a hard problem that needs long careful thought.
        """)

    /// The settings for Jev's score (0 for the first level to 4 for the last).
    static func settings(_ score: Double) -> SessionSettings? {
        guard score.isFinite else { return nil }
        let row = table[min(max(Int(score.rounded()), 0), table.count - 1)]
        return SessionSettings(model: row.model, effort: row.effort)
    }

    /// What the history says picked them.
    static let by = "Jev"
}

extension Store {
    /// Sessions the Router starts without a model or effort named get Jev's pick (Settings → Claude); on unless turned off.
    var jevPicksSessionModels: Bool { settings.jevPicksSessionModels ?? true }
}

// MARK: - The target while you type

/// Jev's pick for the draft, asked once typing pauses: shown over the composer when he is sure (as the dispatcher would act
/// on it), its card or working row marked on the page. Clicking it fixes the target; Esc waves it off for this draft.
@Observable @MainActor
final class RouterLiveTarget {
    struct Prediction: Equatable {
        var target: String
        /// The chip's words ("Fix the login bug", "New session · lookout") and the tooltip's.
        var title: String
        var detail: String
        /// The draft it was made for.
        var text: String
        /// What the page marks: the card's id or the working row's.
        var mark: String?
        /// What Jev made of the draft (its task's size), for the send to use.
        var found: RouterDispatcher.Classification? = nil
    }

    private(set) var prediction: Prediction?
    /// A target you fixed by clicking the prediction (a card's goes to `RouterModel.replyTo` instead).
    var pinned: String?
    var pinnedTitle: String?
    /// The prediction you clicked: while it is still where the draft goes, the send goes with what Jev made of it and logs
    /// his pick as confirmed.
    var chosen: Prediction?
    /// The target you waved off for this draft: it isn't shown again, and the message doesn't go there unasked.
    private(set) var dismissed: String?

    /// How long typing pauses before Jev is asked, and the fewest characters worth asking about.
    @ObservationIgnored var delay: Duration = .milliseconds(600)
    static let minLength = 12
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The words and projects Jev is being asked about, the draft's as they now are (nil while nothing is to be asked), and
    /// the ones the prediction shown was made for.
    @ObservationIgnored private var asking: String?
    @ObservationIgnored private var current: String?
    @ObservationIgnored private var predicted: String?

    /// The draft (as it will be sent) changed, or what fixes its target did. Nothing is asked while a reply, a pinned target
    /// or a lone @project fixes where it goes, nor for a few characters. A pick for other words goes at once; only an answer
    /// for the draft as it is when it lands is shown.
    func update(text: String, context: RouterContext, store: Store) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixed = pinned != nil || RouterDispatcher.plan(text: text, context: context, store: store) != .classify
        guard store.routerOn, !Store.isDemo, !fixed, text.count >= Self.minLength else {
            cancel()
            clear()
            if text.isEmpty { dismissed = nil }
            return
        }
        let key = RouterDispatcher.liveKey(text, context.projects)
        current = key
        if prediction != nil, predicted != key { clear() }
        // The pick shown is for these words: whatever was asked since is for others.
        if prediction != nil { return cancel() }
        guard key != asking else { return }
        task?.cancel()
        asking = key
        let delay = delay
        task = Task { [weak self, weak store] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let store else { return }
            let found = await store.routerDispatcher.predict(text, projects: context.projects)
            guard !Task.isCancelled, let self, self.current == key else { return }
            self.asking = nil
            self.task = nil
            self.prediction = found.flatMap { self.prediction(from: $0, text: text, store: store) }
            self.predicted = self.prediction == nil ? nil : key
        }
    }

    /// The prediction, if it is still for this draft and its target can still be sent to: what a click may pin.
    func valid(text: String, context: RouterContext, store: Store) -> Prediction? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = prediction, predicted == RouterDispatcher.liveKey(text, context.projects), context.replyTo == nil,
              context.target == nil, p.target != dismissed, store.routerDispatcher.eligible(p.target, store: store) else { return nil }
        return p
    }

    /// Shown only when Jev is sure, as the dispatcher would send it, and not to what you waved off.
    private func prediction(from found: RouterDispatcher.Classification, text: String, store: Store) -> Prediction? {
        guard found.assisted, found.sure, let top = found.top, top.target != dismissed,
              store.routerDispatcher.eligible(top.target, store: store),
              let option = store.routerDispatcher.option(top.target, store: store) else { return nil }
        let title = top.target.hasPrefix("new:") ? "\(option.title) · \(option.detail)" : option.title
        return Prediction(target: top.target, title: title, detail: store.routerDispatcher.describe(top.target, store: store),
                          text: text, mark: Self.mark(top.target, store: store), found: found)
    }

    /// The page's item for a target: the card, or the session's working row, else its open card.
    static func mark(_ target: String, store: Store) -> String? {
        if target.hasPrefix("answer:") { return String(target.dropFirst("answer:".count)) }
        guard target.hasPrefix("session:") else { return nil }
        let session = String(target.dropFirst("session:".count))
        if store.routerWorkingRows.contains(where: { $0.id == session }) { return RouterModel.workingID(session) }
        return store.openRouterCards.first { $0.sessionID == session }?.id
    }

    /// Esc: the prediction goes, and stays away for this draft.
    func dismiss() {
        dismissed = prediction?.target
        clear()
    }

    /// A demo or a shot: a pick shown with nothing behind it, for its words.
    func preview(_ prediction: Prediction) {
        self.prediction = prediction
        predicted = RouterDispatcher.liveKey(prediction.text, [])
    }

    /// The composer is gone (its window closed, the page left): nothing more is asked, and no pick is shown, until it is
    /// back. What you pinned or waved off stays with the draft.
    func suspend() {
        cancel()
        clear()
        current = nil
    }

    /// Sent or cleared: everything starts over.
    func reset() {
        cancel()
        clear()
        current = nil
        pinned = nil
        pinnedTitle = nil
        chosen = nil
        dismissed = nil
    }

    private func cancel() {
        task?.cancel()
        task = nil
        asking = nil
    }

    /// The prediction goes (it no longer holds), with nothing waved off.
    func clear() {
        prediction = nil
        predicted = nil
    }
}

extension RouterModel {
    /// What the draft goes with: the reply, the @projects, the target you pinned and the one you waved off.
    func context(_ store: Store) -> RouterContext {
        let reply = replyTo.flatMap { id in store.router.cards.contains { $0.id == id } ? id : nil }
        var context = RouterContext(replyTo: reply, projects: projects, target: live.pinned, notTo: live.dismissed)
        // Jev's pick you clicked, while the draft still goes there (as the pinned target or the reply to its card).
        if let chosen = live.chosen, chosen.target == live.pinned || reply.map({ "answer:\($0)" }) == chosen.target {
            context.predicted = chosen.target
            context.jev = chosen.found
        }
        return context
    }

    /// The draft's words as they will be sent (pills written as @name).
    func plainDraft(_ store: Store) -> String {
        MentionText.plain(draft, tokens: tokens, name: store.folderName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The draft changed: Jev's pick follows it.
    func predictTarget(store: Store) {
        live.update(text: plainDraft(store), context: context(store), store: store)
    }

    /// The prediction's item changed (`from` → `to`): the page marks the new one; a mark of another (a reveal) isn't touched.
    func markPrediction(from old: String?, to new: String?) {
        if let old, highlighted == old { highlighted = nil }
        if let new { highlighted = new }
    }

    /// The prediction clicked: a card's becomes the reply, anything else the pinned target.
    func pinPrediction(store: Store) {
        // Only a pick for the draft as it is, to a target still there.
        guard let p = live.valid(text: plainDraft(store), context: context(store), store: store) else {
            live.clear()
            return predictTarget(store: store)
        }
        if p.target.hasPrefix("answer:") {
            replyTo = String(p.target.dropFirst("answer:".count))
        } else {
            live.pinned = p.target
            live.pinnedTitle = p.title
        }
        live.reset(keepingPin: true)
        live.chosen = p
        focusRequest &+= 1
    }

    /// Esc on the prediction.
    func dismissPrediction() { live.dismiss() }
}

extension RouterLiveTarget {
    /// After a pin: the prediction goes, the pin stays.
    func reset(keepingPin: Bool) {
        let (pin, title) = (pinned, pinnedTitle)
        reset()
        if keepingPin { (pinned, pinnedTitle) = (pin, title) }
    }
}
