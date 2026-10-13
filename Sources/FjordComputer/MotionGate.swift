import Foundation

/// While the window's morph plays, main-thread work that can wait (a sync's results, the Claude feed, a folder scan's
/// answer) waits for it to end, so the motion and the handoff get the main thread to themselves. The morph says when it
/// starts and ends (`began`, `ended`); work that can wait goes through `whenStill`. A morph that never says it ended (a
/// bug) lets the work go after `longest` anyway.
@MainActor
enum MotionGate {
    /// Longer than any morph (an opening and its handoff take some 0.5 s), so a missed `ended` only delays, never holds.
    static let longest: TimeInterval = 1.5

    private(set) static var moving = false
    private static var waiting: [() -> Void] = []
    private static var generation = 0

    static func began() {
        moving = true
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + longest) {
            MainActor.assumeIsolated { if generation == mine, moving { ended() } }
        }
    }

    static func ended() {
        guard moving else { return }
        moving = false
        let work = waiting
        waiting = []
        for item in work { item() }
    }

    /// Runs `work` now when nothing moves, else once the motion ends, in the order it was asked.
    static func whenStill(_ work: @escaping () -> Void) {
        if moving { waiting.append(work) } else { work() }
    }

    /// Returns at once when nothing moves, else once the motion ends.
    static func still() async {
        guard moving else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            whenStill { done.resume() }
        }
    }
}
