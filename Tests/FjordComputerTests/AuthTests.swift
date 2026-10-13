import Foundation
import Testing
@testable import FjordComputer

/// Answers every GitHub request from `handler`, so the store can run without a network.
final class StubAuthGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (URLRequest) -> (status: Int, body: String) = { _ in (200, "[]") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Requests this answers only once `releaseHeld()` is called, to land a response late.
    nonisolated(unsafe) static var holds: (URLRequest) -> Bool = { _ in false }
    nonisolated(unsafe) private static var held: [StubAuthGitHub] = []
    private static let heldLock = NSLock()

    static func releaseHeld() {
        let all = heldLock.withLock { () -> [StubAuthGitHub] in defer { held = [] }; return held }
        all.forEach { $0.respond() }
    }

    override func startLoading() {
        if Self.holds(request) {
            Self.heldLock.withLock { Self.held.append(self) }
        } else {
            respond()
        }
    }

    private func respond() {
        let (status, body) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAuthGitHub.self]
        return URLSession(configuration: config)
    }
}

@MainActor
@Suite(.serialized) struct Auth {
    private func store(login: String = "me") -> Store {
        let s = Store()
        s.persists = false
        s.settings.triage = true
        s.gh.session = StubAuthGitHub.session
        s.gh.token = "token"
        s.me = GHUser(login: login, avatarUrl: nil, type: nil)
        return s
    }

