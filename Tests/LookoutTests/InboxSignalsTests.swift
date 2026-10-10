import Foundation
import Testing
@testable import Lookout

/// The conditions Jev's signals drive: asks me, noise or a person, importance; and what nothing judged leaves as it was.
@Suite struct InboxSignalsEngine {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let me = Person(login: "me")
    let tok = Person(login: "tok", association: .member)
    let bot = Person(login: "netlify[bot]", isBot: true)
    let ci = Person(login: "ci-reporter")

    private var context: InboxContext { InboxContext(me: "me", myTeams: ["acme/core"], now: now) }

    private func pr(by author: Person? = nil) -> Thing {
        Thing(id: "pr:a/one#1", kind: .pr, repo: "a/one", number: 1, title: "t", url: URL(string: "https://github.com/a/one/pull/1")!,
              author: author ?? tok, createdAt: now.addingTimeInterval(-5000), updatedAt: now)
    }

    private func comment(_ id: String, _ author: Person, at: TimeInterval) -> ThingComment {
        ThingComment(id: id, author: author, at: now.addingTimeInterval(at), snippet: "…")
    }

    private func keys(_ conditions: [Condition], _ thing: Thing, marks: EntryMarks? = nil) -> [String]? {
        let rule = Rule(scope: Scope(kinds: [.pr, .issue]), conditions: conditions, createdAt: .distantPast)
        return InboxEngine.facts(rule, thing, marks: marks, context: context)?.map(\.key)
    }

    @Test func aCommentThatAsksMeIsAFactUntilIAnswerOrMarkItDone() {
        var t = pr()
        t.comments = [comment("c1", tok, at: -300), comment("c2", tok, at: -200)]
        t.threads = [ThingThread(id: "t1", isResolved: false, startedBy: tok, lastReplyBy: tok, lastReplyID: "r1",
                                 lastReplyAt: now.addingTimeInterval(-100), snippet: "…")]
        // Nothing judged: no fact, never a guess.
        #expect(keys([.asksMe], t) == nil)
        t.signals = ThingSignals(messages: ["c1": MessageSignal(asksMe: true, noise: false), "c2": MessageSignal(asksMe: nil),
                                            "r1": MessageSignal(asksMe: true)])
        // Unsure (c2) is no fact; a thread reply asks like a comment.
        #expect(keys([.asksMe], t) == ["asks:c1", "asks:r1"])
        let entry = InboxEngine.facts(Rule(scope: Scope(kinds: [.pr]), conditions: [.asksMe], createdAt: .distantPast), t,
                                      marks: nil, context: context)
        #expect(entry?.first?.label == "Asks you")
        // My reply after c1: only what came after it still asks.
        t.comments.append(comment("c3", me, at: -150))
        #expect(keys([.asksMe], t) == ["asks:r1"])
        // Done after it: nothing.
        #expect(keys([.asksMe], t, marks: EntryMarks(doneAt: now.addingTimeInterval(-50))) == nil)
    }

    @Test func noiseIsBotsUntilJevReadsItAndAPersonIsTheRest() {
        var t = pr()
        t.comments = [comment("h", tok, at: -30), comment("b", bot, at: -20), comment("c", ci, at: -10), comment("mine", me, at: -5)]
        // Before Jev: bots are noise, people are the rest; mine is neither.
        #expect(keys([.noise(true)], t) == ["noise:b"])
        #expect(keys([.noise(false)], t) == ["person:h", "person:c"])
        // Jev reads the CI account as automated; a bot it reads as a person's words is no longer noise; unsure is neither.
        t.signals = ThingSignals(messages: ["c": MessageSignal(noise: true), "b": MessageSignal(noise: false), "h": MessageSignal()])
        #expect(keys([.noise(true)], t) == ["noise:c"])
        #expect(keys([.noise(false)], t) == ["person:b"])
    }

