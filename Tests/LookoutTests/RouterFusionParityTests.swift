import Foundation
import Testing
@testable import Lookout

/// RouterLexical and RouteFusion compute and decide as the policy measured in evals/router did (explore/final3.py), on
/// the inputs Jev gave for the 360 written cases there (Fixtures/router-fusion-parity.json, made by evals/router/parity.py).
@MainActor
struct RouterFusionParityTests {
    struct Session: Decodable {
        var title: String
        var turns: [[String]]
    }

    struct Case: Decodable {
        var id: String
        var message: String
        var route: [String: Double]
        var reply: [String: Double]
        var next: [String: Double]
        var gates: [String: Double]
        var latest: [String]
        var running: [String]
        var idle: [String: Double]
        var lastTold: String?
        var leaves: [String]
        var sessions: [String: Session]
        var lexical: [String: [String: Double]]
        var sure: Bool
        var top: String?
    }

    private func cases() throws -> [Case] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/router-fusion-parity.json")
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test func theWordsScoreAsMeasured() throws {
        var differ: [String] = []
        for c in try cases() {
            let sessions = c.sessions.mapValues { s in
                (title: s.title, turns: s.turns.map { RouterLexical.Turn(you: $0[0], said: $0[1]) })
            }
            let swift = RouterLexical.all(c.message, sessions: sessions)
            for (field, expected) in c.lexical {
                for (id, x) in expected where abs((swift[field]?[id] ?? -1) - x) > 1e-6 {
                    differ.append("\(c.id) \(field) \(id): swift \(swift[field]?[id] ?? -1), measured \(x)")
                }
            }
        }
        #expect(differ.isEmpty, "\(differ.count) differ: \(differ.prefix(8))")
    }

    @Test func itDecidesAsTheMeasuredPolicy() throws {
        let cases = try cases()
        #expect(cases.count == 360)
        var differ: [String] = []
        for c in cases {
            var facts = RouterTools.Facts()
            facts.latest = c.latest
            facts.running = Set(c.running)
            facts.idleMinutes = c.idle
            facts.lastTold = c.lastTold
            facts.targetOf = Dictionary(uniqueKeysWithValues: c.idle.keys.map { ($0, "session:\($0)") })
            facts.message = c.message
            facts.leavesItToYou = Set(c.leaves)
            let signals = RouteFusion.Signals(route: c.route, reply: c.reply, next: c.next, gates: c.gates, lexical: c.lexical)
            let answers = c.reply.map { (target: "session:\($0.key)", session: $0.key, p: $0.value) }
            let v = RouteFusion.decide(signals, facts: facts, answers: answers) {
                $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil
            }
            if v.sure != c.sure || (v.sure && v.ranked.first?.target != c.top) {
                differ.append("\(c.id): swift \(v.sure ? v.ranked.first?.target ?? "?" : "ask"), measured \(c.top ?? "ask")")
            }
        }
        #expect(differ.isEmpty, "\(differ.count) differ: \(differ.prefix(10))")
    }

    /// As `--card top1,other,recent` in evals/router/v2/run/episodes.py: the first, the best non-session in the first
    /// four, then sessions by recency, then the rest; `unclear` is never a button.
    @Test func theAskCardHoldsTheFirstAnOtherKindAndTheLatest() {
        var facts = RouterTools.Facts(message: "")
        facts.idleMinutes = ["a": 30, "b": 1, "c": 1, "d": 90]
        facts.targetOf = ["a": "session:a", "b": "session:b", "c": "session:c", "d": "session:d"]
        #expect(RouterTools.recent(facts) == ["session:b", "session:c", "session:a", "session:d"])
        let card = RouterTools.askCard(ranked: ["unclear", "session:d", "session:a", "question", "new:x"],
                                       recent: RouterTools.recent(facts))
        #expect(Array(card.prefix(4)) == ["session:d", "question", "session:b", "session:c"])
        #expect(Array(RouterTools.askCard(ranked: ["session:a", "session:b"], recent: ["session:c"]).prefix(3))
                == ["session:a", "session:c", "session:b"])
    }

    /// The routing trace records what `decide` read: its ranking, its sureness, and whether that was sure.
    @Test func theTraceHoldsWhatTheFusionDecidedOn() throws {
        let c = try cases().first { $0.sure }!
        var facts = RouterTools.Facts()
        facts.latest = c.latest
        facts.running = Set(c.running)
        facts.idleMinutes = c.idle
        facts.lastTold = c.lastTold
        facts.targetOf = Dictionary(uniqueKeysWithValues: c.idle.keys.map { ($0, "session:\($0)") })
        facts.message = c.message
        facts.leavesItToYou = Set(c.leaves)
        let signals = RouteFusion.Signals(route: c.route, reply: c.reply, next: c.next, gates: c.gates, lexical: c.lexical)
        let sessionOf: (String) -> String? = { $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil }
        let answers = c.reply.map { (target: "session:\($0.key)", session: $0.key, p: $0.value) }
        let v = RouteFusion.decide(signals, facts: facts, answers: answers, sessionOf: sessionOf)
        let trace = RouterTrace.Inputs(signals: signals, facts: facts, destinations: [], ranked: v.ranked, sure: v.sure,
                                       card: [], sessionOf: sessionOf)
        #expect(trace.sure == v.sure && trace.ranked.first?.target == v.ranked.first?.target && trace.ranked.count <= 8)
        #expect((trace.sureness ?? 0) > 0 && (trace.sureness ?? 1) < 1)
        #expect(trace.route == c.route && trace.latest == c.latest)
    }

    @Test func theLastMessageLeavesItToYou() {
        #expect(RouterLexical.leavesItToYou("Want me to push it?", waiting: false))
        #expect(RouterLexical.leavesItToYou("I can open the PR next.", waiting: false))
        #expect(RouterLexical.leavesItToYou("All 1,137 tests passed.", waiting: true))
        #expect(!RouterLexical.leavesItToYou("All 1,137 tests passed.", waiting: false))
    }

    @Test func aTranscriptsTurnsAreWhatYouTypedAndItsLastAnswer() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"fix the login bug"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking."}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Fixed: the redirect."}]}}"#,
            #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"user","isMeta":true,"message":{"content":"meta"}}"#,
            #"{"type":"user","message":{"content":[{"type":"text","text":"now add a test"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Writing it."}]}}"#,
        ]
        let tail = Data(lines.joined(separator: "\n").utf8)
        #expect(RouterLexical.turns(tail: tail, working: false) == [.init(you: "fix the login bug", said: "Fixed: the redirect."),
                                                                 .init(you: "now add a test", said: "Writing it.")])
        #expect(RouterLexical.turns(tail: tail, working: true).last == .init(you: "now add a test", said: ""))
    }

    @Test func keysNeverReachJev() {
        let text = "use sk-or-v1-0123456789abcdef0123456789abcdef and 0123456789abcdef0123456789abcdef.AbCdEfGhIjKlMnOp"
        let out = RouterTools.redacted(text)
        #expect(!out.contains("sk-or") && !out.contains("AbCdEfGh") && out.hasPrefix("use [redacted] and [redacted]"))
        #expect(RouterTools.hinted("Fix the login bug", 80) == "Fix the login bug")
        let invoice = RouterTools.redacted("pay to FR76 3000 6000 0112 3456 7890 189, card 4970 1012 3456 7890, acct 0123456789")
        let digits = invoice.filter(\.isNumber)
        #expect(digits.isEmpty, "\(invoice)")
    }
}
