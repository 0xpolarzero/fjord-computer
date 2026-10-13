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
