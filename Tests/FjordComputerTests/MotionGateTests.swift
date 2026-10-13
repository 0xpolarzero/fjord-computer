import Foundation
import Testing
@testable import FjordComputer

/// Work that can wait holds while the window's morph plays, then goes in the order it was asked, a turn at a time.
@MainActor @Suite struct MotionGateTests {
    /// Lets the main queue run its turns.
    private func turns(_ n: Int = 10) async {
        for _ in 0..<n { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func workWaitsForTheMotionAndGoesInOrderAfterIt() async {
        let gate = MotionGate.Gate()
        var done: [Int] = []
        gate.whenStill { done.append(0) }
        #expect(done == [0])
        gate.began()
        gate.whenStill { done.append(1) }
        gate.whenStill { done.append(2) }
        await turns()
        #expect(done == [0])
        gate.ended()
        // Not inside the turn that ends the morph.
        #expect(done == [0])
        // Asked while the held work is still being let go: it goes behind it.
        gate.whenStill { done.append(3) }
        await turns()
        #expect(done == [0, 1, 2, 3])
        #expect(!gate.holding)
    }

    @Test func stillWaitsItsTurnBehindWhatWasHeld() async {
        let gate = MotionGate.Gate()
        var done: [String] = []
        gate.began()
        gate.whenStill { done.append("held") }
        gate.ended()
        // Nothing moves, but held work has yet to go: an await takes its turn behind it.
        await gate.still()
        done.append("still")
        #expect(done == ["held", "still"])
    }

    @Test func stillWaitsOutAMotionThatBeganBeforeItResumed() async {
        let gate = MotionGate.Gate()
        gate.began()
        var resumed = false
        let waiter = Task { @MainActor in
            await gate.still()
            resumed = true
            #expect(!gate.moving)
        }
        await turns()
        gate.ended()
        // Another morph starts before the waiter's turn comes.
        gate.began()
        await turns()
        #expect(!resumed)
        gate.ended()
        await waiter.value
        #expect(resumed)
    }

    @Test func aMorphThatNeverSaysItEndedLetsTheWorkGo() async {
        let gate = MotionGate.Gate(longest: 0.05)
        var done = false
        gate.began()
        gate.whenStill { done = true }
        for _ in 0..<100 where !done { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(done && !gate.moving)
    }
}

/// Claude's reads that come while the window moves are taken in after it, every one in order, as if each came then.
@MainActor @Suite struct ClaudeFeedHold {
    private let now = Date()

    private func session(_ id: String, turns: Int, message: Double = -120, archived: Bool = false) -> ClaudeSession {
        var s = ClaudeSession(id: id, title: "Session \(id)", folder: "/code/app", completedTurns: turns,
                              lastActivity: now.addingTimeInterval(-60), lastFocused: now.addingTimeInterval(-3600),
                              lastUserMessage: now.addingTimeInterval(message), summary: .init(blocked: false, detail: "Done it"),
                              cliID: "cli-\(id)")
        s.isArchived = archived
        return s
    }

    private func store(_ dir: TempDir, _ sessions: [ClaudeSession], dots: Set<String> = []) -> Store {
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Fjord Computer.app/Contents/MacOS/FjordComputer"
        s.interceptOpen = { _ in }
        s.claudeIsFrontmost = { false }
        s.claudeLink = .ok
        s.agents.enabled = true
        s.agents.enabledAt = now.addingTimeInterval(-7200)
        s.ingest(sessions, appUnread: dots, claudeFrontmost: false)
        s.setRouterEnabled(true)
        s.feedRouter()
        return s
    }

    private func read(_ sessions: [ClaudeSession], dots: Set<String> = []) -> ClaudeSnapshot {
        var read = ClaudeSnapshot()
        read.link = .ok
        read.sessions = sessions
        read.appUnread = dots
        read.activity = [:]
        read.tasks = [:]
        return read
    }

    /// The reads taken in one by one, and held by a motion then let go: the same cards, the same read flags.
    private func expectHeldAsInTurn(_ start: [ClaudeSession], dots: Set<String> = [], setUp: (Store) -> Void = { _ in },
                                    _ reads: [ClaudeSnapshot], sourceLocation: SourceLocation = #_sourceLocation) async {
        let dirA = TempDir(), dirB = TempDir()
        let inTurn = store(dirA, start, dots: dots), held = store(dirB, start, dots: dots)
        setUp(inTurn)
        setUp(held)
        for var read in reads {
            read.stamp = inTurn.claudeStamp
            inTurn.applyClaude(read)
        }
        let gate = MotionGate.Gate()
        gate.began()
        var applied = 0
        for var read in reads {
            read.stamp = held.claudeStamp
            held.claudeFeed.deliver(read, { applied += 1; held.applyClaude($0) }, gate: gate)
        }
        await Task.yield()
        #expect(applied == 0, sourceLocation: sourceLocation)
        gate.ended()
        for _ in 0..<100 where applied < reads.count { try? await Task.sleep(for: .milliseconds(2)) }
        func cards(_ s: Store) -> [String] { s.router.cards.map { "\($0.id) \($0.isOpen) \(String(describing: $0.addressedBy))" } }
        #expect(cards(held) == cards(inTurn), sourceLocation: sourceLocation)
        #expect(held.agents.entries.map(\.unread) == inTurn.agents.entries.map(\.unread), sourceLocation: sourceLocation)
        #expect(held.routerHistory.map(\.id) == inTurn.routerHistory.map(\.id), sourceLocation: sourceLocation)
    }

    @Test func aTurnThatEndedThenANewMessageStillMakesItsCard() async {
        await expectHeldAsInTurn([session("local_a", turns: 1)], [
            read([session("local_a", turns: 2)]),
            read([session("local_a", turns: 2, message: -1)]),
        ])
    }

    @Test func aSessionArchivedThenBackLeavesItsCardGone() async {
        await expectHeldAsInTurn([session("local_a", turns: 1)], setUp: { s in
            s.ingest([self.session("local_a", turns: 2)], appUnread: [], claudeFrontmost: false)
            s.feedRouter()
        }, [
            read([session("local_a", turns: 2, archived: true)]),
            read([session("local_a", turns: 2)]),
        ])
    }

    @Test func aDotClearedThenBackLeavesTheSessionUnread() async {
        await expectHeldAsInTurn([session("local_a", turns: 1)], dots: ["local_a"], [
            read([session("local_a", turns: 1)], dots: []),
            read([session("local_a", turns: 1)], dots: ["local_a"]),
        ])
    }
}

/// A sync's results, and what it says of them, wait for the window's morph.
@MainActor @Suite struct SyncHeldByMotion {
    @Test func aSyncsResultsAndItsErrorWaitForTheMotion() async {
        let gate = MotionGate.Gate()
        let s = Store()
        s.persists = false
        s.settings.triage = true
        s.motionGate = gate
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        s.gh.session = StubbedGitHub.session { request in
            switch request.url?.path ?? "" {
            case "/repos/a/x": return .init(200, #"{"full_name":"a/x","default_branch":"main"}"#)
            case "/repos/a/x/branches/main": return .init(200, #"{"commit":{"sha":"s1","commit":{"message":"Fix"}}}"#)
            default: return .init(500, #"{"message":"Server Error"}"#)
            }
        }
        var ci = InboxStore.ci
        ci.rules = [Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("a/x")])), conditions: [.workflow([.failing])],
                         createdAt: .distantPast)]
        s.categories = [ci]
        gate.began()
        let sync = Task { await s.syncInbox() }
        for _ in 0..<500 where gate.waitingCount == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(gate.waitingCount == 1)
        // Answered, but nothing said or taken while the window moves.
        #expect(s.inboxError == nil)
        gate.ended()
        await sync.value
        #expect(s.inboxError != nil)
    }
}

/// A poll, and a refresh that stops early, say nothing while the window moves.
@MainActor @Suite struct PollHeldByMotion {
    private func store(_ gate: MotionGate.Gate) -> Store {
        let s = Store()
        s.persists = false
        s.settings.triage = true
        s.motionGate = gate
        return s
    }

    @Test func aPollStartsAndEndsOnlyOnceTheWindowIsStill() async {
        let gate = MotionGate.Gate()
        let s = store(gate)
        s.me = nil
        s.gh.token = nil
        s.resolveToken = { nil }
        gate.began()
        let poll = Task { await s.pollAll() }
        for _ in 0..<200 where gate.waitingCount == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(gate.waitingCount == 1)
        #expect(!s.isSyncing && s.authError == nil && s.lastSync == nil)
        gate.ended()
        await poll.value
        #expect(s.authError != nil && s.lastSync != nil && !s.isSyncing)
    }

    @Test func aRefreshThatStopsAtItsTeamsSaysSoOnlyOnceTheWindowIsStill() async {
        final class Ref: @unchecked Sendable { var gate: MotionGate.Gate? }
        let gate = MotionGate.Gate(), ref = Ref()
        ref.gate = gate
        let s = store(gate)
        s.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        // The window starts to open while GitHub is asked for your teams.
        s.gh.session = StubbedGitHub.session { _ in
            DispatchQueue.main.sync { MainActor.assumeIsolated { ref.gate?.began() } }
            return .init(502, #"{"message":"Server Error"}"#)
        }
        s.categories = [InboxCategory(name: "Team", symbol: "eye", color: .blue, rules: [
            Rule(scope: Scope(kinds: [.pr], to: Pick(include: [.myTeams]), toRoles: [.reviewRequested])),
        ])]
        let sync = Task { await s.syncInbox() }
        for _ in 0..<200 where gate.waitingCount == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(gate.waitingCount == 1 && s.inboxError == nil)
        gate.ended()
        await sync.value
        #expect(s.inboxError?.hasPrefix("Your teams couldn't be looked up") == true)
    }
}

/// The icons a session can get are worked out off the main thread.
@Suite struct SessionIconsOffMain {
    @Test func theIconsOfferedOffTheMainThreadAreThoseOfferedOnIt() async {
        let excluded: Set<String> = ["hammer", "ladybug"]
        let off = await Task.detached { await SessionIcons.openOffMain(excluding: excluded) }.value
        let on = SessionIcons.open(excluding: excluded)
        #expect(off.map(\.category) == on.map(\.category) && off.map(\.icons) == on.map(\.icons))
        #expect(SessionIcons.drawableCount != nil)
    }
}
