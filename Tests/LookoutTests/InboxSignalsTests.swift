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
        #expect(keys([.importance(.high)], t) == ["importance:urgent"])
        let entries = InboxEngine.evaluate(things: [t], categories: [InboxCategory(name: "R", symbol: "eye", color: .blue,
            rules: [Rule(scope: Scope(kinds: [.pr]), createdAt: .distantPast)])], marks: [:], context: context)
        #expect(entries.first?.importance == .urgent)
        t.signals?.importance?.level = .normal
        #expect(keys([.importance(.high)], t) == nil)
        #expect(keys([.importance(.normal)], t) == ["importance:normal"])
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