    private func revoke() {
        StubAuthGitHub.handler = { _ in (401, #"{"message":"Bad credentials"}"#) }
    }

    @Test func aRevokedTokenAndItsIdentityAreDropped() async {
        let s = store()
        InboxFixture.watch(s)
        revoke()
        await s.pollAll()
        #expect(s.me == nil)
        #expect(s.gh.token == nil)
        #expect(s.authError != nil)
    }

    @Test func aTokenGitHubRejectsIsAnnouncedOnceForTheAttemptThatSavedIt() async {
        let s = store()
        s.me = nil
        s.gh.token = nil
        s.keychainWrite = { _, _ in true }
        s.resolveToken = { ("ghp_revoked", .keychain) }
        revoke()
        // This store's own announcements: a global sink would also hear other tests' stores, running beside it while this one
        // waits on its polls.
        var said: [String] = []
        s.announce = { text, _ in said.append(text) }
        // A poll that fails to sign in with nobody having tried anything says nothing.
        await s.pollAll()
        #expect(s.authError == "GitHub rejected the token" && said.isEmpty)
        // The token saved in Settings is refused: that attempt's result is said.
        #expect(s.setToken("ghp_revoked"))
        await waitUntil { !said.isEmpty && !s.isSyncing }
        #expect(said == ["GitHub rejected the token"] && s.awaitingSignIn == false)
        // The next poll's failure is not the attempt's.
        await s.pollAll()
        #expect(said == ["GitHub rejected the token"])
    }

    @Test func retryPicksUpTheTokenFromANewLogin() async {
        let s = store()
        InboxFixture.watch(s)
        revoke()
        await s.pollAll()
        StubAuthGitHub.handler = { req in
            req.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
                ? (200, req.url?.path == "/user" ? #"{"login":"me"}"# : "[]")
                : (401, #"{"message":"Bad credentials"}"#)
        }
        s.resolveToken = { ("fresh", .ghCLI) }
        s.refreshNow()
        while s.me == nil || s.isSyncing { await Task.yield() }
        #expect(s.gh.token == "fresh")
        #expect(s.me?.login == "me")
        #expect(s.authError == nil)
    }

    @Test func aLateRejectionOfAnOlderTokenLeavesTheNewOneAlone() async {
        let gh = GitHubClient()
        gh.session = StubAuthGitHub.session
        let sent = Counter()
        let isA = { (req: URLRequest) in req.value(forHTTPHeaderField: "Authorization") == "Bearer A" }
        StubAuthGitHub.holds = { req in
            if isA(req) { sent.bump() }
            return isA(req)
        }
        StubAuthGitHub.handler = { req in isA(req) ? (401, #"{"message":"Bad credentials"}"#) : (200, #"{"login":"me"}"#) }
        defer { StubAuthGitHub.holds = { _ in false } }
        gh.token = "A"
        let late = Task { try? await gh.get("/user", as: GHUser.self) }
        while sent.count == 0 { await Task.yield() }
        gh.token = "B"
        #expect((try? await gh.get("/user", as: GHUser.self))?.login == "me")
        StubAuthGitHub.releaseHeld()
        _ = await late.value
        #expect(!gh.tokenRejected)
    }

    @Test func aRejectionOutsideAPollIsDroppedByTheNextRefresh() async {
        let s = store()
        InboxFixture.watch(s)
        revoke()
        await s.loadSuggestions()
        #expect(s.gh.tokenRejected)
        StubAuthGitHub.handler = { req in
            req.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
                ? (200, req.url?.path == "/user" ? #"{"login":"me"}"# : "[]")
                : (401, #"{"message":"Bad credentials"}"#)
        }
        s.resolveToken = { ("fresh", .ghCLI) }
        await s.pollAll()
        #expect(s.gh.token == "fresh")
        #expect(!s.gh.tokenRejected)
        #expect(s.me?.login == "me")
        #expect(s.authError == nil)
    }

    @Test func signedOutPollsDoNotSpawnGhEveryTime() async {
        let s = store()
        s.me = nil
        s.gh.token = nil
        let looks = Counter()
        s.resolveToken = { looks.bump(); return nil }
        await s.pollAll()
        await s.pollAll()
        await s.pollAll()
        #expect(looks.count == 1)
        s.refreshNow()  // asked for: looks again
        while looks.count < 2 { await Task.yield() }
    }

    @Test func comingBackToTheAppOrOpeningTheHubLooksAgainForAMissingToken() async {
        let s = store()
        s.me = nil
        s.gh.token = nil
        let looks = Counter()
        s.resolveToken = { looks.bump(); return nil }
        await s.pollAll()
        #expect(looks.count == 1 && s.authError != nil)
        // `gh auth login` was run in Terminal: coming back is a look, though the poll is within its backoff.
        s.appBecameActive()
        while looks.count < 2 { await Task.yield() }
        while s.isSyncing { await Task.yield() }
        // So is opening the hub, though the last poll was a moment ago.
        s.setHubOpen(true)
        while looks.count < 3 { await Task.yield() }
        while s.isSyncing { await Task.yield() }
    }

    @Test func aPeekSyncsNothingAtOnceAndTheWindowThenSyncsAStaleInbox() async {
        let s = store()
        let stale = Date(timeIntervalSinceNow: -120)
        s.lastSync = stale
        // The bar hovered: its rows aren't reshuffled under the pointer by a sync it started.
        s.setHubOpen(true, window: false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!s.isSyncing && s.lastSync == stale)
        // The window opened from it: the stale inbox is synced.
        s.setHubOpen(true, window: true)
        for _ in 0..<200 where s.lastSync == stale { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(s.lastSync != stale)
    }

    @Test func aPeekLeavesTheNextPollWhereItWas() async {
        StubAuthGitHub.handler = { _ in (200, "[]") }
        let s = store()
        s.resolveToken = { nil }
        s.restartPolling()
        defer { s.stopPolling() }
        for _ in 0..<300 where s.sleeperWakes == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let wakes = s.sleeperWakes
        let last = s.lastSync
        // Last polled 45 s ago, with the 60 s interval: the hub's 30 s is past, but a peek starts no poll.
        s.lastSync = Date(timeIntervalSinceNow: -45)
        s.setHubOpen(true, window: false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(s.sleeperWakes == wakes && !s.isSyncing && last != nil)
        #expect(s.lastSync.map { $0 < Date(timeIntervalSinceNow: -40) } == true)
    }

    @Test func openingTheHubSetsTheNextPollForItsShorterInterval() async {
        StubAuthGitHub.handler = { _ in (200, "[]") }
        let s = store()
        s.resolveToken = { nil }
        s.settings.pollInterval = 300
        s.restartPolling()
        defer { s.stopPolling() }
        for _ in 0..<300 where s.sleeperWakes == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let last = try? #require(s.lastSync)
        #expect(s.sleeperWakes.map { $0 > Date().addingTimeInterval(200) } == true)
        // Opened 5 s or so after a poll: the next comes 30 s after it, not 300.
        s.setHubOpen(true)
        for _ in 0..<300 where s.sleeperWakes.map({ $0 > Date().addingTimeInterval(60) }) ?? true {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(s.sleeperWakes.map { $0 <= (last ?? .distantPast).addingTimeInterval(31) } == true)
        #expect(s.lastSync == last)
    }

    @Test func aTokenHeldIsNotLookedForAgainWhenTheAppComesBack() async {
        let s = store()
        s.me = nil
        s.gh.token = "held"
        s.authError = "The Internet connection appears to be offline."
        let looks = Counter()
        s.resolveToken = { looks.bump(); return nil }
        s.lastSync = Date()
        s.appBecameActive()
        s.setHubOpen(true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(looks.count == 0 && !s.isSyncing)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}

@MainActor
@Suite struct TokenSaving {
    @Test func aGitHubTokenTheKeychainRefusedIsNotSavedAndIsNotSignedInWith() {
        let s = Store()
        s.persists = false
        var written: [(String, String)] = []
        s.keychainWrite = { key, account in written.append((key, account)); return false }
        s.lastSync = nil
        #expect(!s.setToken("ghp_test"))
        #expect(written.count == 1 && written[0].0 == "ghp_test" && written[0].1 == Keychain.github)
        // Nothing was refreshed with the token that was not kept.
        #expect(s.lastSync == nil && !s.isSyncing)
    }

    @Test func aTokenTheKeychainKeptSignsInAgain() {
        let s = Store()
        s.persists = false
        s.gh.session = StubAuthGitHub.session
        s.resolveToken = { nil }
        s.keychainWrite = { _, _ in true }
        s.me = GHUser(login: "old", avatarUrl: nil, type: nil)
        #expect(s.setToken("ghp_test"))
        #expect(s.me == nil)
    }
}
