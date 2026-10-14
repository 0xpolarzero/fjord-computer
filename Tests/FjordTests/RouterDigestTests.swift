import Foundation
import Testing
@testable import Fjord

/// The Brief: its markup and diff, the writer's events, checks and recording, its persistence and the `mark_seen` tool.
@MainActor
@Suite(.serialized) struct RouterDigestTests {
    private typealias Writer = RouterDigestWriter
    private typealias Revision = RouterDigest.Revision
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func card(_ id: String, session: String? = nil, kind: RouterCard.Kind = .done, title: String? = nil,
                      folder: String = "/code/lookout", open: Bool = true) -> RouterCard {
        let s = session ?? String(id.split(separator: "#").first ?? "")
        var c = RouterCard(id: id, sessionID: s, kind: kind, title: title ?? "T \(s)", folder: folder, text: "Text of \(s)",
                           createdAt: t0, addressedAt: open ? nil : t0, addressedBy: open ? nil : .you)
        c.triage = RouterTriage(state: kind == .asks ? .asks : .done)
        return c
    }

    private func state(_ cards: [RouterCard] = [], decisions: [RouterDecision] = []) -> RouterState {
        var s = RouterState()
        s.enabled = true
        s.cards = cards
        s.decisions = decisions
        return s
    }

    private func board(projects: [(String, [(String, DigestMarkup.Kind)])] = [("/p/a", [("s1", .need), ("s2", .look)])]) -> Writer.Board {
        var b = Writer.Board()
        for (key, sessions) in projects {
            var list: [Writer.Board.Session] = []
            for (id, kind) in sessions {
                list.append(.init(id: id, title: "Title \(id)", kind: kind, state: "x", text: "", asks: []))
                b.projectOf[id] = key
                b.kinds[id] = kind
                b.titles[id] = "Title \(id)"
                if kind == .need { b.needs.append(id) }
                if kind == .look { b.looks.append(id) }
            }
            b.projects.append(.init(key: key, name: key, sessions: list))
        }
        return b
    }

    private func answer(forYou: String = "", look: String = "", projects: [(key: String, text: String)] = [],
                        label: String = "L", why: String = "W") -> DigestPrompt.Answer {
        .init(changed: true, forYou: forYou, worthALook: look, projects: projects, label: label, why: why)
    }

    // MARK: Markup

