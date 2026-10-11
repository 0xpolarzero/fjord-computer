import Foundation
import Testing
@testable import Lookout

/// RouteFusion.decide decides as the policy measured in evals/router did (explore/fuse2.py `guarded`), on the inputs Jev
/// gave for the 360 written cases there (Fixtures/router-fusion-parity.json, made by evals/router/parity.py).
@MainActor
struct RouterFusionParityTests {
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
        var sure: Bool
        var top: String?
    }

    @Test func itDecidesAsTheMeasuredPolicy() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/router-fusion-parity.json")
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
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
            let signals = RouteFusion.Signals(route: c.route, reply: c.reply, next: c.next, gates: c.gates)
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
}