    @Test func importanceCountsForTheRequestItWasRatedFor() {
        var t = pr()
        let asked = now.addingTimeInterval(-600)
        t.requestedReviewers = ["acme/core"]
        t.reviewRequests = [ThingReviewRequest(reviewer: "acme/core", at: asked)]
        let stamp = InboxEngine.importanceStamp(t, context: context)
        #expect(stamp == "requested:\(Int(asked.timeIntervalSince1970))")
        t.signals = ThingSignals(importance: ImportanceSignal(level: .urgent, stamp: stamp!))
        #expect(keys([.importance(.high)], t) == ["importance:urgent:\(stamp!)"])
        let entries = InboxEngine.evaluate(things: [t], categories: [InboxCategory(name: "R", symbol: "eye", color: .blue,
            rules: [Rule(scope: Scope(kinds: [.pr]), createdAt: .distantPast)])], marks: [:], context: context)
        #expect(entries.first?.importance == .urgent)
        t.signals?.importance?.level = .normal
        #expect(keys([.importance(.high)], t) == nil)
        #expect(keys([.importance(.normal)], t) == ["importance:normal:\(stamp!)"])
        // Asked again: the old rating is for the old request.
        t.reviewRequests = [ThingReviewRequest(reviewer: "acme/core", at: now)]
        #expect(keys([.importance(.low)], t) == nil)
        // Not for me at all: nothing to rate. An issue assigned to me is.
        t.requestedReviewers = []
        #expect(InboxEngine.importanceStamp(t, context: context) == nil)
        var issue = pr()
        issue.kind = .issue
        issue.assignees = ["Me"]
        #expect(InboxEngine.importanceStamp(issue, context: context) == "assigned")
    }

    @Test func aNewRequestAfterDoneOnAnOldOneIsNewEvenRatedTheSame() {
        var t = pr()
        t.requestedReviewers = ["me"]
        t.reviewRequests = [ThingReviewRequest(reviewer: "me", at: now.addingTimeInterval(-6000))]
        t.signals = ThingSignals(importance: ImportanceSignal(level: .urgent, stamp: InboxEngine.importanceStamp(t, context: context)!))
        let rule = Rule(scope: Scope(kinds: [.pr]), conditions: [.importance(.high)], createdAt: .distantPast)
        let old = InboxEngine.facts(rule, t, marks: nil, context: context)!.map(\.key)
        let done = EntryMarks(acked: Set(old), doneAt: now.addingTimeInterval(-3000))
        // Asked again, and Jev rates the new request urgent too: not the fact Done acknowledged.
        t.reviewRequests = [ThingReviewRequest(reviewer: "me", at: now.addingTimeInterval(-100))]
        let stamp = InboxEngine.importanceStamp(t, context: context)!
        t.signals?.importance = ImportanceSignal(level: .urgent, stamp: stamp)
        let new = InboxEngine.facts(rule, t, marks: done, context: context)!.map(\.key)
        #expect(new.count == 1 && !done.acked.contains(new[0]))
    }

    @Test func theNewConditionsAreOfferedForPRsAndIssuesAndRoundTrip() throws {
        for kinds: Set<ThingKind> in [[.pr], [.issue], [.pr, .issue]] {
            let tags = InboxEngine.conditions(for: kinds).map(RuleEditing.tag)
            #expect(tags.contains("asksMe") && tags.contains("noise") && tags.contains("importance"))
        }
        #expect(!InboxEngine.conditions(for: [.workflow]).contains(.asksMe))
        for c: Condition in [.asksMe, .noise(false), .importance(.urgent)] {
            #expect(try JSONDecoder().decode(Condition.self, from: JSONEncoder().encode(c)) == c)
        }
    }

    @Test func aThingSavedBeforeSignalsDecodesWithNone() throws {
        let t = pr()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as? [String: Any])
        json["signals"] = nil
        json["additions"] = nil
        let old = try JSONDecoder().decode(Thing.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.signals == nil && old.additions == nil && old == t)
        var judged = t
        judged.signals = ThingSignals(messages: ["c": MessageSignal(asksMe: true)], importance: ImportanceSignal(level: .high, stamp: "assigned"))
        #expect(try JSONDecoder().decode(Thing.self, from: JSONEncoder().encode(judged)) == judged)
    }

    @MainActor @Test func rulesReadNaturally() {
        let words = RuleWords(store: Store())
        let rule = Rule(scope: Scope(kinds: [.pr, .issue]), conditions: [.asksMe, .noise(false), .importance(.high)])
        #expect(words.summary(rule) == "PRs and issues · when any of: a comment asks me; new comment is from a person; rated at least high")
    }
}

