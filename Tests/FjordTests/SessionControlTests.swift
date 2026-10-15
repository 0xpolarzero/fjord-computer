import Foundation
import Testing
@testable import Fjord

/// Stopping a turn and interrupting it: the wire (the vectors `relay.test.ts` checks too), the presence the plugin writes,
/// the running state that follows from it, and the Store's API with a fake plugin answering in the inbox.
@MainActor
@Suite(.serialized) struct SessionControlTests {
    private static let nonce = UUID(uuidString: "423e4567-e89b-12d3-a456-426614174000")!
    private static let now = Date(timeIntervalSince1970: Double(RelaySigning.ts) / 1000)

    // MARK: Wire

    @Test func theStopIsSignedAsThePluginChecksIt() throws {
        let withTurn = RelaySigner.signStop(target: RelaySigning.target, turn: "t1", key: RelaySigning.key, nonce: Self.nonce, now: Self.now)
        #expect(withTurn == "⟦fjord stop v1 cli-target \(Self.nonce.uuidString.lowercased()) 2000000000000 t1 "
            + "e782a0a0eec1e2c602dfcb2085b8da83d7c47dfc505ce7aa93179f4a00ec831b⟧\n")
        let any = RelaySigner.signStop(target: RelaySigning.target, turn: nil, key: RelaySigning.key, nonce: Self.nonce, now: Self.now)
        #expect(any == "⟦fjord stop v1 cli-target \(Self.nonce.uuidString.lowercased()) 2000000000000 - "
            + "f8d40719bb6cd8b283e0415d5982f789446c8f35b39ea8a46334c611bc55835e⟧\n")
        // The inbox goes by the stop's own nonce, for its own ack.
        let header = try #require(RelayInbox.header(of: withTurn))
        #expect(header.target == "cli-target" && header.nonce == Self.nonce.uuidString.lowercased())
    }

    @Test func aStopIsBoundToItsTurnItsTargetAndItsKey() {
        let signed = RelaySigner.signStop(target: "cli-target", turn: "t1", key: RelaySigning.key, nonce: Self.nonce, now: Self.now)
        func mac(_ text: String) -> Substring { text.dropLast(2).split(separator: " ").last ?? "" }
        let id = Self.nonce.uuidString.lowercased()
        // Another turn, another session, another time and another key each sign differently: a tampered header fails the check.
        for other in [
            RelaySigner.signStop(target: "cli-target", turn: "t2", key: RelaySigning.key, nonce: Self.nonce, now: Self.now),
            RelaySigner.signStop(target: "cli-other", turn: "t1", key: RelaySigning.key, nonce: Self.nonce, now: Self.now),
            RelaySigner.signStop(target: "cli-target", turn: "t1", key: RelaySigning.key, nonce: Self.nonce, now: Self.now.addingTimeInterval(1)),
            RelaySigner.signStop(target: "cli-target", turn: "t1", key: String(repeating: "00", count: 32), nonce: Self.nonce, now: Self.now),
            RelaySigner.signStop(target: "cli-target", turn: nil, key: RelaySigning.key, nonce: Self.nonce, now: Self.now),
        ] { #expect(mac(other) != mac(signed)) }
        // A stop is not an abort of a delivery, nor the reverse: the kinds sign differently over the same fields.
        let abort = RelaySigner.signAbort(target: "cli-target", cancels: "t1", key: RelaySigning.key, nonce: Self.nonce, now: Self.now)
        #expect(mac(abort) != mac(signed) && abort.contains("abort v1 cli-target \(id)"))
    }

    @Test func theInterruptIsAV3MessageWithASignedFlag() throws {
        let plain = RelaySigner.sign(body: RelaySigning.body, target: RelaySigning.target, key: RelaySigning.key,
                                     nonce: UUID(uuidString: RelaySigning.nonce)!, now: Self.now, interrupt: true)
        #expect(plain == "⟦fjord v3 cli-target \(RelaySigning.nonce) 2000000000000 - - 1 "
            + "397d706bea305bc49650a5a83e5000bc850c791b9e3e06aa7769a0815afacd4c⟧\nVXNlIFBvc3RncmVzCmFuZCBzaGlwIOKfpsOp4p+n")
        let settings = RelaySigner.sign(body: RelaySigning.body, target: RelaySigning.target, key: RelaySigning.key,
                                        nonce: UUID(uuidString: RelaySigning.nonce)!, now: Self.now, model: "opus", effort: "high", interrupt: true)
        #expect(settings.hasPrefix("⟦fjord v3 cli-target \(RelaySigning.nonce) 2000000000000 opus high 1 "
            + "61a6003925d90fe9ddb2513a15952a918ae05e2d3b40f05a41aae4e11fa37742⟧\n"))
        // The flag is inside the signature: the same header with it cleared would need another MAC (the vector of flag 0).
        #expect(RelaySigner.mac(key: RelaySigning.key, target: RelaySigning.target, nonce: RelaySigning.nonce, ts: "2000000000000",
                                body: Data(RelaySigning.body.utf8), model: "-", effort: "-", interrupt: false)
            == "0fe96e552c0da9b6bd0bf6c704e0c87a77c6ffcb1e6a9158f562bf7e14242692")
        // The inbox reads its header; without the interrupt the v1 and v2 texts are what they were.
        let header = try #require(RelayInbox.header(of: plain))
        #expect(header.target == "cli-target" && header.nonce == RelaySigning.nonce)
        #expect(RelaySigner.sign(body: RelaySigning.body, target: RelaySigning.target, key: RelaySigning.key,
                                 nonce: UUID(uuidString: RelaySigning.nonce)!, now: Self.now) == RelaySigning.wire)
    }

    @Test func theAcksAreReadStrictly() {
        #expect(SessionControlAck.stop("ok stopped t1") == .stopped("t1"))
        #expect(SessionControlAck.stop("ok idle") == .idle)
        #expect(SessionControlAck.stop("ok not-running") == .notRunning)
        #expect(SessionControlAck.stop("ok") == nil && SessionControlAck.stop("ok stopped") == nil)
        #expect(SessionControlAck.stop("ok aborted") == nil && SessionControlAck.stop("stopped t1") == nil)
        #expect(SessionControlAck.delivery("ok interrupted t1")?.interrupted == "t1")
        #expect(SessionControlAck.delivery("ok interrupted t1 model=opus effort=high")?.interrupted == "t1")
        #expect(SessionControlAck.delivery("ok idle")?.interrupted == nil)
        #expect(SessionControlAck.delivery("ok")?.interrupted == nil)
        #expect(SessionControlAck.delivery("refused: stale") == nil)
    }

    // MARK: Presence

    @Test func presenceSaysWhichTurnRunsAndWhatThePluginCanDo() throws {
        func decode(_ json: String) throws -> ClaudePlugin.Presence {
            try JSONDecoder().decode(ClaudePlugin.Presence.self, from: Data(json.utf8))
        }
        let running = try decode(#"{"state":"live","capabilities":["inbox-v1","stop-v1"],"turn":{"id":"t1","startedAt":1700000000000}}"#)
        #expect(running.turn == .init(id: "t1", startedAt: 1_700_000_000_000) && running.hasTurnField)
        #expect(running.can("stop-v1") && !running.can("interrupt-v1"))
        let idle = try decode(#"{"state":"live","turn":null}"#)
        #expect(idle.turn == nil && idle.hasTurnField)
        // An older plugin says nothing of turns: the guess stands.
        let old = try decode(#"{"state":"live","capabilities":["inbox-v1"]}"#)
        #expect(old.turn == nil && !old.hasTurnField)
        // Something unreadable in `turn` is no turn, not a failure to read the file.
        let odd = try decode(#"{"state":"live","turn":"t1"}"#)
        #expect(odd.turn == nil)
        #expect(ClaudePlugin.stopCapability == "stop-v1" && ClaudePlugin.interruptCapability == "interrupt-v1")
    }

    @Test func theRunningStateFollowsThePluginWhereItSpeaksAndTheGuessElsewhere() {
        func session(_ id: String, cli: String?, running: Bool, archived: Bool = false) -> ClaudeSession {
            ClaudeSession(id: id, title: id, isArchived: archived, lastActivity: Self.now, running: running, cliID: cli)
        }
        func presence(turn: String?, field: Bool = true) -> ClaudePlugin.Presence {
            var json = #"{"state":"live","capabilities":["stop-v1"]"#
            if field { json += turn.map { #","turn":{"id":"\#($0)"}"# } ?? #","turn":null"# }
            return try! JSONDecoder().decode(ClaudePlugin.Presence.self, from: Data((json + "}").utf8))
        }
        let read = ClaudeFeed.applying(presence: ["cli-run": presence(turn: "t1"), "cli-idle": presence(turn: nil), "cli-old": presence(turn: nil, field: false),
                                                  "cli-arch": presence(turn: "t9")], to: [
            session("a", cli: "cli-run", running: false),   // the guess said idle, the plugin says a turn runs
            session("b", cli: "cli-idle", running: true),   // the guess said running, the plugin says idle
            session("c", cli: "cli-old", running: true),    // an old plugin: the guess stands
            session("d", cli: "cli-none", running: true),   // no presence: the guess stands
            session("e", cli: nil, running: false),
            session("f", cli: "cli-arch", running: false, archived: true),
        ])
        #expect(read.map(\.running) == [true, false, true, true, false, false])
    }

    // MARK: The Store's API

    private struct Local {
        var dir = TempDir()
        var store: Store
        var inbox: RelayInbox
        var paths: RouterPaths
    }

    /// A store with the Router's files in a temp folder, the key held, and `cli-a` (Desktop id `local_a`) live with `extra`
    /// in its presence file.
    private func local(extra: [String: Any]) throws -> Local {
        let dir = TempDir()
        let paths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try ClaudePlugin.ensureKey(at: paths.relayKey)
        let store = Store()
        store.persists = false
        store.routerPaths = paths
        PluginFixture.useKey(store)
        store.claudeSessions["local_a"] = ClaudeSession(id: "local_a", title: "A", lastActivity: Self.now, cliID: "cli-a")
        PluginFixture.live("cli-a", support: paths.support, claude: paths.claudeDir, extra: extra)
        store.claudeFeed.seedPresence(ClaudePlugin.live(in: paths.pluginSessions,
            registry: ClaudePeers.registry(dir: paths.claudeDir.appendingPathComponent("sessions")),
            keyID: ClaudePlugin.currentKeyID(beside: paths.pluginSessions)))
        return Local(dir: dir, store: store, inbox: RelayInbox(root: paths.relay), paths: paths)
    }

    private static let capable: [String: Any] = [
        "capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.settingsCapability, ClaudePlugin.stopCapability, ClaudePlugin.interruptCapability],
        "turn": ["id": "t1", "startedAt": 1],
    ]

    /// The plugin in `cli-a`'s inbox: answers the first message it sees with `answer`, and returns the text.
    private func plugin(_ inbox: RelayInbox, answer: String) -> Task<String?, Never> {
        Task.detached {
            let folder = inbox.folder(for: "cli-a")
            var watchdog = Watchdog()
            while !watchdog.expired() {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                if let name = names.first(where: { $0.hasSuffix(".msg") }),
                   let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) {
                    try? Data((answer + "\n").utf8).write(to: folder.appendingPathComponent(name.replacingOccurrences(of: ".msg", with: ".ack")), options: .atomic)
                    return text
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return nil
        }
    }

    private func messages(_ l: Local) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: l.inbox.folder(for: "cli-a").path)) ?? []).filter { $0.hasSuffix(".msg") }
    }

    @Test func aStopIsOfferedOnlyForAPluginThatCanAndATurnThatRuns() throws {
        let l = try local(extra: Self.capable)
        #expect(l.store.canStop(sessionID: "local_a") && l.store.runningTurn(sessionID: "local_a")?.id == "t1")
        // By the CLI id too; not for one that isn't there.
        #expect(l.store.canStop(sessionID: "cli-a") && !l.store.canStop(sessionID: "local_zzz"))
        let idle = try local(extra: ["capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.stopCapability], "turn": NSNull()])
        #expect(!idle.store.canStop(sessionID: "local_a"))
        let old = try local(extra: ["capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.abortCapability]])
        #expect(!old.store.canStop(sessionID: "local_a"))
    }

    @Test func stoppingGoesThroughTheInboxNamingTheTurnPresenceShows() async throws {
        let l = try local(extra: Self.capable)
        let fake = plugin(l.inbox, answer: "ok stopped t1")
        #expect(await l.store.stopTurn(sessionID: "local_a") == .stopped("t1"))
        let text = try #require(await fake.value)
        let key = try #require(ClaudePlugin.key(at: l.paths.relayKey))
        let fields = text.dropFirst("⟦fjord stop v1 ".count).dropLast(2).split(separator: " ").map(String.init)
        #expect(text.hasPrefix("⟦fjord stop v1 cli-a ") && fields.count == 5 && fields[3] == "t1")
        // Signed with the key held, over exactly what the plugin checks.
        let expected = RelaySigner.signStop(target: "cli-a", turn: "t1", key: key, nonce: UUID(uuidString: fields[1])!,
                                            now: Date(timeIntervalSince1970: (Double(fields[2]) ?? 0) / 1000))
        #expect(expected == text)
        // Both files are gone after.
        #expect(messages(l).isEmpty)
    }

    @Test func theOutcomesFollowThePluginsAnswer() async throws {
        let l = try local(extra: Self.capable)
        var fake = plugin(l.inbox, answer: "ok not-running")
        #expect(await l.store.stopTurn(sessionID: "local_a") == .notRunning)
        _ = await fake.value
        fake = plugin(l.inbox, answer: "ok idle")
        #expect(await l.store.stopTurn(sessionID: "local_a") == .idle)
        _ = await fake.value
        fake = plugin(l.inbox, answer: "refused: stale")
        #expect(await l.store.stopTurn(sessionID: "local_a") == .failed("The session's plugin refused the message: stale"))
        _ = await fake.value
        fake = plugin(l.inbox, answer: "ok something else")
        let odd = await l.store.stopTurn(sessionID: "local_a")
        #expect(odd == .failed("The session's plugin answered “ok something else”"))
        _ = await fake.value
    }

    @Test func aSessionPresenceSaysIsIdleIsNotWrittenTo() async throws {
        let l = try local(extra: ["capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.stopCapability], "turn": NSNull()])
        #expect(await l.store.stopTurn(sessionID: "local_a") == .idle)
        #expect(messages(l).isEmpty)
    }

    @Test func aPluginThatCantStopIsUnsupportedAndNothingIsWritten() async throws {
        let l = try local(extra: ["capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.abortCapability], "turn": ["id": "t1"]])
        guard case .unsupported = await l.store.stopTurn(sessionID: "local_a") else { Issue.record("not unsupported"); return }
        guard case .unsupported = await l.store.interrupt(sessionID: "local_a", text: "hi") else { Issue.record("not unsupported"); return }
        #expect(messages(l).isEmpty)
        // No plugin in the session at all.
        guard case .unsupported = await l.store.stopTurn(sessionID: "local_nowhere") else { Issue.record("not unsupported"); return }
    }

    @Test func anInterruptTheTurnWouldNotYieldToIsNotDelivered() async throws {
        let l = try local(extra: Self.capable)
        var fake = plugin(l.inbox, answer: "refused: the running turn could not be stopped")
        #expect(await l.store.interrupt(sessionID: "local_a", text: "Go") == .refused("the running turn could not be stopped"))
        _ = await fake.value
        // An older plugin's "ok not-running" was not a delivery either.
        #expect(SessionControlAck.delivery("ok not-running") == nil)
        fake = plugin(l.inbox, answer: "refused: not submitted: nothing to send")
        #expect(await l.store.interrupt(sessionID: "local_a", text: "Go") == .refused("not submitted: nothing to send"))
        _ = await fake.value
    }

    // MARK: Presence reads

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        func bump() { lock.lock(); n += 1; lock.unlock() }
    }

    /// Lets the main queue run what the presence scan handed it.
    private func drain() async {
        for _ in 0..<5 { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    @Test func aHeartbeatRenewsTheLeaseWithoutAReadOfTheSessionsButATurnChangeAsksForOne() async throws {
        let l = try local(extra: Self.capable)
        let calls = Calls()
        l.store.claudeFeed.readPresence(from: l.paths) { calls.bump() }
        await drain()
        l.store.claudeFeed.scanPresence()
        await drain()
        let base = calls.count
        let renewed = Int64(ClaudePlugin.leaseNow.timeIntervalSince1970 * 1000) + 10_000
        func rewrite(_ extra: [String: Any]) {
            PluginFixture.live("cli-a", support: l.paths.support, claude: l.paths.claudeDir, extra: Self.capable.merging(extra) { _, new in new })
        }
        // The heartbeat: the same file with a later time.
        rewrite(["renewedAt": renewed])
        l.store.claudeFeed.presenceNow = { Date(timeIntervalSince1970: Double(renewed) / 1000) }
        l.store.claudeFeed.scanPresence()
        await drain()
        #expect(calls.count == base)
        #expect(l.store.claudeFeed.presence["cli-a"]?.renewedAt == renewed)
        // The turn ends: that is something to reconcile.
        rewrite(["renewedAt": renewed, "turn": NSNull()])
        l.store.claudeFeed.scanPresence()
        await drain()
        #expect(calls.count == base + 1)
        #expect(l.store.claudeFeed.presence["cli-a"]?.turn == nil)
    }

    @Test func aLeaseThatRunsOutDropsTheStateAndAsksForAReconcile() async throws {
        let l = try local(extra: Self.capable)
        let calls = Calls()
        l.store.claudeFeed.readPresence(from: l.paths) { calls.bump() }
        await drain()
        // The clock: 0.3 s before the lease ends, running on in real time. The scan schedules its own look for the expiry.
        let renewed = ClaudePlugin.leaseNow.timeIntervalSince1970
        let start = Date()
        l.store.claudeFeed.presenceNow = { Date(timeIntervalSince1970: renewed + ClaudePlugin.lease - 1.5 + Date().timeIntervalSince(start)) }
        l.store.claudeFeed.scanPresence()
        await drain()
        let base = calls.count
        #expect(l.store.canStop(sessionID: "local_a"))
        var watchdog = Watchdog()
        while l.store.canStop(sessionID: "local_a"), !watchdog.expired() { try? await Task.sleep(nanoseconds: 20_000_000) }
        await drain()
        #expect(!l.store.canStop(sessionID: "local_a") && l.store.claudeFeed.presence["cli-a"] == nil)
        #expect(calls.count == base + 1)
    }

    @Test func theGateIsAskedRightBeforeTheWriteAndAStaleRequestWritesNothing() async throws {
        let l = try local(extra: Self.capable)
        let stop = await l.store.stopTurn(sessionID: "local_a") { "The card was archived" }
        #expect(stop == .failed("The card was archived"))
        let interrupt = await l.store.interrupt(sessionID: "local_a", text: "hi") { "The card was archived" }
        #expect(interrupt == .refused("The card was archived"))
        #expect(messages(l).isEmpty)
        // And the gate that says yes lets it through.
        let fake = plugin(l.inbox, answer: "ok stopped t1")
        #expect(await l.store.stopTurn(sessionID: "local_a") { nil } == .stopped("t1"))
        _ = await fake.value
    }

    @Test func anInterruptCarriesTheWordsAndTheFlagAndSaysWhatItStopped() async throws {
        let l = try local(extra: Self.capable)
        var fake = plugin(l.inbox, answer: "ok interrupted t1 model=opus effort=high")
        let settings = SessionSettings(model: "opus", effort: "high")
        let done = await l.store.interrupt(sessionID: "local_a", text: "Do this instead", settings: settings)
        #expect(done == .delivered(ack: "ok interrupted t1 model=opus effort=high", interrupted: "t1"))
        let text = try #require(await fake.value)
        let lines = text.split(separator: "\n", maxSplits: 1).map(String.init)
        #expect(lines[0].hasPrefix("⟦fjord v3 cli-a ") && lines[0].contains(" opus high 1 "))
        #expect(Data(base64Encoded: lines[1]) == Data("Do this instead".utf8))
        // Nothing was running: the plugin only submitted it.
        fake = plugin(l.inbox, answer: "ok idle")
        #expect(await l.store.interrupt(sessionID: "local_a", text: "Go") == .delivered(ack: "ok idle", interrupted: nil))
        _ = await fake.value
        fake = plugin(l.inbox, answer: "refused: stale")
        #expect(await l.store.interrupt(sessionID: "local_a", text: "Go") == .refused("stale"))
        _ = await fake.value
    }

    @Test func settingsGoOnlyToAPluginThatAppliesThem() async throws {
        let l = try local(extra: ["capabilities": [ClaudePlugin.inboxCapability, ClaudePlugin.interruptCapability], "turn": ["id": "t1"]])
        let fake = plugin(l.inbox, answer: "ok interrupted t1")
        _ = await l.store.interrupt(sessionID: "local_a", text: "Go", settings: SessionSettings(model: "opus", effort: "high"))
        let text = try #require(await fake.value)
        #expect(text.hasPrefix("⟦fjord v3 cli-a ") && text.split(separator: "\n")[0].contains(" - - 1 "))
    }

    @Test func withoutTheRouterNothingIsSent() async {
        let store = Store()
        store.persists = false
        #expect(await store.stopTurn(sessionID: "local_a") == .failed("The Router is off"))
        #expect(await store.interrupt(sessionID: "local_a", text: "hi") == .failed("The Router is off"))
        #expect(!store.canStop(sessionID: "local_a"))
    }
}
