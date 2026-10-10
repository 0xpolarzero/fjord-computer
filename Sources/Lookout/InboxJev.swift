import Foundation

// Jev's reading of the inbox (TypeSafe, with the user's key): each new message (comment, review's words, thread reply) is
// read once, for whether it asks you something and whether it is noise; each review request to you (or a team of yours) and
// each assignment is rated once. One call a refresh, every question in it, a few at most; what Jev isn't sure of is kept as
// unsure (never a fact) and not asked again. Without a key, or when TypeSafe fails, nothing changes.
enum InboxJev {
    /// Messages read and things rated in one call at most; the rest wait for the next refresh, newest first.
    static let maxMessages = 12
    static let maxRatings = 6
    /// Messages older than this aren't read: they were there before anything Jev could change.
    static let horizon: TimeInterval = 14 * 86400
    /// A yes is at least this likely, a no at most 1 minus it; between, Jev isn't sure.
    static let sure = 0.75
    /// A rating whose confidence is lower is no rating.
    static let sureScore = 0.4
    /// A banner for a message Jev hasn't read yet waits at most this many refreshes for it (beyond the cap, or a slow
    /// round), so it can still turn out to be noise; then it shows whatever Jev said.
    static let bannerWaits = 2

    typealias Asker = ([String: JevClient.Question], [String: Any]) async throws -> [String: JevClient.Answer]

    struct Work: Equatable {
        struct Read: Equatable {
            var thing: String
            var message: InboxEngine.Message
            /// Only people are asked whether they ask you something; bots only whether they are noise.
            var asks: Bool { !message.author.isBot }
        }
        struct Rating: Equatable {
            var thing: String
            var stamp: String
        }
        var reads: [Read] = []
        var ratings: [Rating] = []
        var isEmpty: Bool { reads.isEmpty && ratings.isEmpty }
    }

    /// What is new since the last round: messages not read yet (not yours, open things, recent), and review requests or
    /// assignments not rated for what they are now.
    static func work(_ things: [String: Thing], context: InboxContext) -> Work {
        let me = context.me.lowercased()
        var reads: [Work.Read] = []
        var ratings: [(Work.Rating, Date)] = []
        for thing in things.values where isRead(thing) {
            let mine = InboxEngine.signals(thing, me)
            let judged = mine?.messages ?? [:]
            for m in InboxEngine.messages(thing) where judged[m.id] == nil && unread(m, context) {
                reads.append(Work.Read(thing: thing.id, message: m))
            }
            if let stamp = InboxEngine.importanceStamp(thing, context: context), mine?.importance?.stamp != stamp {
                ratings.append((Work.Rating(thing: thing.id, stamp: stamp), thing.updatedAt))
            }
        }
        return Work(reads: Array(reads.sorted { ($0.message.at, $0.message.id) > ($1.message.at, $1.message.id) }.prefix(maxMessages)),
                    ratings: ratings.sorted { ($0.1, $0.0.thing) > ($1.1, $1.0.thing) }.prefix(maxRatings).map(\.0))
    }

    /// Things whose messages Jev reads: open PRs and issues.
    private static func isRead(_ thing: Thing) -> Bool {
        thing.kind != .workflow && (thing.status == .open || thing.status == .draft)
    }

    /// A message Jev reads once: not yours, and recent.
    private static func unread(_ m: InboxEngine.Message, _ context: InboxContext) -> Bool {
        InboxEngine.viewer(m.author.login) != InboxEngine.viewer(context.me) && context.now.timeIntervalSince(m.at) < horizon
    }

    /// A fact about a message Jev will read but hasn't yet: its banner waits (see `bannerWaits`).
    static func awaitsReading(_ fact: Fact, _ thing: Thing, context: InboxContext) -> Bool {
        guard isRead(thing), let id = messageID(fact),
              let m = InboxEngine.messages(thing).first(where: { $0.id == id }) else { return false }
        return InboxEngine.signals(thing, context.me)?.messages[id] == nil && unread(m, context)
    }