/// Jev's one call a refresh: what it asks, what it keeps, and what it changes.
@MainActor
@Suite struct InboxSignalsJev {
    final class Calls {
        var questions: [[String: JevClient.Question]] = []
        var states: [[String: Any]] = []
    }

    let now = Date()
    let tok = Person(login: "tok", association: .member)
    let bot = Person(login: "netlify[bot]", isBot: true)

    private func pr(_ n: Int, comments: [ThingComment]) -> Thing {
        var t = InboxFixture.pr(n, by: tok, greptile: nil, updated: now)
        t.comments = comments
        return t
    }

    private func comment(_ id: String, _ author: Person, ago: TimeInterval = 60) -> ThingComment {
        ThingComment(id: id, author: author, at: now.addingTimeInterval(-ago), snippet: "Could you take a look at \(id)?")
    }

    /// A store whose asker answers every yes/no with `yes` and every score with `score`, and records each call.
    private func store(_ things: [Thing], yes: Double = 0.9, score: Double = 2, conditions: [Condition] = [.asksMe]) -> (Store, Calls) {
        let category = InboxCategory(name: "Mine", symbol: "star", color: .blue,
                                     rules: [Rule(scope: Scope(kinds: [.pr, .issue]), conditions: conditions, createdAt: .distantPast)])
        let s = InboxFixture.store(things, category: category)
        let calls = Calls()
        s.inboxAsker = { questions, state in
            calls.questions.append(questions)
            calls.states.append(state)
            return questions.mapValues { q in
                if case .score = q { return .score(score, confidence: 0.8) }
                return .noul(yes)
            }
        }
        return (s, calls)
    }

    @Test func oneCallReadsEachNewMessageOnceAndNeverAgain() async {
        let mine = ThingComment(id: "c0", author: Person(login: "me"), at: now.addingTimeInterval(-500), snippet: "Done")
        let (s, calls) = store([pr(1, comments: [mine, comment("c1", tok), comment("c2", bot, ago: 120)])])
        await s.readInbox()
        #expect(calls.questions.count == 1)
        // Mine isn't read; a bot is only asked whether it is noise.
        #expect(Set(calls.questions[0].keys) == ["m1_asks", "m1_noise", "m2_noise"])
        #expect((calls.states[0]["messages"] as? [String: Any])?.count == 2)
        let signals = s.things["pr:a/one#1"]?.signals?.messages
        #expect(signals?["c1"] == MessageSignal(asksMe: true, noise: true) && signals?["c2"] == MessageSignal(asksMe: nil, noise: true))
        // Asked once: nothing new, no call.
        await s.readInbox()
        #expect(calls.questions.count == 1)
        // A refresh keeps what was read; only the new comment is asked about.
        var next = s.things
        next["pr:a/one#1"]?.signals = nil
        next["pr:a/one#1"]?.comments.append(comment("c3", tok, ago: 10))
        s.applyThings(next)
        #expect(s.things["pr:a/one#1"]?.signals?.messages["c1"] != nil)
        await s.readInbox()
        #expect(calls.questions.count == 2 && Set(calls.questions[1].keys) == ["m1_asks", "m1_noise"])
        #expect(s.entries.first?.facts.map(\.key) == ["asks:c1", "asks:c3"])
    }

    @Test func unsureIsReadButNoFactAndTheCapWaitsForTheNextRound() async {
        let many = (1...(InboxJev.maxMessages + 3)).map { comment("c\($0)", tok, ago: Double($0) * 60) }
        let (s, calls) = store([pr(1, comments: many)], yes: 0.5)
        await s.readInbox()
        #expect(calls.questions[0].count == InboxJev.maxMessages * 2)
        #expect(s.things["pr:a/one#1"]?.signals?.messages.count == InboxJev.maxMessages)
        // Newest first: the oldest three wait.
        #expect(s.things["pr:a/one#1"]?.signals?.messages["c\(InboxJev.maxMessages + 1)"] == nil)
        #expect(s.entries.isEmpty)
        await s.readInbox()
        #expect(calls.questions.count == 2 && calls.questions[1].count == 6)
        await s.readInbox()
        #expect(calls.questions.count == 2)
    }

