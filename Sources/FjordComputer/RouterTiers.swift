import Foundation

// Where a card stands, by whose move is next (agreed with the user, 2026-10-11):
// 1. Needs you: the move is yours (a question, a plan, an OK, an ask, a stuck turn, a last step left to you, a wait that is
//    over while nothing continues it on its own).
// 2. Waiting: the move is something else's (CI, a deploy, another session, someone else's review).
// 3. Worth a look: done, nothing to do, but it tells you something (a caveat, a risk, a decision it took, a claim it didn't
//    check). Unsure, a finished turn is this, never quieter.
// 4. Done: done, nothing to do, nothing to tell. It goes straight to the history, unread until you acknowledge it.
// 5. Working: not a card (the Working rows).

enum RouterTier: Int, Comparable, CaseIterable {
    case needsYou, waiting, note, done

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension RouterCard {
    /// Its tier as it stands. `autoContinue`: whether its session is told on its own once its wait is over (a wait that is
    /// over and isn't is yours to continue).
    func tier(autoContinue: Bool) -> RouterTier {
        if kind.needsYou { return .needsYou }
        switch kind {
        case .waiting:
            guard let triage, triage.ready != nil, triage.told == nil, !autoContinue else { return .waiting }
            return .needsYou
        case .done:
            guard let triage else { return .note }
            // A trivial turn is never quieter than its claim it didn't check, nor than partway (a step left to you made
            // it Finish up already).
            if triage.unverified { return .note }
            if triage.trivial, triage.state == .done { return .done }
            return triage.next == .nothing ? .done : .note
        default:
            return .needsYou
        }
    }

    /// A finished turn the triage found nothing in for you (nor a question your last message left that it went on without):
    /// it goes to the history on its own, unread.
    var settles: Bool { isOpen && kind == .done && triage != nil && tier(autoContinue: false) == .done && wentAheadWithout.isEmpty }
}

extension Store {
    /// A card's tier, with whether it is continued on its own (`autoContinues`).
    func routerTier(_ card: RouterCard) -> RouterTier { card.tier(autoContinue: autoContinues(card)) }

    /// Whether a waiting card is told on its own once its wait is over, as `resolveWaits` does it: its session's switch on,
    /// a wait its message named, and no send on its own that failed. Otherwise continuing it is yours.
    func autoContinues(_ card: RouterCard) -> Bool {
        continuesAutomatically(card.sessionID) && card.triage?.watch?.named == true && !routerTriager.autoFailed.contains(card.id)
    }

    /// The cards the history shows unread: finished turns that went there on their own and you haven't acknowledged.
    var routerUnread: [RouterCard] { router.cards.filter { $0.unread == true && !$0.isOpen } }

    /// You've seen it: it reads as any other line of the history.
    func acknowledgeRouterCard(_ id: String) {
        guard let i = router.cards.firstIndex(where: { $0.id == id }), router.cards[i].unread == true else { return }
        router.cards[i].unread = nil
    }

    /// Every unread line of the history, seen.
    func acknowledgeAllRouterCards() {
        guard router.cards.contains(where: { $0.unread == true }) else { return }
        var state = router
        for i in state.cards.indices where state.cards[i].unread == true { state.cards[i].unread = nil }
        router = state
    }
}

// MARK: - What is left for you (Jev)

extension RouterTriage {
    /// A step is yours from this sure.
    static let stepSure = 0.6
    /// The history takes a finished turn only when Jev is this sure it is done, and both a step and a note at most
    /// `quiet` likely: a step sent to the history unseen costs more than a note too many.
    static let doneSure = 0.7
    static let quiet = 0.2

    /// Asked in every triage call, as two questions (a turn may leave you a step and tell you something too): which is
    /// what decides between Finish up, Worth a look and the history (`next`).
    static let nextExtra = TriageExtra(
        questions: [
            "userStep": .noul(instructions: "Does the final message leave a concrete action the user needs to take now to complete, apply, verify or continue this work?",
                              yes: "A required answer, decision, approval, merge, push, relaunch, command or manual test",
                              no: "No required user action now. Optional suggestions, offers of further work, and steps that wait on unfinished outside work don't count"),
            "notable": .noul(instructions: "Does the final message report a material caveat, risk, unverified success claim, consequential decision the session made on its own, or important finding?",
                             yes: "It reports at least one such thing, whether or not the user also has something to do",
                             no: "It reports nothing like that: a routine completion or acknowledgement"),
        ],
        apply: { answers, triage in triage.next = next(answers, triage) })

    /// You, when a step is sure; nothing, only when the turn is surely done with nothing in it for you; else a note
    /// (unsure, it is never quieter than Worth a look). Nil when neither was answered.
    static func next(_ answers: [String: JevClient.Answer], _ triage: RouterTriage) -> Next? {
        let step = answers["userStep"]?.yes, notable = answers["notable"]?.yes
        guard step != nil || notable != nil else { return nil }
        if (step ?? 0) >= stepSure { return .you }
        let done = answers["state"]?.choice.map { $0.probabilities["done"] ?? 0 } ?? 0
        if triage.state == .done, done >= doneSure, let step, step <= quiet, let notable, notable <= quiet, !triage.unverified {
            return .nothing
        }
        return .note
    }
}
