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

/// Claude's reads that come while the window moves are taken in once, folded together, after it.
@MainActor @Suite struct ClaudeFeedHold {
    private func session(_ id: String) -> ClaudeSession {
        ClaudeSession(id: id, title: id, folder: nil, lastActivity: Date())
    }

    @Test func readsHeldByAMotionAreTakenInOnceFoldedTogether() async {
        let gate = MotionGate.Gate()
        let feed = ClaudeFeed(activityReader: Claude.ActivityReader())
        var applied: [ClaudeSnapshot] = []
        let apply: @MainActor (ClaudeSnapshot) -> Void = { applied.append($0) }
        var full = ClaudeSnapshot()
        full.link = .ok
        full.sessions = [session("a")]
        full.appUnread = ["a"]
        full.activity = [:]
        var activity = ClaudeSnapshot()
        activity.activity = ["a": ClaudeActivity(text: "Reading", since: Date())]
        activity.tasks = [:]
        gate.began()
        feed.deliver(full, apply, gate: gate)
        feed.deliver(activity, apply, gate: gate)
        feed.deliver(activity, apply, gate: gate)
        #expect(applied.isEmpty)
        gate.ended()
        for _ in 0..<20 where applied.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
        #expect(applied.count == 1)
        #expect(applied.first?.sessions?.map(\.id) == ["a"] && applied.first?.appUnread == ["a"])
        #expect(applied.first?.activity?["a"]?.text == "Reading" && applied.first?.tasks?.isEmpty == true)
        // Nothing moving: taken in at once.
        feed.deliver(activity, apply, gate: gate)
        #expect(applied.count == 2)
    }

    @Test func aReadThatFailedOrAnotherStampIsNotFoldedIn() {
        var ok = ClaudeSnapshot()
        ok.link = .ok
        ok.sessions = []
        var failed = ClaudeSnapshot()
        failed.link = .missing
        #expect(ok.merging(failed) == nil)
        var other = ClaudeSnapshot()
        other.stamp.generation = 1
        #expect(ok.merging(other) == nil)
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
