import Foundation

/// While the window's morph plays, main-thread work that can wait (a sync's results, the Claude feed, a folder scan's
/// answer) waits for it to end, so the motion and the handoff get the main thread to themselves. The morph says when it
/// starts and ends (`began`, `ended`); work that can wait goes through `whenStill`. A morph that never says it ended (a
/// bug) lets the work go after `longest` anyway.
@MainActor
enum MotionGate {
    /// Longer than any morph (an opening and its handoff take some 0.5 s), so a missed `ended` only delays, never holds.
    static let longest: TimeInterval = 1.5

    /// The app's one gate (a test makes gates of its own).
    static let shared = Gate()

    static var moving: Bool { shared.moving }
    /// Something moves, or work held for a motion is still being let go: work that can wait goes behind it.
    static var holding: Bool { shared.holding }
    static func began() { shared.began() }
    static func ended() { shared.ended() }
    static func whenStill(_ work: @escaping () -> Void) { shared.whenStill(work) }
    static func still() async { await shared.still() }

    @MainActor
    final class Gate {
        private(set) var moving = false
        private var waiting: [() -> Void] = []
        private var generation = 0
        let longest: TimeInterval

        init(longest: TimeInterval = MotionGate.longest) { self.longest = longest }

        var holding: Bool { moving || !waiting.isEmpty }

        func began() {
            moving = true
            generation += 1
            let mine = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + longest) { [weak self] in
                MainActor.assumeIsolated { if let self, self.generation == mine, self.moving { self.ended() } }
            }
        }

        func ended() {
            guard moving else { return }
            moving = false
            release()
        }

        /// What waited goes one item per turn of the main run loop, starting with the next: not inside the turn that ends
        /// the morph (its handoff), and with frames free to come between items. A motion that starts again meanwhile holds
        /// the rest.
        private func release() {
            guard !waiting.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.moving, !self.waiting.isEmpty else { return }
                    self.waiting.removeFirst()()
                    self.release()
                }
            }
        }

        /// Runs `work` now when nothing moves and nothing still waits, else once the motion ends, in the order it was asked.
        func whenStill(_ work: @escaping () -> Void) {
            if holding { waiting.append(work) } else { work() }
        }

        /// Returns at once when nothing moves and nothing still waits, else once the motion ends, in its turn behind what
        /// was asked before. What follows the await runs with nothing moving: a motion that began between its release and
        /// its resuming is waited out too.
        func still() async {
            guard holding else { return }
            repeat {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    whenStill { done.resume() }
                }
            } while moving
        }
    }
}
