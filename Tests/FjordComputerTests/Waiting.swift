import AppKit
import Foundation
import Testing

/// How long a wait goes on before it fails the test. The work these waits see takes a few seconds at most, and a loaded
/// parallel run has held tests of a millisecond up for about 8 s; a wait for something that never comes fails in this,
/// not in a minute.
let waitWatchdog: TimeInterval = 20

/// A wait's watchdog, counting the time the process got to run rather than the time that passed: each check counts at most
/// a quarter of a second since the last. A parallel run on the macos-26 runner (3 cores, no GPU) stops the whole process
/// for 13 to 26 s while its windows first draw; counting that, a wait stopped in it got three reads in 20 s and failed with
/// nothing wrong but the machine. A process that never runs again still ends its waits, at six times the watchdog.
struct Watchdog {
    let seconds: TimeInterval
    private let started = Date()
    private var checked = Date(), ran: TimeInterval = 0

    init(_ seconds: TimeInterval = waitWatchdog) { self.seconds = seconds }

    /// Whether the wait has had its time; called once a check, so the time since the last is the check's own.
    mutating func expired() -> Bool {
        let now = Date()
        ran += min(now.timeIntervalSince(checked), 0.25)
        checked = now
        return ran >= seconds || now.timeIntervalSince(started) >= seconds * 6
    }

    /// The time that passed, which a stall makes more than the watchdog's.
    var elapsed: TimeInterval { Date().timeIntervalSince(started) }
}

/// Waits for `condition`, which something the test started brings about: returns as soon as it holds. `seconds` is a
/// watchdog, not a guess at how long the work takes: a runner many times slower still gets there, and one that runs out
/// fails the test at the wait, so a wait on a condition that can't hold doesn't sit out the watchdog and let the checks
/// after it pass on whatever state it left.
@MainActor func waitUntil(within seconds: TimeInterval = waitWatchdog, sourceLocation: SourceLocation = #_sourceLocation,
                          _ condition: () -> Bool) async {
    var watchdog = Watchdog(seconds)
    while !condition() {
        guard !watchdog.expired() else {
            Issue.record("Waited \(Int(watchdog.elapsed)) s for a condition that never held", sourceLocation: sourceLocation)
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
    let start = Date()
    var watchdog = Watchdog(seconds), last = value(), same = 0, since = start
    // What a wait that runs out reports: how often it got to read, and the values it read last with when, so a starved
    // main actor tells from a value that keeps moving.
    var polls = 0, longest: TimeInterval = 0, polled = start, changes = 0, seen: [String] = []
    while same < turns || Date().timeIntervalSince(since) < quiet {
        guard !watchdog.expired() else {
            Issue.record("""
                Waited \(Int(watchdog.elapsed)) s for a value that never settled (last \(last)): \(polls) reads, the longest gap \
                \(Int(longest * 1000)) ms, \(changes) changes, the last at \(seen.joined(separator: ", ")); \
                \(waitContext())
                """, sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(20))
        let now = value()
        polls += 1
        longest = max(longest, Date().timeIntervalSince(polled))
        polled = Date()
        if now == last { same += 1 } else {
            same = 0; since = Date(); changes += 1
            seen = (seen + ["\(String(format: "%.2f", since.timeIntervalSince(start))) s: \(now)"]).suffix(6)
        }
        last = now
    }
}

/// The runner's screens and process, for a wait's failure: a test run on a machine unlike the one it was written on.
@MainActor func waitContext() -> String {
    let screens = NSScreen.screens.map { "\($0.frame) @\($0.backingScaleFactor)x" }.joined(separator: " ")
    var context = "screens \(screens.isEmpty ? "none" : screens), \(ProcessInfo.processInfo.activeProcessorCount) cores"
    if let app = NSApp {
        let shown = app.windows.filter(\.isVisible)
        context += ", app active \(app.isActive), \(app.windows.count) windows, \(shown.count) shown, "
            + "\(shown.filter { $0.occlusionState.contains(.visible) }.count) of them unoccluded"
    }
    return context
}

/// `waitUntil` for a test off the main actor: `condition` reads only what is safe to read from any thread.
func waitUntilAnywhere(within seconds: TimeInterval = waitWatchdog, sourceLocation: SourceLocation = #_sourceLocation,
                       _ condition: @Sendable () -> Bool) async {
    var watchdog = Watchdog(seconds)
    while !condition() {
        guard !watchdog.expired() else {
            Issue.record("Waited \(Int(watchdog.elapsed)) s for a condition that never held", sourceLocation: sourceLocation)
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