    /// The message a fact is about, if it is about one.
    private static func messageID(_ fact: Fact) -> String? {
        let parts = fact.key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "comment", "review", "mention", "last", "person": return parts[1]
        case "thread": return parts[1].split(separator: ":").last.map(String.init)
        default: return nil
        }
    }

    /// The call: one state with every message (`m1`…) and every thing to rate (`t1`…), and the questions about each.
    static func request(_ work: Work, things: [String: Thing], context: InboxContext) -> (questions: [String: JevClient.Question], state: [String: Any]) {
        let me = "@" + context.me
        var questions: [String: JevClient.Question] = [:]
        var messages: [String: Any] = [:]
        for (i, read) in work.reads.enumerated() {
            guard let thing = things[read.thing] else { continue }
            let id = "m\(i + 1)"
            messages[id] = messageState(read.message, in: thing, context: context)
            if read.asks {
                questions[id + "_asks"] = .noul(
                    instructions: "Message \(id): does it ask \(me) something, or need their answer, decision or action (a question to them, a request to review or change something, a blocker only they can clear)?",
                    yes: "It asks \(me) to answer or act", no: "It informs, thanks, agrees, or asks someone else")
            }
            questions[id + "_noise"] = .noul(
                instructions: "Message \(id): is it automated output nobody needs to read (CI or coverage reports, deploy previews, dependency update notes, lint or bot boilerplate)? A person's words, or a code review with findings even from a bot, are not.",
                yes: "Automated noise", no: "Words for a person to read")
        }
        var rated: [String: Any] = [:]
        for (i, rating) in work.ratings.enumerated() {
            guard let thing = things[rating.thing] else { continue }
            let id = "t\(i + 1)"
            rated[id] = thingState(thing, context: context)
            questions[id + "_importance"] = .score(levels: Importance.allCases.map(\.rawValue),
                instructions: "How important is it that \(me) acts on \(id) soon, compared with the rest of a busy developer's inbox?")
        }
        var state: [String: Any] = ["you": me]
        if !messages.isEmpty { state["messages"] = messages }
        if !rated.isEmpty { state["asked of you"] = rated }
        return (questions, state)
    }

    /// The answers, onto `things`, for `me`: every message asked is read (unsure included), every thing asked is rated.
    /// What was read for someone else is dropped.
    static func apply(_ answers: [String: JevClient.Answer], _ work: Work, for me: String, to things: inout [String: Thing]) {
        let viewer = InboxEngine.viewer(me)
        func fresh(_ id: String) -> ThingSignals {
            things[id].flatMap { InboxEngine.signals($0, me) } ?? ThingSignals(viewer: viewer)
        }
        func verdict(_ key: String) -> Bool? {
            guard let p = answers[key]?.yes else { return nil }
            return p >= sure ? true : p <= 1 - sure ? false : nil
        }
        for (i, read) in work.reads.enumerated() where things[read.thing] != nil {
            let id = "m\(i + 1)"
            var signals = fresh(read.thing)
            signals.messages[read.message.id] = MessageSignal(asksMe: read.asks ? verdict(id + "_asks") : nil, noise: verdict(id + "_noise"))
            things[read.thing]?.signals = signals
        }
        for (i, rating) in work.ratings.enumerated() where things[rating.thing] != nil {
            var level: Importance?
            if case .score(let score, let confidence)? = answers["t\(i + 1)_importance"], confidence >= sureScore {
                let index = min(max(Int(score.rounded()), 0), Importance.allCases.count - 1)
                level = Importance.allCases[index]
            }
            var signals = fresh(rating.thing)
            signals.importance = ImportanceSignal(level: level, stamp: rating.stamp)
            things[rating.thing]?.signals = signals
        }
    }

    /// A refreshed thing keeps what Jev said of the messages it still has, and its rating, when it was said for `me`; and
    /// your latest word there only ever moves later.
    static func carry(_ old: ThingSignals?, into thing: inout Thing, me: String) {
        guard thing.kind != .workflow else { return }
        guard !me.isEmpty else { thing.signals = nil; return }
        let viewer = InboxEngine.viewer(me)
        var signals = old.flatMap { $0.viewer == viewer ? $0 : nil } ?? ThingSignals(viewer: viewer)
        let ids = Set(InboxEngine.messages(thing).map(\.id))
        signals.messages = signals.messages.filter { ids.contains($0.key) }
        signals.answeredAt = [signals.answeredAt, InboxEngine.latestWord(thing, by: me)].compactMap { $0 }.max()
        thing.signals = signals.messages.isEmpty && signals.importance == nil && signals.answeredAt == nil ? nil : signals
    }

    /// A fact that never shows a banner: noise, or a message Jev read as noise (unless it asks you something).
    static func isQuiet(_ fact: Fact, _ thing: Thing, context: InboxContext) -> Bool {
        if fact.key.hasPrefix("noise:") { return true }
        guard let id = messageID(fact) else { return false }
        return InboxEngine.signals(thing, context: context)?.messages[id]?.noise == true
    }

    // MARK: What Jev reads

    private static func who(_ p: Person) -> String {
        var notes: [String] = []
        if p.isBot { notes.append("bot") }
        if p.association.isMaintainer { notes.append("maintainer") }
        return "@" + p.login + (notes.isEmpty ? "" : " (" + notes.joined(separator: ", ") + ")")
    }

    private static func name(_ thing: Thing) -> String {
        "\(thing.kind == .pr ? "PR" : "issue") \(thing.repo)#\(thing.number ?? 0): \(thing.title)"
    }

    private static func age(_ date: Date, _ now: Date) -> String {
        let hours = Int(max(now.timeIntervalSince(date), 0) / 3600)
        return hours < 1 ? "less than an hour" : hours < 48 ? "\(hours) hours" : "\(hours / 24) days"
    }

    /// Your part in a thing, in words: "author, requested reviewer".
    private static func role(_ thing: Thing, _ context: InboxContext) -> String {
        let me = context.me.lowercased()
        let teams = Set(context.myTeams.map { $0.lowercased() })
        var roles: [String] = []
        if thing.author?.login.lowercased() == me { roles.append("author") }
        if thing.requestedReviewers.contains(where: { $0.lowercased() == me }) { roles.append("requested reviewer") }
        if thing.requestedReviewers.contains(where: { teams.contains($0.lowercased()) }) { roles.append("in a requested team") }
        if thing.assignees.contains(where: { $0.lowercased() == me }) { roles.append("assignee") }
        if thing.reviews.contains(where: { $0.author.login.lowercased() == me }) { roles.append("reviewed it") }
        if thing.comments.contains(where: { $0.author.login.lowercased() == me }) { roles.append("commented") }
        if thing.mentioned.contains(me) { roles.append("mentioned") }
        return roles.isEmpty ? "not involved" : roles.joined(separator: ", ")
    }

    private static func messageState(_ m: InboxEngine.Message, in thing: Thing, context: InboxContext) -> [String: Any] {
        let all = InboxEngine.messages(thing)
        let before = all.last { $0.at < m.at && $0.path == m.path }
        var out: [String: Any] = [
            "on": name(thing), "your part": role(thing, context), "from": who(m.author),
            "kind": m.path.map { $0.isEmpty ? "reply in a review thread" : "reply in a review thread on \($0)" } ?? (m.isReview ? "review" : "comment"),
            "text": m.text, "mentions you": m.text.lowercased().contains("@" + context.me.lowercased()) ? "yes" : "no",
        ]
        if let before { out["just before, \(who(before.author))"] = String(before.text.prefix(200)) }
        return out
    }

    private static func thingState(_ thing: Thing, context: InboxContext) -> [String: Any] {
        let me = context.me.lowercased()
        let teams = Set(context.myTeams.map { $0.lowercased() })
        var asks = thing.requestedReviewers.contains { $0.lowercased() == me } ? "your review"
            : thing.requestedReviewers.first { teams.contains($0.lowercased()) }.map { "a review from your team @\($0)" } ?? "assigned to you"
        if let request = thing.reviewRequests.first(where: { $0.reviewer.lowercased() == me || teams.contains($0.reviewer.lowercased()) }) {
            asks += ", asked \(age(request.at, context.now)) ago"
        }
        var out: [String: Any] = [
            "what": name(thing), "asks": asks, "opened": age(thing.createdAt, context.now) + " ago",
            "by": thing.author.map(who) ?? "unknown",
        ]
        if thing.status == .draft { out["draft"] = "yes" }
        if !thing.labels.isEmpty { out["labels"] = thing.labels.joined(separator: ", ") }
        if let checks = thing.checks { out["checks"] = checks.rawValue }
        if let add = thing.additions, let del = thing.deletions {
            out["size"] = "+\(add) −\(del)" + (thing.changedFiles.map { " in \($0) files" } ?? "")
        }
        if let last = InboxEngine.messages(thing).last { out["latest message"] = who(last.author) + ": " + String(last.text.prefix(200)) }
        return out
    }
}

