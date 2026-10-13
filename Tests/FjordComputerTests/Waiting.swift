import Foundation
import Testing

/// How long a wait goes on before it fails the test. The work these waits see takes a few seconds at most, and a loaded
/// parallel run has held tests of a millisecond up for about 8 s; a wait for something that never comes fails in this,
/// not in a minute.
let waitWatchdog: TimeInterval = 20

/// Waits for `condition`, which something the test started brings about: returns as soon as it holds. `seconds` is a
/// watchdog, not a guess at how long the work takes: a runner many times slower still gets there, and one that runs out
/// fails the test at the wait, so a wait on a condition that can't hold doesn't sit out the watchdog and let the checks
/// after it pass on whatever state it left.
@MainActor func waitUntil(within seconds: TimeInterval = waitWatchdog, sourceLocation: SourceLocation = #_sourceLocation,
                          _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("Waited \(seconds) s for a condition that never held", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Waits until `value` reads the same over `turns` consecutive turns of the main actor: what SwiftUI had pending (a
/// layout, an update) has happened, however slowly it ran. `quiet` also asks for that much time unchanged: turns alone
/// can pass in a stall, with an animation or a deferred layout still to move the value once the machine lets it.
/// Bounded by a watchdog like `waitUntil`, and fails the test like it when the value never settles.
@MainActor func waitUntilSteady<T: Equatable>(within seconds: TimeInterval = waitWatchdog, turns: Int = 5,
                                              quiet: TimeInterval = 0, sourceLocation: SourceLocation = #_sourceLocation,
                                              _ value: () -> T) async {
    let deadline = Date().addingTimeInterval(seconds)
    var last = value(), same = 0, since = Date()
    while same < turns || Date().timeIntervalSince(since) < quiet {
        guard Date() < deadline else {
            Issue.record("Waited \(seconds) s for a value that never settled (last \(last))", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(20))
        let now = value()
        if now == last { same += 1 } else { same = 0; since = Date() }
        last = now
    }
}

/// `waitUntil` for a test off the main actor: `condition` reads only what is safe to read from any thread.
func waitUntilAnywhere(within seconds: TimeInterval = waitWatchdog, sourceLocation: SourceLocation = #_sourceLocation,
                       _ condition: @Sendable () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("Waited \(seconds) s for a condition that never held", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Lets what the main queue has queued run, `hops` times over (what a hop queues runs on the next): ordered, not timed,
/// so a slow machine only makes it later. For work a view defers with `DispatchQueue.main.async` (a focus request, say).
@MainActor func drainMainQueue(hops: Int = 8) async {
    for _ in 0..<hops {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { done.resume() } }
    }
}
