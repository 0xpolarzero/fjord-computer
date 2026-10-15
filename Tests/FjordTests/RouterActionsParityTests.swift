import Foundation
import Testing
@testable import Fjord

/// `RouterActionChecks.decideAction` decides as `decide()` of evals/router/explore/actions_d3.py did, on recorded check and
/// route answers of the D3-all dev traces and on made-up boards that reach the branches the traces rarely do
/// (Fixtures/router-actions-parity.json, made by `python3 -m explore.actions_d3 export-parity`).
struct RouterActionsParityTests {
    struct Routing: Decodable {
        var decision: String
        var act: String?
        var options: [String]
    }

    struct Info: Decodable {
        var T: String?
        var pT: Double?
        var raw_top: String?
        var checks: [[Check]]
        var globals: [String: Double]
        var stoppable: [String]
        var T_act: String?
        var routing: Routing

        enum Check: Decodable {
            case string(String), number(Double), bool(Bool), null
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if c.decodeNil() { self = .null }
                else if let b = try? c.decode(Bool.self) { self = .bool(b) }
                else if let n = try? c.decode(Double.self) { self = .number(n) }
                else { self = .string(try c.decode(String.self)) }
            }
            var string: String? { if case .string(let s) = self { s } else { nil } }
            var number: Double? { if case .number(let n) = self { n } else { nil } }
        }