extension Store {
    /// Settings' "Let Jev read new comments" (default on).
    var jevReadsInbox: Bool { settings.jevReadsInbox ?? true }

    /// Jev reads the inbox at the next refresh: switched on, with a key (or a test's asker).
    var jevReadsInboxNow: Bool { jevReadsInbox && (inboxAsker != nil || !(typesafeKey ?? "").isEmpty) }

    /// Jev's reading of what is new, in one call: before the refresh announces, so noise is known before it would show a
    /// banner. Switched off or without a key nothing is asked; a failure leaves everything as it was, and the gate
    /// (`JevGate`) says when to ask again.
    func readInbox() async {
        guard jevReadsInbox else { return }
        let key = typesafeKey ?? ""
        let generation = jevGate.generation
        let ask: InboxJev.Asker? = inboxAsker ?? (key.isEmpty ? nil : { [client = jevClient(key)] questions, state in
            try await client.ask(questions, about: state)
        })
        guard let ask, jevGate.isOpen(for: key) else { return }
        let context = inboxContext
        guard !context.me.isEmpty else { return }
        let work = InboxJev.work(things, context: context)
        guard !work.isEmpty else { return }
        let (questions, state) = InboxJev.request(work, things: things, context: context)
        do {
            let answers = try await throughJevGate(.inbox, generation: generation) { try await ask(questions, state) }
            // Onto the things as they are now: the refresh may have moved on while Jev answered. Signed in as someone else
            // meanwhile, the answers were about another's inbox.
            guard InboxEngine.viewer(inboxContext.me) == InboxEngine.viewer(context.me) else { return }
            var next = things
            InboxJev.apply(answers, work, for: context.me, to: &next)
            if next != things { things = next }
        } catch {}
    }
}