    @Test func markupReadsTagsAndLeavesUnknownOrOpenOnesAsText() {
        let pieces = DigestMarkup.parse(#"Go <need s="a">answer it</need> and <look s="b">see</look>, <run s="c">x</run>."#)
        #expect(pieces == [.text("Go "), .span(.need, session: "a", text: "answer it"), .text(" and "),
                           .span(.look, session: "b", text: "see"), .text(", "), .span(.run, session: "c", text: "x"), .text(".")])
        // Not a known tag: left as it is, as text.
        #expect(DigestMarkup.parse(#"a <bold s="a">b</bold> c"#) == [.text(#"a <bold s="a">b</bold> c"#)])
        // Left open: text.
        #expect(DigestMarkup.parse(#"a <need s="a">b"#) == [.text(#"a <need s="a">b"#)])
        #expect(DigestMarkup.parse("").isEmpty)
        // A closing tag of another kind doesn't close it.
        #expect(DigestMarkup.parse(#"<need s="a">b</look>"#) == [.text(#"<need s="a">b</look>"#)])
    }

    // MARK: Diff

    @Test func sentencesDropTagsAndCutAfterPunctuation() {
        #expect(DigestDiff.sentences(#"<need s="a">One</need> thing. Then two? Yes; three! end"#)
                == ["One thing.", "Then two?", "Yes;", "three!", "end"])
        #expect(DigestDiff.sentences("  ").isEmpty)
    }

    @Test func aRewrittenSentenceIsMarkedWordByWord() {
        let lines = DigestDiff.lines("It is red.", "It is blue.")
        #expect(lines.count == 2)
        guard case .removed(let old, let gone) = lines[0], case .added(let new, let came) = lines[1] else {
            Issue.record("expected a removed then an added line"); return
        }
        #expect(old == "It is red." && new == "It is blue.")
        #expect(gone.map { String(old[$0]) } == ["red."] && came.map { String(new[$0]) } == ["blue."])
    }

    @Test func changedWordsMarkARunWithTheSpaceBetween() {
        let old = "a b c d", new = "a x y d"
        let (gone, came) = DigestDiff.changedWords(old, new)
        #expect(gone.map { String(old[$0]) } == ["b c"] && came.map { String(new[$0]) } == ["x y"])
        let same = DigestDiff.changedWords("a b", "a b")
        #expect(same.0.isEmpty && same.1.isEmpty)
    }

    @Test func keptSentencesFarFromAChangeFoldToOneMark() {
        let before = "A one. B two. C three. D four. E five. F six."
        let after = "A one. B two. C three. D four. E five. F changed."
        let lines = DigestDiff.lines(before, after)
        #expect(lines.first == .fold)
        #expect(lines.contains(.same("E five.")))
        #expect(!lines.contains(.same("A one.")) && lines.filter { $0 == .fold }.count == 1)
        // Pure additions and removals.
        #expect(DigestDiff.lines("", "New.") == [.added("New.", changed: [])])
        #expect(DigestDiff.lines("Old.", "") == [.removed("Old.", changed: [])])
        #expect(DigestDiff.lines("Same.", "Same.") == [.fold])
    }

    // MARK: Digest

    @Test func textByKeyAndChangedSinceSeen() {
        var d = RouterDigest(forYou: "you", worthALook: "look", projects: [.init(folder: "/p/a", text: "pa")], at: t0)
        #expect(d.text("lead-you") == "you" && d.text("lead-look") == "look" && d.text("/p/a") == "pa" && d.text("/p/zz") == nil)
        #expect(d.changedSinceSeen.isEmpty)
        d.record(.init(at: t0.addingTimeInterval(10), trigger: .session("s"), label: "l", why: "w",
                       changes: [.init(key: "/p/a", before: "", after: "pa")]))
        d.record(.init(at: t0.addingTimeInterval(20), trigger: .session("s"), label: "l", why: "w",
                       changes: [.init(key: "lead-you", before: "", after: "you")]))
        #expect(d.changedSinceSeen == ["/p/a", "lead-you"])
        d.seenAt = t0.addingTimeInterval(15)
        #expect(d.changedSinceSeen == ["lead-you"])
        d.seenAt = t0.addingTimeInterval(25)
        #expect(d.changedSinceSeen.isEmpty)
    }

    @Test func historyIsNewestFirstAndCapped() {
        var d = RouterDigest(forYou: "", worthALook: "", projects: [], at: t0)
        for n in 0..<(RouterDigest.historyLimit + 5) {
            d.record(.init(at: t0.addingTimeInterval(Double(n)), trigger: .you("m\(n)"), label: "\(n)", why: "", changes: []))
        }
        #expect(d.history.count == RouterDigest.historyLimit)
        #expect(d.history.first?.label == "\(RouterDigest.historyLimit + 4)")
        #expect(d.history.last?.label == "5")
    }

    // MARK: Events

    @Test func eventsFromStateChanges() {
        let a = card("a#1")
        // A load: no cards before, no events.
        #expect(Writer.events(from: state(), to: state([a])).isEmpty)
        // A new open card.
        #expect(Writer.events(from: state([a]), to: state([a, card("b#1")])) == [.card(session: "b", card: "b#1")])
        // A new card that is already handled isn't one.
        #expect(Writer.events(from: state([a]), to: state([a, card("b#1", open: false)])).isEmpty)
        // Open to addressed.
        #expect(Writer.events(from: state([a]), to: state([card("a#1", open: false)])) == [.handled(session: "a", card: "a#1", by: "you")])
        // Kind change.
        #expect(Writer.events(from: state([a]), to: state([card("a#1", kind: .asks)])) == [.card(session: "a", card: "a#1")])
        // Nothing changed.
        #expect(Writer.events(from: state([a]), to: state([a])).isEmpty)
        // Decisions: a new one of yours is an event; session ones and old ones aren't.
        let said = RouterDecision(trigger: .you("push it"))
        let sys = RouterDecision(trigger: .session(sessionID: "a", event: "x"))
        #expect(Writer.events(from: state([a]), to: state([a], decisions: [said, sys])) == [.you("push it")])
        #expect(Writer.events(from: state([a], decisions: [said]), to: state([a], decisions: [said, RouterDecision(trigger: .you("two"))]))
                == [.you("two")])
    }

    // MARK: Writer checks

    @Test func fixReadsAnUnknownSessionAsTextAndCorrectsAWrongKind() {
        let b = board()
        let fixed = Writer.fix(#"  <need s="s1">ok</need>, <need s="s2">hm</need>, <run s="gone">x</run> "#, b)
        #expect(fixed == #"<need s="s1">ok</need>, <look s="s2">hm</look>, x"#)
    }

    @Test func coverAppendsMissingOpenSessionsInTheLeadAndProjects() {
        let b = board()
        #expect(Writer.cover("Fine.", ["s1"], in: b, kind: .need, lead: true) == #"Fine. Also: <need s="s1">Title s1</need>."#)
        #expect(Writer.cover("", ["s1", "s2"], in: b, kind: .need, lead: true)
                == #"<need s="s1">Title s1</need> and <need s="s2">Title s2</need>."#)
        #expect(Writer.cover(#"<need s="s1">x</need>"#, ["s1"], in: b, kind: .need, lead: true) == #"<need s="s1">x</need>"#)
        // Not on the board: not added.
        #expect(Writer.cover("Fine.", ["nope"], in: b, kind: .need, lead: true) == "Fine.")
        // A project: a sentence for each, by what it is.
        let project = Writer.cover("Going.", ["s1", "s2"], in: b, kind: nil, lead: false)
        #expect(project == #"Going. <need s="s1">Title s1</need> needs you. <look s="s2">Title s2</look> is worth a look."#)
        var running = board(projects: [("/p/a", [("r", .run)])])
        running.titles["r"] = "Runner"
        #expect(Writer.cover("", ["r"], in: running, kind: nil, lead: false) == #"<run s="r">Runner</run> is running."#)
    }

    @Test func triggersPutWhatYouSaidFirstAndDedupe() {
        let events: [Writer.Event] = [.card(session: "a", card: "a#1"), .you("hi"), .handled(session: "a", card: "a#1", by: "you"),
                                      .running(["z"]), .card(session: "b", card: "b#1"), .you("hi")]
        #expect(Writer.triggers(events) == [.you("hi"), .session("a"), .session("b")])
        #expect(Writer.triggers([.running(["z"])]).isEmpty)
    }

    // MARK: Apply

    @Test func theFirstBriefHasNoHistory() throws {
        let b = board()
        let made = try #require(Writer.apply(answer(forYou: #"<need s="s1">a</need>"#, look: #"<look s="s2">b</look>"#,
                                                    projects: [("/p/a", #"<need s="s1">a</need> <look s="s2">b</look>"#)]),
                                             to: nil, rewriting: ["/p/a"], board: b, events: [], now: t0))
        #expect(made.history.isEmpty && made.at == t0 && made.projects.map(\.folder) == ["/p/a"])
        #expect(made.forYou == #"<need s="s1">a</need>"# && made.worthALook == #"<look s="s2">b</look>"#)
    }

    @Test func aRewriteRecordsOnlyWhatChangedAndKeepsTheOrder() throws {
        let b = board(projects: [("/p/a", [("s1", .need)]), ("/p/b", [("s2", .look)]), ("/p/c", [("s3", .need)])])
        let current = RouterDigest(forYou: #"<need s="s1">a</need>"#, worthALook: #"<look s="s2">b</look>"#,
                                   projects: [.init(folder: "/p/b", text: #"<look s="s2">old b</look>"#),
                                              .init(folder: "/p/a", text: #"<need s="s1">old a</need>"#)], at: t0)
        let now = t0.addingTimeInterval(60)
        // /p/b rewritten, /p/c is new (appended), /p/a not touched.
        let next = try #require(Writer.apply(
            answer(forYou: #"<need s="s1">a</need> <need s="s3">c</need>"#, look: #"<look s="s2">b</look>"#,
                   projects: [("/p/b", #"<look s="s2">new b</look>"#), ("/p/c", #"<need s="s3">c</need>"#)], label: "", why: "because"),
            to: current, rewriting: ["/p/b", "/p/c"], board: b, events: [.you("hi"), .card(session: "s3", card: "s3#1")], now: now))
        #expect(next.projects.map(\.folder) == ["/p/b", "/p/a", "/p/c"])
        let rev = try #require(next.history.first)
        #expect(rev.at == now && next.at == now && rev.label == "The brief changed" && rev.why == "because")
        #expect(rev.triggers == [.you("hi"), .session("s3")])
        #expect(rev.changes.map(\.key) == ["lead-you", "/p/b", "/p/c"])
        #expect(rev.changes[1] == .init(key: "/p/b", before: #"<look s="s2">old b</look>"#, after: #"<look s="s2">new b</look>"#))
        #expect(rev.changes[2].before == "")
    }

    @Test func anEmptyParagraphRemovesItsProject() throws {
        let b = board(projects: [("/p/a", [("s1", .need)])])
        let current = RouterDigest(forYou: #"<need s="s1">a</need>"#, worthALook: "",
                                   projects: [.init(folder: "/p/a", text: #"<need s="s1">a</need>"#),
                                              .init(folder: "/p/gone", text: "Was going.")], at: t0)
        let next = try #require(Writer.apply(answer(forYou: #"<need s="s1">a</need>"#, projects: [("/p/gone", "")]), to: current,
                                             rewriting: ["/p/gone"], board: b, events: [.running(["x"])], now: t0.addingTimeInterval(1)))
        #expect(next.projects.map(\.folder) == ["/p/a"])
        #expect(next.history.first?.changes.map(\.key) == ["/p/gone"])
    }

    @Test func nothingChangedRecordsNothing() {
        let b = board(projects: [("/p/a", [("s1", .need)])])
        let current = RouterDigest(forYou: #"<need s="s1">a</need>"#, worthALook: "",
                                   projects: [.init(folder: "/p/a", text: #"<need s="s1">a</need>"#)], at: t0)
        let next = Writer.apply(answer(forYou: #"<need s="s1">a</need>"#, projects: [("/p/a", #"<need s="s1">a</need>"#)]), to: current,
                                rewriting: ["/p/a"], board: b, events: [.card(session: "s1", card: "s1#1")], now: t0.addingTimeInterval(5))
        #expect(next == current)
    }

    @Test func theLeadAndProjectsAreCompletedWithOpenCards() throws {
        let b = board()
        let next = try #require(Writer.apply(answer(forYou: "Nothing.", projects: [("/p/a", "Quiet.")]), to: nil, rewriting: ["/p/a"],
                                             board: b, events: [], now: t0))
        #expect(next.forYou.contains(#"<need s="s1">"#) && next.worthALook.contains(#"<look s="s2">"#))
        #expect(next.projects.first?.text.contains(#"<need s="s1">Title s1</need> needs you."#) == true)
    }

    // MARK: Reading the answer

    @Test func theAnswerIsReadOrIgnored() throws {
        #expect(DigestPrompt.read(#"{"changed":false,"for_you":"x"}"#) == nil)
        #expect(DigestPrompt.read("not json") == nil)
        #expect(DigestPrompt.read("[1]") == nil)
        let read = try #require(DigestPrompt.read(
            #"{"changed":true,"for_you":"Y","worth_a_look":"L","projects":[{"key":"/p","text":"T"},{"key":"/q"}],"label":" lab ","why":"why\n"}"#))
        #expect(read.forYou == "Y" && read.worthALook == "L" && read.label == "lab" && read.why == "why")
        #expect(read.projects.map(\.key) == ["/p"] && read.projects.map(\.text) == ["T"])
        // Missing "changed" reads as changed.
        #expect(DigestPrompt.read(#"{"for_you":"Y"}"#)?.forYou == "Y")
    }

    // MARK: Persistence

    @Test func theDigestSurvivesAnEncodeAndDecode() throws {
        var digest = RouterDigest(forYou: #"<need s="a">x</need>"#, worthALook: "", projects: [.init(folder: "/p", text: "T")],
                                  at: t0, seenAt: t0.addingTimeInterval(3))
        digest.record(.init(at: t0.addingTimeInterval(1), triggers: [.you("hello"), .session("a")], label: "l", why: "w",
                            changes: [.init(key: "/p", before: "", after: "T")]))
        digest.record(.init(at: t0.addingTimeInterval(2), trigger: .session("b"), label: "l2", why: "w2", changes: []))
        var s = RouterState()
        s.digest = digest
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RouterState.self, from: data)
        #expect(back.digest == digest)
        let without = try JSONDecoder().decode(RouterState.self, from: JSONEncoder().encode(RouterState()))
        #expect(without.digest == nil)
        #expect(try JSONDecoder().decode(RouterState.self, from: Data("{}".utf8)).digest == nil)
    }

    // MARK: The writer, end to end

    @Test func theWriterWritesTheFirstBriefAndThenARecordedRewrite() async throws {
        let store = InboxFixture.store([])
        store.router.enabled = true
        store.routerDigester.runner = { _, _, _ in
            #"{"changed":true,"for_you":"<look s=\"a\">T a</look> is done.","worth_a_look":"<look s=\"a\">T a</look>","projects":[{"key":"/code/lookout","text":"<look s=\"a\">T a</look> finished."}],"label":"first","why":"w"}"#
        }
        store.router.cards = [card("a#1")]
        await store.routerDigester.flush(store: store)
        let first = try #require(store.routerDigest)
        #expect(first.history.isEmpty && first.projects.map(\.folder) == ["/code/lookout"])
        #expect(first.projects.first?.text == #"<look s="a">T a</look> finished."#)

        store.routerDigester.runner = { _, context, _ in
            #expect(context.contains("id=b") && context.contains("REWRITE"))
            return #"{"changed":true,"for_you":"<need s=\"b\">T b</need> asks.","worth_a_look":"<look s=\"a\">T a</look>","projects":[{"key":"/code/lookout","text":"<look s=\"a\">T a</look> done. <need s=\"b\">T b</need> asks."}],"label":"b asks","why":"b stopped"}"#
        }
        store.router.cards.append(card("b#1", kind: .asks))
        await store.routerDigester.flush(store: store)
        let second = try #require(store.routerDigest)
        #expect(second.forYou == #"<need s="b">T b</need> asks."#)
        let rev = try #require(second.history.first)
        #expect(second.history.count == 1 && rev.label == "b asks" && rev.triggers == [.session("b")])
        #expect(rev.changes.map(\.key).contains("lead-you") && rev.changes.map(\.key).contains("/code/lookout"))
    }

    @Test func aFailedOrUnchangedAnswerLeavesTheBriefAsItWas() async throws {
        let store = InboxFixture.store([])
        store.router.enabled = true
        store.routerDigester.runner = { _, _, _ in
            #"{"changed":true,"for_you":"","worth_a_look":"<look s=\"a\">T a</look>","projects":[{"key":"/code/lookout","text":"<look s=\"a\">T a</look>"}],"label":"","why":""}"#
        }
        store.router.cards = [card("a#1")]
        await store.routerDigester.flush(store: store)
        let first = try #require(store.routerDigest)
        store.routerDigester.runner = { _, _, _ in #"{"changed":false}"# }
        store.router.cards.append(card("b#1", kind: .asks))
        await store.routerDigester.flush(store: store)
        #expect(store.routerDigest == first)
        struct Boom: Error {}
        store.routerDigester.runner = { _, _, _ in throw Boom() }
        store.router.cards.append(card("c#1", kind: .asks))
        await store.routerDigester.flush(store: store)
        #expect(store.routerDigest == first)
    }

    // MARK: mark_seen

    @Test func markSeenAddressesTheCardsWorthALookByIdOrTitle() async throws {
        let store = InboxFixture.store([])
        store.router.enabled = true
        store.agents.enabled = true
        store.router.cards = [card("a#1", title: "Fix notifications"), card("b#1", title: "Fix badges"), card("c#1", kind: .asks)]
        let t = RouterTools(store: store)
        t.beginTurn("I've seen those")
        #expect(store.routerZones.notes.map(\.id).sorted() == ["a#1", "b#1"])
        // Ambiguous words match two cards: nothing marked.
        let both = await t.call("mark_seen", ["cards": ["fix"]])
        #expect(both?.isError == true && both?.text.contains("more than one") == true)
        #expect(store.router.cards.allSatisfy { $0.isOpen })
        let byId = await t.call("mark_seen", ["cards": ["a#1"]])
        #expect(byId?.isError == false)
        #expect(store.router.cards.first { $0.id == "a#1" }?.isOpen == false)
        #expect(store.router.cards.first { $0.id == "a#1" }?.addressedBy == .you)
        // One that needs you isn't marked.
        #expect(await t.call("mark_seen", ["cards": ["c#1"]])?.isError == true)
        #expect(store.router.cards.first { $0.id == "c#1" }?.isOpen == true)
        // By words of the title; the rest reported.
        let words = await t.call("mark_seen", ["cards": ["badges", "zzz"]])
        #expect(words?.isError == false && words?.text.contains("Not found") == true)
        #expect(store.router.cards.first { $0.id == "b#1" }?.isOpen == false)
        #expect(await t.call("mark_seen", ["cards": [String]()])?.isError == true)
    }
}