    @Test func withoutJevOrWhenItFailsNothingChanges() async {
        let thing = pr(1, comments: [comment("c1", tok)])
        let s = InboxFixture.store([thing])
        await s.readInbox()
        #expect(s.things["pr:a/one#1"] == thing)
        var asked = 0
        s.inboxAsker = { _, _ in asked += 1; throw JevClient.Failure(message: "TypeSafe is busy, will retry later") }
        await s.readInbox()
        #expect(s.things["pr:a/one#1"] == thing && asked == 1)
        // It waits before asking again.
        await s.readInbox()
        #expect(asked == 1 && s.inboxJevPausedUntil > Date())
    }

    @Test func aReviewRequestIsRatedOnceForEachRequest() async {
        var t = pr(1, comments: [])
        t.requestedReviewers = ["me"]
        t.reviewRequests = [ThingReviewRequest(reviewer: "me", at: now.addingTimeInterval(-3600))]
        t.additions = 120
        t.deletions = 4
        t.changedFiles = 3
        let (s, calls) = store([t], score: 2.6, conditions: [.importance(.high)])
        await s.readInbox()
        #expect(Set(calls.questions[0].keys) == ["t1_importance"])
        let rated = (calls.states[0]["asked of you"] as? [String: [String: Any]])?["t1"]
        #expect(rated?["size"] as? String == "+120 −4 in 3 files" && rated?["asks"] as? String == "your review, asked 1 hours ago")
        #expect(s.entries.first?.importance == .urgent && s.entries.first?.facts.map(\.key)
            == ["importance:urgent:requested:\(Int(t.reviewRequests[0].at.timeIntervalSince1970))"])
        await s.readInbox()
        #expect(calls.questions.count == 1)
    }

    @Test func noiseIsNotedButNeverAnnounced() async {
        let (s, calls) = store([pr(1, comments: []), pr(2, comments: [])], yes: 0.9, conditions: [.newComment(by: Pick())])
        var posted: [String] = []
        s.notifier.onPost = { posted.append($0.identifier) }
        s.announceInbox()
        // A comment Jev reads as noise on #1, one it reads as a person's on #2.
        s.inboxAsker = { questions, _ in
            calls.questions.append(questions)
            return questions.mapValues { _ in .noul(0.95) }
        }
        var next = s.things
        next["pr:a/one#1"]?.comments = [comment("n1", Person(login: "ci-reporter"))]
        s.applyThings(next)
        await s.readInbox()
        s.inboxAsker = { questions, _ in questions.mapValues { _ in .noul(0.05) } }
        next = s.things
        next["pr:a/one#2"]?.comments = [comment("p1", tok)]
        s.applyThings(next)
        await s.readInbox()
        s.announceInbox()
        #expect(posted == ["inbox:pr:a/one#2"])
        #expect(s.marks["pr:a/one#1"]?.notified == ["comment:n1"])
    }
}

@MainActor
@Suite struct InboxSignalsOrder {
    @Test func aCategoryListsWhatJevRatesMoreImportantFirstThenTheNewest() {
        let now = Date()
        func pr(_ n: Int, minutes: Double, level: Importance?) -> Thing {
            var t = InboxFixture.pr(n, greptile: nil, updated: now.addingTimeInterval(-minutes * 60))
            t.assignees = ["me"]
            if let level { t.signals = ThingSignals(importance: ImportanceSignal(level: level, stamp: "assigned")) }
            return t
        }
        let category = InboxCategory(name: "Mine", symbol: "star", color: .blue,
                                     rules: [Rule(scope: Scope(kinds: [.pr]), createdAt: .distantPast)])
        let s = InboxFixture.store([pr(1, minutes: 1, level: nil), pr(2, minutes: 50, level: .urgent), pr(3, minutes: 5, level: .low),
                                    pr(4, minutes: 9, level: .high), pr(5, minutes: 3, level: .normal)], category: category)
        #expect(s.entries(in: category.id).map { $0.thing.number } == [2, 4, 1, 5, 3])
    }
}