        enum CodingKeys: String, CodingKey { case T, pT, raw_top, checks, globals, stoppable, T_act, routing }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            T = try c.decodeIfPresent(String.self, forKey: .T)
            pT = try c.decodeIfPresent(Double.self, forKey: .pT)
            raw_top = try c.decodeIfPresent(String.self, forKey: .raw_top)
            checks = try c.decode([[Check]].self, forKey: .checks)
            globals = try c.decode([String: Double].self, forKey: .globals)
            stoppable = try c.decode([String].self, forKey: .stoppable)
            T_act = try c.decodeIfPresent(String.self, forKey: .T_act)
            routing = try c.decode(Routing.self, forKey: .routing)
        }
    }

    struct Expected: Decodable {
        var decision: String
        var act: String?
        var options: [String]?
        var why: String
    }

    struct Case: Decodable {
        var name: String
        var info: Info
        var expected: Expected
    }

    struct AssemblySession: Decodable {
        var id: String
        var project: String
        var running: Bool
        var waits_on_you: Bool
        var archived: Bool
        var last_activity: Double
    }

    struct AssemblyCase: Decodable {
        struct Board: Decodable {
            struct Card: Decodable { var id: String; var session: String }
            var sessions: [AssemblySession]
            var cards: [Card]
        }
        struct Scope: Decodable { var projects: [String]?; var sessions: [String] }
        struct Expected: Decodable { var cards: [String]; var stoppable: [String] }
        var name: String
        var board: Board
        var scope: Scope
        var expected: Expected
    }

    struct InfoCase: Decodable {
        struct Found: Decodable {
            var ranked: [[Info.Check]]
            var sure: Bool
            var card: [String]?
            var route: [String: Double]
            var options: [String]
        }
        struct Expected: Decodable {
            var T: String?
            var pT: Double
            var raw_top: String?
            var T_act: String?
            var routing: Routing
        }
        var name: String
        var found: Found
        var cards: [[String]]
        var expected: Expected
    }

    struct Fixture: Decodable {
        var cases: [Case]
        var assembly: [AssemblyCase]
        var info: [InfoCase]
    }

    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/router-actions-parity.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func info(_ i: Info) -> RouterActionInfo {
        var reading = RouterActionReading(stoppable: i.stoppable)
        for c in i.checks {
            guard c.count >= 4, let kind = c[0].string.flatMap(RouterActionCheck.Kind.init(rawValue:)), let p = c[3].number,
                  let session = c[2].string else { continue }
            reading.checks.append(.init(kind: kind, card: c[1].string, session: session, p: p))
        }
        reading.urgent = i.globals["urgent"] ?? 0
        reading.instead = i.globals["instead"] ?? 0
        var out = RouterActionInfo(reading: reading)
        out.target = i.T
        out.targetP = i.pT ?? 0
        out.rawTop = i.raw_top
        out.targetAct = i.T_act.map(RouterAct.init(wire:))
        out.routeAsks = i.routing.decision == "ask"
        out.routeAct = i.routing.act.map(RouterAct.init(wire:))
        out.routeOptions = i.routing.options.map(RouterAct.init(wire:))
        return out
    }

    @Test func itDecidesAsTheMeasuredPolicy() throws {
        let cases = try fixture().cases
        #expect(cases.count > 500)
        var differ: [String] = []
        var seen = Set<String>()
        for c in cases {
            let d = RouterActionChecks.decideAction(Self.info(c.info))
            seen.insert("\(d.kind.rawValue)/\(d.why)")
            let expectedKind = c.expected.decision
            let expectedAct = c.expected.act
            if d.kind.rawValue != expectedKind || d.why != c.expected.why || d.act?.wire != expectedAct
                || (expectedKind == "ask" && d.options.map(\.wire) != (c.expected.options ?? [])) {
                differ.append("\(c.name): swift \(d.kind.rawValue)/\(d.why) \(d.act?.wire ?? "-") \(d.options.map(\.wire)); python \(expectedKind)/\(c.expected.why) \(expectedAct ?? "-") \(c.expected.options ?? [])")
            }
        }
        #expect(differ.isEmpty, "\(differ.count) of \(cases.count) differ: \(differ.prefix(6))")
        // Every branch is compared: a fixture that lost one would pass for nothing.
        for branch in ["act/T", "act/urgent", "act/standing-out", "ask/elsewhere", "ask/unsure", "ask/route-ask", "route/route"] {
            #expect(seen.contains(branch), "\(branch) is in the fixture")
        }
    }

    /// The checks' inputs (which cards and sessions they are asked about, in what order, under a scope) are assembled as the
    /// evals' `assemble_inputs` does, not only decided on after.
    @Test func theChecksAreAskedAboutWhatTheEvalsAssemble() throws {
        let cases = try fixture().assembly
        #expect(cases.count >= 200)
        var differ: [String] = []
        var scoped = 0
        for c in cases {
            let sessions = c.board.sessions.map {
                RouterActionChecks.BoardSession(id: $0.id, folder: $0.project, working: $0.running, waits: $0.waits_on_you, lastActivity: $0.last_activity)
            }
            let project = Dictionary(uniqueKeysWithValues: c.board.sessions.map { ($0.id, $0.project) })
            let cards = c.board.cards.map { RouterActionChecks.BoardCard(id: $0.id, session: $0.session, folder: project[$0.session] ?? "") }
            let live = Set(c.board.sessions.filter { !$0.archived }.map(\.id))
            let scope = RouterActionChecks.Scope(projects: c.scope.projects.map(Set.init), sessions: Set(c.scope.sessions))
            let got = RouterActionChecks.assemble(cards: cards, sessions: sessions, live: live, scope: scope)
            if got.cards != c.expected.cards || got.sessions != c.expected.stoppable {
                differ.append("\(c.name): swift \(got.cards) \(got.sessions); python \(c.expected.cards) \(c.expected.stoppable)")
            }
            if c.scope.projects != nil || !c.scope.sessions.isEmpty { scoped += 1 }
        }
        #expect(differ.isEmpty, "\(differ.count) of \(cases.count) differ: \(differ.prefix(4))")
        #expect(scoped > 50, "the fixture reaches scopes")
    }

    /// What the decision reads of the route (the target, the raw top with its tie rule, the act and the options) is assembled as
    /// the evals' `assemble_info` does.
    @Test func theRoutesOutcomeIsReadAsTheEvalsReadIt() throws {
        let cases = try fixture().info
        #expect(cases.count >= 200)
        var differ: [String] = []
        var ties = 0
        for c in cases {
            let kinds: [String: RouterCard.Kind] = ["question": .question, "plan": .plan, "done": .done]
            let cards = c.cards.map { (id: $0[0], session: $0[1], kind: kinds[$0[2]] ?? .done) }
            var found = RouterDispatcher.Classification(ranked: c.found.ranked.map { .init(target: $0[0].string ?? "", p: $0[1].number ?? 0) },
                                                        sure: c.found.sure, assisted: true)
            found.card = c.found.card
            if !c.found.route.isEmpty {
                var trace = RouterTrace.Inputs()
                trace.options = c.found.options.map { .init(target: $0, name: "") }
                trace.route = c.found.route
                found.trace = trace
            }
            let canon: (String) -> String = { target in
                guard target.hasPrefix("answer:") else { return target }
                return cards.first { $0.id == String(target.dropFirst(7)) }.map { "session:\($0.session)" } ?? target
            }
            let info = RouterActionChecks.info(found: found, reading: RouterActionReading(), cards: cards, canon: canon)
            let e = c.expected
            if info.target != e.T || info.targetP != e.pT || info.rawTop != e.raw_top || info.targetAct?.wire != e.T_act
                || info.routeAsks != (e.routing.decision == "ask") || info.routeAct?.wire != e.routing.act
                || info.routeOptions.map(\.wire) != e.routing.options {
                differ.append("\(c.name): swift \(info.target ?? "-") \(info.rawTop ?? "-") \(info.routeAct?.wire ?? "-") \(info.routeOptions.map(\.wire)); python \(e.T ?? "-") \(e.raw_top ?? "-") \(e.routing.act ?? "-") \(e.routing.options)")
            }
            if Set(c.found.route.values).count < c.found.route.count { ties += 1 }
        }
        #expect(differ.isEmpty, "\(differ.count) of \(cases.count) differ: \(differ.prefix(4))")
        #expect(ties > 50, "the fixture has ties between options")
    }

    @Test func aTieInTheRoutesTopGoesToTheOptionSentFirst() {
        var trace = RouterTrace.Inputs()
        trace.options = [.init(target: "session:b", name: ""), .init(target: "unclear", name: ""), .init(target: "session:a", name: "")]
        trace.route = ["session:a": 0.4, "unclear": 0.4, "session:b": 0.2]
        #expect(RouterActionChecks.rawTop(trace) == "unclear", "the earlier of two equal options, whatever a dictionary iterates first")
        trace.options = [.init(target: "session:a", name: ""), .init(target: "unclear", name: "")]
        #expect(RouterActionChecks.rawTop(trace) == "session:a")
        trace.options = []
        #expect(RouterActionChecks.rawTop(trace) == "session:a", "without the options, by name")
        #expect(RouterActionChecks.rawTop(nil) == nil)
    }

    @Test func theWireFormsRoundTrip() {
        for wire in ["archive:card:abc#c", "stop:session:s1", "interrupt:session:s1", "say:session:s1", "answer:card:s#w1",
                     "start:new:/code/lookout", "configure", "ask_fjord", "compound", "unclear", "retry:session:s1"] {
            #expect(RouterAct(wire: wire).wire == wire)
        }
        for target in ["session:s1", "answer:s#w1", "new:/code/x", "change_fjord", "question", "compound", "archive:card:c", "stop:session:s",
                       "interrupt:session:s"] {
            #expect(RouterAct(target: target).target == target)
        }
    }
}
