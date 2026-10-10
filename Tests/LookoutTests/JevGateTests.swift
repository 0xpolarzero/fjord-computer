import Foundation
import Testing
@testable import Lookout

/// TypeSafe's failures, typed, and the one gate every call to Jev goes through.
@MainActor
@Suite(.serialized) struct JevGateTests {
    private func response(_ status: Int, headers: [String: String] = [:]) -> JevClient.Transport {
        { request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
    }

    private func failure(_ transport: @escaping JevClient.Transport) async -> JevClient.Failure? {
        var client = JevClient(key: "k")
        client.transport = transport
        do {
            _ = try await client.ask(["q": .noul(instructions: "?")], about: "x")
            return nil
        } catch {
            return error as? JevClient.Failure
        }
    }

    @Test func failuresAreTyped() async {
        #expect(await failure(response(401)) == .unauthorized)
        #expect(await failure(response(429, headers: ["Retry-After": "7"])) == .rateLimited(retryAfter: 7))
        #expect(await failure(response(429)) == .rateLimited(retryAfter: nil))
        #expect(await failure(response(529)) == .overloaded(retryAfter: nil))
        #expect(await failure(response(500)) == .transport("TypeSafe returned 500"))
        if case .refused = await failure(response(422)) {} else { Issue.record("422 isn't refused") }
        #expect(await failure { _ in throw URLError(.cancelled) } == .cancelled)
        #expect(await failure { _ in throw CancellationError() } == .cancelled)
        if case .transport = await failure({ _ in throw URLError(.notConnectedToInternet) }) {} else { Issue.record("offline isn't transport") }
        if case .invalidAnswer = await failure(response(200)) {} else { Issue.record("an empty answer isn't invalid") }
    }

    @Test func theGateLatchesARejectedKeyHonoursRetryAfterAndBacksOff() {
        let gate = JevGate()
        var now = Date(timeIntervalSince1970: 1_000_000)
        gate.now = { now }
        gate.failed(JevClient.Failure.unauthorized, key: "old")
        #expect(!gate.isOpen(for: "old") && gate.isOpen(for: "other"))
        // Retry-After, then nothing until it passes.
        gate.failed(JevClient.Failure.rateLimited(retryAfter: 90), key: "k")
        #expect(!gate.isOpen(for: "k"))
        now += 89
        #expect(!gate.isOpen(for: "k"))
        now += 2
        #expect(gate.isOpen(for: "k"))
        // Failures in a row wait longer each time (the rate limit above was the first).
        gate.failed(JevClient.Failure.transport("offline"), key: "k")
        #expect(gate.until == now.addingTimeInterval(JevGate.shortest * 2))
        now = gate.until
        gate.failed(JevClient.Failure.overloaded(retryAfter: nil), key: "k")
        #expect(gate.until == now.addingTimeInterval(JevGate.shortest * 4))
        // A call that worked starts over; odd answers and refusals are that call's alone; other errors aren't TypeSafe's.
        gate.succeeded()
        gate.failed(JevClient.Failure.invalidAnswer("odd"), key: "k")
        gate.failed(JevClient.Failure.refused("bad"), key: "k")
        gate.failed(URLError(.timedOut), key: "k")
        #expect(gate.isOpen(for: "k") && gate.failures == 0)
        // Still latched until a new key is saved.
        #expect(!gate.isOpen(for: "old"))
        gate.keyChanged()
        #expect(gate.isOpen(for: "old"))
    }

    private func store() -> Store {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.agents.enabled = true
        s.typesafeKeyCache = "sk-old"
        s.hasTypesafeKey = true
        s.keychainWrite = { _, _ in true }
        return s
    }

    @Test func aRejectedKeyStopsEveryUseUntilANewOneIsSaved() async {
        let s = store()
        var sent: [String] = []
        s.jevGate.transport = { request in
            sent.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let routing = s.jevAsker(.routing)
        await #expect(throws: JevClient.Failure.unauthorized) { try await routing?(["q": .noul(instructions: "?")], [:]) }
        #expect(sent == ["Bearer sk-old"])
        // The triage, the cards, the icons and the inbox don't call with it either.
        await #expect(throws: JevClient.Failure.unauthorized) { try await s.jevAsker(.triage)?(["q": .noul(instructions: "?")], [:]) }
        await #expect(throws: JevClient.Failure.unauthorized) { try await s.jevChooser(.cards)?(["a"], [:], [:], "") }
        s.agents.iconsEnabled = true
        await #expect(throws: JevClient.Failure.unauthorized) { try await s.jevChooser(.icons)?(["a"], [:], [:], "") }
        #expect(!s.jevGate.isOpen(for: "sk-old") && sent.count == 1)
        // A new key is tried.
        #expect(s.setTypesafeKey("sk-new"))
        _ = try? await s.jevAsker(.routing)?(["q": .noul(instructions: "?")], [:])
        #expect(sent == ["Bearer sk-old", "Bearer sk-new"])
    }

    @Test func aBusyTypeSafeIsLeftAloneByEveryUse() async {
        let s = store()
        var calls = 0
        s.inboxAsker = { _, _ in calls += 1; throw JevClient.Failure.overloaded(retryAfter: 60) }
        s.routerTriager.asker = { _, _ in calls += 1; return [:] }
        await #expect(throws: JevClient.Failure.overloaded(retryAfter: 60)) {
            try await s.throughJevGate(.inbox, generation: s.jevGate.generation) { try await s.inboxAsker!([:], [:]) }
        }
        await #expect(throws: JevClient.Failure.overloaded(retryAfter: 60)) {
            try await s.jevAsker(.triage, base: s.routerTriager.asker)?([:], [:])
        }
        #expect(calls == 1)
    }

    @Test func anAnswerAfterTheKeyOrTheSwitchChangedIsDropped() async {
        let s = store()
        var flip: () -> Void = {}
        let ask = s.jevAsker(.triage, base: { _, _ in flip(); return ["q": .noul(1)] })
        flip = { _ = s.setTypesafeKey("sk-other") }
        await #expect(throws: JevClient.Failure.cancelled) { try await ask?([:], [:]) }
        // Taken before the switch went off, it asks nothing.
        var asked = false
        let off = s.jevAsker(.triage, base: { _, _ in asked = true; return [:] })
        s.router.enabled = false
        await #expect(throws: JevClient.Failure.cancelled) { try await off?([:], [:]) }
        #expect(!asked && s.jevAsker(.triage, base: { _, _ in [:] }) == nil)
    }
}
