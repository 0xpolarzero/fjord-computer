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

    struct Fixture: Decodable {
        var cases: [Case]
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

    @Test func theWireFormsRoundTrip() {
        for wire in ["archive:card:abc#c", "stop:session:s1", "interrupt:session:s1", "say:session:s1", "answer:card:s#w1",
                     "start:new:/code/lookout", "configure", "ask_fjord", "compound", "unclear"] {
            #expect(RouterAct(wire: wire).wire == wire)
        }
        for target in ["session:s1", "answer:s#w1", "new:/code/x", "change_fjord", "question", "compound", "archive:card:c", "stop:session:s",
                       "interrupt:session:s"] {
            #expect(RouterAct(target: target).target == target)
        }
    }
}
